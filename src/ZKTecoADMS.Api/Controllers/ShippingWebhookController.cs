using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Services.Shipping;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Webhook trạng thái vận đơn từ hãng — không yêu cầu JWT.</summary>
[ApiController]
[Route("api/webhooks/shipping")]
[AllowAnonymous]
public class ShippingWebhookController(
    PosShippingService shipping,
    ILogger<ShippingWebhookController> logger) : ControllerBase
{
    [HttpPost("ghn")]
    public async Task<IActionResult> Ghn(CancellationToken ct)
    {
        using var reader = new StreamReader(Request.Body);
        var raw = await reader.ReadToEndAsync(ct);
        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
            var root = doc.RootElement;
            var data = root.TryGetProperty("Data", out var d) ? d
                : root.TryGetProperty("data", out var d2) ? d2 : root;
            var tracking = data.TryGetProperty("OrderCode", out var oc) ? oc.GetString()
                : data.TryGetProperty("order_code", out var oc2) ? oc2.GetString() : null;
            var status = data.TryGetProperty("Status", out var st) ? st.GetString()
                : data.TryGetProperty("status", out var st2) ? st2.GetString()
                : data.TryGetProperty("StatusText", out var st3) ? st3.GetString() : null;
            if (string.IsNullOrWhiteSpace(status) && data.TryGetProperty("StatusName", out var sn))
                status = sn.GetString();

            var ok = await shipping.ApplyWebhookStatusAsync("Ghn", tracking, tracking, status, ct);
            return Ok(new { code = ok ? 200 : 404, message = ok ? "ok" : "order not found" });
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "GHN shipping webhook failed");
            return Ok(new { code = 200, message = "accepted" });
        }
    }

    [HttpPost("ghtk")]
    public async Task<IActionResult> Ghtk(CancellationToken ct)
    {
        using var reader = new StreamReader(Request.Body);
        var raw = await reader.ReadToEndAsync(ct);
        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
            var root = doc.RootElement;
            var label = root.TryGetProperty("label_id", out var l) ? l.GetString()
                : root.TryGetProperty("label", out var l2) ? l2.GetString()
                : root.TryGetProperty("order", out var o) && o.TryGetProperty("label", out var l3)
                    ? l3.GetString()
                    : null;
            var status = root.TryGetProperty("status_text", out var st) ? st.GetString()
                : root.TryGetProperty("status", out var st2) ? st2.GetRawText().Trim('"') : null;
            var ok = await shipping.ApplyWebhookStatusAsync("Ghtk", label, label, status, ct);
            return Ok(new { success = true, updated = ok });
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "GHTK shipping webhook failed");
            return Ok(new { success = true });
        }
    }

    [HttpPost("{carrier}")]
    public async Task<IActionResult> Generic(string carrier, CancellationToken ct)
    {
        using var reader = new StreamReader(Request.Body);
        var raw = await reader.ReadToEndAsync(ct);
        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
            var root = doc.RootElement;
            var tracking = root.TryGetProperty("trackingCode", out var t) ? t.GetString()
                : root.TryGetProperty("tracking_code", out var t2) ? t2.GetString()
                : root.TryGetProperty("order_id", out var oid) ? oid.GetString() : null;
            var status = root.TryGetProperty("status", out var st) ? st.GetString()
                : root.TryGetProperty("statusText", out var st2) ? st2.GetString() : null;
            var ok = await shipping.ApplyWebhookStatusAsync(carrier, tracking, tracking, status, ct);
            return Ok(new { ok });
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Shipping webhook {Carrier} failed", carrier);
            return Ok(new { ok = true });
        }
    }
}
