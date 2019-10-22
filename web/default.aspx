<%-- A web page that you can simply drop in any ASP.NET host (like IIS or Azure App Service) to get a lot of info on the web server where it's running --%>
<%@ Page Language="C#" %>
<%@ Import Namespace="System.Data.SqlClient" %>
<%@ Import Namespace="System.Diagnostics" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Net" %>
<%@ Import Namespace="System.Runtime" %>
<%@ Import Namespace="System.Runtime.InteropServices" %>
<%@ Import Namespace="System.Security.Claims" %>
<!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.1.3/css/bootstrap.min.css" integrity="sha384-MCw98/SFnGE8fJT3GXwEOngsV7Zt27NXFoaoApmYm81iuXoPkFOJwJ8ERdknLPMO" crossorigin="anonymous">
    <title>Web Server Info</title>
</head>
<body style="<%: GetBodyStyle() %>">
    <div class="container">
        <h1>Web Server Info</h1>
        <ol class="list-inline">
            <li class="list-inline-item">&raquo; <a href="#request">Request</a></li>
            <li class="list-inline-item">&raquo; <a href="#http-headers">HTTP Headers</a></li>
            <li class="list-inline-item">&raquo; <a href="#identity">Identity</a></li>
            <li class="list-inline-item">&raquo; <a href="#app-settings">App Settings</a></li>
            <li class="list-inline-item">&raquo; <a href="#connection-strings">Connection Strings</a></li>
            <li class="list-inline-item">&raquo; <a href="#system">System</a></li>
            <li class="list-inline-item">&raquo; <a href="#server-variables">Server Variables</a></li>
            <li class="list-inline-item">&raquo; <a href="#environment-variables">Environment Variables</a></li>
            <li class="list-inline-item">&raquo; <a href="#dns-lookup">DNS Lookup</a></li>
            <li class="list-inline-item">&raquo; <a href="#outbound-http-request">Outbound HTTP Request</a></li>
            <li class="list-inline-item">&raquo; <a href="#outbound-sql-connection">Outbound SQL Connection</a></li>
        </ol>

        <% RenderHeader("Request", "request"); %>
        <% RenderTable(GetRequestInfo()); %>

        <% RenderHeader("HTTP Headers", "http-headers"); %>
        <% RenderTable(GetHttpHeadersInfo()); %>

        <% RenderHeader("Identity", "identity"); %>
        <% RenderTable(GetIdentityInfo()); %>

        <% RenderHeader("App Settings", "app-settings"); %>
        <p class="text-muted">You can change this page's background color by setting the <code>BackgroundColor</code> App Setting.</p>
        <% RenderTable(ConfigurationManager.AppSettings.AllKeys.OrderBy(k => k).Select(k => new KeyValuePair<string, string>(k, ConfigurationManager.AppSettings[k]))); %>

        <% RenderHeader("Connection Strings", "connection-strings"); %>
        <% RenderTable(ConfigurationManager.ConnectionStrings.Cast<ConnectionStringSettings>().Select(k => new KeyValuePair<string, string>(k.Name, k.ConnectionString))); %>

        <% RenderHeader("System", "system"); %>
        <% RenderTable(GetSystemInfo()); %>

        <% RenderHeader("Server Variables", "server-variables"); %>
        <% RenderTable(GetServerVariablesInfo()); %>

        <% RenderHeader("Environment Variables", "environment-variables"); %>
        <% RenderTable(Environment.GetEnvironmentVariables().Keys.Cast<string>().OrderBy(k => k).Select(k => new KeyValuePair<string, string>(k, Environment.GetEnvironmentVariable(k)))); %>

        <% RenderHeader("DNS Lookup", "dns-lookup"); %>
        <% RenderDnsLookup(); %>

        <% RenderHeader("Outbound HTTP Request", "outbound-http-request"); %>
        <% RenderOutboundHttpRequest(); %>

        <% RenderHeader("Outbound SQL Connection", "outbound-sql-connection"); %>
        <% RenderOutboundSqlConnection(); %>
    </div>
