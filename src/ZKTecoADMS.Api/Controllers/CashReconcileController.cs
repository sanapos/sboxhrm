using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Đối soát sổ quỹ ↔ chứng từ gốc (từng cửa hàng, theo chi nhánh đang xem): phiếu mất liên kết, chứng từ đã hủy
/// mà phiếu còn hiệu lực, đơn bán đã thu mà sổ quỹ thiếu / thừa.
/// </summary>
[ApiController]
[Route("api/cashtransactions/reconcile")]
[Authorize(Policy = PolicyNames.AtLeastEmployee)]
public class CashReconcileController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    public sealed record Issue(
        string Kind, string Message, Guid? CashId, string? CashCode, decimal Amount,
        string? SourceLabel, string? DocumentNo, DateTime? Date);

    [HttpGet]
    [RequireModulePermission("CashTransaction", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Get(
        [FromQuery] DateTime? fromDate, [FromQuery] DateTime? toDate, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var nowVn = DateTime.UtcNow.AddHours(7);
        var fromVn = (fromDate ?? new DateTime(nowVn.Year, nowVn.Month, 1)).Date;
        var toVn = (toDate ?? nowVn).Date.AddDays(1);
        var from = fromVn.AddHours(-7);
        var to = toVn.AddHours(-7);
        var issues = new List<Issue>();

        var cash = await db.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.IsActive && c.Deleted == null
                        && c.TransactionDate >= fromVn && c.TransactionDate < toVn)
            .ApplyBranchScope(HttpContext.BranchContext())
            .Select(c => new { c.Id, c.TransactionCode, c.Type, c.Amount, c.TransactionDate, c.Description,
                c.SourceType, c.SourceId, c.InternalNote, c.Status })
            .ToListAsync(ct);

        // 1. Phiếu có dấu hiệu tự sinh nhưng mất liên kết (ghi chú bị sửa trước khi khóa).
        foreach (var c in cash.Where(c => !CashSources.IsLinked(c.SourceType)
                                          && CashSources.ParseNote(c.InternalNote) == null
                                          && (c.Description.StartsWith("Bán hàng POS") || c.Description.StartsWith("Thu tiền hợp đồng")
                                              || c.Description.StartsWith("Chi lương") || c.Description.Contains("ứng lương"))))
            issues.Add(new("unlinked", "Phiếu có vẻ tự sinh nhưng mất liên kết chứng từ — kiểm tra trùng / thiếu",
                c.Id, c.TransactionCode, c.Amount, null, null, c.TransactionDate));

        // 2. Phiếu bán hàng còn hiệu lực nhưng đơn đã hủy / xóa.
        var saleCash = cash.Where(c => c.SourceType == CashSources.PosSale && c.SourceId != null
                                       && c.Status != CashTransactionStatus.Cancelled).ToList();
        var orderIds = saleCash.Select(c => c.SourceId!.Value).Distinct().ToList();
        var orders = await db.PosSaleOrders.IgnoreQueryFilters().AsNoTracking()
            .Where(o => orderIds.Contains(o.Id))
            .Select(o => new { o.Id, o.OrderNo, o.Status, o.Deleted, o.PaidAmount })
            .ToDictionaryAsync(o => o.Id, ct);
        foreach (var c in saleCash)
        {
            if (!orders.TryGetValue(c.SourceId!.Value, out var o) || o.Deleted != null || o.Status == PosSaleOrderStatus.Cancelled)
                issues.Add(new("source_cancelled", "Đơn đã hủy / xóa nhưng phiếu thu bán hàng còn hiệu lực",
                    c.Id, c.TransactionCode, c.Amount, CashSources.Label(c.SourceType), o?.OrderNo, c.TransactionDate));
        }

        // 3. Đơn đã thu trong kỳ: tiền đã thu (ròng, sau trả hàng) ≠ phiếu thu bán hàng + cọc đã trừ vào đơn − phiếu chi trả khách.
        var completed = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive && o.Status == PosSaleOrderStatus.Completed
                        && (o.SaleDate ?? o.CreatedAt) >= from && (o.SaleDate ?? o.CreatedAt) < to && o.PaidAmount > 0)
            .ApplyBranchScope(HttpContext.BranchContext())
            .Select(o => new { o.Id, o.OrderNo, o.PaidAmount, At = o.SaleDate ?? o.CreatedAt })
            .ToListAsync(ct);
        var completedIds = completed.Select(o => o.Id).ToList();
        var receiptSums = await db.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.IsActive && c.Deleted == null && c.Status != CashTransactionStatus.Cancelled
                        && (c.SourceType == CashSources.PosSale || c.SourceType == CashSources.PosCustomerReturn)
                        && c.SourceId != null && completedIds.Contains(c.SourceId.Value))
            .GroupBy(c => c.SourceId!.Value)
            .Select(g => new { Id = g.Key, Sum = g.Sum(x => x.Type == CashTransactionType.Income ? x.Amount : -x.Amount) })
            .ToDictionaryAsync(x => x.Id, x => x.Sum, ct);
        // Thu nợ sau bán gắn với đơn (phiếu «pos thu nợ kh») cũng là tiền của đơn đó.
        var debtPays = await db.PosCustomerPayments.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.SaleOrderId != null && completedIds.Contains(p.SaleOrderId.Value))
            .Select(p => new { p.Id, OrderId = p.SaleOrderId!.Value })
            .ToListAsync(ct);
        var debtPayIds = debtPays.Select(p => p.Id).ToList();
        var debtCash = await db.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.IsActive && c.Deleted == null && c.Status != CashTransactionStatus.Cancelled
                        && c.SourceType == CashSources.PosCustomerPayment && c.SourceId != null && debtPayIds.Contains(c.SourceId.Value))
            .Select(c => new { Id = c.SourceId!.Value, c.Amount })
            .ToListAsync(ct);
        foreach (var dc in debtCash)
        {
            var oid = debtPays.First(p => p.Id == dc.Id).OrderId;
            receiptSums[oid] = receiptSums.GetValueOrDefault(oid) + dc.Amount;
        }
        var deposits = await db.PosResourceReservations.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.DepositAppliedOrderId != null && completedIds.Contains(r.DepositAppliedOrderId.Value))
            .GroupBy(r => r.DepositAppliedOrderId!.Value)
            .Select(g => new { Id = g.Key, Sum = g.Sum(x => x.DepositPaid) })
            .ToDictionaryAsync(x => x.Id, x => x.Sum, ct);
        foreach (var o in completed)
        {
            var inCash = receiptSums.GetValueOrDefault(o.Id) + deposits.GetValueOrDefault(o.Id);
            var diff = o.PaidAmount - inCash;
            if (Math.Abs(diff) < 1) continue;
            issues.Add(new(diff > 0 ? "missing_receipt" : "extra_receipt",
                diff > 0
                    ? $"Đơn đã thu {o.PaidAmount:N0}đ nhưng sổ quỹ chỉ có {inCash:N0}đ (thiếu {diff:N0}đ)"
                    : $"Sổ quỹ ghi {inCash:N0}đ, nhiều hơn số đơn đã thu {o.PaidAmount:N0}đ (thừa {-diff:N0}đ)",
                null, null, Math.Abs(diff), CashSources.Label(CashSources.PosSale), o.OrderNo, o.At));
        }

        // 4. Phiếu nhân sự còn hiệu lực nhưng chứng từ gốc đã bị xóa.
        foreach (var c in cash.Where(c => CashSources.IsHrmPayable(c.SourceType) || c.SourceType == CashSources.Payslip))
        {
            var exists = c.SourceType switch
            {
                CashSources.Payslip => await db.Payslips.AnyAsync(p => p.Id == c.SourceId, ct),
                CashSources.Advance => await db.AdvanceRequests.AnyAsync(a => a.Id == c.SourceId, ct),
                CashSources.Reward => await db.PaymentTransactions.AnyAsync(p => p.Id == c.SourceId, ct),
                CashSources.PenaltyTicket => await db.PenaltyTickets.AnyAsync(p => p.Id == c.SourceId, ct),
                CashSources.TripAdvance => await db.BusinessTripAdvanceClaims.AnyAsync(p => p.Id == c.SourceId, ct),
                _ => await db.BusinessTripSettlementClaims.AnyAsync(p => p.Id == c.SourceId, ct),
            };
            if (!exists)
                issues.Add(new("source_missing", "Chứng từ nhân sự đã bị xóa nhưng phiếu thu / chi còn hiệu lực",
                    c.Id, c.TransactionCode, c.Amount, CashSources.Label(c.SourceType), null, c.TransactionDate));
        }

        return Ok(AppResponse<object>.Success(new
        {
            from = from.AddHours(7).Date,
            to = to.AddHours(7).Date.AddDays(-1),
            checkedVouchers = cash.Count,
            checkedOrders = completed.Count,
            issues = issues.OrderBy(i => i.Date).ToList(),
        }));
    }
}
