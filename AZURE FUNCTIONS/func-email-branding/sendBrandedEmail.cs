using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Text.Json;

namespace Takeda.SendBrandedEmail;

public class sendBrandedEmail
{
    private readonly ILogger<sendBrandedEmail> _logger;
    private readonly string _basePath;

    public sendBrandedEmail(ILogger<sendBrandedEmail> logger)
    {
        _logger = logger;
        // AppContext.BaseDirectory is the most reliable way to find the bin/execution folder
        // in both local development and deployed Azure environments.
        _basePath = AppContext.BaseDirectory;
    }

    [Function("sendBrandedEmail")]
    public async Task<IActionResult> Run([HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequest req)
    {
        _logger.LogInformation("Processing branded email request...");

        try 
        {
            using var reader = new StreamReader(req.Body);
            var body = await reader.ReadToEndAsync();
            var jsonDoc = JsonDocument.Parse(body);

            // Safe extraction with null coalescing
            var identifier = jsonDoc.RootElement.GetProperty("data").GetProperty("otpContext").GetProperty("identifier").GetString() ?? string.Empty;
            var oneTimeCode = jsonDoc.RootElement.GetProperty("data").GetProperty("otpContext").GetProperty("oneTimeCode").GetString() ?? string.Empty;
            var clientId = jsonDoc.RootElement.GetProperty("data").GetProperty("authenticationContext").GetProperty("clientServicePrincipal").GetProperty("appId").GetString() ?? string.Empty;

            // Kick off background task to avoid blocking the Auth flow
            _ = Task.Run(() => SendBrandedEmailAsync(identifier, oneTimeCode, clientId));

            // Return required response immediately to unblock Azure AD / Entra ID
            var response = new
            {
                data = new Dictionary<string, object>
                {
                    { "@odata.type", "microsoft.graph.OnOtpSendResponseData" },
                    { "actions", new[]
                        {
                            new Dictionary<string, string>
                            {
                                { "@odata.type", "microsoft.graph.OtpSend.continueWithDefaultBehavior" }
                            }
                        }
                    }
                }
            };

            return new OkObjectResult(response);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error parsing request body");
            return new BadRequestObjectResult("Invalid request format");
        }
    }

    private async Task SendBrandedEmailAsync(string identifier, string oneTimeCode, string clientId)
    {
        // 1. Initial Trace: Log the incoming data immediately for manual testing/verification
        _logger.LogInformation("[TRACE] Starting email prep. ID: {identifier} | OTP: {oneTimeCode} | Client: {clientId}",
            identifier, oneTimeCode, clientId);

        try
        {
            // Use Path.Combine with the BaseDirectory set in the constructor
            var templatePath = Path.Combine(_basePath, "templates", $"{clientId}.html");
            bool usingDefault = false;

            // 2. Log path resolution for debugging
            _logger.LogDebug("[PATH] Searching for template at: {templatePath}", templatePath);

            if (!File.Exists(templatePath))
            {
                _logger.LogWarning("[MISSING] Branded template not found for {clientId}. Falling back to default.html.", clientId);
                templatePath = Path.Combine(_basePath, "templates", "default.html");
                usingDefault = true;

                if (!File.Exists(templatePath))
                {
                    // 3. Critical failure logging
                    _logger.LogError("[CRITICAL] Default template missing at {templatePath}. Check 'Copy to Output' settings.", templatePath);
                    return;
                }
            }

            // 4. Load the file
            _logger.LogInformation("[LOAD] Using {status} template: {fileName}",
                usingDefault ? "DEFAULT" : "BRANDED", Path.GetFileName(templatePath));

            var template = await File.ReadAllTextAsync(templatePath);

            // 5. Replace placeholders
            template = template.Replace("{{identifier}}", identifier)
                               .Replace("{{oneTimeCode}}", oneTimeCode);

            // 6. Final Result Log: Structured for easy copy-paste from Log Stream
            _logger.LogInformation("--------------------------------------------------");
            _logger.LogInformation("EMAIL READY FOR: {identifier}", identifier);
            _logger.LogInformation("VERIFICATION CODE: {oneTimeCode}", oneTimeCode);
            _logger.LogInformation("FULL HTML BODY PREVIEW:\n{template}", template);
            _logger.LogInformation("--------------------------------------------------");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[ERROR] Failure processing email for {identifier}. Message: {msg}",
                identifier, ex.Message);
        }
    }
}
