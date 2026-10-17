using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// «Nguy cơ gian lận» (chủ / quản lý): đơn giảm / hủy sau tạm tính, đá bill, đá món, không in hóa đơn,
/// in lại nhiều lần, giảm giá tay lớn, hủy hóa đơn đã thu, trả hàng ngay sau bán — gom theo đơn và nhân viên.
/// </summary>
[ApiController]
[Route("api/pos/risk-report")]
[Authorize]
public class PosRiskController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    /// <summary>[from]/[to] = ngày giờ VN (yyyy-MM-dd); mặc định 7 ngày gần nhất. Tối đa 92 ngày.</summary>
    [HttpGet]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PosSaleRiskReportBuilder.Report>>> Get(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, CancellationToken ct)
    {
        if (!IsAdmin && !IsManager)
            return StatusCode(StatusCodes.Status403Forbidden,
                AppResponse<PosSaleRiskReportBuilder.Report>.Fail("Chỉ chủ / quản lý xem được"));
        var storeId = RequiredStoreId;
        var vnToday = DateTime.UtcNow.AddHours(7).Date;
        var toVnEx = (to ?? vnToday).Date.AddDays(1);
        var fromVn = (from ?? toVnEx.AddDays(-7)).Date;
        if (toVnEx <= fromVn) toVnEx = fromVn.AddDays(1);
        if ((toVnEx - fromVn).TotalDays > 92) fromVn = toVnEx.AddDays(-92);
        var fromUtc = DateTime.SpecifyKind(fromVn.AddHours(-7), DateTimeKind.Utc);
        var toUtc = DateTime.SpecifyKind(toVnEx.AddHours(-7), DateTimeKind.Utc);

        var audits = await db.PosCancelReturnAudits.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.Deleted == null && a.OccurredAt >= fromUtc && a.OccurredAt < toUtc)
            .ToListAsync(ct);
        var sessions = await db.PosResourceSessions.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null && s.BillRequestedAt != null
                && s.BillRequestedAt >= fromUtc && s.BillRequestedAt < toUtc)
            .Select(s => new
            {
                s.Id, ResourceName = s.Resource != null ? s.Resource.Name : null, s.Status, s.BillRequestedAt,
                s.BillRequestedTotal, s.BillRequestedBy, s.BillRequestCount,
            })
            .ToListAsync(ct);
        var sessionIds = sessions.Select(s => s.Id).ToList();
        var auditOrderIds = audits.Where(a => a.SaleOrderId != null).Select(a => a.SaleOrderId!.Value).Distinct().ToList();
        // Đơn trong kỳ (theo giờ bán) + đơn của bàn đã tạm tính + đơn bị hủy / trả trong kỳ (có thể bán từ trước).
        var orders = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null
                && (((o.SaleDate ?? o.CreatedAt) >= fromUtc && (o.SaleDate ?? o.CreatedAt) < toUtc
                        && o.Status != PosSaleOrderStatus.Draft)
                    || (o.ResourceSessionId != null && sessionIds.Contains(o.ResourceSessionId.Value))
                    || auditOrderIds.Contains(o.Id)))
            .Select(o => new PosSaleRiskReportBuilder.OrderRow(
                o.Id, o.OrderNo, o.Status, o.SaleDate ?? o.CreatedAt, o.SubTotal, o.Discount, o.Total, o.PaymentMethod,
                o.PrintCount, o.UpdatedBy ?? o.CreatedBy, o.SoldBy, o.ResourceSessionId,
                o.ServiceResource != null ? o.ServiceResource.Name : null, o.EInvoiceStatus))
            .ToListAsync(ct);

        var emails = audits.Select(a => a.Actor).Concat(orders.Select(o => o.Cashier))
            .Concat(sessions.Select(s => s.BillRequestedBy))
            .Where(e => !string.IsNullOrWhiteSpace(e)).Select(e => e!.Trim().ToLower()).Distinct().ToList();
        var names = emails.Count == 0
            ? new Dictionary<string, string>()
            : (await db.Users.AsNoTracking()
                .Where(u => u.Email != null && emails.Contains(u.Email.ToLower()))
                .Select(u => new { u.Email, u.LastName, u.FirstName })
                .ToListAsync(ct))
                .GroupBy(u => u.Email!.ToLower())
                .ToDictionary(g => g.Key, g => $"{g.First().LastName} {g.First().FirstName}".Trim());

        var report = PosSaleRiskReportBuilder.Build(
            orders,
            sessions.Select(s => new PosSaleRiskReportBuilder.SessionRow(
                s.Id, s.ResourceName, s.Status, s.BillRequestedAt, s.BillRequestedTotal, s.BillRequestedBy,
                s.BillRequestCount)).ToList(),
            audits, names, fromUtc, toUtc);
        return Ok(AppResponse<PosSaleRiskReportBuilder.Report>.Success(report));
    }
}
