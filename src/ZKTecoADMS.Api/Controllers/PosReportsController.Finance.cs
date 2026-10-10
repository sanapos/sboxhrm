using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Controllers.Reports;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
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

        var txs = dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                        && c.Status == CashTransactionStatus.Completed
                        && c.TransactionDate >= fromDt.AddHours(7) && c.TransactionDate < toDt.AddHours(7) /* phiếu thu chi lưu giờ VN */);

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
                byDay = scoped
                    .GroupBy(c => c.TransactionDate.Date)
                    .OrderBy(g => g.Key)
                    .Select(g => new
                    {
                        date = g.Key,
                        income = g.Where(x => x.Type == CashTransactionType.Income).Sum(x => x.Amount),
                        expense = g.Where(x => x.Type == CashTransactionType.Expense).Sum(x => x.Amount),
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

        // Tồn đầu kỳ = thu − chi mọi phiếu hoàn thành trước kỳ (cùng phạm vi chi nhánh). Chuyển quỹ chỉ đổi
        // tiền giữa các quỹ nên không làm đổi tổng.
        var opening = await dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                        && c.Status == CashTransactionStatus.Completed
                        && c.TransactionDate < fromDt.AddHours(7))
            .SumAsync(c => (decimal?)(c.Type == CashTransactionType.Income ? c.Amount : -c.Amount)) ?? 0;

        // Thu – chi theo ngày trên toàn kỳ (biểu đồ trước đây cộng từ 80 phiếu gần nhất → thiếu khi kỳ nhiều phiếu).
        var byDay = (await txs
                .GroupBy(c => c.TransactionDate.Date)
                .Select(g => new
                {
                    date = g.Key,
                    income = g.Sum(x => x.Type == CashTransactionType.Income ? x.Amount : 0),
                    expense = g.Sum(x => x.Type == CashTransactionType.Expense ? x.Amount : 0),
                })
                .ToListAsync())
            .OrderBy(d => d.date)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            openingBalance = opening,
            income,
            expense,
            net = income - expense,
            closingBalance = opening + income - expense,
            incomeCount = await txs.CountAsync(c => c.Type == CashTransactionType.Income),
            expenseCount = await txs.CountAsync(c => c.Type == CashTransactionType.Expense),
            byMethod,
            byDay,
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

        var txs = dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                        && c.Status == CashTransactionStatus.Completed
                        && c.Type == CashTransactionType.Expense
                        && c.TransactionDate >= fromDt.AddHours(7) && c.TransactionDate < toDt.AddHours(7) /* phiếu thu chi lưu giờ VN */);
        if (!IsManager)
            txs = txs.Where(c => c.CreatedBy == CurrentUserEmail || c.CreatedByUserId == CurrentUserId);

        // Như KQKD: tiền nhập hàng (vào giá vốn), hoàn tiền trả hàng (giảm doanh thu), hoàn cọc
        // không phải chi phí hoạt động — tách riêng để hai báo cáo khớp nhau.
        var nonCost = txs.Where(c => c.Category != null &&
            (c.Category.Name == "Nhập hàng" || c.Category.Name == "Trả hàng khách" || c.Category.Name == "Hoàn cọc đặt chỗ"));
        var excludedTotal = await nonCost.SumAsync(c => (decimal?)c.Amount) ?? 0;
        txs = txs.Where(c => c.Category == null ||
            (c.Category.Name != "Nhập hàng" && c.Category.Name != "Trả hàng khách" && c.Category.Name != "Hoàn cọc đặt chỗ"));

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
            excludedTotal,
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

        // ── Doanh thu thuần = Σ Total đơn hoàn thành trong kỳ. Total đã trừ giảm giá / voucher / điểm và
        // hàng khách trả (trả hàng giảm Total của đơn gốc), CHƯA gồm VAT (VAT lưu riêng) → không trừ thêm
        // hoàn trả hay VAT (trước đây trừ cả hai → doanh thu thuần thấp hơn thực tế).
        var revenue = await orders.SumAsync(o => (decimal?)o.Total) ?? 0;
        var vat = await orders.SumAsync(o => (decimal?)o.VatAmount) ?? 0;
        var discount = await orders.SumAsync(o => (decimal?)(o.Discount + o.VoucherDiscount + o.PointsDiscount)) ?? 0;
        var orderCount = await orders.CountAsync();
        var orderIds = await orders.Select(o => o.Id).ToListAsync();
        var returnedByOrder = await PosSaleReturnLedger.ReturnedByOrderAsync(dbContext, storeId, orderIds);
        // Hàng trả của các đơn trong kỳ (trình bày: tiền hàng trước trả − hàng trả = doanh thu thuần).
        var refunds = returnedByOrder.Values.Sum(x => x.Refund);
        var grossSales = revenue + refunds;

        // ── Giá vốn thuần của các đơn: giá vốn khi bán (gồm dịch vụ, topping) − giá vốn hàng khách trả.
        var cogsByOrder = await PosReportMoney.CogsByOrderAsync(dbContext, storeId, orderIds);
        var cogs = cogsByOrder.Values.Sum();
        var returnedCost = returnedByOrder.Values.Sum(x => x.Cost);
        var saleCost = cogs + returnedCost;
        var gross = revenue - cogs;

        // ── Hao hụt kho trong kỳ: xuất hủy, xuất dùng nội bộ, xuất khác, chênh lệch kiểm kê (thiếu − thừa)
        // — trước đây không vào kết quả kinh doanh. Chỉ quản lý xem (không gắn với đơn của nhân viên).
        decimal damageCost = 0, internalUseCost = 0, otherIssueCost = 0, countLossCost = 0;
        if (IsManager)
        {
            var issueRows = await dbContext.PosStockTransactions.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.Deleted == null && t.IsActive &&
                            t.StockIssueId != null &&
                            t.CreatedAt >= fromDt && t.CreatedAt < toDt)
                .Select(t => new
                {
                    t.StockIssue!.Kind,
                    t.StockIssue.QuoteId,
                    // Xuất (SL âm) = chi phí; hủy phiếu xuất (SL dương) = trừ lại.
                    Amount = -t.QtyChange * (t.UnitCost ?? 0),
                })
                .ToListAsync();
            // Phiếu xuất theo báo giá thương mại là bán ngoài hóa đơn — không tính hao hụt.
            damageCost = issueRows.Where(r => r.Kind == PosStockIssueKind.Damage).Sum(r => r.Amount);
            internalUseCost = issueRows.Where(r => r.Kind == PosStockIssueKind.InternalUse).Sum(r => r.Amount);
            otherIssueCost = issueRows.Where(r => r.Kind == PosStockIssueKind.Generic && r.QuoteId == null).Sum(r => r.Amount);
            countLossCost = await dbContext.PosStockTransactions.AsNoTracking()
                .Where(t => t.StoreId == storeId && t.Deleted == null && t.IsActive &&
                            t.StockCountId != null && t.TransactionType == PosStockTransactionType.Adjust &&
                            t.CreatedAt >= fromDt && t.CreatedAt < toDt)
                .SumAsync(t => (decimal?)(-t.QtyChange * (t.UnitCost ?? 0))) ?? 0;
        }
        var inventoryLoss = damageCost + internalUseCost + otherIssueCost + countLossCost;

        // ── Thu / chi khác từ sổ quỹ (phiếu đã hoàn thành). Loại các khoản không phải lãi / lỗ:
        // tiền bán hàng & thu nợ khách (đã nằm trong doanh thu), nhập hàng (đã nằm trong giá vốn),
        // trả hàng khách (đã trừ doanh thu), cọc đặt chỗ nhận / hoàn (tiền giữ hộ),
        // thu trả hàng NCC (giảm tồn kho). Hoàn ứng công tác → giảm chi phí.
        var cashQ = dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                        && c.Status == CashTransactionStatus.Completed
                        && c.TransactionDate >= fromDt.AddHours(7) && c.TransactionDate < toDt.AddHours(7) /* phiếu thu chi lưu giờ VN */);
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

        var net = gross - inventoryLoss - expense + otherIncome;
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
            damageCost,
            internalUseCost,
            otherIssueCost,
            countLossCost,
            inventoryLoss,
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
                new { code = "01", label = "Tiền hàng bán (đã trừ giảm giá, chưa VAT)", amount = grossSales },
                new { code = "02", label = "Hàng khách trả lại", amount = -refunds },
                new { code = "10", label = "Doanh thu thuần", amount = revenue },
                new { code = "11", label = "Giá vốn hàng bán", amount = -cogs },
                new { code = "20", label = "Lợi nhuận gộp", amount = gross },
                new { code = "15", label = "Xuất hủy hàng", amount = -damageCost },
                new { code = "16", label = "Xuất dùng nội bộ", amount = -internalUseCost },
                new { code = "17", label = "Xuất kho khác", amount = -otherIssueCost },
                new { code = "18", label = "Chênh lệch kiểm kê (thiếu − thừa)", amount = -countLossCost },
                new { code = "21", label = "Chi phí hoạt động (sổ quỹ)", amount = -expense },
                new { code = "22", label = "Thu nhập khác", amount = otherIncome },
                new { code = "50", label = "Lợi nhuận thuần", amount = net },
            },
        }));
    }
}
