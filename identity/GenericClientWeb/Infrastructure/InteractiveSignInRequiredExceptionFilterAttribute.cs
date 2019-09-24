using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Identity.Client;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;

namespace GenericClientWeb.Infrastructure
{
    public class InteractiveSignInRequiredExceptionFilterAttribute : ExceptionFilterAttribute
    {
        public const string MsalUiRequiredExceptionErrorCodeRequestedScopeMissing = "requested_scope_missing"; // A custom error code to signal that a requested scope was not granted (likely because it was not previously consented to).
        public string[] Scopes { get; set; }

        public override void OnException(ExceptionContext context)
        {
            if (ShouldUserReauthenticate(context.Exception))
            {
                var properties = new AuthenticationProperties();

                // Set the scopes to request, including the scopes that the MSAL token provider needs.
                var scopesToRequest = new List<string> { OpenIdConnectScope.OpenIdProfile, OpenIdConnectScope.OfflineAccess };
                if (this.Scopes != null && this.Scopes.Any())
                {
                    // Use the MSAL token provider to replace scope placeholders with their actual values from configuration.
                    var msalTokenProvider = context.HttpContext.RequestServices.GetRequiredService<MsalTokenProvider>();
                    scopesToRequest.AddRange(msalTokenProvider.GetFullyQualifiedScopes(this.Scopes));
                }
                properties.SetParameter(OpenIdConnectParameterNames.Scope, scopesToRequest);

                // Try to avoid displaying the "pick an account" dialog to the user if we already know who they are.
                properties.SetParameter(OpenIdConnectParameterNames.LoginHint, context.HttpContext.User.GetLoginHint());
                properties.SetParameter(OpenIdConnectParameterNames.DomainHint, context.HttpContext.User.GetDomainHint());

                context.Result = new ChallengeResult(properties);
                context.ExceptionHandled = true;
            }

            base.OnException(context);
        }

        private static bool ShouldUserReauthenticate(Exception exc)
        {
            var msalUiRequiredException = exc as MsalUiRequiredException;
            if (msalUiRequiredException == null)
            {
                msalUiRequiredException = exc?.InnerException as MsalUiRequiredException;
            }

            if (msalUiRequiredException == null)
            {
                return false;
            }

            if (msalUiRequiredException.ErrorCode == MsalUiRequiredExceptionErrorCodeRequestedScopeMissing)
            {
                // A custom error code was used to explicitly signal that an interactive flow should be triggered.
                return true;
            }

            if (msalUiRequiredException.ErrorCode == MsalError.UserNullError)
            {
                // If the error code is "user_null", this indicates a cache problem.
                // When calling an [Authenticate]-decorated controller we expect an authenticated
                // user and therefore its account should be in the cache. However in the case of an
                // InMemoryCache, the cache could be empty if the server was restarted. This is why
                // the null_user exception is thrown.
                return true;
            }

            if (msalUiRequiredException.ErrorCode == MsalError.InvalidGrantError
                && msalUiRequiredException.Message.Contains("AADSTS65001", StringComparison.OrdinalIgnoreCase)
                && msalUiRequiredException.ResponseBody.Contains("consent_required", StringComparison.OrdinalIgnoreCase))
            {
                // The grant was invalid with a "suberror" indicating that consent is required.
                // This is typically the case with incremental consent, when requesteing an access token
                // for a permission that was not yet consented to.
                return true;
            }

            return false;
        }
    }
}