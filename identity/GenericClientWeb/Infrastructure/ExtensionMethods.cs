using System;
using System.Security.Claims;

namespace GenericClientWeb.Infrastructure
{
    public static class ExtensionMethods
    {
        public static string GetAccountId(this ClaimsPrincipal user)
        {
            return user.FindFirst(Constants.ClaimTypes.AccountId)?.Value;
        }
        
        public static string GetLoginHint(this ClaimsPrincipal user)
        {
            return user.FindFirst(Constants.ClaimTypes.PreferredUsername)?.Value;
        }

        public static string GetTenantId(this ClaimsPrincipal user)
        {
            return user.FindFirst(Constants.ClaimTypes.TenantId)?.Value;
        }

        public static string GetDomainHint(this ClaimsPrincipal user)
        {
            // This is the well-known Tenant ID for Microsoft Accounts (MSA).
            const string msaTenantId = "9188040d-6c67-4c5b-b112-36a304b66dad";
            var tenantId = user.GetTenantId();
            return string.IsNullOrWhiteSpace(tenantId) ? null : string.Equals(tenantId, msaTenantId, StringComparison.OrdinalIgnoreCase) ? "consumers" : "organizations";
        }
    }
}