</body>
</html>
<%
    System.Net.ServicePointManager.SecurityProtocol = System.Net.SecurityProtocolType.Tls12;
%>
<script runat="server">
    
    protected void RenderHeader(string name, string anchor)
    {
        Response.Write(Environment.NewLine);
        Response.Write("<a name=\"" + anchor + "\"></a>");
        Response.Write(Environment.NewLine);
        Response.Write("<h3>" + name + "</h3>");
        Response.Write(Environment.NewLine);
    }

    protected void RenderTable(IEnumerable<KeyValuePair<string, string>> values)
    {
        Response.Write("<table class=\"table table-striped table-hover table-sm table-bordered\">");
        Response.Write(Environment.NewLine);
        foreach (var item in values)
        {
            Response.Write("<tr>");
            Response.Write("<td>" + HttpUtility.HtmlEncode(item.Key) + "</td>");
            Response.Write("<td>" + HttpUtility.HtmlEncode(item.Value) + "</td>");
            Response.Write("</tr>");
        Response.Write(Environment.NewLine);
        }
        Response.Write("</table>");
        Response.Write(Environment.NewLine);
    }

    protected string GetBodyStyle()
    {
        var backgroundColor = ConfigurationManager.AppSettings["BackgroundColor"];
        if (!string.IsNullOrWhiteSpace(backgroundColor))
        {
            return "background-color: " + backgroundColor + ";";
        }
        return string.Empty;
    }
    
    protected IList<KeyValuePair<string, string>> GetRequestInfo()
    {
        var info = new List<KeyValuePair<string, string>>();
        info.Add(new KeyValuePair<string, string>("Application Path", Request.ApplicationPath));
        info.Add(new KeyValuePair<string, string>("Client Certificate Serial Number", Request.ClientCertificate == null ? null : Request.ClientCertificate.SerialNumber));
        info.Add(new KeyValuePair<string, string>("HTTP Method", Request.HttpMethod));
        info.Add(new KeyValuePair<string, string>("Is Secure Connection", Request.IsSecureConnection.ToString()));
        info.Add(new KeyValuePair<string, string>("Physical Application Path", Request.PhysicalApplicationPath));
        info.Add(new KeyValuePair<string, string>("Physical Path", Request.PhysicalPath));
        info.Add(new KeyValuePair<string, string>("URL", Request.Url.ToString()));
        info.Add(new KeyValuePair<string, string>("Referrer", Request.UrlReferrer == null ? null : Request.UrlReferrer.ToString()));
        return info;
    }

    protected IList<KeyValuePair<string, string>> GetHttpHeadersInfo()
    {
        var info = new List<KeyValuePair<string, string>>();
        foreach (var key in Request.Headers.AllKeys.OrderBy(k => k))
        {
            foreach (var value in Request.Headers.GetValues(key))
            {
                info.Add(new KeyValuePair<string, string>(key, value));
            }
        }
        return info;
    }

    protected IList<KeyValuePair<string, string>> GetIdentityInfo()
    {
        var info = new List<KeyValuePair<string, string>>();
        var identity = (ClaimsIdentity)User.Identity;
        info.Add(new KeyValuePair<string, string>("User Name", User.Identity.Name));
        info.Add(new KeyValuePair<string, string>("User Is Authenticated", User.Identity.IsAuthenticated.ToString()));
        info.Add(new KeyValuePair<string, string>("User Authentication Type", User.Identity.AuthenticationType));
        foreach (var claim in identity.Claims.OrderBy(c => c.Type))
        {
            info.Add(new KeyValuePair<string, string>(claim.Type, claim.Value));
        }
        return info;
    }

    protected IList<KeyValuePair<string, string>> GetSystemInfo()
    {
        var info = new List<KeyValuePair<string, string>>();
        info.Add(new KeyValuePair<string, string>("Machine Name", Environment.MachineName));
        info.Add(new KeyValuePair<string, string>("64-bit OS", Environment.Is64BitOperatingSystem.ToString()));
        info.Add(new KeyValuePair<string, string>("64-bit Process", Environment.Is64BitProcess.ToString()));
        info.Add(new KeyValuePair<string, string>("OS Version", Environment.OSVersion.ToString()));
        info.Add(new KeyValuePair<string, string>("Processor Count", Environment.ProcessorCount.ToString()));
        info.Add(new KeyValuePair<string, string>("CLR Version", Environment.Version.ToString()));
        info.Add(new KeyValuePair<string, string>("Logged On User Domain", Environment.UserDomainName));
        info.Add(new KeyValuePair<string, string>("Logged On User Name", Environment.UserName));
        info.Add(new KeyValuePair<string, string>("Garbage Collection Mode", GCSettings.IsServerGC ? "Server" : "Workstation"));
        info.Add(new KeyValuePair<string, string>("System Time", Format(DateTimeOffset.UtcNow)));
        info.Add(new KeyValuePair<string, string>("System Uptime", GetSystemUptime().ToString()));
        info.Add(new KeyValuePair<string, string>("System Start Time", Format(DateTime.UtcNow - GetSystemUptime())));
        info.Add(new KeyValuePair<string, string>("Process Uptime", GetProcessUptime().ToString()));
        info.Add(new KeyValuePair<string, string>("Process Start Time", Format(DateTime.UtcNow - GetProcessUptime())));
        return info;
    }

    protected IList<KeyValuePair<string, string>> GetServerVariablesInfo()
    {
        var info = new List<KeyValuePair<string, string>>();
        foreach (var key in Request.ServerVariables.AllKeys.OrderBy(k => k))
        {
            foreach (var value in Request.ServerVariables.GetValues(key))
            {
                info.Add(new KeyValuePair<string, string>(key, value));
            }
        }
        return info;
    }

    protected void RenderDnsLookup()
    {
        var dnsLookup = Request["dnsLookup"];

        Response.Write(Environment.NewLine);
        Response.Write(@"
        <form method=""POST"" action=""#dns-lookup"">
            <p class=""text-muted"">Allows you to perform a DNS lookup from the web server and render the results below.</p>
            <div class=""form-group"">
                <label for=""dnsLookup"">Host name (or IP address)</label>
                <input type=""text"" name=""dnsLookup"" id=""dnsLookup"" value=""" + dnsLookup + @""" class=""form-control"" />
            </div>
            <div class=""form-group"">
                <input type=""submit"" value=""Submit"" class=""btn btn-primary"" />
            </div>
        </form>
");

        if (!string.IsNullOrWhiteSpace(dnsLookup))
        {
            var result = string.Empty;
            try
            {
                var host = Dns.GetHostEntry(dnsLookup);
                var resultBuilder = new StringBuilder();
                resultBuilder.AppendFormat("Host name: \"{0}\"", host.HostName).AppendLine();
                resultBuilder.AppendFormat("IP Addresses: " + string.Join(", ", (object[])host.AddressList)).AppendLine();
                if (host.Aliases != null && host.Aliases.Length > 0)
                {
                    resultBuilder.AppendFormat("Aliases: " + string.Join(", ", host.Aliases)).AppendLine();
                }
                result = resultBuilder.ToString().TrimEnd();
            }
            catch (Exception exc)
            {
                result = HttpUtility.HtmlEncode(exc.ToString());
            }
            RenderResultCard(result);
        }
    }
    
    protected void RenderOutboundHttpRequest()
    {
        var requestUrl = Request["requestUrl"];
        var requestHostName = Request["requestHostName"];

        Response.Write(Environment.NewLine);
        Response.Write(@"
        <form method=""POST"" action=""#outbound-http-request"">
            <p class=""text-muted"">Allows you to perform an HTTP request from the web server and render the results below.</p>
            <div class=""form-group"">
                <label for=""requestUrl"">URL</label>
                <input type=""text"" name=""requestUrl"" id=""requestUrl"" value=""" + requestUrl + @""" class=""form-control"" />
            </div>
            <div class=""form-group"">
                <label for=""requestHostName"">Host Name (optional)</label>
                <input type=""text"" name=""requestHostName"" id=""requestHostName"" value=""" + requestHostName + @""" class=""form-control"" />
            </div>
            <div class=""form-group"">
                <input type=""submit"" value=""Submit"" class=""btn btn-primary"" />
            </div>
        </form>
");

        if (!string.IsNullOrWhiteSpace(requestUrl))
        {
            var result = string.Empty;
            try
            {
                var request = (HttpWebRequest)WebRequest.Create(requestUrl);
                if (!string.IsNullOrWhiteSpace(requestHostName))
                {
                    request.Host = requestHostName;
                }
                using (var response = (HttpWebResponse)request.GetResponse())
                using (var dataStream = response.GetResponseStream())
                using (var reader = new StreamReader(dataStream))
                {
                    var responseFromServer = reader.ReadToEnd();
                    result = HttpUtility.HtmlEncode(responseFromServer);
                }
            }
            catch (Exception exc)
            {
                result = HttpUtility.HtmlEncode(exc.ToString());
            }
            RenderResultCard(result);
        }
    }

    protected void RenderOutboundSqlConnection()
    {
        var sqlConnectionString = Request["sqlConnectionString"];
        var sqlQuery = Request["sqlQuery"] == null ? "SELECT CONNECTIONPROPERTY('client_net_address')" : Request["sqlQuery"];

        Response.Write(Environment.NewLine);
        Response.Write(@"
        <form method=""POST"" action=""#outbound-sql-connection"">
            <p class=""text-muted"">Allows you to perform a (scalar) query on a SQL Connection from the web server and render the results below.</p>
            <div class=""form-group"">
                <label for=""sqlConnectionString"">SQL Connection String</label>
                <input type=""password"" name=""sqlConnectionString"" id=""sqlConnectionString"" value=""" + sqlConnectionString + @""" class=""form-control"" autocomplete=""off"" />
            </div>
            <div class=""form-group"">
                <label for=""sqlQuery"">Query</label>
                <input type=""text"" name=""sqlQuery"" id=""sqlQuery"" value=""" + sqlQuery + @""" class=""form-control"" />
            </div>
            <div class=""form-group"">
                <input type=""submit"" value=""Submit"" class=""btn btn-primary"" />
            </div>
        </form>
");

        if (!string.IsNullOrWhiteSpace(sqlConnectionString))
        {
            var result = string.Empty;
            try
            {
                using (var connection = new SqlConnection(sqlConnectionString))
                using (var command = connection.CreateCommand())
                {
                    connection.Open();
                    command.CommandText = sqlQuery;
                    result = HttpUtility.HtmlEncode(command.ExecuteScalar());
                }
            }
            catch (Exception exc)
            {
                result = HttpUtility.HtmlEncode(exc.ToString());
            }
            RenderResultCard(result);
        }
    }
    
    protected void RenderResultCard(string result)
    {
        Response.Write(Environment.NewLine);
            Response.Write("<h5>Result at " + Format(DateTimeOffset.UtcNow) + "</h5>");
            Response.Write(Environment.NewLine);
            Response.Write("<div class=\"card\"><div class=\"card-body\"><pre>");
            Response.Write(Environment.NewLine);
            Response.Write(result);
            Response.Write(Environment.NewLine);
            Response.Write("</pre></div></div>");
            Response.Write(Environment.NewLine);
    }

    [DllImport("kernel32")]
    extern static UInt64 GetTickCount64();

    public static TimeSpan GetSystemUptime()
    {
        return TimeSpan.FromMilliseconds(GetTickCount64());
    }
    
    public static TimeSpan GetProcessUptime()
    {
        return (DateTime.Now - Process.GetCurrentProcess().StartTime);
    }

    public static string Format(DateTime value)
    {
        return value.ToString("u") + " (UTC)";
    }

    public static string Format(DateTimeOffset value)
    {
        return value.ToString("u") + " (UTC)";
    }

</script>