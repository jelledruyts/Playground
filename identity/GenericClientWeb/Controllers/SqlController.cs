using System;
using System.Data.SqlClient;
using System.Threading.Tasks;
using GenericClientWeb.Infrastructure;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;

namespace GenericClientWeb.Controllers
{
    [Authorize]
    public class SqlController : Controller
    {
        // The OAuth 2.0 scope used by the Azure SQL Database service.
        // NOTE: When using MSAL and the Azure AD v2.0 endpoint, the double forward slash // is required,
        // see https://docs.microsoft.com/en-us/azure/active-directory/develop/msal-net-migration#warning-should-you-have-one-or-two-slashes-in-the-scope-corresponding-to-a-v10-web-api.
        private const string AzureSqlDatabaseScopeForUser = "https://database.windows.net//user_impersonation";
        private const string AzureSqlDatabaseScopeForApp = "https://database.windows.net//.default";
        private readonly MsalTokenProvider tokenProvider;
        private readonly IConfiguration configuration;

        public SqlController(MsalTokenProvider tokenProvider, IConfiguration configuration)
        {
            this.tokenProvider = tokenProvider;
            this.configuration = configuration;
        }

        [Route("[controller]")]
        public IActionResult Index()
        {
            return View();
        }

        [Route("[controller]/[action]")]
        [InteractiveSignInRequiredExceptionFilter(Scopes = new[] { AzureSqlDatabaseScopeForUser })]
        public async Task<IActionResult> ConnectOnBehalfOfUser()
        {
            // This connects to the SQL database using an Azure AD token representing the currently signed in user.
            // See https://docs.microsoft.com/en-us/azure/sql-database/sql-database-aad-authentication-configure#azure-ad-token.
            // You need to complete the following steps in order to make this work:
            // - Create an Azure SQL Database, and ensure that the firewall allows access from your app
            // - Set up an Azure AD admin for the Azure SQL Database
            // - Using that Azure AD admin account, create a contained database user for the other users accessing the database, e.g.:
            //     CREATE USER [myuser@mydomain.onmicrosoft.com] FROM EXTERNAL PROVIDER;
            // - Verify with:
            //     SELECT * FROM sys.database_principals;
            // - Configure the connection string in the app configuration as "Sql:ConnectionString"
            //     NOTE that the connection string should NOT contain any user information because the user will be set
            //     via the access token, e.g. the connection string could be simply:
            //     "Server=tcp:myserver.database.windows.net,1433;Initial Catalog=mydatabase;Connection Timeout=30;"
            // - On the app registration representing this application in Azure AD, add an API permission to access Azure SQL Database (represented as "https://database.windows.net/")
            //     In the Azure Portal, you can do this by searching for "Azure SQL Database" as the API and then selecting
            //     the delegated permission "user_impersonation" (displayed as "Access Azure SQL DB and Data Warehouse")
            //     which represents the full scope value of "https://database.windows.net//user_impersonation".
            //     If "Azure SQL Database" is not listed in the search results, ensure you have first created at least one contained
            //     Azure AD database user.
            //     Alternatively, add the permission via the app manifest in the "requiredResourceAccess" property:
            //       {
            //         "resourceAppId": "022907d3-0f1b-48f7-badc-1ba6abab6d66",
            //         "resourceAccess": [
            //           {
            //             "id": "c39ef2d1-04ce-46dc-8b5f-e9a5c60f0fc9",
            //             "type": "Scope"
            //           }
            //         ]
            //      }
            // - Even though that permission is declared to NOT require admin consent, at runtime you will not be able
            //   to consent to this scope as a non-admin user. Therefore, you must grant an admin consent for this scope
            //   e.g. via the Azure Portal on the API permissions page.
            // NOTE: For web apps, this approach isn't ideal as connection pooling is performed on a per-user basis (i.e. the
            // access token is used as one of the connection pool identifiers) which can limit scalability for a web app with many users.
            // See https://docs.microsoft.com/en-us/dotnet/framework/data/adonet/sql-server-connection-pooling?view=netframework-4.8#pool-fragmentation-due-to-integrated-security.
            // This is also true for .NET Core, see https://github.com/dotnet/corefx/issues/13660#issuecomment-407429106.
            var token = await this.tokenProvider.GetTokenForUserAsync(this.HttpContext, this.User, new[] { AzureSqlDatabaseScopeForUser });
            return await ConnectAsync(token.AccessToken);
        }


        [Route("[controller]/[action]")]
        public async Task<IActionResult> ConnectOnBehalfOfApp()
        {
            // This connects to the SQL database using an Azure AD token representing the application itself.
            // See above, with the difference of having to register the app as a database container user, e.g.:
            //   CREATE USER [myappname] FROM EXTERNAL PROVIDER;
            // Retrieve an access token for the database representing the application itself.
            var token = await this.tokenProvider.GetTokenForApplicationAsync(this.HttpContext, new[] { AzureSqlDatabaseScopeForApp });
            return await ConnectAsync(token.AccessToken);
        }

        private async Task<IActionResult> ConnectAsync(string accessToken)
        {
            var connectionString = this.configuration.GetValue<string>("Sql:ConnectionString");
            if (!string.IsNullOrWhiteSpace(connectionString))
            {
                // Retrieve an access token for the database representing the currently signed in user.
                if (accessToken != null)
                {
                    try
                    {
                        // Set up a connection using the access token.
                        using (var sqlConnection = new SqlConnection(connectionString))
                        {
                            sqlConnection.AccessToken = accessToken;
                            // Execute a command that returns the current user as seen by the database.
                            using (var command = sqlConnection.CreateCommand())
                            {
                                await sqlConnection.OpenAsync();
                                command.CommandText = "SELECT SUSER_SNAME()";
                                var result = await command.ExecuteScalarAsync();
                                ViewData["SqlCurrentUser"] = result;
                            }
                        }
                    }
                    catch (Exception exc)
                    {
                        ViewData["Exception"] = exc;
                    }
                }
            }
            return View(nameof(Index));
        }
    }
}