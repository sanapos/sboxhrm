using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Api.Services.PaymentGateway;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Webhook IPN từ cổng thanh toán — không yêu cầu JWT.</summary>
[ApiController]
[Route("api/webhooks/payment")]
[AllowAnonymous]
public class PaymentWebhookController(
    IPosPaymentGatewayService gateway,
    IHubContext<AttendanceHub> hub,
    ILogger<PaymentWebhookController> logger) : ControllerBase
{
    [HttpPost("tingee")]
    public async Task<IActionResult> Tingee(CancellationToken ct)
    {
        using var reader = new StreamReader(Request.Body);
        var rawBody = await reader.ReadToEndAsync(ct);
        var signature = Request.Headers["x-signature"].FirstOrDefault();
        var timestamp = Request.Headers["x-request-timestamp"].FirstOrDefault();

        try
        {
            var result = await gateway.ProcessWebhookAsync(
                PosPaymentNotifyProvider.Tingee,
                signature,
                timestamp,
                rawBody,
                hub,
                ct);

            return Ok(new { code = result.ResponseCode, message = result.Message });
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Tingee webhook processing failed");
            return Ok(new { code = "xx", message = "Internal error" });
        }
    }

    /// <summary>Route dự phòng cho cổng khác — /api/webhooks/payment/{provider}</summary>
    [HttpPost("{provider}")]
    public async Task<IActionResult> Generic(string provider, CancellationToken ct)
    {
        if (!Enum.TryParse<PosPaymentNotifyProvider>(provider, true, out var prov))
            return BadRequest(new { code = "09", message = $"Unknown provider: {provider}" });

        using var reader = new StreamReader(Request.Body);
        var rawBody = await reader.ReadToEndAsync(ct);
        var signature = Request.Headers["x-signature"].FirstOrDefault()
            ?? Request.Headers["X-Signature"].FirstOrDefault();
        var timestamp = Request.Headers["x-request-timestamp"].FirstOrDefault()
            ?? Request.Headers["X-Request-Timestamp"].FirstOrDefault();

        try
        {
            var result = await gateway.ProcessWebhookAsync(prov, signature, timestamp, rawBody, hub, ct);
            return Ok(new { code = result.ResponseCode, message = result.Message });
        }
        catch (NotImplementedException)
        {
            return Ok(new { code = "09", message = "Provider not implemented" });
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Webhook {Provider} failed", provider);
            return Ok(new { code = "xx", message = "Internal error" });
        }
    }
}
