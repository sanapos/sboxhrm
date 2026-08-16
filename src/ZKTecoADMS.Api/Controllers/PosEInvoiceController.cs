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
    PosEInvoiceService eInvoice) : AuthenticatedControllerBase
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

    public record EInvoiceSettingsSaveDto(
        bool Enabled,
        string? Provider,
        string? ApiBaseUrl,
        string? Username,
        string? Password,
        string? SupplierTaxCode,
        string? TemplateCode,
        string? InvoiceSeries,
        string? InvoiceType,
        bool AskAtCheckout,
        bool DefaultIssueAtCheckout,
        string? TaxMode,
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

    [HttpGet("settings")]
    [RequireModulePermission("PosEInvoice", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<EInvoiceSettingsDto>>> GetSettings()
    {
        var s = await eInvoice.GetOrCreateSettingsAsync(RequiredStoreId);
        return Ok(AppResponse<EInvoiceSettingsDto>.Success(ToDto(s)));
    }

    [HttpPut("settings")]
    [RequireModulePermission("PosEInvoice", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<EInvoiceSettingsDto>>> SaveSettings(
        [FromBody] EInvoiceSettingsSaveDto dto)
    {
        var incoming = new PosEInvoiceSetting
        {
            Enabled = dto.Enabled,
            Provider = dto.Provider ?? "Viettel",
            ApiBaseUrl = dto.ApiBaseUrl ?? "",
            Username = dto.Username ?? "",
            SupplierTaxCode = dto.SupplierTaxCode ?? "",
            TemplateCode = dto.TemplateCode ?? "1/001",
            InvoiceSeries = dto.InvoiceSeries ?? "",
            InvoiceType = dto.InvoiceType ?? "1",
            AskAtCheckout = dto.AskAtCheckout,
            DefaultIssueAtCheckout = dto.DefaultIssueAtCheckout,
            TaxMode = dto.TaxMode ?? "included",
            DefaultTaxPercent = dto.DefaultTaxPercent,
        };
        await eInvoice.SaveSettingsAsync(RequiredStoreId, incoming, dto.Password);
        var s = await eInvoice.GetOrCreateSettingsAsync(RequiredStoreId);
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
        if (order.EInvoiceStatus == "Failed")
            return BadRequest(AppResponse<object>.Fail(order.EInvoiceError ?? "Xuất hóa đơn thất bại"));

        return Ok(AppResponse<object>.Success(new
        {
            order.EInvoiceStatus,
            order.EInvoiceProvider,
            order.EInvoiceNo,
            order.EInvoiceSeries,
            order.EInvoiceReservationCode,
            order.EInvoiceCode,
            order.EInvoiceIssuedAt,
            order.EInvoiceError,
            order.EInvoiceTransactionUuid,
        }));
    }

    [HttpGet("summary")]
    [RequireModulePermission("PosEInvoice", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Summary(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to)
    {
        var fromUtc = from?.ToUniversalTime() ?? DateTime.UtcNow.Date.AddDays(-30);
        var toUtc = to?.ToUniversalTime() ?? DateTime.UtcNow.AddDays(1);
        var data = await eInvoice.SummaryAsync(RequiredStoreId, fromUtc, toUtc);
        return Ok(AppResponse<object>.Success(data));
    }
}
