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
/// «Số này từ đâu ra» cho các chip của báo cáo POS tách màn (doanh thu, lợi nhuận, voucher, KQKD, PTTT, sổ quỹ,
/// chi phí): trả đúng các đơn / phiếu đã cộng ra số trên chip. Bộ lọc cửa hàng / chi nhánh / người xem / kỳ / trạng thái
/// chép y hệt endpoint tổng tương ứng (sales/summary, pnl/summary, vouchers/summary, cashbook/summary, expenses/summary)
/// để tổng danh sách khớp chip. Tối đa 500 dòng; tổng (`sum…`) luôn tính trên toàn bộ.
/// </summary>
public partial class PosReportsController
{
    const int DrillSplitMaxRows = 500;

    // ─── Đơn bán ──────────────────────────────────────────────────────────

    /// <summary>Đơn của báo cáo bán hàng / lợi nhuận (cùng lọc với sales/summary).</summary>
    [HttpGet("drill-split/orders")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    [MaskCostData("sumCogs", "sumProfit")]
    public Task<ActionResult<AppResponse<object>>> DrillSplitOrders(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] int? dayStartHour = null,
        [FromQuery] bool onlyDiscount = false, [FromQuery] bool withCogs = false,
        [FromQuery] string? sort = null, [FromQuery] int limit = DrillSplitMaxRows) =>
        DrillSplitOrdersCoreAsync("sales", from, to, dayStartHour, null, onlyDiscount, withCogs, sort, limit);

