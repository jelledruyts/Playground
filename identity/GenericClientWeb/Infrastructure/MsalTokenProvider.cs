using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Extensions;
using Microsoft.Identity.Client;

namespace GenericClientWeb.Infrastructure
{
    public class MsalTokenProvider
    {
        private readonly MsalTokenProviderOptions options;

        public MsalTokenProvider(MsalTokenProviderOptions options)
        {
            this.options = options;
        }

        public string GetFullyQualifiedScope(string scope)
        {
            // Scopes can have placeholders in them so that the App ID URI can be replaced from configuration.
            if (this.options.ScopePlaceholderMappings != null)
            {
                foreach (var mapping in this.options.ScopePlaceholderMappings)
                {
                    scope = scope.Replace(mapping.Key, mapping.Value);
                }
            }
            return scope;
        }

        public IEnumerable<string> GetFullyQualifiedScopes(IEnumerable<string> scopes)
        {
            return scopes.Select(s => GetFullyQualifiedScope(s)).ToArray();
        }

        public async Task<AuthenticationResult> RedeemAuthorizationCodeAsync(HttpContext httpContext, string authorizationCode, IEnumerable<string> scopes)
        {
            var confidentialClientApplication = GetConfidentialClientApplication(httpContext, httpContext.User);
            var fullyQualifiedScopes = GetFullyQualifiedScopes(scopes);
            var token = await confidentialClientApplication.AcquireTokenByAuthorizationCode(fullyQualifiedScopes, authorizationCode).ExecuteAsync();
            ValidateScopes(token, fullyQualifiedScopes);
            return token;
        }

        public async Task<AuthenticationResult> GetTokenForApplicationAsync(HttpContext httpContext, IEnumerable<string> scopes)
        {
            var confidentialClientApplication = GetConfidentialClientApplication(httpContext);
            var fullyQualifiedScopes = GetFullyQualifiedScopes(scopes);
            var token = await confidentialClientApplication.AcquireTokenForClient(fullyQualifiedScopes).ExecuteAsync();
            ValidateScopes(token, fullyQualifiedScopes);
            return token;
        }

        public async Task<AuthenticationResult> GetTokenForUserAsync(HttpContext httpContext, ClaimsPrincipal user, IEnumerable<string> scopes)
        {
            if (user == null || !user.Identity.IsAuthenticated)
            {
                throw new ArgumentException($"The current user is not authenticated.");
            }
            var confidentialClientApplication = GetConfidentialClientApplication(httpContext, user);
            var userAccount = await confidentialClientApplication.GetAccountAsync(user.GetAccountId());
            var fullyQualifiedScopes = GetFullyQualifiedScopes(scopes);
            var token = await confidentialClientApplication.AcquireTokenSilent(fullyQualifiedScopes, userAccount).ExecuteAsync();
            ValidateScopes(token, fullyQualifiedScopes);
            return token;
        }

        private void ValidateScopes(AuthenticationResult token, IEnumerable<string> scopes)
        {
            // Even though the scopes are requested, they may not always be returned from a refresh token flow if the user
            // hasn't consented to a new scope yet; in that case, trigger a new interactive consent flow.
            if (!scopes.All(scope => token.Scopes.Any(s => string.Equals(s, scope, StringComparison.OrdinalIgnoreCase))))
            {
                // Throw an MsalUiRequiredException with a custom error code to signal to the exception filter that it should trigger.
                throw new MsalUiRequiredException(InteractiveSignInRequiredExceptionFilterAttribute.MsalUiRequiredExceptionErrorCodeRequestedScopeMissing, null);
            }
        }

        public async Task RemoveUserAsync(HttpContext httpContext, ClaimsPrincipal user)
        {
            var confidentialClientApplication = GetConfidentialClientApplication(httpContext, user);
            var userAccount = await confidentialClientApplication.GetAccountAsync(user.GetAccountId());
            await confidentialClientApplication.RemoveAsync(userAccount);
            UserTokenCacheWrapper.RemoveUser(user);
        }

        private IConfidentialClientApplication GetConfidentialClientApplication(HttpContext httpContext)
        {
            return GetConfidentialClientApplication(httpContext, null);
        }

