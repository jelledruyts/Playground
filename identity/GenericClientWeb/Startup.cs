using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Threading.Tasks;
using GenericClientWeb.Infrastructure;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.AzureAD.UI;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;

namespace GenericClientWeb
{
    public class Startup
    {
        public Startup(IConfiguration configuration)
        {
            Configuration = configuration;
        }

        public IConfiguration Configuration { get; }

        // This method gets called by the runtime. Use this method to add services to the container.
        public void ConfigureServices(IServiceCollection services)
        {
            // Create a token provider based on MSAL.
            var tokenProvider = new MsalTokenProvider(new MsalTokenProviderOptions
            {
                CallbackPath = Configuration["AzureAd:CallbackPath"] ?? string.Empty,
                ClientId = Configuration["AzureAd:ClientId"],
                ClientSecret = Configuration["AzureAd:ClientSecret"],
                TenantId = Configuration["AzureAd:TenantId"]
            });
            services.AddSingleton<MsalTokenProvider>(tokenProvider);

            // Don't map any standard OpenID Connect claims to Microsoft-specific claims.
            // See https://leastprivilege.com/2017/11/15/missing-claims-in-the-asp-net-core-2-openid-connect-handler/.
            JwtSecurityTokenHandler.DefaultInboundClaimTypeMap.Clear();

            services.AddAuthentication(AzureADDefaults.AuthenticationScheme)
                .AddAzureAD(options => Configuration.Bind("AzureAd", options));
            services.Configure<OpenIdConnectOptions>(AzureADDefaults.OpenIdScheme, options =>
            {
                // Don't remove any incoming claims.
                options.ClaimActions.Clear();

                // Use the Azure AD v2.0 endpoint.
                options.Authority += "/v2.0";

                // The Azure AD v2.0 endpoint returns the display name in the "preferred_username" claim for ID tokens.
                options.TokenValidationParameters.NameClaimType = Constants.ClaimTypes.PreferredUsername;

                // Azure AD returns the roles in the "roles" claims (if any).
                options.TokenValidationParameters.RoleClaimType = "roles";

                // Trigger a hybrid OIDC + auth code flow.
                options.ResponseType = OpenIdConnectResponseType.CodeIdToken;

                // Define the API scopes that are requested by default as part of the sign-in so that the user can consent to them up-front.
                // This uses the "/.default" scope to request all statically declared scopes, including those of downstream API's that have
                // the "knownClientApplications" set to the current application's Client ID.
                // See https://docs.microsoft.com/en-us/azure/active-directory/develop/v2-oauth2-on-behalf-of-flow#gaining-consent-for-the-middle-tier-application
                var defaultApiScopes = new[] { "User.Read" };

                // Request the scopes from the API as part of the authorization code flow.
                foreach (var apiScope in defaultApiScopes)
                {
                    options.Scope.Add(apiScope);
                }

                // Request a refresh token as part of the authorization code flow.
                options.Scope.Add(OpenIdConnectScope.OfflineAccess);

                // Handle events.
                var onMessageReceived = options.Events.OnMessageReceived;
                options.Events.OnMessageReceived = context =>
                {
                    if (onMessageReceived != null)
                    {
                        onMessageReceived(context);
                    }
                    return Task.CompletedTask;
                };

                var onRedirectToIdentityProvider = options.Events.OnRedirectToIdentityProvider;
                options.Events.OnRedirectToIdentityProvider = context =>
                {
                    if (onRedirectToIdentityProvider != null)
                    {
                        onRedirectToIdentityProvider(context);
                    }
                    return Task.CompletedTask;
                };

                var onAuthorizationCodeReceived = options.Events.OnAuthorizationCodeReceived;
                options.Events.OnAuthorizationCodeReceived = async context =>
                {
                    if (onAuthorizationCodeReceived != null)
                    {
                        await onAuthorizationCodeReceived(context);
                    }

                    // Use the MSAL token provider to redeem the authorizaation code for an ID token, access token and refresh token.
                    // These aren't used here directly (except the ID token) but they are added to the MSAL cache for later use.
                    var result = await tokenProvider.RedeemAuthorizationCodeAsync(context.HttpContext, context.ProtocolMessage.Code, defaultApiScopes);

                    // Remember the MSAL home account identifier so it can be stored in the claims later on.
                    context.Properties.SetParameter(Constants.ClaimTypes.AccountId, result.Account.HomeAccountId.Identifier);

                    // Signal to the OpenID Connect middleware that the authorization code is already redeemed and it should not be redeemed again.
                    // Pass through the ID token so that it can be validated and used as the identity that has signed in.
                    // Do not pass through the access token as we are taking control over the token acquisition and don't want ASP.NET Core to
                    // cache and reuse the access token itself.
                    context.HandleCodeRedemption(null, result.IdToken);
                };

                var onTokenResponseReceived = options.Events.OnTokenResponseReceived;
                options.Events.OnTokenResponseReceived = context =>
                {
                    if (onTokenResponseReceived != null)
                    {
                        onTokenResponseReceived(context);
                    }

                    // The authorization code has been redeemed, and the resulting ID token has been used to construct
                    // the user principal representing the identity that has signed in.
                    // As part of the authorization code redemption, the access token was stored in the MSAL token provider's
                    // cache and it can now be used to call a back-end Web API.
                    // We use it here to retrieve role information for the user, as defined on the back-end Web API, so that
                    // the roles the user has on the back-end can also be used to modify the UI the user will see (e.g. to disable
                    // certain actions the user is not allowed to perform anyway based on their role in the back-end Web API).
                    // NOTE: Technically, we could decode the access token for the back-end Web API and get the role claims
                    // from there (as they are emitted as part of the token), but that would violate the principle of access
                    // tokens being only intended for the rightful audience.
                    // See http://www.cloudidentity.com/blog/2018/04/20/clients-shouldnt-peek-inside-access-tokens/.
                    var identity = (ClaimsIdentity)context.Principal.Identity;

                    // See if an account identifier was provided by a previous step.
                    var accountId = context.Properties.GetParameter<string>(Constants.ClaimTypes.AccountId);
                    if (accountId != null)
                    {
                        // Add the account identifier claim so it can be used to look up the user's tokens later.
                        identity.AddClaim(new Claim(Constants.ClaimTypes.AccountId, accountId));
                    }

                    return Task.CompletedTask;
                };

                var onTokenValidated = options.Events.OnTokenValidated;
                options.Events.OnTokenValidated = context =>
                {
                    if (onTokenValidated != null)
                    {
                        onTokenValidated(context);
                    }
                    var identity = (ClaimsIdentity)context.Principal.Identity;
                    //context.Properties.IsPersistent = true; // Optionally ensure the cookie is persistent across browser sessions.
                    return Task.CompletedTask;
                };
            });
            services.AddMvc()
                .SetCompatibilityVersion(CompatibilityVersion.Version_2_2)
                .AddMvcOptions(options =>
                {
                    // Add a global filter that triggers interactive sign-ins on certain exceptions.
                    options.Filters.Add(new InteractiveSignInRequiredExceptionFilterAttribute());
                });
            services.AddRouting(options => { options.LowercaseUrls = true; });
        }

        // This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        public void Configure(IApplicationBuilder app, IHostingEnvironment env)
        {
            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
            }
            else
            {
                app.UseExceptionHandler("/error");
                // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
                app.UseHsts();
            }

            app.UseHttpsRedirection();
            app.UseStaticFiles();
            app.UseAuthentication();
            app.UseMvc();
        }
    }
}
