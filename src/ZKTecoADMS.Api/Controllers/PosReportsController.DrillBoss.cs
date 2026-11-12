using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// «Số này từ đâu ra» cho báo cáo SBOX BOSS: danh sách phiếu thu / chi đứng sau từng ô số
/// (Sổ quỹ, Chi phí, dòng chi phí / thu nhập khác của Lãi lỗ). Bộ lọc cửa hàng, chi nhánh, quyền và kỳ
/// chép đúng từ endpoint tổng tương ứng để tổng danh sách khớp số trên ô.
/// </summary>
public partial class PosReportsController
{
    private const int DrillBossMaxRows = 500;

    /// <summary>Phiếu thu (type=Income) hoặc chi (type=Expense) của Sổ quỹ — cùng phạm vi với cashbook/summary.</summary>
    [HttpGet("drill-boss/cashbook")]
    [RequireModulePermission("PosReportCashbook", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> DrillBossCashbook(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string? type,
        [FromQuery] string? paymentMethod = null,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, _, _) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);
        var wantIncome = !string.Equals(type, "Expense", StringComparison.OrdinalIgnoreCase);
        var txType = wantIncome ? CashTransactionType.Income : CashTransactionType.Expense;

        var txs = dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                        && c.Status == CashTransactionStatus.Completed
                        && c.Type == txType
                        && c.TransactionDate >= fromDt.AddHours(7) && c.TransactionDate < toDt.AddHours(7) /* phiếu thu chi lưu giờ VN */);
        if (!string.IsNullOrWhiteSpace(paymentMethod)
            && Enum.TryParse<PaymentMethodType>(paymentMethod.Trim(), true, out var pm))
            txs = txs.Where(c => c.PaymentMethod == pm);

