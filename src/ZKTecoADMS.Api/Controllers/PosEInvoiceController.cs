using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services.EInvoice;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/einvoice")]
[Authorize]
public class PosEInvoiceController(
    ZKTecoDbContext db,
    PosEInvoiceService eInvoice,
    ILogger<PosEInvoiceController> logger) : AuthenticatedControllerBase
{
    public record EInvoiceSettingsDto(
        bool Enabled,
        string Provider,
        string ApiBaseUrl,
        string Username,
        bool HasPassword,
        string SupplierTaxCode,
        string TemplateCode,
        string InvoiceSeries,
        string InvoiceType,
        bool AskAtCheckout,
        bool DefaultIssueAtCheckout,
        string TaxMode,
        decimal DefaultTaxPercent);

    static EInvoiceSettingsDto ToDto(PosEInvoiceSetting s) => new(
        s.Enabled,
        s.Provider,
        s.ApiBaseUrl,
        s.Username,
        !string.IsNullOrEmpty(s.Password),
        s.SupplierTaxCode,
        s.TemplateCode,
        s.InvoiceSeries,
        s.InvoiceType,
        s.AskAtCheckout,
        s.DefaultIssueAtCheckout,
        s.TaxMode,
        s.DefaultTaxPercent);

    static bool TryGetProp(JsonElement root, string name, out JsonElement p)
    {
        if (root.ValueKind != JsonValueKind.Object)
        {
            p = default;
            return false;
        }
        if (root.TryGetProperty(name, out p)) return true;
        foreach (var prop in root.EnumerateObject())
        {
            if (string.Equals(prop.Name, name, StringComparison.OrdinalIgnoreCase))
            {
                p = prop.Value;
                return true;
            }
        }
        p = default;
        return false;
    }

    static string? JsonStr(JsonElement root, string name)
    {
        if (!TryGetProp(root, name, out var p)) return null;
        return p.ValueKind switch
        {
            JsonValueKind.String => p.GetString(),
            JsonValueKind.Number => p.ToString(),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            JsonValueKind.Null => null,
            _ => p.ToString(),
        };
    }

    static bool JsonBool(JsonElement root, string name, bool fallback = false)
    {
        if (!TryGetProp(root, name, out var p)) return fallback;
        return p.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.String => bool.TryParse(p.GetString(), out var b) && b,
            _ => fallback,
        };
    }

    static decimal JsonDec(JsonElement root, string name, decimal fallback = 0)
    {
        if (!TryGetProp(root, name, out var p)) return fallback;
        if (p.ValueKind == JsonValueKind.Number && p.TryGetDecimal(out var d)) return d;
        if (p.ValueKind == JsonValueKind.String &&
            decimal.TryParse(p.GetString(), System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out var s))
            return s;
        return fallback;
    }

    async Task<string> ReadBodyRawAsync()
    {
        Request.EnableBuffering();
        if (Request.Body.CanSeek)
            Request.Body.Position = 0;
        using var reader = new StreamReader(Request.Body, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);
        var raw = await reader.ReadToEndAsync();
        if (Request.Body.CanSeek)
            Request.Body.Position = 0;
        return raw ?? "";
    }

    [HttpGet("settings")]
    [RequireModulePermission("PosEInvoice", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<EInvoiceSettingsDto>>> GetSettings()
    {
        var s = await eInvoice.GetOrCreateSettingsAsync(RequiredStoreId);
        return Ok(AppResponse<EInvoiceSettingsDto>.Success(ToDto(s)));
    }

    /// <summary>Lưu cấu hình HĐĐT. PUT + POST (một số client/proxy không gửi body đúng với PUT).</summary>
    [HttpPut("settings")]
    [HttpPost("settings")]
    [RequireModulePermission("PosEInvoice", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<EInvoiceSettingsDto>>> SaveSettings()
    {
        var raw = await ReadBodyRawAsync();
        if (string.IsNullOrWhiteSpace(raw) || raw.Trim() is "{}" or "null")
        {
            logger.LogWarning("EInvoice save empty body store={StoreId} method={Method} len={Len}",
                RequiredStoreId, Request.Method, raw?.Length ?? 0);
            return BadRequest(AppResponse<EInvoiceSettingsDto>.Fail(
                "Body cấu hình HĐĐT trống — không lưu. Thử lại hoặc cập nhật app."));
        }

        JsonElement body;
        try
        {
            using var doc = JsonDocument.Parse(raw);
            body = doc.RootElement.Clone();
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "EInvoice save invalid JSON store={StoreId}", RequiredStoreId);
            return BadRequest(AppResponse<EInvoiceSettingsDto>.Fail("JSON cấu hình HĐĐT không hợp lệ"));
        }

        var incoming = new PosEInvoiceSetting
        {
            Enabled = JsonBool(body, "enabled"),
            Provider = JsonStr(body, "provider") ?? "Viettel",
            ApiBaseUrl = JsonStr(body, "apiBaseUrl") ?? "",
            Username = JsonStr(body, "username") ?? "",
            SupplierTaxCode = JsonStr(body, "supplierTaxCode") ?? "",
            TemplateCode = JsonStr(body, "templateCode") ?? "1/001",
            InvoiceSeries = JsonStr(body, "invoiceSeries") ?? "",
            InvoiceType = JsonStr(body, "invoiceType") ?? "1",
            AskAtCheckout = JsonBool(body, "askAtCheckout", true),
            DefaultIssueAtCheckout = JsonBool(body, "defaultIssueAtCheckout"),
            TaxMode = JsonStr(body, "taxMode") ?? "included",
            DefaultTaxPercent = JsonDec(body, "defaultTaxPercent", 10),
        };

        logger.LogInformation(
            "EInvoice save store={StoreId} provider={Provider} template={Template} series={Series} user={User} tax={Tax}",
            RequiredStoreId, incoming.Provider, incoming.TemplateCode, incoming.InvoiceSeries,
            incoming.Username, incoming.SupplierTaxCode);

        await eInvoice.SaveSettingsAsync(RequiredStoreId, incoming, JsonStr(body, "password"));

        // Đọc lại không cache tracker — xác nhận đã ghi DB.
        var s = await db.PosEInvoiceSettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == RequiredStoreId && x.Deleted == null);
        if (s == null)
            return BadRequest(AppResponse<EInvoiceSettingsDto>.Fail("Không đọc lại được cấu hình sau khi lưu"));

        var sentTemplate = (incoming.TemplateCode ?? "").Trim();
        if (!string.IsNullOrWhiteSpace(sentTemplate) &&
            !string.Equals(s.TemplateCode, sentTemplate, StringComparison.Ordinal))
        {
            logger.LogError(
                "EInvoice save mismatch store={StoreId} sentTemplate={Sent} dbTemplate={Db}",
                RequiredStoreId, sentTemplate, s.TemplateCode);
            return BadRequest(AppResponse<EInvoiceSettingsDto>.Fail(
                $"Lưu HĐĐT không ghi được DB (gửi mẫu «{sentTemplate}», DB vẫn «{s.TemplateCode}»)."));
        }

        return Ok(AppResponse<EInvoiceSettingsDto>.Success(ToDto(s)));
    }

    [HttpPost("test")]
    [RequireModulePermission("PosEInvoice", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Test()
    {
        var (ok, message) = await eInvoice.TestConnectionAsync(RequiredStoreId);
        return ok
            ? Ok(AppResponse<object>.Success(new { message }))
            : BadRequest(AppResponse<object>.Fail(message));
    }

    public record IssueEInvoiceDto(
        string? Name,
        string? TaxCode,
        string? CompanyName,
        string? Address,
        string? Email,
        string? Phone);

    [HttpPost("issue/{orderId:guid}")]
    [RequireModulePermission("PosEInvoice", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<object>>> Issue(
        Guid orderId, [FromBody] IssueEInvoiceDto? buyer = null)
    {
        var storeId = RequiredStoreId;
        var order = await db.PosSaleOrders
            .Include(o => o.Lines)
            .FirstOrDefaultAsync(o => o.Id == orderId && o.StoreId == storeId && o.Deleted == null);
        if (order == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status != PosSaleOrderStatus.Completed)
            return BadRequest(AppResponse<object>.Fail("Chỉ xuất HĐĐT cho đơn đã thanh toán"));

        EInvoiceBuyerInput? input = null;
        if (buyer != null &&
            (!string.IsNullOrWhiteSpace(buyer.Name) ||
             !string.IsNullOrWhiteSpace(buyer.TaxCode) ||
             !string.IsNullOrWhiteSpace(buyer.CompanyName)))
        {
            input = new EInvoiceBuyerInput(
                buyer.Name, buyer.TaxCode, buyer.CompanyName, buyer.Address, buyer.Email, buyer.Phone);
        }

        await eInvoice.IssueNowAsync(order, input);
        await db.Entry(order).ReloadAsync();
        return Ok(AppResponse<object>.Success(new
        {
            order.EInvoiceStatus,
            order.EInvoiceNo,
            order.EInvoiceSeries,
            order.EInvoiceCode,
            order.EInvoiceReservationCode,
            order.EInvoiceError,
            order.EInvoiceProvider,
            order.EInvoiceIssuedAt,
        }));
    }

    [HttpGet("summary")]
    [RequireModulePermission("PosEInvoice", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Summary(
        [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null)
    {
        var fromUtc = from ?? DateTime.UtcNow.Date.AddDays(-30);
        var toUtc = to ?? DateTime.UtcNow.Date.AddDays(1);
        if (fromUtc.Kind == DateTimeKind.Unspecified) fromUtc = DateTime.SpecifyKind(fromUtc, DateTimeKind.Utc);
        if (toUtc.Kind == DateTimeKind.Unspecified) toUtc = DateTime.SpecifyKind(toUtc, DateTimeKind.Utc);
        var data = await eInvoice.SummaryAsync(RequiredStoreId, fromUtc, toUtc);
        return Ok(AppResponse<object>.Success(data));
    }
}