        private IConfidentialClientApplication GetConfidentialClientApplication(HttpContext httpContext, ClaimsPrincipal user)
        {
            var redirectUri = UriHelper.BuildAbsolute(httpContext.Request.Scheme, httpContext.Request.Host, httpContext.Request.PathBase, this.options.CallbackPath);
            var confidentialClientApplication = ConfidentialClientApplicationBuilder.CreateWithApplicationOptions(new ConfidentialClientApplicationOptions
            {
                ClientId = this.options.ClientId,
                ClientSecret = this.options.ClientSecret,
                TenantId = this.options.TenantId,
                RedirectUri = redirectUri
            }).Build();
            // Use in-memory cache persistence classes that are by design very naive and not designed for real production
            // scenarios (e.g. these are explicitly not thread-safe so they won't be usable under real user load).
            // See https://aka.ms/msal-net-token-cache-serialization for details on production level token caches.
            new AppTokenCacheWrapper(confidentialClientApplication.AppTokenCache);
            if (user != null)
            {
                new UserTokenCacheWrapper(confidentialClientApplication.UserTokenCache, user);
            }
            return confidentialClientApplication;
        }

        private class AppTokenCacheWrapper
        {
            private static byte[] appTokenCache;

            public AppTokenCacheWrapper(ITokenCache appTokenCache)
            {
                appTokenCache.SetBeforeAccess(AppTokenCacheBeforeAccessNotification);
                appTokenCache.SetBeforeWrite(AppTokenCacheBeforeWriteNotification);
                appTokenCache.SetAfterAccess(AppTokenCacheAfterAccessNotification);
            }

            private void AppTokenCacheBeforeAccessNotification(TokenCacheNotificationArgs args)
            {
                args.TokenCache.DeserializeMsalV3(appTokenCache);
            }

            private void AppTokenCacheBeforeWriteNotification(TokenCacheNotificationArgs args)
            {
            }

            private void AppTokenCacheAfterAccessNotification(TokenCacheNotificationArgs args)
            {
                if (args.HasStateChanged)
                {
                    appTokenCache = args.TokenCache.SerializeMsalV3();
                }
            }
        }

        private class UserTokenCacheWrapper
        {
            private readonly ClaimsPrincipal user;
            private static readonly IDictionary<string, byte[]> userTokenCache = new Dictionary<string, byte[]>();

            public UserTokenCacheWrapper(ITokenCache userTokenCache, ClaimsPrincipal user)
            {
                this.user = user;
                userTokenCache.SetBeforeAccess(UserTokenCacheBeforeAccessNotification);
                userTokenCache.SetBeforeWrite(UserTokenCacheBeforeWriteNotification);
                userTokenCache.SetAfterAccess(UserTokenCacheAfterAccessNotification);
            }

            public static void RemoveUser(ClaimsPrincipal user)
            {
                var userKey = user.GetAccountId();
                if (userTokenCache.ContainsKey(userKey))
                {
                    userTokenCache.Remove(userKey);
                }
            }

            private void UserTokenCacheBeforeAccessNotification(TokenCacheNotificationArgs args)
            {
                var cacheKey = GetCacheKey(args);
                if (!string.IsNullOrEmpty(cacheKey) && userTokenCache.ContainsKey(cacheKey))
                {
                    args.TokenCache.DeserializeMsalV3(userTokenCache[cacheKey]);
                }
            }

            private void UserTokenCacheBeforeWriteNotification(TokenCacheNotificationArgs args)
            {
            }

            private void UserTokenCacheAfterAccessNotification(TokenCacheNotificationArgs args)
            {
                if (args.HasStateChanged)
                {
                    userTokenCache[GetCacheKey(args)] = args.TokenCache.SerializeMsalV3();
                }
            }

            private string GetCacheKey(TokenCacheNotificationArgs args)
            {
                // The user's account identifier is used as the cache key, and can either be found
                // in the requested cache notification (e.g. when redeeming the authorization code
                // for an access token), or in the current user's claims (when the user is already
                // authenticated).
                var accountId = args.Account?.HomeAccountId?.Identifier;
                return string.IsNullOrEmpty(accountId) ? this.user.GetAccountId() : accountId;
            }
        }
    }
}