    /// <summary>Đơn của Kết quả kinh doanh (cùng lọc với pnl/summary — không lọc IsActive như endpoint đó).</summary>
    [HttpGet("drill-split/pnl-orders")]
    [RequireModulePermission("PosReportPnl", ModulePermissionAction.View)]
    [MaskCostData("sumCogs", "sumProfit")]
    public Task<ActionResult<AppResponse<object>>> DrillSplitPnlOrders(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] int? dayStartHour = null,
        [FromQuery] bool onlyDiscount = false, [FromQuery] bool withCogs = false,
        [FromQuery] string? sort = null, [FromQuery] int limit = DrillSplitMaxRows) =>
        DrillSplitOrdersCoreAsync("pnl", from, to, dayStartHour, null, onlyDiscount, withCogs, sort, limit);

    /// <summary>Đơn dùng voucher (cùng lọc với vouchers/summary); <paramref name="voucherCode"/> = đúng một mã.</summary>
    [HttpGet("drill-split/voucher-orders")]
    [RequireModulePermission("PosReportVoucher", ModulePermissionAction.View)]
    [MaskCostData("sumCogs", "sumProfit")]
    public Task<ActionResult<AppResponse<object>>> DrillSplitVoucherOrders(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] int? dayStartHour = null,
        [FromQuery] string? voucherCode = null, [FromQuery] string? sort = null,
        [FromQuery] int limit = DrillSplitMaxRows) =>
        DrillSplitOrdersCoreAsync("voucher", from, to, dayStartHour, voucherCode, false, false, sort, limit);

    async Task<ActionResult<AppResponse<object>>> DrillSplitOrdersCoreAsync(
        string source, DateTime? from, DateTime? to, int? dayStartHour, string? voucherCode,
        bool onlyDiscount, bool withCogs, string? sort, int limit)
    {
        var storeId = RequiredStoreId;
        limit = Math.Clamp(limit, 1, DrillSplitMaxRows);
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var baseQ = dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt);
        // sales/summary lọc thêm IsActive; pnl/summary và vouchers/summary thì không.
        if (source == "sales") baseQ = baseQ.Where(o => o.IsActive);
        if (source == "voucher")
        {
            baseQ = baseQ.Where(o => o.VoucherCode != null && o.VoucherCode != "");
            if (!string.IsNullOrWhiteSpace(voucherCode))
            {
                var code = voucherCode.Trim();
                baseQ = baseQ.Where(o => o.VoucherCode == code);
            }
        }
        var orders = ScopeOrdersForViewer(baseQ);
        if (onlyDiscount)
            orders = orders.Where(o => o.Discount + o.VoucherDiscount + o.PointsDiscount != 0 ||
                                       dbContext.PosSaleOrderLines.Any(l => l.SaleOrderId == o.Id && l.Deleted == null &&
                                                                            l.DiscountAmount != 0));

        var orderIds = orders.Select(o => o.Id);
        var sums = await orders.GroupBy(o => 1)
            .Select(g => new
            {
                Count = g.Count(),
                Total = g.Sum(o => o.Total),
                Vat = g.Sum(o => o.VatAmount),
                Paid = g.Sum(o => o.PaidAmount),
                OrderDiscount = g.Sum(o => o.Discount + o.VoucherDiscount + o.PointsDiscount),
                Voucher = g.Sum(o => o.VoucherDiscount),
                Grand = g.Sum(o => o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee),
            })
            .FirstOrDefaultAsync();
        var sumLineDiscount = await dbContext.PosSaleOrderLines.AsNoTracking()
            .Where(l => orderIds.Contains(l.SaleOrderId) && l.Deleted == null)
            .SumAsync(l => (decimal?)l.DiscountAmount) ?? 0m;

        IQueryable<PosSaleOrder> sorted = (sort ?? "").ToLowerInvariant() switch
        {
            "total" => orders.OrderByDescending(o => o.Total),
            "discount" => orders.OrderByDescending(o => o.Discount + o.VoucherDiscount + o.PointsDiscount),
            "voucher" => orders.OrderByDescending(o => o.VoucherDiscount),
            "vat" => orders.OrderByDescending(o => o.VatAmount),
            _ => orders.OrderByDescending(o => o.SaleDate ?? o.CreatedAt),
        };
        var raw = await sorted
            .Take(limit)
            .Select(o => new
            {
                o.Id,
                o.OrderNo,
                At = o.SaleDate ?? o.CreatedAt,
                o.Total,
                o.VatAmount,
                o.PaidAmount,
                OrderDiscount = o.Discount + o.VoucherDiscount + o.PointsDiscount,
                o.VoucherDiscount,
                o.VoucherCode,
                Grand = o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee,
                o.PaymentMethod,
                o.CustomerName,
                o.SoldBy,
                o.SoldByEmployeeId,
            })
            .ToListAsync();
        var pageIds = raw.Select(o => o.Id).ToList();
        var lineDiscount = pageIds.Count == 0
            ? new Dictionary<Guid, decimal>()
            : await dbContext.PosSaleOrderLines.AsNoTracking()
                .Where(l => pageIds.Contains(l.SaleOrderId) && l.Deleted == null)
                .GroupBy(l => l.SaleOrderId)
                .Select(g => new { g.Key, D = g.Sum(x => x.DiscountAmount) })
                .ToDictionaryAsync(x => x.Key, x => x.D);
        Dictionary<Guid, decimal>? cogsByOrder = null;
        decimal? sumCogs = null;
        if (withCogs)
        {
            cogsByOrder = await PosReportMoney.CogsByOrderAsync(dbContext, storeId, pageIds);
            // Cùng cách tính totalCogs của sales/summary (Σ giá vốn thuần theo đơn) và cogs của pnl/summary.
            sumCogs = await PosReportMoney.CogsTotalAsync(dbContext, storeId, orderIds);
        }
        var names = await SellerDisplayNamesAsync(raw.Select(o => o.SoldByEmployeeId), raw.Select(o => o.SoldBy));

        var items = raw.Select(o =>
        {
            var cogs = cogsByOrder?.GetValueOrDefault(o.Id);
            return new
            {
                id = o.Id,
                orderNo = o.OrderNo,
                saleDate = DateTime.SpecifyKind(o.At, DateTimeKind.Utc),
                total = o.Total,
                vatAmount = o.VatAmount,
                paidAmount = o.PaidAmount,
                grandTotal = o.Grand,
                discount = o.OrderDiscount + lineDiscount.GetValueOrDefault(o.Id),
                voucherDiscount = o.VoucherDiscount,
                voucherCode = o.VoucherCode,
                paymentMethod = o.PaymentMethod,
                customerName = o.CustomerName,
                soldByName = SellerDisplayName(names, o.SoldByEmployeeId, o.SoldBy),
                cogs,
                profit = cogs.HasValue ? o.Total - cogs.Value : (decimal?)null,
            };
        }).ToList();

        var count = sums?.Count ?? 0;
        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            count,
            truncated = count > items.Count,
            sumTotal = sums?.Total ?? 0m,
            sumVat = sums?.Vat ?? 0m,
            sumPaid = sums?.Paid ?? 0m,
            sumGrandTotal = sums?.Grand ?? 0m,
            sumDiscount = (sums?.OrderDiscount ?? 0m) + sumLineDiscount,
            sumVoucherDiscount = sums?.Voucher ?? 0m,
            sumCogs,
            sumProfit = sumCogs.HasValue ? (sums?.Total ?? 0m) - sumCogs.Value : (decimal?)null,
            items,
        }));
    }

    // ─── Phiếu trả hàng bán (chip «Hoàn trả») ────────────────────────────

    /// <summary>
    /// Phiếu khách trả hàng theo NGÀY TRẢ trong kỳ — cùng nguồn <see cref="PosSaleReturnLedger"/> và cùng giới hạn đơn với
    /// totalRefund của sales/summary (quản lý: đơn của chi nhánh đang lọc; nhân viên: đơn của mình bán trong kỳ).
    /// </summary>
    [HttpGet("drill-split/refunds")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> DrillSplitRefunds(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        IQueryable<Guid>? restrict;
        if (IsManager)
            restrict = BranchRefundOrderIds(storeId);
        else
            restrict = ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
                    .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                                o.Status == PosSaleOrderStatus.Completed &&
                                (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                                (o.SaleDate ?? o.CreatedAt) < toDt))
                .Select(o => o.Id);

        var slips = await PosSaleReturnLedger.RefundSlipsByReturnDateAsync(dbContext, storeId, fromDt, toDt);
        var slipOrderIds = slips.Select(s => s.OrderId).Distinct().ToList();
        if (restrict != null && slipOrderIds.Count > 0)
        {
            var allowed = (await restrict.Where(id => slipOrderIds.Contains(id)).ToListAsync()).ToHashSet();
            slips = slips.Where(s => allowed.Contains(s.OrderId)).ToList();
            slipOrderIds = slipOrderIds.Where(allowed.Contains).ToList();
        }
        var orderInfo = (await dbContext.PosSaleOrders.AsNoTracking()
                .Where(o => slipOrderIds.Contains(o.Id))
                .Select(o => new { o.Id, o.OrderNo, o.CustomerName })
                .ToListAsync())
            .ToDictionary(o => o.Id);

        var ordered = slips.OrderByDescending(s => s.ReturnedAt).ToList();
        var items = ordered.Take(DrillSplitMaxRows).Select(s =>
        {
            var info = orderInfo.GetValueOrDefault(s.OrderId);
            return new
            {
                orderId = s.OrderId,
                returnNo = s.ReturnNo,
                returnedAt = s.ReturnedAt,
                refund = s.Refund,
                orderNo = info?.OrderNo,
                customerName = info?.CustomerName,
            };
        }).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            count = ordered.Count,
            truncated = ordered.Count > items.Count,
            sumRefund = ordered.Sum(s => s.Refund),
            items,
        }));
    }

    // ─── Phiếu thu / chi (sổ quỹ, chi phí, tiền thu khi bán, thu nợ) ──────

    static readonly string[] DrillSplitNonCostExpense = ["Nhập hàng", "Trả hàng khách", "Hoàn cọc đặt chỗ"];

    /// <summary>Nhãn PTTT của sales/summary («Tiền mặt», «Chuyển khoản»…) → các giá trị enum («Khác» = còn lại).</summary>
    static PaymentMethodType[]? DrillSplitMethodsOfLabel(string? label, out bool other)
    {
        other = false;
        switch ((label ?? "").Trim())
        {
            case "": return null;
            case "Tiền mặt": return [PaymentMethodType.Cash];
            case "Chuyển khoản": return [PaymentMethodType.BankTransfer];
            case "VietQR": return [PaymentMethodType.VietQR];
            case "Thẻ": return [PaymentMethodType.Card];
            case "Ví điện tử": return [PaymentMethodType.EWallet];
            case "Khác":
                other = true;
                return [PaymentMethodType.Cash, PaymentMethodType.BankTransfer, PaymentMethodType.VietQR,
                    PaymentMethodType.Card, PaymentMethodType.EWallet];
        }
        return Enum.TryParse<PaymentMethodType>(label!.Trim(), true, out var m) ? [m] : null;
    }

    /// <summary>
    /// Danh sách phiếu thu / chi của một chip. <paramref name="scope"/>:
    /// <list type="bullet">
    /// <item><c>cashbook</c> — như cashbook/summary (nhân viên: phiếu thu của đơn mình bán, phiếu chi mình lập).</item>
    /// <item><c>expense</c> — như expenses/summary (chỉ phiếu chi, bỏ nhập hàng / trả hàng khách / hoàn cọc).</item>
    /// <item><c>sale</c> — phiếu thu bán hàng (thẻ «Đã thu» / PTTT của sales/summary, chỉ quản lý).</item>
    /// <item><c>debt</c> — phiếu thu nợ khách (debtCollected của sales/summary, chỉ quản lý).</item>
    /// </list>
    /// <paramref name="type"/>: Income / Expense; <paramref name="paymentMethod"/>: tên enum («Cash») hoặc nhãn
    /// sales/summary («Tiền mặt», «Khác»); <paramref name="category"/>: tên danh mục («Khác» = không danh mục).
    /// </summary>
    [HttpGet("drill-split/cash")]
    [RequireModulePermission("PosReportCashbook", ModulePermissionAction.View)]
    public Task<ActionResult<AppResponse<object>>> DrillSplitCash(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] int? dayStartHour = null,
        [FromQuery] string? type = null, [FromQuery] string? paymentMethod = null,
        [FromQuery] string? category = null) =>
        DrillSplitCashCoreAsync("cashbook", from, to, dayStartHour, type, paymentMethod, category);

    [HttpGet("drill-split/expenses")]
    [RequireModulePermission("PosReportExpense", ModulePermissionAction.View)]
    public Task<ActionResult<AppResponse<object>>> DrillSplitExpenses(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] int? dayStartHour = null,
        [FromQuery] string? category = null) =>
        DrillSplitCashCoreAsync("expense", from, to, dayStartHour, "Expense", null, category);

    [HttpGet("drill-split/sale-receipts")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public Task<ActionResult<AppResponse<object>>> DrillSplitSaleReceipts(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] int? dayStartHour = null,
        [FromQuery] string? kind = null, [FromQuery] string? paymentMethod = null) =>
        DrillSplitCashCoreAsync(string.Equals(kind, "debt", StringComparison.OrdinalIgnoreCase) ? "debt" : "sale",
            from, to, dayStartHour, "Income", paymentMethod, null);

    async Task<ActionResult<AppResponse<object>>> DrillSplitCashCoreAsync(
        string scope, DateTime? from, DateTime? to, int? dayStartHour,
        string? type, string? paymentMethod, string? category)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        if ((scope is "sale" or "debt") && !IsManager)
        {
            // sales/summary: nhân viên → «Đã thu» lấy PaidAmount đơn (không phải phiếu thu), thu nợ = 0.
            return Ok(AppResponse<object>.Success(new
            {
                from = fromVn.Date, to = toVnEx.AddDays(-1).Date, mode = "orders",
                count = 0, truncated = false, sumAmount = 0m, items = Array.Empty<object>(),
            }));
        }

        var txs = dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                        && c.Status == CashTransactionStatus.Completed
                        && c.TransactionDate >= fromDt.AddHours(7) && c.TransactionDate < toDt.AddHours(7) /* phiếu thu chi lưu giờ VN */);

        CashTransactionType? txType = Enum.TryParse<CashTransactionType>(type ?? "", true, out var tt) ? tt : null;
        if (txType.HasValue) txs = txs.Where(c => c.Type == txType.Value);

        switch (scope)
        {
            case "expense":
                txs = txs.Where(c => c.Type == CashTransactionType.Expense);
                if (!IsManager)
                    txs = txs.Where(c => c.CreatedBy == CurrentUserEmail || c.CreatedByUserId == CurrentUserId);
                txs = txs.Where(c => c.Category == null || !DrillSplitNonCostExpense.Contains(c.Category.Name));
                break;
            case "sale":
                txs = txs.Where(c => c.Type == CashTransactionType.Income && c.InternalNote != null &&
                                     c.InternalNote.StartsWith(PosFinanceSyncHelper.SaleMarker));
                break;
            case "debt":
                txs = txs.Where(c => c.Type == CashTransactionType.Income && c.InternalNote != null &&
                                     c.InternalNote.StartsWith(PosFinanceSyncHelper.CustomerPaymentMarker));
                break;
        }

        var methods = DrillSplitMethodsOfLabel(paymentMethod, out var otherMethods);
        if (methods != null)
            txs = otherMethods
                ? txs.Where(c => !methods.Contains(c.PaymentMethod))
                : txs.Where(c => methods.Contains(c.PaymentMethod));
        if (!string.IsNullOrWhiteSpace(category))
        {
            var cat = category.Trim();
            txs = cat == "Khác"
                ? txs.Where(c => c.Category == null || c.Category.Name == "Khác")
                : txs.Where(c => c.Category != null && c.Category.Name == cat);
        }

        // Sắp xếp / cắt TRƯỚC khi chiếu sang record (EF không dịch OrderBy trên thuộc tính của record).
        static IQueryable<DrillSplitCashRow> Project(IQueryable<CashTransaction> q) => q.Select(c => new DrillSplitCashRow(
            c.Id, c.TransactionCode, c.TransactionDate, c.Type, c.Amount, c.PaymentMethod, c.Description,
            c.Category != null ? c.Category.Name : null, c.InternalNote, c.CreatedBy, c.CreatedByUserId));

        List<DrillSplitCashRow> list;
        int count;
        decimal sum;
        if (scope == "cashbook" && !IsManager)
        {
            // Như cashbook/summary nhánh nhân viên: lọc trong bộ nhớ theo đơn của mình / phiếu mình lập.
            var myOrderIds = (await ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
                    .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive
                                && o.Status == PosSaleOrderStatus.Completed
                                && (o.SaleDate ?? o.CreatedAt) >= fromDt
                                && (o.SaleDate ?? o.CreatedAt) < toDt))
                .Select(o => o.Id)
                .ToListAsync()).ToHashSet();
            var email = CurrentUserEmail;
            var userId = CurrentUserId;
            var scoped = (await Project(txs).ToListAsync())
                .Where(c => c.Type == CashTransactionType.Income
                    ? ParseSaleOrderIdFromMarker(c.InternalNote) is Guid oid && myOrderIds.Contains(oid)
                    : string.Equals(c.CreatedBy, email, StringComparison.OrdinalIgnoreCase) || c.CreatedByUserId == userId)
                .OrderByDescending(c => c.TransactionDate)
                .ToList();
            count = scoped.Count;
            sum = scoped.Sum(c => c.Amount);
            list = scoped.Take(DrillSplitMaxRows).ToList();
        }
        else
        {
            count = await txs.CountAsync();
            sum = await txs.SumAsync(c => (decimal?)c.Amount) ?? 0m;
            list = await Project(txs.OrderByDescending(c => c.TransactionDate).Take(DrillSplitMaxRows)).ToListAsync();
        }

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            mode = "cash",
            count,
            truncated = count > list.Count,
            sumAmount = sum,
            items = list.Select(c => new
            {
                id = c.Id,
                transactionCode = c.TransactionCode,
                transactionDate = c.TransactionDate,
                type = c.Type.ToString(),
                amount = c.Amount,
                paymentMethod = c.PaymentMethod.ToString(),
                description = c.Description,
                category = c.Category,
                internalNote = c.InternalNote,
            }).ToList(),
        }));
    }

    sealed record DrillSplitCashRow(
        Guid Id, string? TransactionCode, DateTime TransactionDate, CashTransactionType Type, decimal Amount,
        PaymentMethodType PaymentMethod, string? Description, string? Category, string? InternalNote,
        string? CreatedBy, Guid CreatedByUserId);
}
