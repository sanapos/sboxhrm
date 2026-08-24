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
        // Docs: form-urlencoded hoặc JSON; bảo mật qua ?hash= trên URL webhook.
        string raw;
        if (Request.HasFormContentType)
        {
            var form = await Request.ReadFormAsync(ct);
            var map = form.Keys.ToDictionary(k => k, k => form[k].ToString(), StringComparer.OrdinalIgnoreCase);
            raw = JsonSerializer.Serialize(map);
        }
        else
        {
            using var reader = new StreamReader(Request.Body);
            raw = await reader.ReadToEndAsync(ct);
        }

        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
            var root = doc.RootElement;

            var label = GetStr(root, "label_id", "label", "Label");
            var partnerId = GetStr(root, "partner_id", "partnerId", "PartnerId");
            var statusText = GetStr(root, "status_text", "statusText", "reason");
            int? statusId = null;
            if (root.TryGetProperty("status_id", out var sid) ||
                root.TryGetProperty("statusId", out sid) ||
                root.TryGetProperty("status", out sid))
            {
                if (sid.ValueKind == JsonValueKind.Number && sid.TryGetInt32(out var n))
                    statusId = n;
                else if (sid.ValueKind == JsonValueKind.String && int.TryParse(sid.GetString(), out var ns))
                    statusId = ns;
            }

            var hash = Request.Query["hash"].FirstOrDefault();
            if (!await shipping.ValidateGhtkWebhookHashAsync(hash, label, partnerId, ct))
            {
                logger.LogWarning("GHTK webhook rejected — hash không khớp");
                return Unauthorized(new { success = false, message = "Unauthorized" });
            }

            var ok = await shipping.ApplyGhtkWebhookAsync(label, partnerId, statusId, statusText, ct);
            return Ok(new { success = true, updated = ok });
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "GHTK shipping webhook failed");
            return Ok(new { success = true });
        }
    }

    static string? GetStr(JsonElement root, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (!root.TryGetProperty(key, out var p)) continue;
            if (p.ValueKind == JsonValueKind.String)
            {
                var s = p.GetString()?.Trim();
                if (!string.IsNullOrWhiteSpace(s)) return s;
            }
            else if (p.ValueKind is JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False)
            {
                var s = p.GetRawText().Trim('"');
                if (!string.IsNullOrWhiteSpace(s)) return s;
            }
        }
        return null;
    }

    /// <summary>Viettel Post — payload DATA.ORDER_NUMBER, DATA.ORDER_STATUS, DATA.STATUS_NAME.</summary>
    [HttpPost("viettelpost")]
    public async Task<IActionResult> ViettelPost(CancellationToken ct)
    {
        using var reader = new StreamReader(Request.Body);
        var raw = await reader.ReadToEndAsync(ct);
        try
        {
            using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(raw) ? "{}" : raw);
            var root = doc.RootElement;
            var data = root.TryGetProperty("DATA", out var d) ? d
                : root.TryGetProperty("data", out var d2) ? d2 : root;

            var tracking = data.TryGetProperty("ORDER_NUMBER", out var on) ? on.GetString()
                : data.TryGetProperty("order_number", out var on2) ? on2.GetString() : null;
            var statusName = data.TryGetProperty("STATUS_NAME", out var sn) ? sn.GetString()
                : data.TryGetProperty("status_name", out var sn2) ? sn2.GetString() : null;
            int? statusCode = null;
            if (data.TryGetProperty("ORDER_STATUS", out var os))
            {
                if (os.ValueKind == JsonValueKind.Number && os.TryGetInt32(out var n))
                    statusCode = n;
                else if (os.ValueKind == JsonValueKind.String && int.TryParse(os.GetString(), out var ns))
                    statusCode = ns;
            }

            var auth = Request.Headers.Authorization.ToString();
            string? bodyToken = null;
            if (root.TryGetProperty("TOKEN", out var tk) && tk.ValueKind == JsonValueKind.String)
                bodyToken = tk.GetString();
            else if (root.TryGetProperty("token", out var tk2) && tk2.ValueKind == JsonValueKind.String)
                bodyToken = tk2.GetString();

            if (!await shipping.ValidateViettelPostWebhookAuthAsync(auth, bodyToken, tracking, ct))
            {
                logger.LogWarning("ViettelPost webhook rejected — Authorization không khớp secret");
                return Unauthorized(new { status = 401, error = true, message = "Unauthorized" });
            }

            var ok = await shipping.ApplyViettelPostWebhookAsync(
                tracking, statusCode, statusName, ct);
            // VTP yêu cầu HTTP 200 — body đơn giản.
            return Ok(new { status = 200, error = false, message = ok ? "OK" : "order not found" });
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "ViettelPost shipping webhook failed");
            return Ok(new { status = 200, error = false, message = "accepted" });
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
