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
                revenue = g.Sum(x => x.Total + x.VatAmount + x.SurchargeAmount + x.DeliveryFee),
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

        // ── Doanh thu: tổng HĐ (đã trừ giảm giá, gồm VAT) − hoàn trả khách − VAT phải nộp.
        var grossSales = await orders.SumAsync(o => (decimal?)o.Total) ?? 0;
        var vat = await orders.SumAsync(o => (decimal?)o.VatAmount) ?? 0;
        var discount = await orders.SumAsync(o => (decimal?)(o.Discount + o.VoucherDiscount)) ?? 0;
        var orderCount = await orders.CountAsync();
        var orderIds = await orders.Select(o => o.Id).ToListAsync();
        // Hoàn trả trong kỳ (theo đơn người xem được) — cùng cách báo cáo doanh thu.
        var refunds = await SumPeriodSaleRefundsAsync(storeId, fromDt, toDt,
            IsManager ? null : orderIds);
        var revenue = grossSales - refunds - vat;

        // ── Giá vốn: phiếu kho bán (gồm topping không có dòng HĐ riêng) − giá vốn hàng khách trả lại.
        var saleCost = orderIds.Count == 0
            ? 0m
            : await dbContext.PosStockTransactions.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.Deleted == null
                            && t.TransactionType == PosStockTransactionType.Sale
                            && t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value))
                .SumAsync(t => (decimal?)(t.LineAmount ?? 0)) ?? 0;
        var returnQ = dbContext.PosStockTransactions.AsNoTracking()
            .Where(t => t.StoreId == storeId && t.Deleted == null && t.IsActive
                        && t.TransactionType == PosStockTransactionType.Return
                        && t.CreatedAt >= fromDt && t.CreatedAt < toDt
                        && (t.Note == null || !t.Note.StartsWith("Hủy đơn"))
                        && (t.Note == null || !t.Note.StartsWith("Hủy trả hàng")));
        if (!IsManager)
            returnQ = returnQ.Where(t => t.SaleOrderId != null && orderIds.Contains(t.SaleOrderId.Value));
        var returnedCost = await returnQ.SumAsync(t => (decimal?)(t.QtyChange * (t.UnitCost ?? 0))) ?? 0;
        var cogs = saleCost - returnedCost;
        var gross = revenue - cogs;

        // ── Thu / chi khác từ sổ quỹ (phiếu đã hoàn thành). Loại các khoản không phải lãi / lỗ:
        // tiền bán hàng & thu nợ khách (đã nằm trong doanh thu), nhập hàng (đã nằm trong giá vốn),
        // trả hàng khách (đã trừ doanh thu), cọc đặt chỗ nhận / hoàn (tiền giữ hộ),
        // thu trả hàng NCC (giảm tồn kho). Hoàn ứng công tác → giảm chi phí.
        var cashQ = dbContext.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                        && c.Status == CashTransactionStatus.Completed
                        && c.TransactionDate >= fromDt && c.TransactionDate < toDt);
        if (!IsManager)
            cashQ = cashQ.Where(c => c.CreatedBy == CurrentUserEmail || c.CreatedByUserId == CurrentUserId);
        var cashRows = await cashQ
            .GroupBy(c => new { c.Type, Category = c.Category.Name })
            .Select(g => new { g.Key.Type, g.Key.Category, Amount = g.Sum(c => c.Amount), Count = g.Count() })
            .ToListAsync();

        static bool IsNonPnlExpense(string? c) => c is "Nhập hàng" or "Trả hàng khách" or "Hoàn cọc đặt chỗ";
        static bool IsNonPnlIncome(string? c) =>
            c is "Bán hàng" or "Thu nợ khách" or "Cọc đặt chỗ" or "Thu trả hàng NCC";
        const string tripRefund = "Thu hoàn ứng công tác";

        var expenseByCategory = cashRows
            .Where(r => r.Type == CashTransactionType.Expense && !IsNonPnlExpense(r.Category))
            .Select(r => new { category = r.Category ?? "Khác", amount = r.Amount, count = r.Count })
            .OrderByDescending(r => r.amount)
            .ToList();
        var tripRefundAmount = cashRows
            .Where(r => r.Type == CashTransactionType.Income && r.Category == tripRefund)
            .Sum(r => r.Amount);
        var expense = expenseByCategory.Sum(r => r.amount) - tripRefundAmount;
        var otherIncomeByCategory = cashRows
            .Where(r => r.Type == CashTransactionType.Income && !IsNonPnlIncome(r.Category) && r.Category != tripRefund)
            .Select(r => new { category = r.Category ?? "Khác", amount = r.Amount, count = r.Count })
            .OrderByDescending(r => r.amount)
            .ToList();
        var otherIncome = otherIncomeByCategory.Sum(r => r.amount);
        var excludedCash = cashRows
            .Where(r => r.Type == CashTransactionType.Expense ? IsNonPnlExpense(r.Category) : IsNonPnlIncome(r.Category))
            .Select(r => new { type = r.Type.ToString(), category = r.Category ?? "", amount = r.Amount, count = r.Count })
            .ToList();

        var net = gross - expense + otherIncome;
        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            orderCount,
            grossSales,
            refunds,
            vat,
            discount,
            revenue,
            saleCost,
            returnedCost,
            cogs,
            grossProfit = gross,
            expenses = expense,
            tripAdvanceRefunds = tripRefundAmount,
            otherIncome,
            netProfit = net,
            marginPct = revenue > 0 ? Math.Round(gross * 100 / revenue, 1) : 0,
            netMarginPct = revenue > 0 ? Math.Round(net * 100 / revenue, 1) : 0,
            expenseByCategory,
            otherIncomeByCategory,
            excludedCash,
            // Dòng báo cáo KQKD theo thứ tự trình bày.
            lines = new object[]
            {
                new { code = "01", label = "Tổng tiền hóa đơn (đã trừ giảm giá)", amount = grossSales },
                new { code = "02", label = "Hoàn trả khách", amount = -refunds },
                new { code = "03", label = "Thuế GTGT phải nộp", amount = -vat },
                new { code = "10", label = "Doanh thu thuần", amount = revenue },
                new { code = "11", label = "Giá vốn hàng bán", amount = -cogs },
                new { code = "20", label = "Lợi nhuận gộp", amount = gross },
                new { code = "21", label = "Chi phí hoạt động (sổ quỹ)", amount = -expense },
                new { code = "22", label = "Thu nhập khác", amount = otherIncome },
                new { code = "50", label = "Lợi nhuận thuần", amount = net },
            },
        }));
    }
}