        List<DrillBossCashRow> rows;
        if (!IsManager)
        {
            // Như cashbook/summary: nhân viên chỉ thấy phiếu thu gắn đơn của mình và phiếu chi do mình lập.
            var email = CurrentUserEmail;
            var userId = CurrentUserId;
            var all = await ProjectDrillBossCash(txs).ToListAsync();
            if (wantIncome)
            {
                var myOrderIds = (await ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
                        .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive
                                    && o.Status == PosSaleOrderStatus.Completed
                                    && (o.SaleDate ?? o.CreatedAt) >= fromDt
                                    && (o.SaleDate ?? o.CreatedAt) < toDt))
                    .Select(o => o.Id)
                    .ToListAsync()).ToHashSet();
                rows = all.Where(c => ParseSaleOrderIdFromMarker(c.InternalNote) is Guid oid && myOrderIds.Contains(oid)).ToList();
            }
            else
            {
                rows = all.Where(c => string.Equals(c.CreatedBy, email, StringComparison.OrdinalIgnoreCase)
                                      || c.CreatedByUserId == userId).ToList();
            }
        }
        else
        {
            rows = await ProjectDrillBossCash(txs).ToListAsync();
        }

        return Ok(AppResponse<object>.Success(DrillBossCashResult(rows)));
    }

    /// <summary>Phiếu chi phí — cùng phạm vi với expenses/summary (loại nhập hàng, trả hàng khách, hoàn cọc).
    /// category: lọc một danh mục («Khác» = phiếu không có danh mục).</summary>
    [HttpGet("drill-boss/expenses")]
    [RequireModulePermission("PosReportExpense", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> DrillBossExpenses(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string? category = null,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, _, _) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var txs = dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                        && c.Status == CashTransactionStatus.Completed
                        && c.Type == CashTransactionType.Expense
                        && c.TransactionDate >= fromDt.AddHours(7) && c.TransactionDate < toDt.AddHours(7) /* phiếu thu chi lưu giờ VN */);
        if (!IsManager)
            txs = txs.Where(c => c.CreatedBy == CurrentUserEmail || c.CreatedByUserId == CurrentUserId);
        txs = txs.Where(c => c.Category == null ||
            (c.Category.Name != "Nhập hàng" && c.Category.Name != "Trả hàng khách" && c.Category.Name != "Hoàn cọc đặt chỗ"));
        if (!string.IsNullOrWhiteSpace(category))
        {
            var cat = category.Trim();
            txs = cat == "Khác"
                ? txs.Where(c => c.Category == null || c.Category.Name == "Khác")
                : txs.Where(c => c.Category != null && c.Category.Name == cat);
        }

        var rows = await ProjectDrillBossCash(txs).ToListAsync();
        return Ok(AppResponse<object>.Success(DrillBossCashResult(rows)));
    }

    /// <summary>
    /// Phiếu sổ quỹ đứng sau một dòng Lãi lỗ — cùng phạm vi với pnl/summary.
    /// kind=expense: chi phí hoạt động (trừ nhập hàng, trả hàng khách, hoàn cọc, ứng lương, mua tài sản;
    ///   phiếu «Thu hoàn ứng công tác» ghi số âm vì làm giảm chi phí).
    /// kind=otherIncome: thu nhập khác. kind=forfeited: cọc khách bỏ. category: lọc một danh mục.
    /// </summary>
    [HttpGet("drill-boss/pnl-cash")]
    [RequireModulePermission("PosReportPnl", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> DrillBossPnlCash(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string kind = "expense",
        [FromQuery] string? category = null,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, _, _) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var cashQ = dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                        && c.Status == CashTransactionStatus.Completed
                        && c.TransactionDate >= fromDt.AddHours(7) && c.TransactionDate < toDt.AddHours(7) /* phiếu thu chi lưu giờ VN */);
        if (!IsManager)
            cashQ = cashQ.Where(c => c.CreatedBy == CurrentUserEmail || c.CreatedByUserId == CurrentUserId);

        // Cùng danh sách loại trừ với pnl/summary.
        string[] nonPnlExpense = ["Nhập hàng", "Trả hàng khách", "Hoàn cọc đặt chỗ", "Ứng lương", PosPnlExtras.AssetPurchaseCategory];
        string[] nonPnlIncome = ["Bán hàng", "Thu nợ khách", "Cọc đặt chỗ", "Thu trả hàng NCC", "Thu hộ COD"];
        const string tripRefund = "Thu hoàn ứng công tác";
        const string forfeited = PosPnlExtras.ForfeitedDepositCategory;

        var k = (kind ?? "expense").Trim().ToLowerInvariant();
        IQueryable<CashTransaction> q = k switch
        {
            "otherincome" => cashQ.Where(c => c.Type == CashTransactionType.Income
                                              && !nonPnlIncome.Contains(c.Category.Name)
                                              && c.Category.Name != tripRefund
                                              && c.Category.Name != forfeited),
            "forfeited" => cashQ.Where(c => c.Type == CashTransactionType.Income && c.Category.Name == forfeited),
            _ => cashQ.Where(c => (c.Type == CashTransactionType.Expense && !nonPnlExpense.Contains(c.Category.Name))
                                  || (c.Type == CashTransactionType.Income && c.Category.Name == tripRefund)),
        };
        if (!string.IsNullOrWhiteSpace(category))
        {
            var cat = category.Trim();
            q = q.Where(c => c.Category.Name == cat);
        }

        var rows = (await ProjectDrillBossCash(q).ToListAsync())
            .Select(r => k is not ("otherincome" or "forfeited") && r.Type == nameof(CashTransactionType.Income)
                ? r with { Amount = -r.Amount }
                : r)
            .ToList();
        return Ok(AppResponse<object>.Success(DrillBossCashResult(rows)));
    }

    private sealed record DrillBossCashRow(
        Guid Id,
        string TransactionCode,
        DateTime TransactionDate,
        string Type,
        decimal Amount,
        string PaymentMethod,
        string Description,
        string? Category,
        string? ContactName,
        string? CreatedBy,
        Guid CreatedByUserId,
        string? InternalNote);

    private static IQueryable<DrillBossCashRow> ProjectDrillBossCash(IQueryable<CashTransaction> q) =>
        q.OrderByDescending(c => c.TransactionDate)
            .Select(c => new DrillBossCashRow(
                c.Id,
                c.TransactionCode,
                c.TransactionDate,
                c.Type.ToString(),
                c.Amount,
                c.PaymentMethod.ToString(),
                c.Description,
                c.Category != null ? c.Category.Name : null,
                c.ContactName,
                c.CreatedBy,
                c.CreatedByUserId,
                c.InternalNote));

    /// <summary>Tổng / số phiếu tính trên mọi phiếu; danh sách cắt <see cref="DrillBossMaxRows"/> dòng mới nhất.</summary>
    private static object DrillBossCashResult(List<DrillBossCashRow> rows) => new
    {
        count = rows.Count,
        total = rows.Sum(r => r.Amount),
        truncated = rows.Count > DrillBossMaxRows,
        items = rows.Take(DrillBossMaxRows).Select(r => new
        {
            id = r.Id,
            transactionCode = r.TransactionCode,
            transactionDate = r.TransactionDate,
            type = r.Type,
            amount = r.Amount,
            paymentMethod = r.PaymentMethod,
            description = r.Description,
            category = r.Category,
            contactName = r.ContactName,
        }).ToList(),
    };
}
