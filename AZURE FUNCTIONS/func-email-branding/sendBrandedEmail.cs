using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using System.Text.Json;

namespace Takeda.SendBrandedEmail;

public class sendBrandedEmail
{
    private readonly ILogger<sendBrandedEmail> _logger;

    public sendBrandedEmail(ILogger<sendBrandedEmail> logger)
    {
        _logger = logger;
    }

    [Function("sendBrandedEmail")]
    public async Task<IActionResult> Run([HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequest req)
    {
        _logger.LogInformation("Processing branded email request...");

        using var reader = new StreamReader(req.Body);
        var body = await reader.ReadToEndAsync();
        var jsonDoc = JsonDocument.Parse(body);

        var identifier = jsonDoc.RootElement
            .GetProperty("data")
            .GetProperty("otpContext")
            .GetProperty("identifier").GetString() ?? string.Empty;

        var oneTimeCode = jsonDoc.RootElement
            .GetProperty("data")
            .GetProperty("otpContext")
            .GetProperty("oneTimeCode").GetString() ?? string.Empty;

        var clientId = jsonDoc.RootElement
            .GetProperty("data")
            .GetProperty("authenticationContext")
            .GetProperty("clientServicePrincipal")
            .GetProperty("appId").GetString() ?? string.Empty;

        // Kick off background task
        _ = Task.Run(() => SendBrandedEmailAsync(identifier, oneTimeCode, clientId));

        // Return required response immediately
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


    private async Task SendBrandedEmailAsync(string identifier, string oneTimeCode, string clientId)
    {
        try
        {
            var basePath = Environment.CurrentDirectory;
            var templatePath = Path.Combine(basePath, "templates", $"{clientId}.html");

            if (!File.Exists(templatePath))
            {
                _logger.LogWarning("Template not found for clientId {clientId}", clientId);
                return;
            }

            var template = await File.ReadAllTextAsync(templatePath);

            // Replace placeholders
            template = template.Replace("{{identifier}}", identifier)
                               .Replace("{{oneTimeCode}}", oneTimeCode);

            // Instead of sending via SendGrid, log details
            _logger.LogInformation("Prepared email for {identifier}", identifier);
            _logger.LogInformation("ClientId: {clientId}", clientId);
            _logger.LogInformation("Email body:\n{template}", template);

            // Here you would normally send via SendGrid
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error preparing branded email");
        }
    }
}
