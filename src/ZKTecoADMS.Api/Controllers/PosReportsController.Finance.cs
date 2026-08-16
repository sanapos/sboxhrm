using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosReportsController
{
    [HttpGet("cashbook/summary")]
    [RequireModulePermission("PosReportCashbook", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetCashbookSummary(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var txs = dbContext.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                        && c.Status == CashTransactionStatus.Completed
                        && c.TransactionDate >= fromDt && c.TransactionDate < toDt);

        if (!IsManager)
        {
            var myOrderIds = (await ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
                .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive
                            && o.Status == PosSaleOrderStatus.Completed
                            && (o.SaleDate ?? o.CreatedAt) >= fromDt
                            && (o.SaleDate ?? o.CreatedAt) < toDt))
                .Select(o => o.Id)
                .ToListAsync()).ToHashSet();
            var email = CurrentUserEmail;
            var userId = CurrentUserId;
            var scoped = (await txs.ToListAsync())
                .Where(c =>
                {
                    if (c.Type == CashTransactionType.Income)
                    {
                        var oid = ParseSaleOrderIdFromMarker(c.InternalNote);
                        return oid.HasValue && myOrderIds.Contains(oid.Value);
                    }
                    return string.Equals(c.CreatedBy, email, StringComparison.OrdinalIgnoreCase)
                           || c.CreatedByUserId == userId;
                })
                .ToList();
            var scopedIncome = scoped.Where(c => c.Type == CashTransactionType.Income).ToList();
            var scopedExpense = scoped.Where(c => c.Type == CashTransactionType.Expense).ToList();
            return Ok(AppResponse<object>.Success(new
            {
                from = fromVn.Date,
                to = toVnEx.AddDays(-1).Date,
                income = scopedIncome.Sum(c => c.Amount),
                expense = scopedExpense.Sum(c => c.Amount),
                net = scopedIncome.Sum(c => c.Amount) - scopedExpense.Sum(c => c.Amount),
                incomeCount = scopedIncome.Count,
                expenseCount = scopedExpense.Count,
                byMethod = scoped
                    .GroupBy(c => new { c.Type, c.PaymentMethod })
                    .Select(g => new
                    {
                        type = g.Key.Type.ToString(),
                        paymentMethod = g.Key.PaymentMethod.ToString(),
                        total = g.Sum(x => x.Amount),
                        count = g.Count()
                    })
                    .ToList(),
                items = scoped
                    .OrderByDescending(c => c.TransactionDate)
                    .Take(80)
                    .Select(c => new
                    {
                        c.Id,
                        c.TransactionCode,
                        c.TransactionDate,
                        type = c.Type.ToString(),
                        c.Amount,
                        paymentMethod = c.PaymentMethod.ToString(),
                        c.Description,
                        category = (string?)null,
                    })
                    .ToList()
            }));
        }

        var income = await txs.Where(c => c.Type == CashTransactionType.Income)
            .SumAsync(c => (decimal?)c.Amount) ?? 0;
        var expense = await txs.Where(c => c.Type == CashTransactionType.Expense)
            .SumAsync(c => (decimal?)c.Amount) ?? 0;

        var byMethod = await txs
            .GroupBy(c => new { c.Type, c.PaymentMethod })
            .Select(g => new
            {
                type = g.Key.Type.ToString(),
                paymentMethod = g.Key.PaymentMethod.ToString(),
                total = g.Sum(x => x.Amount),
                count = g.Count()
            })
            .ToListAsync();

        var items = await txs
            .OrderByDescending(c => c.TransactionDate)
            .Take(80)
            .Select(c => new
            {
                c.Id,
                c.TransactionCode,
                c.TransactionDate,
                type = c.Type.ToString(),
                c.Amount,
                paymentMethod = c.PaymentMethod.ToString(),
                c.Description,
                category = c.Category != null ? c.Category.Name : null,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            income,
            expense,
            net = income - expense,
            incomeCount = await txs.CountAsync(c => c.Type == CashTransactionType.Income),
            expenseCount = await txs.CountAsync(c => c.Type == CashTransactionType.Expense),
            byMethod,
            items
        }));
    }

    [HttpGet("expenses/summary")]
    [RequireModulePermission("PosReportExpense", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetExpenseSummary(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var txs = dbContext.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                        && c.Status == CashTransactionStatus.Completed
                        && c.Type == CashTransactionType.Expense
                        && c.TransactionDate >= fromDt && c.TransactionDate < toDt);
        if (!IsManager)
            txs = txs.Where(c => c.CreatedBy == CurrentUserEmail || c.CreatedByUserId == CurrentUserId);

        var total = await txs.SumAsync(c => (decimal?)c.Amount) ?? 0;
        var byCategory = await txs
            .GroupBy(c => c.Category != null ? c.Category.Name : "Khác")
            .Select(g => new { category = g.Key, total = g.Sum(x => x.Amount), count = g.Count() })
            .OrderByDescending(x => x.total)
            .ToListAsync();
        var items = await txs
            .OrderByDescending(c => c.TransactionDate)
            .Take(80)
            .Select(c => new
            {
                c.Id,
                c.TransactionCode,
                c.TransactionDate,
                c.Amount,
                c.Description,
                category = c.Category != null ? c.Category.Name : null,
                paymentMethod = c.PaymentMethod.ToString(),
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            total,
            count = await txs.CountAsync(),
            byCategory,
            items
        }));
    }

    [HttpGet("vouchers/summary")]
    [RequireModulePermission("PosReportVoucher", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetVoucherReport(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var used = ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null
                        && o.Status == PosSaleOrderStatus.Completed
                        && o.VoucherCode != null && o.VoucherCode != ""
                        && (o.SaleDate ?? o.CreatedAt) >= fromDt
                        && (o.SaleDate ?? o.CreatedAt) < toDt));

        var items = await used
            .GroupBy(o => o.VoucherCode!)
            .Select(g => new
            {
                voucherCode = g.Key,
                uses = g.Count(),
                discount = g.Sum(x => x.VoucherDiscount),
                revenue = g.Sum(x => x.Total + x.VatAmount),
            })
            .OrderByDescending(x => x.discount)
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            voucherCount = items.Count,
            uses = items.Sum(x => x.uses),
            totalDiscount = items.Sum(x => x.discount),
            revenueWithVoucher = items.Sum(x => x.revenue),
            items
        }));
    }

    [HttpGet("pnl/summary")]
    [RequireModulePermission("PosReportPnl", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetPnlSummary(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var orders = ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null
                        && o.Status == PosSaleOrderStatus.Completed
                        && (o.SaleDate ?? o.CreatedAt) >= fromDt
                        && (o.SaleDate ?? o.CreatedAt) < toDt));

        var revenue = await orders.SumAsync(o => (decimal?)o.Total) ?? 0;
        var vat = await orders.SumAsync(o => (decimal?)o.VatAmount) ?? 0;
        var discount = await orders.SumAsync(o => (decimal?)(o.Discount + o.VoucherDiscount)) ?? 0;
        var orderCount = await orders.CountAsync();

        // COGS từ phiếu kho (gồm topping không có dòng HĐ riêng) — khớp báo cáo doanh thu.
        var orderIds = await orders.Select(o => o.Id).ToListAsync();
        var cogs = orderIds.Count == 0
            ? 0m
            : await dbContext.PosStockTransactions.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.Deleted == null
                            && t.TransactionType == PosStockTransactionType.Sale
                            && t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
                .SumAsync(t => (decimal?)(t.LineAmount ?? 0)) ?? 0;

        var expenseQ = dbContext.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                        && c.Status == CashTransactionStatus.Completed
                        && c.Type == CashTransactionType.Expense
                        && c.TransactionDate >= fromDt && c.TransactionDate < toDt);
        if (!IsManager)
            expenseQ = expenseQ.Where(c => c.CreatedBy == CurrentUserEmail || c.CreatedByUserId == CurrentUserId);
        var expense = await expenseQ.SumAsync(c => (decimal?)c.Amount) ?? 0;

        var gross = revenue - cogs;
        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            orderCount,
            revenue,
            vat,
            discount,
            cogs,
            grossProfit = gross,
            expenses = expense,
            netProfit = gross - expense,
            marginPct = revenue > 0 ? Math.Round(gross * 100 / revenue, 1) : 0
        }));
    }
}
