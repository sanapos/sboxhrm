using ClosedXML.Excel;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/reports")]
[Authorize]
public partial class PosReportsController(
    ZKTecoDbContext dbContext,
    IModulePermissionService modulePermissionService) : AuthenticatedControllerBase
{
    [HttpGet("sales/summary")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    // Thu ngân / NV không có quyền «Xem giá vốn & lợi nhuận»: bỏ giá vốn, lãi (Tổng quan, báo cáo bán hàng).
    [MaskCostData("totalCogs", "totalProfit", "profitMarginPct")]
    public async Task<ActionResult<AppResponse<object>>> GetSalesSummary(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        // Ngày doanh thu = SaleDate ?? CreatedAt; cửa sổ UTC+7 (+ ngày qua đêm nếu hour>0).
        var orders = ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt));

        // Mã đơn của kỳ là truy vấn con (IN (SELECT …)) — kỳ 1 năm không nạp ~100 nghìn mã rồi gửi lại thành mảng.
        var orderIds = orders.Select(o => o.Id);
        var totals = await OrderTotalsAsync(orders);
        var totalRevenue = totals.Revenue;
        var totalVat = totals.Vat;
        var totalPaid = totals.Paid;
        // Giảm giá = giảm từng dòng + giảm cả đơn + voucher + đổi điểm (doanh thu đã trừ đủ các khoản này).
        var totalDiscount = totals.Discount
            + await dbContext.PosSaleOrderLines.AsNoTracking()
                .Where(l => orderIds.Contains(l.SaleOrderId) && l.Deleted == null)
                .SumAsync(l => l.DiscountAmount);
        var orderCount = totals.Count;
        var totalRefund = await PosSaleReturnLedger.SumRefundsByReturnDateAsync(
            dbContext, storeId, fromDt, toDt, IsManager ? BranchRefundOrderIds(storeId) : orderIds);
        var totalRevenueInclVat = totalRevenue + totalVat;

        var byPaymentRaw = await dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                && c.Status == CashTransactionStatus.Completed
                && c.Type == CashTransactionType.Income
                && c.InternalNote != null
                && c.InternalNote.StartsWith(PosFinanceSyncHelper.SaleMarker)
                && c.TransactionDate >= fromDt.AddHours(7) && c.TransactionDate < toDt.AddHours(7) /* phiếu thu chi lưu giờ VN */)
            .GroupBy(c => c.PaymentMethod)
            .Select(g => new { Method = g.Key, total = g.Sum(x => x.Amount), count = g.Count() })
            .ToListAsync();

        static string PayLabel(PaymentMethodType method) => method switch
        {
            PaymentMethodType.Cash => "Tiền mặt",
            PaymentMethodType.BankTransfer => "Chuyển khoản",
            PaymentMethodType.VietQR => "VietQR",
            PaymentMethodType.Card => "Thẻ",
            PaymentMethodType.EWallet => "Ví điện tử",
            _ => "Khác",
        };

        object byPayment;
        if (byPaymentRaw.Count > 0 && IsManager)
        {
            byPayment = byPaymentRaw
                .Select(g => new { paymentMethod = PayLabel(g.Method), g.total, g.count })
                .OrderByDescending(x => x.total)
                .ToList();
            // «Đã thu» = tiền thu khi bán trong kỳ — cùng nguồn với biểu đồ PTTT.
            // PaidAmount của đơn cộng dồn cả tiền khách trả nợ về sau (kể cả ngày khác) và giảm khi
            // trả hàng → trước đây thẻ «Đã thu» lệch tổng các phương thức và tự đổi khi khách trả nợ.
            totalPaid = byPaymentRaw.Sum(g => g.total);
        }
        else
        {
            var byPaymentRows = await orders
                .GroupBy(o => o.PaymentMethod)
                .Select(g => new { paymentMethod = g.Key ?? "Khác", total = g.Sum(x => x.PaidAmount), count = g.Count() })
                .OrderByDescending(x => x.total)
                .ToListAsync();
            byPayment = byPaymentRows;
            totalPaid = byPaymentRows.Sum(x => x.total);
        }


        var topProducts = (await PosReportMoney.ProductSalesAsync(dbContext, storeId, orderIds))
            .Take(20)
            .Select(x => new
            {
                productId = x.ProductId,
                productName = x.ProductName,
                qty = x.Qty,
                revenue = x.Revenue,
            })
            .ToList();

        // Giá vốn thuần: đã trừ hàng khách trả, gồm giá vốn món dịch vụ.
        var cogsByOrder = await PosReportMoney.CogsByOrderAsync(dbContext, storeId, orderIds);
        var totalCogs = cogsByOrder.Values.Sum();

        // Cột ngày = NGÀY KINH DOANH VN: giờ bán (UTC trong DB) → giờ VN → lùi theo giờ cắt qua đêm.
        // Trước đây gom theo ngày UTC → đơn 00:00–06:59 sáng (và phần qua đêm) rơi sang cột ngày hôm trước.
        var orderRows = (await orders
                .Select(o => new { o.Id, BizAt = o.SaleDate ?? o.CreatedAt, o.Total })
                .ToListAsync())
            .Select(o => new { o.Id, o.BizAt, o.Total, BizDate = VnTimeHelper.ResolveBusinessDate(VnTimeHelper.UtcToVn(o.BizAt), hour) })
            .ToList();

        var byDay = orderRows
            .GroupBy(o => o.BizDate)
            .Select(g => new { date = g.Key, total = g.Sum(x => x.Total), count = g.Count() })
            .OrderBy(x => x.date)
            .ToList();

        var profitByDay = orderRows
            .GroupBy(o => o.BizDate)
            .Select(g =>
            {
                var revenue = g.Sum(x => x.Total);
                var cogs = g.Sum(x => cogsByOrder.GetValueOrDefault(x.Id));
                return new
                {
                    date = g.Key,
                    revenue,
                    cogs,
                    profit = revenue - cogs,
                    count = g.Count(),
                };
            })
            .OrderBy(x => x.date)
            .ToList();

        var topEmployees = await orders
            .GroupBy(o => new { o.SoldBy, o.SoldByEmployeeId })
            .Select(g => new
            {
                soldBy = g.Key.SoldBy,
                employeeId = g.Key.SoldByEmployeeId,
                revenue = g.Sum(x => x.Total),
                orderCount = g.Count(),
            })
            .OrderByDescending(x => x.revenue)
            .Take(200)
            .ToListAsync();

        var storeName = await dbContext.Stores.AsNoTracking()
            .Where(s => s.Id == storeId)
            .Select(s => s.Name)
            .FirstOrDefaultAsync();

        var reservations = await dbContext.PosResourceReservations.AsNoTracking()
            .Where(x => x.StoreId == storeId
                && x.ReservedAt >= fromDt && x.ReservedAt < toDt)
            .Select(x => new { x.Status, x.DepositPaid, x.DepositStatus, x.Deleted })
            .ToListAsync();
        var reservationBookedCount = reservations.Count(x =>
            x.Deleted == null && x.Status == PosResourceReservationStatus.Booked);
        var reservationDepositHeld = reservations
            .Where(x => x.Deleted == null && x.DepositStatus == PosReservationDepositStatus.Held)
            .Sum(x => x.DepositPaid);
        var reservationDepositApplied = reservations
            .Where(x => x.DepositStatus == PosReservationDepositStatus.Applied)
            .Sum(x => x.DepositPaid);
        var reservationDepositForfeited = reservations
            .Where(x => x.DepositStatus == PosReservationDepositStatus.Forfeited)
            .Sum(x => x.DepositPaid);
        var reservationDepositRefunded = reservations
            .Where(x => x.DepositStatus == PosReservationDepositStatus.Refunded)
            .Sum(x => x.DepositPaid);

        var depositCash = await dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                && c.Status == CashTransactionStatus.Completed
                && c.InternalNote != null
                && c.TransactionDate >= fromDt.AddHours(7) && c.TransactionDate < toDt.AddHours(7) /* phiếu thu chi lưu giờ VN */
                && (c.InternalNote.StartsWith(PosFinanceSyncHelper.ReservationDepositMarker)
                    || c.InternalNote.StartsWith(PosFinanceSyncHelper.ReservationDepositRefundMarker)))
            .Select(c => new { c.Type, c.Amount, c.PaymentMethod, c.InternalNote })
            .ToListAsync();
        var reservationDepositCollected = depositCash
            .Where(c => c.Type == CashTransactionType.Income
                && (c.InternalNote ?? "").StartsWith(PosFinanceSyncHelper.ReservationDepositMarker))
            .Sum(c => c.Amount);
        var reservationDepositRefundedCash = depositCash
            .Where(c => c.Type == CashTransactionType.Expense
                && (c.InternalNote ?? "").StartsWith(PosFinanceSyncHelper.ReservationDepositRefundMarker))
            .Sum(c => c.Amount);
        var reservationDepositByPayment = depositCash
            .Where(c => c.Type == CashTransactionType.Income
                && (c.InternalNote ?? "").StartsWith(PosFinanceSyncHelper.ReservationDepositMarker))
            .GroupBy(c => c.PaymentMethod)
            .Select(g => new { paymentMethod = PayLabel(g.Key), total = g.Sum(x => x.Amount), count = g.Count() })
            .OrderByDescending(x => x.total)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            dayStartHour = hour,
            overnight = hour > 0,
            storeName,
            totalRevenue,
            totalVat,
            totalRevenueInclVat,
            totalRefund,
            totalPaid,
            totalDiscount,
            totalCogs,
            totalProfit = totalRevenue - totalCogs,
            profitMarginPct = totalRevenue > 0
                ? Math.Round((totalRevenue - totalCogs) / totalRevenue * 100, 1)
                : 0m,
            orderCount,
            reservationBookedCount,
            reservationDepositHeld,
            reservationDepositApplied,
            reservationDepositForfeited,
            reservationDepositRefunded,
            reservationDepositCollected,
            reservationDepositRefundedCash,
            reservationDepositByPayment,
            byPayment,
            byDay,
            profitByDay,
            topProducts,
            topEmployees,
        }));
    }

    [HttpGet("sales/orders")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetSalesOrders(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] int? dayStartHour = null,
        [FromQuery] Guid? productId = null,
        [FromQuery] string? soldBy = null,
        [FromQuery] string? paymentMethod = null,
        [FromQuery] Guid? customerId = null,
        [FromQuery] string? voucherCode = null,
        [FromQuery] bool? hasVoucher = null,
        [FromQuery] string? staffKey = null)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        DateTime? fromDt = null;
        DateTime? toDt = null;
        if (from.HasValue || to.HasValue)
        {
            var range = ResolvePosRange(from, to, hour);
            fromDt = range.fromUtc;
            toDt = range.toUtcExclusive;
        }

        var query = ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive
                        && o.Status == PosSaleOrderStatus.Completed));
        if (fromDt.HasValue) query = query.Where(o => (o.SaleDate ?? o.CreatedAt) >= fromDt);
        if (toDt.HasValue) query = query.Where(o => (o.SaleDate ?? o.CreatedAt) < toDt);
        if (productId.HasValue)
        {
            var saleIds = dbContext.PosSaleOrderLines.AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Deleted == null &&
                            l.ProductId == productId.Value)
                .Select(l => l.SaleOrderId);
            query = query.Where(o => saleIds.Contains(o.Id));
        }
        if (!string.IsNullOrWhiteSpace(staffKey))
            query = ApplyStaffKey(query, staffKey);
        else if (!string.IsNullOrWhiteSpace(soldBy))
            query = query.Where(o => o.SoldBy != null && o.SoldBy.Contains(soldBy.Trim()));
        // «Công nợ» không phải phương thức lưu trên đơn — lọc đơn còn nợ (thu chưa đủ).
        if (string.Equals(paymentMethod?.Trim(), "Công nợ", StringComparison.OrdinalIgnoreCase))
            query = query.Where(o => o.Status == PosSaleOrderStatus.Completed &&
                                     o.PaidAmount + 0.5m < o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee);
        else if (!string.IsNullOrWhiteSpace(paymentMethod))
            query = query.Where(o => o.PaymentMethod != null &&
                                     o.PaymentMethod.Contains(paymentMethod.Trim()));
        if (customerId.HasValue)
            query = query.Where(o => o.CustomerId == customerId);
        if (!string.IsNullOrWhiteSpace(voucherCode))
            query = query.Where(o => o.VoucherCode != null &&
                                     o.VoucherCode.Contains(voucherCode.Trim()));
        if (hasVoucher == true)
            query = query.Where(o => o.VoucherCode != null && o.VoucherCode != "");

        var total = await query.CountAsync();
        var rawItems = await query
            .OrderByDescending(o => o.SaleDate ?? o.CreatedAt)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(o => new
            {
                o.Id,
                o.OrderNo,
                Status = o.Status.ToString(),
                o.SubTotal,
                o.Discount,
                o.Total,
                o.VatAmount,
                o.PaidAmount,
                o.PaymentMethod,
                o.CustomerName,
                o.CreatedAt,
                o.SaleDate,
                o.CreatedBy,
                o.SoldBy,
                o.VoucherCode,
                LineCount = o.Lines.Count,
            })
            .ToListAsync();

        var items = rawItems.Select(o =>
        {
            var saleAt = o.SaleDate ?? o.CreatedAt;
            var closedOff = o.Status == nameof(PosSaleOrderStatus.Completed)
                && PosSaleStockHelper.IsClosedOffDay(o.OrderNo, o.CreatedAt, saleAt);
            return new
            {
                o.Id,
                o.OrderNo,
                o.Status,
                o.SubTotal,
                o.Discount,
                o.Total,
                o.VatAmount,
                o.PaidAmount,
                o.PaymentMethod,
                o.CustomerName,
                o.CreatedAt,
                o.SaleDate,
                o.CreatedBy,
                o.SoldBy,
                o.VoucherCode,
                o.LineCount,
                closedOffDay = closedOff,
            };
        }).ToList();

        return Ok(AppResponse<object>.Success(new { total, page, pageSize, items }));
    }

    [HttpGet("sales/export/excel")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportSalesExcel(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var orders = await ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt))
            .OrderByDescending(o => o.SaleDate ?? o.CreatedAt)
            .ToListAsync();

        using var workbook = new XLWorkbook();
        var ws = workbook.Worksheets.Add("Doanh thu POS");
        var headers = new[]
        {
            "STT", "Mã đơn", "Ngày", "Khách hàng", "Tạm tính", "Giảm giá",
            "Tổng (chưa VAT)", "VAT", "Tổng gồm VAT", "Đã thu", "Thanh toán", "Trạng thái",
            "Người bán", "Người tạo", "Voucher", "Ghi chú"
        };

        var meta = ReportExcelMeta.FromUser(
            User, "BÁO CÁO DOANH THU POS",
            $"{fromVn:dd/MM/yyyy} - {toVnEx.AddDays(-1):dd/MM/yyyy}" +
            (hour > 0 ? $" (qua đêm từ {hour:00}:00)" : " (UTC+7)"),
            null,
            new[] { $"Tổng đơn: {orders.Count}" }, orders.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);

        var row = dataStartRow;
        var idx = 1;
        foreach (var o in orders)
        {
            ws.Cell(row, 1).Value = idx++;
            ws.Cell(row, 2).Value = o.OrderNo;
            // DB lưu UTC → giờ VN (trước đây cột Ngày lệch 7 giờ).
            ws.Cell(row, 3).Value = VnTimeHelper.UtcToVn(o.SaleDate ?? o.CreatedAt).ToString("dd/MM/yyyy HH:mm");
            ws.Cell(row, 4).Value = o.CustomerName ?? "";
            ws.Cell(row, 5).Value = o.SubTotal;
            ws.Cell(row, 6).Value = o.Discount;
            ws.Cell(row, 7).Value = o.Total;
            ws.Cell(row, 8).Value = o.VatAmount;
            ws.Cell(row, 9).Value = o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee;
            ws.Cell(row, 10).Value = o.PaidAmount;
            ws.Cell(row, 11).Value = o.PaymentMethod;
            ws.Cell(row, 12).Value = SaleStatusLabel(o.Status);
            ws.Cell(row, 13).Value = o.SoldBy ?? "";
            ws.Cell(row, 14).Value = o.CreatedBy ?? "";
            ws.Cell(row, 15).Value = o.VoucherCode ?? "";
            var saleAt = o.SaleDate ?? o.CreatedAt;
            ws.Cell(row, 16).Value = o.Status == PosSaleOrderStatus.Completed
                && PosSaleStockHelper.IsClosedOffDay(o.OrderNo, o.CreatedAt, saleAt)
                ? "Chốt ngày khác"
                : "";
            row++;
        }
        if (orders.Count > 0)
        {
            ws.Cell(row, 2).Value = "TỔNG CỘNG";
            ws.Cell(row, 5).Value = orders.Sum(o => o.SubTotal);
            ws.Cell(row, 6).Value = orders.Sum(o => o.Discount);
            ws.Cell(row, 7).Value = orders.Sum(o => o.Total);
            ws.Cell(row, 8).Value = orders.Sum(o => o.VatAmount);
            ws.Cell(row, 9).Value = orders.Sum(o => o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee);
            ws.Cell(row, 10).Value = orders.Sum(o => o.PaidAmount);
            ws.Range(row, 1, row, headers.Length).Style.Font.Bold = true;
        }

        ReportExcelLayout.FinishSheet(ws, headerRow);

        // Theo PTTT: theo phiếu thu khi bán (cùng nguồn với biểu đồ trên màn hình). Trước đây nhóm theo chữ
        // «phương thức» ghi trên đơn + PaidAmount → tiền khách trả nợ bằng tiền mặt bị cộng vào «Chuyển khoản».
        var orderIdSet = orders.Select(o => o.Id).ToHashSet();
        var saleCash = (await dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
                .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                    && c.Status == CashTransactionStatus.Completed
                    && c.Type == CashTransactionType.Income
                    && c.InternalNote != null
                    && c.InternalNote.StartsWith(PosFinanceSyncHelper.SaleMarker)
                    && c.TransactionDate >= fromDt.AddHours(7) && c.TransactionDate < toDt.AddHours(7))
                .Select(c => new { c.PaymentMethod, c.Amount, c.InternalNote })
                .ToListAsync())
            .Where(c => ParseSaleOrderIdFromMarker(c.InternalNote) is Guid oid && orderIdSet.Contains(oid))
            .ToList();

        var payWs = workbook.Worksheets.Add("Theo PTTT");
        var payHeaders = new[] { "Phương thức", "Số phiếu thu", "Đã thu khi bán" };
        var payMeta = ReportExcelMeta.FromUser(
            User, "DOANH THU THEO PHƯƠNG THỨC",
            $"{fromVn:dd/MM/yyyy} - {toVnEx.AddDays(-1):dd/MM/yyyy}",
            null, Array.Empty<string>(), orders.Count);
        var (payHeaderRow, payDataStart) = ReportExcelLayout.ApplyMeta(payWs, payMeta, payHeaders.Length);
        ReportExcelLayout.ApplyHeaderRow(payWs, payHeaderRow, payHeaders);
        var payRow = payDataStart;
        foreach (var g in saleCash.GroupBy(c => c.PaymentMethod).OrderByDescending(g => g.Sum(x => x.Amount)))
        {
            payWs.Cell(payRow, 1).Value = PaymentMethodLabel(g.Key);
            payWs.Cell(payRow, 2).Value = g.Count();
            payWs.Cell(payRow, 3).Value = g.Sum(x => x.Amount);
            payRow++;
        }
        if (saleCash.Count > 0)
        {
            payWs.Cell(payRow, 1).Value = "TỔNG CỘNG";
            payWs.Cell(payRow, 2).Value = saleCash.Count;
            payWs.Cell(payRow, 3).Value = saleCash.Sum(x => x.Amount);
            payWs.Range(payRow, 1, payRow, payHeaders.Length).Style.Font.Bold = true;
        }
        ReportExcelLayout.FinishSheet(payWs, payHeaderRow);

        var staffWs = workbook.Worksheets.Add("Theo NV");
        var staffHeaders = new[] { "Người bán", "Số HĐ", "Doanh thu", "Đã thu" };
        var staffMeta = ReportExcelMeta.FromUser(
            User, "DOANH THU THEO NHÂN VIÊN",
            $"{fromVn:dd/MM/yyyy} - {toVnEx.AddDays(-1):dd/MM/yyyy}",
            null, Array.Empty<string>(), orders.Count);
        var (staffHeaderRow, staffDataStart) = ReportExcelLayout.ApplyMeta(staffWs, staffMeta, staffHeaders.Length);
        ReportExcelLayout.ApplyHeaderRow(staffWs, staffHeaderRow, staffHeaders);
        var staffRow = staffDataStart;
        foreach (var g in orders.GroupBy(o => string.IsNullOrWhiteSpace(o.SoldBy) ? "(trống)" : o.SoldBy!)
                     .OrderByDescending(g => g.Sum(x => x.Total)))
        {
            staffWs.Cell(staffRow, 1).Value = g.Key;
            staffWs.Cell(staffRow, 2).Value = g.Count();
            staffWs.Cell(staffRow, 3).Value = g.Sum(x => x.Total);
            staffWs.Cell(staffRow, 4).Value = g.Sum(x => x.PaidAmount);
            staffRow++;
        }
        ReportExcelLayout.FinishSheet(staffWs, staffHeaderRow);

        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"BaoCaoDoanhThuPOS_{DateTime.Now:yyyyMMdd_HHmm}.xlsx");
    }

    private static string SaleStatusLabel(PosSaleOrderStatus status) => status switch
    {
        PosSaleOrderStatus.Completed => "Hoàn thành",
        PosSaleOrderStatus.Cancelled => "Đã hủy",
        PosSaleOrderStatus.Draft => "Phiếu tạm",
        _ => status.ToString(),
    };

    private static string PaymentMethodLabel(PaymentMethodType method) => method switch
    {
        PaymentMethodType.Cash => "Tiền mặt",
        PaymentMethodType.BankTransfer => "Chuyển khoản",
        PaymentMethodType.VietQR => "VietQR",
        PaymentMethodType.Card => "Thẻ",
        PaymentMethodType.EWallet => "Ví điện tử",
        _ => "Khác",
    };

    /// <summary>Báo cáo hàng hóa: top doanh thu + top giá trị tồn.</summary>
    [HttpGet("goods/summary")]
    [RequireModulePermission("PosReportSoldGoods", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetGoodsSummary(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int limit = 20,
        [FromQuery] int? dayStartHour = null,
        [FromQuery] bool includeGoods = true,
        [FromQuery] bool includeService = true,
        [FromQuery] bool includeCombo = true,
        [FromQuery] bool activeOnly = true,
        [FromQuery] bool inactiveOnly = false,
        [FromQuery] string? inventoryStatus = null,
        [FromQuery] string? staffKey = null)
    {
        var storeId = RequiredStoreId;
        limit = Math.Clamp(limit, 1, 1000);
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, _, _) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var productScope = ApplyGoodsProductScope(
            dbContext.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null),
            includeGoods, includeService, includeCombo, activeOnly, inactiveOnly);

        // staffKey: «Hàng bán theo nhân viên» — chỉ đơn của người bán đó.
        var goodsOrderIds = ApplyStaffKey(ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt)), staffKey)
            .Select(o => o.Id);
        var allowedProducts = await productScope.Select(p => new { p.Id, p.ProductCode }).ToListAsync();
        var codeById = allowedProducts.ToDictionary(p => p.Id, p => p.ProductCode);
        var topByRevenue = (await PosReportMoney.ProductSalesAsync(dbContext, storeId, goodsOrderIds))
            .Where(x => codeById.ContainsKey(x.ProductId))
            .Take(limit)
            .Select(x => new
            {
                productId = x.ProductId,
                // Excel «Hàng hóa bán ra» cần mã hàng (trước đây rơi về GUID) và giảm giá dòng (trước đây 0).
                productCode = codeById.GetValueOrDefault(x.ProductId) ?? "",
                productName = x.ProductName,
                qty = x.Qty,
                revenue = x.Revenue,
                lineDiscount = x.LineDiscount,
                orderCount = x.OrderCount,
            })
            .ToList();

        var stockScope = StockTracked(ApplyGoodsInventoryFilter(productScope, inventoryStatus));
        var topByStockValue = await stockScope
            .OrderByDescending(p => p.OnHandQty * p.CostPrice)
            .Take(limit)
            .Select(p => new
            {
                p.Id,
                p.ProductCode,
                p.Name,
                p.OnHandQty,
                p.MinStockQty,
                p.MaxStockQty,
                p.CostPrice,
                stockValue = p.OnHandQty * p.CostPrice,
                p.BaseUnitName,
                productType = p.ProductType.ToString(),
            })
            .ToListAsync();

        var stockRows = await stockScope
            .Select(p => new { p.Id, p.OnHandQty, p.CostPrice, p.MinStockQty })
            .ToListAsync();
        var inventoryValue = await InventoryValueAsync(dbContext, storeId,
            stockRows.Select(p => (p.Id, p.OnHandQty, p.CostPrice)).ToList());

        return Ok(AppResponse<object>.Success(new
        {
            from = fromDt,
            to = toDt.AddDays(-1),
            inventoryValue,
            productCount = stockRows.Count,
            totalOnHandQty = stockRows.Sum(p => p.OnHandQty),
            outOfStockCount = stockRows.Count(p => p.OnHandQty <= 0),
            belowMinCount = stockRows.Count(p => p.MinStockQty > 0 && p.OnHandQty < p.MinStockQty && p.OnHandQty > 0),
            topByRevenue,
            topByStockValue,
        }));
    }

    /// <summary>Phân tích tình hình kinh doanh — so sánh kỳ trước.</summary>
    [HttpGet("analysis/overview")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetBusinessAnalysis(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);
        var spanDays = Math.Max(1, (toVnEx.Date - fromVn.Date).Days);
        var prevRange = ResolvePosRange(
            fromVn.Date.AddDays(-spanDays), fromVn.Date.AddDays(-1), hour);
        var prevFrom = prevRange.fromUtc;
        var prevTo = prevRange.toUtcExclusive;

        var refundBranchOrderIds = IsManager ? BranchRefundOrderIds(storeId) : null;

        async Task<(decimal revenue, decimal vat, decimal cogs, int orders, decimal discount, decimal refund)> PeriodAsync(
            DateTime start, DateTime end)
        {
            var q = ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
                .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                            o.Status == PosSaleOrderStatus.Completed &&
                            (o.SaleDate ?? o.CreatedAt) >= start &&
                            (o.SaleDate ?? o.CreatedAt) < end));
            var totals = await OrderTotalsAsync(q);
            var revenue = totals.Revenue;
            var vat = totals.Vat;
            var count = totals.Count;
            var ids = q.Select(o => o.Id);
            // Cùng cách tính với báo cáo bán hàng: giảm đơn + voucher + đổi điểm + giảm từng dòng.
            var discount = totals.Discount
                + (await dbContext.PosSaleOrderLines.AsNoTracking()
                    .Where(l => ids.Contains(l.SaleOrderId) && l.Deleted == null)
                    .SumAsync(l => (decimal?)l.DiscountAmount) ?? 0);
            var cogs = await PosReportMoney.CogsTotalAsync(dbContext, storeId, ids);
            var refund = await PosSaleReturnLedger.SumRefundsByReturnDateAsync(
                dbContext, storeId, start, end, IsManager ? refundBranchOrderIds : ids);
            // Total = tiền hàng đã trừ giảm giá và hàng trả, CHƯA gồm VAT (VAT lưu riêng ở VatAmount).
            // Tiền hoàn chỉ để xem — Total đã giảm khi trả hàng, không trừ thêm.
            return (revenue, vat, cogs, count, discount, refund);
        }

        var current = await PeriodAsync(fromDt, toDt);
        var previous = await PeriodAsync(prevFrom, prevTo);
        var yoyRange = ResolvePosRange(
            fromVn.Date.AddYears(-1), toVnEx.Date.AddYears(-1).AddDays(-1), hour);
        var yearAgo = await PeriodAsync(yoyRange.fromUtc, yoyRange.toUtcExclusive);

        var byChannel = await ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt))
            .GroupBy(o => o.SalesChannel ?? "Khác")
            .Select(g => new { channel = g.Key, revenue = g.Sum(x => x.Total), count = g.Count() })
            .OrderByDescending(x => x.revenue)
            .ToListAsync();

        var analysisOrderIds = ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt))
            .Select(o => o.Id);
        var analysisAgg = await PosReportMoney.ProductSalesAsync(dbContext, storeId, analysisOrderIds);
        var analysisProductIds = analysisAgg.Select(x => x.ProductId).Distinct().ToList();
        var analysisCatOf = analysisProductIds.Count == 0
            ? new Dictionary<Guid, Guid?>()
            : await dbContext.PosProducts.AsNoTracking()
                .Where(p => analysisProductIds.Contains(p.Id))
                .ToDictionaryAsync(p => p.Id, p => p.CategoryId);
        var byCategory = analysisAgg
            .GroupBy(x => analysisCatOf.GetValueOrDefault(x.ProductId))
            .Select(g => new
            {
                categoryId = g.Key,
                revenue = g.Sum(x => x.Revenue),
            })
            .OrderByDescending(x => x.revenue)
            .Take(10)
            .ToList();

        var categoryIds = byCategory.Where(c => c.categoryId.HasValue).Select(c => c.categoryId!.Value).ToList();
        var categoryNames = await dbContext.PosProductCategories.AsNoTracking()
            .Where(c => categoryIds.Contains(c.Id))
            .ToDictionaryAsync(c => c.Id, c => c.Name);

        var topCategories = byCategory.Select(c => new
        {
            categoryId = c.categoryId,
            categoryName = c.categoryId.HasValue
                ? categoryNames.GetValueOrDefault(c.categoryId.Value, "Khác")
                : "Khác",
            revenue = c.revenue,
        }).ToList();

        decimal PctChange(decimal cur, decimal prev) =>
            prev == 0 ? (cur > 0 ? 100 : 0) : Math.Round((cur - prev) / prev * 100, 1);

        var storeName = await dbContext.Stores.AsNoTracking()
            .Where(s => s.Id == storeId)
            .Select(s => s.Name)
            .FirstOrDefaultAsync();

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            dayStartHour = hour,
            overnight = hour > 0,
            storeName,
            current = new
            {
                revenue = current.revenue,
                vat = current.vat,
                revenueInclVat = current.revenue + current.vat,
                refund = current.refund,
                cogs = current.cogs,
                profit = current.revenue - current.cogs,
                marginPct = current.revenue > 0
                    ? Math.Round((current.revenue - current.cogs) / current.revenue * 100, 1)
                    : 0m,
                orderCount = current.orders,
                avgOrderValue = current.orders > 0
                    ? Math.Round(current.revenue / current.orders, 0)
                    : 0m,
                discount = current.discount,
            },
            previous = new
            {
                revenue = previous.revenue,
                vat = previous.vat,
                revenueInclVat = previous.revenue + previous.vat,
                refund = previous.refund,
                cogs = previous.cogs,
                profit = previous.revenue - previous.cogs,
                orderCount = previous.orders,
                avgOrderValue = previous.orders > 0
                    ? Math.Round(previous.revenue / previous.orders, 0)
                    : 0m,
            },
            yearAgo = new
            {
                revenue = yearAgo.revenue,
                profit = yearAgo.revenue - yearAgo.cogs,
                orderCount = yearAgo.orders,
            },
            changePct = new
            {
                revenue = PctChange(current.revenue, previous.revenue),
                profit = PctChange(current.revenue - current.cogs, previous.revenue - previous.cogs),
                orders = PctChange(current.orders, previous.orders),
            },
            changePctYoy = new
            {
                revenue = PctChange(current.revenue, yearAgo.revenue),
                profit = PctChange(current.revenue - current.cogs, yearAgo.revenue - yearAgo.cogs),
                orders = PctChange(current.orders, yearAgo.orders),
            },
            byChannel,
            topCategories,
        }));
    }

    /// <summary>Hàng có theo dõi tồn: hàng hóa, NVL, topping, combo bật quản lý tồn gói (dịch vụ / combo theo
    /// thành phần không có tồn riêng → không tính «hết hàng»).</summary>
    static IQueryable<PosProduct> StockTracked(IQueryable<PosProduct> q) =>
        q.Where(p => p.ProductType == PosProductType.Goods || p.ProductType == PosProductType.Material ||
                     p.ProductType == PosProductType.Topping ||
                     (p.ProductType == PosProductType.Combo && p.ComboTrackStock));

    /// <summary>Giá trị tồn: hàng có biến thể riêng tính theo tồn × giá vốn từng biến thể (giống báo cáo tồn kho).</summary>
    static async Task<decimal> InventoryValueAsync(ZKTecoDbContext db, Guid storeId,
        IReadOnlyCollection<(Guid Id, decimal OnHandQty, decimal CostPrice)> products)
    {
        if (products.Count == 0) return 0;
        var ids = products.Select(p => p.Id).ToList();
        var variants = await db.PosProductVariants.AsNoTracking()
            .Where(v => v.StoreId == storeId && v.Deleted == null && v.IsActive && ids.Contains(v.ProductId))
            .Select(v => new { v.ProductId, v.AttributeJson, v.OnHandQty, v.CostPrice })
            .ToListAsync();
        var distinct = variants.Where(v => !PosVariantStockHelper.IsUnitOnlyVariant(v.AttributeJson))
            .Select(v => v.ProductId).ToHashSet();
        return products.Where(p => !distinct.Contains(p.Id)).Sum(p => p.OnHandQty * p.CostPrice) +
               variants.Where(v => distinct.Contains(v.ProductId)).Sum(v => v.OnHandQty * v.CostPrice);
    }

    [HttpGet("stock/summary")]
    [RequireModulePermission("PosReportStock", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetStockSummary()
    {
        var rows = await LoadStockRowsAsync(RequiredStoreId);
        var totalQty = rows.Sum(r => r.OnHandQty);
        var value = rows.Sum(r => r.StockValue);
        var outOfStock = rows.Count(r => r.Status == "OutOfStock");
        return Ok(AppResponse<object>.Success(new
        {
            totalSkus = rows.Count,
            totalQty,
            inventoryValue = value,
            outOfStock,
            belowMin = rows.Count(r => r.Status == "BelowMin"),
            aboveMax = rows.Count(r => r.Status == "AboveMax"),
            okCount = rows.Count(r => r.Status == "Ok"),
            // Tồn âm (bán quá tồn) — giá trị âm kéo tổng xuống, cần kiểm kho.
            negativeCount = rows.Count(r => r.OnHandQty < 0),
            productCount = rows.Count,
            totalStockValue = value,
            totalOnHandQty = totalQty,
            outOfStockCount = outOfStock,
        }));
    }

    [HttpGet("stock/products")]
    [RequireModulePermission("PosReportStock", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetStockProducts(
        [FromQuery] string? search,
        [FromQuery] string? filter,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        [FromQuery] string? sort = null)
    {
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 200);
        var rows = FilterStockRows(await LoadStockRowsAsync(RequiredStoreId, search), filter).ToList();
        // Sắp xếp trên toàn bộ danh sách (trước đây chỉ sắp trong trang đang xem).
        IEnumerable<PosStockRow> ordered = (sort ?? "").ToLowerInvariant() switch
        {
            "value" => rows.OrderByDescending(r => r.StockValue),
            "qty" => rows.OrderByDescending(r => r.OnHandQty),
            "qtyasc" => rows.OrderBy(r => r.OnHandQty),
            "name" => rows.OrderBy(r => r.Name),
            _ => rows.OrderBy(r => r.Status switch { "OutOfStock" => 0, "BelowMin" => 1, "AboveMax" => 2, _ => 3 })
                .ThenBy(r => r.Name),
        };
        var items = ordered.Skip((page - 1) * pageSize).Take(pageSize).Select(r => new
        {
            r.Id, r.ProductCode, r.Barcode, r.Name, r.BaseUnitName, r.CategoryName, r.OnHandQty, r.MinStockQty,
            r.MaxStockQty, r.CostPrice, stockValue = r.StockValue, r.ProductType, status = r.Status,
        }).ToList();
        return Ok(AppResponse<object>.Success(new
        {
            total = rows.Count, page, pageSize, totalValue = rows.Sum(r => r.StockValue), items,
        }));
    }

    /// <summary>
    /// Hàng cần nhập thêm: tồn ≤ tồn tối thiểu. Gợi ý nhập = tồn tối đa − tồn (chưa đặt tồn tối đa → 2 × tối thiểu − tồn),
    /// kèm nhà cung cấp mặc định + giá vốn để tạo phiếu nhập nháp theo từng NCC.
    /// </summary>
    [HttpGet("stock/reorder-suggestions")]
    [RequireModulePermission("PosReportStock", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetReorderSuggestions()
    {
        var storeId = RequiredStoreId;
        // Cùng truy vấn với trợ lý ảo (find_reorder_suggestions).
        var rows = await PosReorderSuggestionHelper.LoadAsync(dbContext, storeId);
        var items = rows.Select(p => new
        {
            productId = p.ProductId, productCode = p.ProductCode, name = p.Name, unitName = p.UnitName,
            onHand = p.OnHand, minStock = p.MinStock, maxStock = p.MaxStock,
            suggestQty = p.SuggestQty, costPrice = p.CostPrice, amount = p.Amount,
            supplierId = p.SupplierId, supplierName = p.SupplierName,
            outOfStock = p.OutOfStock,
        }).ToList();
        return Ok(AppResponse<object>.Success(new
        {
            count = items.Count,
            outOfStock = items.Count(i => i.outOfStock),
            totalAmount = items.Sum(i => i.amount),
            items,
        }));
    }

    /// <summary>Lô còn hàng của cửa hàng (bỏ lô của hàng đã xóa) kèm ngưỡng cảnh báo đã chuẩn hóa.</summary>
    private IQueryable<PosStockLot> ActiveLotsQuery(Guid storeId) =>
        dbContext.PosStockLots.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive &&
                        l.Status == PosStockLotStatus.Active && l.QtyOnHand > 0 &&
                        l.Product != null && l.Product.Deleted == null);

    static string LotStatus(DateTime? expiry, int warnDays, DateTime today)
    {
        if (!expiry.HasValue) return "noexpiry";
        var days = (expiry.Value.Date - today).Days;
        return days < 0 ? "expired" : days <= warnDays ? "expiring" : "ok";
    }

    [HttpGet("stock/lots/summary")]
    [RequireModulePermission("PosReportExpiry", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetStockLotsSummary()
    {
        var storeId = RequiredStoreId;
        var today = VnToday;
        var lots = (await ActiveLotsQuery(storeId)
                .Select(l => new { l.QtyOnHand, l.ExpiryDate, l.UnitCost, Warn = l.Product!.ExpiryWarningDays })
                .ToListAsync())
            .Select(l => (l.QtyOnHand, Value: l.QtyOnHand * l.UnitCost, Status: LotStatus(l.ExpiryDate, ExpiryWarnDays(l.Warn), today)))
            .ToList();
        var expired = lots.Where(l => l.Status == "expired").ToList();
        var expiring = lots.Where(l => l.Status == "expiring").ToList();
        return Ok(AppResponse<object>.Success(new
        {
            activeLotCount = lots.Count,
            totalLotQty = lots.Sum(l => l.QtyOnHand),
            lotInventoryValue = lots.Sum(l => l.Value),
            expiredLotCount = expired.Count,
            expiredQty = expired.Sum(l => l.QtyOnHand),
            expiredValue = expired.Sum(l => l.Value),
            expiringSoonLotCount = expiring.Count,
            expiringSoonQty = expiring.Sum(l => l.QtyOnHand),
            expiringSoonValue = expiring.Sum(l => l.Value),
            okLotCount = lots.Count(l => l.Status == "ok"),
            noExpiryLotCount = lots.Count(l => l.Status == "noexpiry"),
        }));
    }

    /// <summary>
    /// Lô theo hạn dùng. filter: attention (đã hết + sắp hết — mặc định của màn «Hàng sắp hết hạn»), expiring,
    /// expired, ok (còn hạn xa), noexpiry (lô không ghi HSD), trống = tất cả.
    /// </summary>
    [HttpGet("stock/lots")]
    [RequireModulePermission("PosReportExpiry", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetStockLotsReport(
        [FromQuery] string? search,
        [FromQuery] string? filter,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(page, 1);
        pageSize = Math.Clamp(pageSize, 1, 500);
        var today = VnToday;

        var query = ActiveLotsQuery(storeId);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            query = query.Where(l =>
                l.Product!.Name.ToLower().Contains(s) ||
                l.Product.ProductCode.ToLower().Contains(s) ||
                (l.Product.Barcode != null && l.Product.Barcode.ToLower().Contains(s)) ||
                (l.LotNo != null && l.LotNo.ToLower().Contains(s)));
        }

        // Lọc trong bộ nhớ: ngưỡng cảnh báo theo từng hàng (0 → 30) — trước đây bộ lọc và nhãn dùng 2 ngưỡng khác nhau.
        var all = (await query
                .Select(l => new
                {
                    l.Id, l.ProductId, l.VariantId,
                    ProductCode = l.Product!.ProductCode,
                    ProductName = l.Product.Name,
                    UnitName = l.Product.BaseUnitName,
                    l.LotNo, l.ManufactureDate, l.ExpiryDate, l.QtyOnHand, l.UnitCost,
                    Warn = l.Product.ExpiryWarningDays,
                })
                .ToListAsync())
            .Select(r =>
            {
                var warn = ExpiryWarnDays(r.Warn);
                int? days = r.ExpiryDate.HasValue ? (r.ExpiryDate.Value.Date - today).Days : null;
                return new
                {
                    r.Id, r.ProductId, r.VariantId, r.ProductCode, r.ProductName, r.UnitName, r.LotNo,
                    r.ManufactureDate, r.ExpiryDate, r.QtyOnHand, r.UnitCost,
                    stockValue = r.QtyOnHand * r.UnitCost,
                    daysUntilExpiry = days,
                    warningDays = warn,
                    status = LotStatus(r.ExpiryDate, warn, today),
                };
            });

        var f = (filter ?? "").Trim().ToLowerInvariant();
        var rows = (f switch
            {
                "attention" => all.Where(r => r.status is "expired" or "expiring"),
                "expired" or "expiring" or "ok" or "noexpiry" => all.Where(r => r.status == f),
                _ => all,
            })
            .OrderBy(r => r.ExpiryDate ?? DateTime.MaxValue)
            .ThenBy(r => r.ProductName)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            total = rows.Count,
            page,
            pageSize,
            totalQty = rows.Sum(r => r.QtyOnHand),
            totalValue = rows.Sum(r => r.stockValue),
            items = rows.Skip((page - 1) * pageSize).Take(pageSize).ToList(),
        }));
    }

    [HttpGet("stock/export/excel")]
    [RequireModulePermission("PosReportStock", ModulePermissionAction.Export)]
    public async Task<IActionResult> ExportStockExcel([FromQuery] string? search, [FromQuery] string? filter)
    {
        // Cùng dữ liệu với màn hình: bộ lọc tình trạng, tồn theo chi nhánh đang xem, giá trị theo biến thể.
        var products = FilterStockRows(await LoadStockRowsAsync(RequiredStoreId, search), filter)
            .OrderBy(r => r.Name).ToList();

        using var workbook = new XLWorkbook();
        var ws = workbook.Worksheets.Add("Ton kho POS");
        var headers = new[]
        {
            "STT", "Mã hàng", "Mã vạch", "Tên hàng", "Nhóm hàng", "ĐVT", "Tồn kho",
            "Tồn tối thiểu", "Tồn tối đa", "Giá vốn", "Giá trị tồn", "Tình trạng"
        };
        var filterLabel = Enum.TryParse<PosStockFilter>(filter, true, out var sf) && sf != PosStockFilter.All
            ? $"Tình trạng: {StockStatusVi(sf.ToString())}"
            : null;
        var meta = ReportExcelMeta.FromUser(
            User, "BÁO CÁO TỒN KHO POS", null, null,
            new[] { $"Tổng mặt hàng: {products.Count}", $"Giá trị tồn: {products.Sum(p => p.StockValue):#,##0}", filterLabel }
                .Where(x => x != null).Select(x => x!).ToArray(),
            products.Count);
        var (headerRow, dataStartRow) = ReportExcelLayout.ApplyMeta(ws, meta, headers.Length);
        ReportExcelLayout.ApplyHeaderRow(ws, headerRow, headers);

        var row = dataStartRow;
        var idx = 1;
        foreach (var p in products)
        {
            ws.Cell(row, 1).Value = idx++;
            ws.Cell(row, 2).Value = p.ProductCode;
            ws.Cell(row, 3).Value = p.Barcode ?? "";
            ws.Cell(row, 4).Value = p.Name;
            ws.Cell(row, 5).Value = p.CategoryName ?? "";
            ws.Cell(row, 6).Value = p.BaseUnitName ?? "";
            ws.Cell(row, 7).Value = p.OnHandQty;
            ws.Cell(row, 8).Value = p.MinStockQty;
            ws.Cell(row, 9).Value = p.MaxStockQty;
            ws.Cell(row, 10).Value = p.CostPrice;
            ws.Cell(row, 11).Value = p.StockValue;
            ws.Cell(row, 12).Value = StockStatusVi(p.Status);
            row++;
        }

        ReportExcelLayout.FinishSheet(ws, headerRow);
        using var stream = new MemoryStream();
        workbook.SaveAs(stream);
        return File(stream.ToArray(),
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"BaoCaoTonKhoPOS_{DateTime.Now:yyyyMMdd_HHmm}.xlsx");
    }

    static string StockStatusVi(string status) => status switch
    {
        "OutOfStock" => "Hết hàng",
        "BelowMin" => "Dưới tối thiểu",
        "AboveMax" => "Vượt tối đa",
        _ => "Đủ hàng",
    };

    /// <summary>Tổng kết cuối ngày theo nhân viên (người bán / người tạo).</summary>
    [HttpGet("end-of-day")]
    [RequireModulePermission("PosReportEndOfDay", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetEndOfDay(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string? staffEmail,
        [FromQuery] Guid? soldByEmployeeId,
        [FromQuery] string filterBy = "soldByEmployee",
        [FromQuery] bool includeProductDetail = true,
        [FromQuery] bool includeTransactions = false,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour);
        var filter = filterBy.Equals("createdBy", StringComparison.OrdinalIgnoreCase)
            ? "createdBy"
            : filterBy.Equals("soldByEmployee", StringComparison.OrdinalIgnoreCase)
                ? "soldByEmployee"
                : "soldBy";

        string? effectiveStaff = staffEmail?.Trim();
        Guid? effectiveEmployeeId = soldByEmployeeId;
        var canViewAllStaff = await CanViewAllEndOfDayStaffAsync();
        if (!canViewAllStaff)
        {
            effectiveStaff = CurrentUserEmail;
            effectiveEmployeeId = EmployeeId;
            // Ưu tiên hồ sơ NV — SoldBy thường là tên, không phải email đăng nhập.
            if (effectiveEmployeeId.HasValue)
                filter = "soldByEmployee";
            if (string.IsNullOrWhiteSpace(effectiveStaff) && !effectiveEmployeeId.HasValue)
                return BadRequest(AppResponse<object>.Fail("Không xác định được tài khoản nhân viên"));
        }

        var baseQuery = dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt)
            .ApplyBranchScope(HttpContext.BranchContext());
        baseQuery = ApplyStaffFilter(baseQuery, effectiveStaff, effectiveEmployeeId, filter);

        var completedQuery = baseQuery.Where(o => o.Status == PosSaleOrderStatus.Completed);
        var canceledQuery = baseQuery.Where(o => o.Status == PosSaleOrderStatus.Cancelled);

        var orderCount = await completedQuery.CountAsync();
        var subTotal = await completedQuery.SumAsync(o => (decimal?)o.SubTotal) ?? 0;
        var orderDiscount = await completedQuery.SumAsync(o => (decimal?)o.Discount) ?? 0;
        var voucherDiscount = await completedQuery.SumAsync(o => (decimal?)o.VoucherDiscount) ?? 0;
        var pointsDiscount = await completedQuery.SumAsync(o => (decimal?)o.PointsDiscount) ?? 0;
        var netSales = await completedQuery.SumAsync(o => (decimal?)o.Total) ?? 0;
        var vat = await completedQuery.SumAsync(o => (decimal?)o.VatAmount) ?? 0;
        var surchargeTotal = await completedQuery.SumAsync(o => (decimal?)o.SurchargeAmount) ?? 0;
        var deliveryFeeTotal = await completedQuery.SumAsync(o => (decimal?)o.DeliveryFee) ?? 0;
        // Phải thu = Total + VAT + phụ thu + phí GH (Total không gồm VAT khi giá chưa thuế).
        var payableTotal = netSales + vat + surchargeTotal + deliveryFeeTotal;

        var canceledCount = await canceledQuery.CountAsync();
        var canceledTotal = await canceledQuery.SumAsync(o => (decimal?)o.Total) ?? 0;

        var orderIds = await completedQuery.Select(o => o.Id).ToListAsync();
        // Tiền hoàn trả khách trong ngày (theo ngày trả, mọi đơn của người xem) — chỉ để đối chiếu két;
        // doanh thu (netSales = Total) đã giảm khi trả hàng nên không trừ thêm.
        // Truy vấn con (mọi đơn của người xem / chi nhánh, mọi kỳ) — trước đây nạp hết mã đơn về máy chủ.
        var viewerOrderIds = string.IsNullOrWhiteSpace(effectiveStaff) && !effectiveEmployeeId.HasValue
            ? (IsManager ? BranchRefundOrderIds(storeId) : null)
            : ApplyStaffFilter(
                    dbContext.PosSaleOrders.AsNoTracking().Where(o => o.StoreId == storeId && o.Deleted == null),
                    effectiveStaff, effectiveEmployeeId, filter)
                .Select(o => o.Id);
        var refundTotal = await PosSaleReturnLedger.SumRefundsByReturnDateAsync(dbContext, storeId, fromDt, toDt, viewerOrderIds);

        var lineDiscountTotal = orderIds.Count == 0
            ? 0m
            : await dbContext.PosSaleOrderLines.AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Deleted == null &&
                            orderIds.Contains(l.SaleOrderId))
                .SumAsync(l => (decimal?)l.DiscountAmount) ?? 0;

        string paymentLabel(PaymentMethodType method) => method switch
        {
            PaymentMethodType.Cash => "Tiền mặt",
            PaymentMethodType.BankTransfer => "Chuyển khoản",
            PaymentMethodType.VietQR => "VietQR",
            PaymentMethodType.Card => "Thẻ",
            PaymentMethodType.EWallet => "Ví điện tử",
            _ => "Khác",
        };

        // Phân tách theo từng dòng thu quỹ (marker sale), không theo chuỗi PaymentMethod gộp.
        var payments = new List<object>();
        var cashTotal = 0m;
        var saleFundIn = 0m;
        var saleInByOrder = new Dictionary<Guid, decimal>();
        if (orderIds.Count > 0)
        {
            var orderIdSet = orderIds.ToHashSet();
            // Dòng thu của đơn luôn ghi SAU khi tạo đơn → chặn dưới bằng đơn tạo sớm nhất trong kỳ.
            // Trước đây tải MỌI dòng thu bán hàng từ trước tới nay của cửa hàng rồi mới lọc theo đơn trong ngày.
            var earliestOrder = await completedQuery.MinAsync(o => (DateTime?)o.CreatedAt) ?? fromDt;
            var cashFrom = earliestOrder.AddDays(-1); // dư 1 ngày phòng lệch múi giờ giữa 2 bảng
            var saleCashTx = await dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
                .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                    && c.Status == CashTransactionStatus.Completed
                    && c.Type == CashTransactionType.Income
                    && c.CreatedAt >= cashFrom
                    && c.InternalNote != null
                    && c.InternalNote.StartsWith(PosFinanceSyncHelper.SaleMarker))
                .ToListAsync();

            var matched = saleCashTx
                .Where(c =>
                {
                    var oid = ParseSaleOrderIdFromMarker(c.InternalNote);
                    return oid.HasValue && orderIdSet.Contains(oid.Value);
                })
                .ToList();

            var paymentRows = matched
                .GroupBy(c => c.PaymentMethod)
                .Select(g => new
                {
                    paymentMethod = paymentLabel(g.Key),
                    total = g.Sum(x => x.Amount),
                    count = g.Count(),
                })
                .OrderByDescending(x => x.total)
                .ToList();
            payments = paymentRows.Cast<object>().ToList();
            saleInByOrder = matched
                .GroupBy(c => ParseSaleOrderIdFromMarker(c.InternalNote)!.Value)
                .ToDictionary(g => g.Key, g => g.Sum(x => x.Amount));
            cashTotal = paymentRows
                .FirstOrDefault(p => p.paymentMethod.Equals("Tiền mặt", StringComparison.OrdinalIgnoreCase))
                ?.total ?? 0m;
            saleFundIn = matched.Sum(x => x.Amount);
        }

        // Thực thu / công nợ của NGÀY BÁN = tiền thu lúc bán (phiếu thu bán hàng), không lấy PaidAmount: PaidAmount cộng dồn
        // cả tiền khách trả nợ về sau → xem lại ngày cũ «Thực thu» tăng, «Công nợ» về 0, lệch phiếu đã in / đã đối chiếu.
        // Cửa hàng chưa có phiếu thu bán hàng (dữ liệu cũ) → giữ PaidAmount.
        var orderMoney = await completedQuery
            .Select(o => new { o.Id, Payable = o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee, o.PaidAmount })
            .ToListAsync();
        var useSaleTx = saleInByOrder.Count > 0;
        // Cọc đặt bàn đã trừ vào đơn: thu lúc đặt (phiếu thu cọc), không có phiếu thu bán hàng →
        // trước đây đơn trả hết bằng cọc bị tính «Ghi nợ», dù «Thực thu HĐ» ghi là gồm cọc trừ.
        var depositByOrder = orderIds.Count == 0
            ? new Dictionary<Guid, decimal>()
            : await dbContext.PosResourceReservations.AsNoTracking()
                .Where(x => x.StoreId == storeId
                    && x.DepositStatus == PosReservationDepositStatus.Applied
                    && x.DepositAppliedOrderId != null
                    && orderIds.Contains(x.DepositAppliedOrderId.Value))
                .GroupBy(x => x.DepositAppliedOrderId!.Value)
                .Select(g => new { g.Key, Sum = g.Sum(x => x.DepositPaid) })
                .ToDictionaryAsync(x => x.Key, x => x.Sum);
        decimal ReceivedOf(Guid id, decimal paid) => useSaleTx
            ? saleInByOrder.GetValueOrDefault(id) + depositByOrder.GetValueOrDefault(id)
            : paid;
        var actualReceived = orderMoney.Sum(o => ReceivedOf(o.Id, o.PaidAmount));
        var debtTotal = orderMoney.Sum(o => Math.Max(0, o.Payable - ReceivedOf(o.Id, o.PaidAmount)));

        object? products = null;
        if (includeProductDetail && orderIds.Count > 0)
        {
            products = PosReportLineExpand
                .Aggregate(await LoadSaleLinesForExpandAsync(storeId, orderIds))
                .Select(x => new
                {
                    productId = x.ProductId,
                    productName = x.ProductName,
                    qty = x.Qty,
                    revenue = x.Revenue,
                    lineDiscount = x.LineDiscount,
                })
                .ToList();
        }

        var offDaySrc = await completedQuery
            .Select(o => new
            {
                o.OrderNo,
                o.CreatedAt,
                SaleAt = o.SaleDate ?? o.CreatedAt,
                o.Total,
            })
            .ToListAsync();
        var closedOffDayOrders = offDaySrc
            .Where(o => PosSaleStockHelper.IsClosedOffDay(o.OrderNo, o.CreatedAt, o.SaleAt))
            .Select(o =>
            {
                PosSaleStockHelper.TryParseHdOrderNoDate(o.OrderNo, out var noDate);
                return new
                {
                    orderNo = o.OrderNo,
                    draftedOn = VnTimeHelper.UtcToVn(o.CreatedAt).Date,
                    orderNoDate = noDate == default ? (DateTime?)null : noDate.Date,
                    saleDate = VnTimeHelper.UtcToVn(o.SaleAt).Date,
                    total = o.Total,
                };
            })
            .ToList();

        object? transactions = null;
        if (includeTransactions)
        {
            var txRows = await completedQuery
                .OrderBy(o => o.SaleDate ?? o.CreatedAt)
                .Select(o => new
                {
                    o.Id,
                    o.OrderNo,
                    DraftedAt = o.CreatedAt,
                    CreatedAt = o.SaleDate ?? o.CreatedAt,
                    qty = o.Lines.Sum(l => l.Qty),
                    revenue = o.SubTotal,
                    // Giảm giá = giảm cả đơn + voucher + đổi điểm (trước đây chỉ giảm cả đơn).
                    discount = o.Discount + o.VoucherDiscount + o.PointsDiscount,
                    vat = o.VatAmount,
                    rounding = 0m,
                    returnFee = 0m,
                    actualReceived = o.PaidAmount,
                    o.PaymentMethod,
                    o.SoldBy,
                    o.CreatedBy,
                })
                .ToListAsync();

            // Tiền đã hoàn của đơn (sổ trả hàng; phiếu cũ không cộng trùng combo, bỏ phiếu đã hủy).
            var returnedMap = (await PosSaleReturnLedger.ReturnedByOrderAsync(dbContext, storeId, orderIds))
                .ToDictionary(x => x.Key, x => x.Value.Refund);

            transactions = txRows.Select(t =>
            {
                var closedOff = PosSaleStockHelper.IsClosedOffDay(t.OrderNo, t.DraftedAt, t.CreatedAt);
                PosSaleStockHelper.TryParseHdOrderNoDate(t.OrderNo, out var noDate);
                return new
                {
                    t.OrderNo,
                    t.CreatedAt,
                    draftedAt = t.DraftedAt,
                    closedOffDay = closedOff,
                    note = closedOff
                        ? $"Chốt ngày khác · nháp {(noDate == default ? VnTimeHelper.UtcToVn(t.DraftedAt) : noDate):dd/MM}"
                        : (string?)null,
                    t.qty,
                    t.revenue,
                    otherIncome = 0m,
                    t.vat,
                    t.rounding,
                    returnFee = returnedMap.GetValueOrDefault(t.Id),
                    actualReceived = ReceivedOf(t.Id, t.actualReceived),
                    t.PaymentMethod,
                    t.SoldBy,
                    t.CreatedBy,
                };
            }).ToList();
        }

        var storeName = await dbContext.Stores.AsNoTracking()
            .Where(s => s.Id == storeId)
            .Select(s => s.Name)
            .FirstOrDefaultAsync();

        string? staffName = null;
        if (effectiveEmployeeId.HasValue)
            staffName = await ResolveEmployeeDisplayNameAsync(storeId, effectiveEmployeeId.Value);
        else if (!string.IsNullOrWhiteSpace(effectiveStaff))
            staffName = await ResolveStaffDisplayNameAsync(storeId, effectiveStaff);

        var depositEod = await LoadDepositEndOfDayAsync(
            storeId, fromDt, toDt, effectiveStaff, effectiveEmployeeId, filter);

        // Két / quỹ trong ngày còn có: tiền khách trả nợ (+) và tiền hoàn khách trả hàng (−).
        // Trước đây bỏ sót → «Tiền mặt két» lệch tiền thực trong két.
        var cashFlow = await LoadEodDebtAndRefundAsync(storeId, fromDt, toDt, viewerOrderIds);
        var drawerCash = cashTotal + depositEod.CollectedCash - depositEod.RefundedCash
                         + cashFlow.DebtCash - cashFlow.RefundCash;
        var fundInToday = saleFundIn + depositEod.Collected - depositEod.Refunded
                          + cashFlow.Debt - cashFlow.Refund;
        var otherIncome = depositEod.Forfeited;

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn,
            to = toVnEx.AddTicks(-1),
            dayStartHour = hour,
            overnight = hour > 0,
            filterBy = filter,
            canViewAllStaff,
            staffEmail = effectiveStaff,
            soldByEmployeeId = effectiveEmployeeId,
            staffName,
            storeName,
            generatedAt = DateTime.UtcNow,
            orderCount,
            orderDiscount,
            voucherDiscount,
            pointsDiscount,
            totalSales = subTotal,
            vat,
            surchargeTotal,
            deliveryFeeTotal,
            payableTotal,
            netSales,
            refundTotal,
            // Total đã trừ hàng trả → «sau hoàn trả» chính là doanh thu thuần (trước đây trừ hai lần).
            totalAfterRefund = netSales,
            canceledCount,
            canceledTotal,
            cashTotal,
            debtTotal,
            actualReceived,
            lineDiscountTotal,
            closedOffDayCount = closedOffDayOrders.Count,
            closedOffDayOrders,
            payments,
            products,
            transactions,
            depositCollected = depositEod.Collected,
            depositRefunded = depositEod.Refunded,
            depositForfeited = depositEod.Forfeited,
            depositHeld = depositEod.HeldOutstanding,
            depositApplied = depositEod.AppliedInPeriod,
            depositCollectedCash = depositEod.CollectedCash,
            depositRefundedCash = depositEod.RefundedCash,
            depositByPayment = depositEod.CollectedByPayment,
            drawerCash,
            fundInToday,
            otherIncome,
            debtCollected = cashFlow.Debt,
            debtCollectedCash = cashFlow.DebtCash,
            refundPaid = cashFlow.Refund,
            refundPaidCash = cashFlow.RefundCash,
        }));
    }

    /// <summary>Danh sách nhân viên có phát sinh bán hàng (admin/manager).</summary>
    [HttpGet("end-of-day/staff")]
    [RequireModulePermission("PosReportEndOfDay", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetEndOfDayStaff(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string filterBy = "soldByEmployee",
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, _, _) = ResolvePosRange(from, to, hour);
        var filter = filterBy.Equals("createdBy", StringComparison.OrdinalIgnoreCase)
            ? "createdBy"
            : filterBy.Equals("soldBy", StringComparison.OrdinalIgnoreCase)
                ? "soldBy"
                : "soldByEmployee";

        if (!await CanViewAllEndOfDayStaffAsync())
        {
            var email = CurrentUserEmail ?? "";
            var selfId = EmployeeId;
            var selfName = selfId.HasValue
                ? await ResolveEmployeeDisplayNameAsync(storeId, selfId.Value)
                : (string.IsNullOrWhiteSpace(email)
                    ? null
                    : await ResolveStaffDisplayNameAsync(storeId, email));
            return Ok(AppResponse<object>.Success(new[]
            {
                new
                {
                    email,
                    employeeId = selfId,
                    displayName = selfName ?? email,
                    isSelf = true,
                },
            }));
        }

        var orderQuery = dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                        o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                        (o.SaleDate ?? o.CreatedAt) < toDt)
            .ApplyBranchScope(HttpContext.BranchContext());

        if (filter == "soldByEmployee")
        {
            var employeeIds = await orderQuery.Where(o => o.SoldByEmployeeId != null)
                .Select(o => o.SoldByEmployeeId!.Value)
                .Distinct()
                .ToListAsync();
            var employees = await dbContext.Employees.AsNoTracking()
                .Where(e => employeeIds.Contains(e.Id) && e.StoreId == storeId && e.Deleted == null)
                .Select(e => new
                {
                    e.Id,
                    Name = (e.LastName + " " + e.FirstName).Trim(),
                    e.CompanyEmail,
                })
                .OrderBy(e => e.Name)
                .ToListAsync();
            var employeeItems = employees.Select(e => new
            {
                email = e.CompanyEmail,
                employeeId = (Guid?)e.Id,
                displayName = string.IsNullOrWhiteSpace(e.Name) ? e.CompanyEmail ?? e.Id.ToString() : e.Name,
                isSelf = EmployeeId.HasValue && e.Id == EmployeeId.Value,
            }).ToList();
            if (await orderQuery.AnyAsync(o => o.SoldByEmployeeId == null))
                employeeItems.Add(new
                {
                    email = (string?)null,
                    employeeId = (Guid?)Guid.Empty,
                    displayName = "Chưa gắn nhân viên",
                    isSelf = false,
                });
            return Ok(AppResponse<object>.Success(employeeItems));
        }

        var emails = filter == "createdBy"
            ? await orderQuery.Where(o => o.CreatedBy != null)
                .Select(o => o.CreatedBy!)
                .Distinct()
                .OrderBy(e => e)
                .ToListAsync()
            : await orderQuery.Where(o => o.SoldBy != null)
                .Select(o => o.SoldBy!)
                .Distinct()
                .OrderBy(e => e)
                .ToListAsync();

        var nameMap = await ResolveStaffDisplayNamesAsync(storeId, emails);
        var items = emails.Select(e => new
        {
            email = e,
            employeeId = (Guid?)null,
            displayName = nameMap.GetValueOrDefault(e) ?? e,
            isSelf = e.Equals(CurrentUserEmail, StringComparison.OrdinalIgnoreCase),
        }).ToList();

        return Ok(AppResponse<object>.Success(items));
    }

    [HttpGet("customer-debt")]
    [RequireModulePermission("PosReportDebt", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> CustomerDebtReport(
        [FromQuery] string? search,
        [FromQuery] decimal? debtFrom,
        [FromQuery] decimal? debtTo,
        [FromQuery] bool includeZeroDebt = false,
        [FromQuery] int? page = null,
        [FromQuery] int? pageSize = null)
    {
        var storeId = RequiredStoreId;
        // Xem theo chi nhánh: công nợ = phần còn nợ của các đơn thuộc chi nhánh đó (khách mua ở nhiều chi nhánh có nợ riêng từng nơi).
        var bctx = HttpContext.BranchContext();
        var branchScoped = bctx is { StoreUsesBranches: true } && (bctx.FilterBranchId != null || bctx.AllowedBranchIds != null);
        var custQ = dbContext.PosCustomers.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive);
        if (branchScoped)
        {
            var branchCustomerIds = dbContext.PosSaleOrders.AsNoTracking()
                .Where(o => o.StoreId == storeId && o.Deleted == null && o.Status == PosSaleOrderStatus.Completed &&
                            o.CustomerId != null &&
                            o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee > o.PaidAmount)
                .ApplyBranchScope(bctx).Select(o => o.CustomerId!.Value);
            custQ = custQ.Where(c => branchCustomerIds.Contains(c.Id));
        }
        else if (!includeZeroDebt) custQ = custQ.Where(c => c.CurrentDebt > 0);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            custQ = custQ.Where(c =>
                c.Name.ToLower().Contains(s) ||
                c.CustomerCode.ToLower().Contains(s) ||
                (c.Phone != null && c.Phone.Contains(s)));
        }
        if (!branchScoped)
        {
            if (debtFrom.HasValue) custQ = custQ.Where(c => c.CurrentDebt >= debtFrom);
            if (debtTo.HasValue) custQ = custQ.Where(c => c.CurrentDebt <= debtTo);
        }

        var customers = await custQ
            .OrderByDescending(c => c.CurrentDebt)
            .ThenBy(c => c.Name)
            .Select(c => new
            {
                c.Id,
                c.CustomerCode,
                c.Name,
                c.Phone,
                c.TotalPurchase,
                c.CurrentDebt,
                c.PointBalance,
            })
            .ToListAsync();

        // Đơn còn nợ của các khách trong danh sách (truy vấn con, không gửi lại mảng mã khách); tra theo khách một lần
        // — trước đây mỗi khách lọc lại toàn bộ đơn nợ (N khách × M đơn).
        var customerIds = custQ.Select(c => c.Id);
        var unpaidOrders = customers.Count == 0
            ? []
            : await dbContext.PosSaleOrders.AsNoTracking()
                .Where(o => o.StoreId == storeId && o.Deleted == null &&
                            o.Status == PosSaleOrderStatus.Completed &&
                            o.CustomerId != null && customerIds.Contains(o.CustomerId.Value) &&
                            o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee > o.PaidAmount)
                .ApplyBranchScope(bctx)
                .Select(o => new
                {
                    CustomerId = o.CustomerId!.Value,
                    Due = o.Total + o.VatAmount + o.SurchargeAmount + o.DeliveryFee - o.PaidAmount,
                    BizAt = o.SaleDate ?? o.CreatedAt,
                })
                .ToListAsync();
        var unpaidByCustomer = unpaidOrders.ToLookup(x => x.CustomerId);

        // Tuổi nợ theo ngày Việt Nam (trước đây ngày UTC: đơn bán 0h–7h sáng bị tính lùi một ngày).
        var today = DateTime.UtcNow;
        static int AgingBucket(DateTime bizAt, DateTime _)
        {
            var days = PosDebtPolicy.AgeDaysVn(bizAt);
            if (days <= 30) return 0;
            if (days <= 60) return 1;
            if (days <= 90) return 2;
            return 3;
        }

        var items = customers.Select(c =>
        {
            var rows = unpaidByCustomer[c.Id].ToList();
            decimal BucketSum(int bucket) =>
                rows.Where(x => AgingBucket(x.BizAt, today) == bucket).Sum(x => x.Due);
            var d0 = BucketSum(0);
            var d31 = BucketSum(1);
            var d61 = BucketSum(2);
            var d90 = BucketSum(3);
            return new
            {
                c.Id,
                c.CustomerCode,
                c.Name,
                c.Phone,
                c.TotalPurchase,
                CurrentDebt = branchScoped ? rows.Sum(x => x.Due) : c.CurrentDebt,
                totalDebtAllBranches = c.CurrentDebt,
                c.PointBalance,
                openOrderCount = rows.Count,
                openOrderDebt = rows.Sum(x => x.Due),
                // Nợ không gắn đơn (nhập nợ đầu kỳ / điều chỉnh) — không có tuổi nợ.
                debtOther = Math.Max(0, (branchScoped ? rows.Sum(x => x.Due) : c.CurrentDebt) - rows.Sum(x => x.Due)),
                debt0To30 = d0,
                debt31To60 = d31,
                debt61To90 = d61,
                debtOver90 = d90,
            };
        }).ToList();
        if (branchScoped)
            items = items.Where(x => (includeZeroDebt || x.CurrentDebt > 0)
                                     && (!debtFrom.HasValue || x.CurrentDebt >= debtFrom)
                                     && (!debtTo.HasValue || x.CurrentDebt <= debtTo))
                .OrderByDescending(x => x.CurrentDebt).ThenBy(x => x.Name).ToList();

        // Tổng trên mọi khách; ?page=&pageSize= chỉ cắt danh sách trả về (cửa hàng nhiều khách nợ: trước đây trả hết
        // hàng chục nghìn dòng — vài MB — mỗi lần mở báo cáo). Không truyền → như cũ, trả đủ (xuất Excel).
        var paged = page.HasValue || pageSize.HasValue;
        var size = Math.Clamp(pageSize ?? 100, 1, 500);
        var pageNo = Math.Max(1, page ?? 1);
        return Ok(AppResponse<object>.Success(new
        {
            totalCustomers = items.Count,
            sumDebt = items.Sum(x => x.CurrentDebt),
            sumOpenOrderDebt = items.Sum(x => x.openOrderDebt),
            sumDebt0To30 = items.Sum(x => x.debt0To30),
            sumDebt31To60 = items.Sum(x => x.debt31To60),
            sumDebt61To90 = items.Sum(x => x.debt61To90),
            sumDebtOver90 = items.Sum(x => x.debtOver90),
            page = paged ? pageNo : (int?)null,
            pageSize = paged ? size : (int?)null,
            items = paged ? items.Skip((pageNo - 1) * size).Take(size).ToList() : items,
        }));
    }

    async Task<int> ResolveReportDayStartHourAsync(Guid storeId, int? overrideHour)
    {
        if (overrideHour.HasValue) return Math.Clamp(overrideHour.Value, 0, 23);
        var h = await dbContext.PosStoreSellSettings.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null)
            .Select(s => (int?)s.ReportDayStartHour)
            .FirstOrDefaultAsync();
        return Math.Clamp(h ?? 0, 0, 23);
    }

    static IQueryable<PosProduct> ApplyGoodsProductScope(
        IQueryable<PosProduct> query,
        bool includeGoods,
        bool includeService,
        bool includeCombo,
        bool activeOnly,
        bool inactiveOnly)
    {
        if (!includeGoods || !includeService || !includeCombo)
        {
            query = query.Where(p =>
                (includeGoods && (p.ProductType == PosProductType.Goods ||
                                  p.ProductType == PosProductType.Material ||
                                  p.ProductType == PosProductType.Topping)) ||
                (includeService && p.ProductType == PosProductType.Service) ||
                (includeCombo && p.ProductType == PosProductType.Combo));
        }

        if (activeOnly && !inactiveOnly)
            query = query.Where(p => p.IsActive);
        else if (inactiveOnly && !activeOnly)
            query = query.Where(p => !p.IsActive);

        return query;
    }

    static IQueryable<PosProduct> ApplyGoodsInventoryFilter(
        IQueryable<PosProduct> query,
        string? inventoryStatus)
    {
        if (string.IsNullOrWhiteSpace(inventoryStatus)) return query;
        return inventoryStatus.Trim().ToLowerInvariant() switch
        {
            "belowmin" => query.Where(p => p.MinStockQty > 0 && p.OnHandQty < p.MinStockQty),
            "abovemin" => query.Where(p => p.MaxStockQty > 0 && p.OnHandQty > p.MaxStockQty),
            "instock" => query.Where(p => p.OnHandQty > 0),
            "outofstock" => query.Where(p => p.OnHandQty <= 0),
            _ => query,
        };
    }

    static (DateTime fromUtc, DateTime toUtcExclusive, DateTime fromVn, DateTime toVnExclusive)
        ResolvePosRange(DateTime? from, DateTime? to, int dayStartHour, int? defaultLookbackDays = null)
    {
        DateTime? defFrom = null;
        DateTime? defTo = null;
        if (defaultLookbackDays is int days)
        {
            var biz = VnTimeHelper.ResolveBusinessDate(VnTimeHelper.NowVn(), dayStartHour);
            defTo = biz;
            defFrom = biz.AddDays(-Math.Max(0, days));
        }
        var r = ReportHelpers.PosBusinessRange(from, to, dayStartHour, defFrom, defTo);
        // Chặn khoảng thời gian quá dài (vd. từ năm 2000): mọi báo cáo POS đều gom dữ liệu trong khoảng này.
        const int maxDays = 1100;
        if ((r.toUtcExclusive - r.fromUtc).TotalDays > maxDays)
            r = (r.toUtcExclusive.AddDays(-maxDays), r.toUtcExclusive, r.toVnExclusive.AddDays(-maxDays), r.toVnExclusive);
        return r;
    }

    /// <summary>
    /// Xem tổng kết mọi nhân viên: quản lý/admin, hoặc quyền Sửa/Duyệt module cuối ngày / hub báo cáo.
    /// Thu ngân / nhân viên bán (chỉ Xem/Xuất) bị khóa theo tài khoản đang đăng nhập.
    /// </summary>
    private async Task<bool> CanViewAllEndOfDayStaffAsync(CancellationToken ct = default)
    {
        if (IsManager) return true;
        var uid = CurrentUserId;
        var role = CurrentUserRole;
        var storeId = CurrentStoreId;
        if (await modulePermissionService.HasPermissionAsync(
                uid, role, storeId, "PosReportEndOfDay", ModulePermissionAction.Edit, ct))
            return true;
        if (await modulePermissionService.HasPermissionAsync(
                uid, role, storeId, "PosReportEndOfDay", ModulePermissionAction.Approve, ct))
            return true;
        if (await modulePermissionService.HasPermissionAsync(
                uid, role, storeId, "PosSalesReport", ModulePermissionAction.Edit, ct))
            return true;
        return false;
    }

    /// <summary>
    /// Tiền hoàn trả tính theo ngày trả nên cần đơn của chi nhánh đang lọc (mọi kỳ). Không lọc chi nhánh → null (cả cửa hàng).
    /// </summary>
    private IQueryable<Guid>? BranchRefundOrderIds(Guid storeId)
    {
        var ctx = HttpContext.BranchContext();
        if (ctx is not { StoreUsesBranches: true } || (ctx.FilterBranchId == null && ctx.AllowedBranchIds == null)) return null;
        // Truy vấn con — trước đây nạp MỌI đơn của chi nhánh (mọi kỳ) về máy chủ ở mỗi lần xem báo cáo.
        return dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null)
            .ApplyBranchScope(ctx).Select(o => o.Id);
    }

    internal sealed record OrderTotals(decimal Revenue, decimal Vat, decimal Paid, decimal Discount, int Count);

    /// <summary>Tổng tiền / VAT / đã trả / giảm giá đơn + số đơn trong một truy vấn (trước đây 4–5 lần quét đơn).</summary>
    static async Task<OrderTotals> OrderTotalsAsync(IQueryable<PosSaleOrder> orders) =>
        await orders.GroupBy(o => 1)
            .Select(g => new OrderTotals(
                g.Sum(o => o.Total), g.Sum(o => o.VatAmount), g.Sum(o => o.PaidAmount),
                g.Sum(o => o.Discount + o.VoucherDiscount + o.PointsDiscount), g.Count()))
            .FirstOrDefaultAsync()
        ?? new OrderTotals(0, 0, 0, 0, 0);

    /// <summary>Tồn theo chi nhánh đang lọc / được phép xem (cộng các chi nhánh). null = báo cáo tồn cả cửa hàng.</summary>
    private IQueryable<PosSaleOrder> ScopeOrdersForViewer(IQueryable<PosSaleOrder> query)
    {
        // Chi nhánh: ?branchId= hoặc giới hạn theo chi nhánh được phép xem.
        query = query.ApplyBranchScope(HttpContext.BranchContext());
        if (IsManager) return query;
        var filter = EmployeeId.HasValue ? "soldByEmployee" : "soldBy";
        return ApplyStaffFilter(query, CurrentUserEmail, EmployeeId, filter);
    }

    /// <summary>Dòng bán thuần: trừ hàng khách trả, phân bổ giảm giá đơn / voucher / điểm, SL theo đơn vị cơ bản.</summary>
    private Task<List<PosReportLineExpand.LineIn>> LoadSaleLinesForExpandAsync(
        Guid storeId, IReadOnlyCollection<Guid> orderIds) =>
        PosReportMoney.NetLinesAsync(dbContext, storeId, orderIds);

    /// <summary>
    /// Thu nợ khách và hoàn tiền trả hàng trong kỳ (theo ngày phiếu thu chi — giờ VN).
    /// <paramref name="viewerOrderIds"/> ≠ null: chỉ phiếu gắn đơn của nhân viên đang xem.
    /// </summary>
    private async Task<(decimal Debt, decimal DebtCash, decimal Refund, decimal RefundCash)> LoadEodDebtAndRefundAsync(
        Guid storeId, DateTime fromDt, DateTime toDt, IQueryable<Guid>? viewerOrderIds)
    {
        var rows = await dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                && c.Status == CashTransactionStatus.Completed
                && c.TransactionDate >= fromDt.AddHours(7) && c.TransactionDate < toDt.AddHours(7)
                && c.InternalNote != null
                && (c.InternalNote.StartsWith(PosFinanceSyncHelper.CustomerPaymentMarker)
                    || c.InternalNote.StartsWith(PosFinanceSyncHelper.CustomerReturnMarker)))
            .Select(c => new { c.Type, c.Amount, c.PaymentMethod, Note = c.InternalNote! })
            .ToListAsync();
        if (rows.Count == 0) return (0, 0, 0, 0);

        static Guid? IdAfter(string note, string prefix)
        {
            var rest = note[prefix.Length..];
            var pipe = rest.IndexOf('|');
            return Guid.TryParse(pipe >= 0 ? rest[..pipe] : rest, out var id) ? id : null;
        }

        var paymentOrder = new Dictionary<Guid, Guid?>();
        HashSet<Guid>? scope = null;
        if (viewerOrderIds != null)
        {
            var payIds = rows.Where(r => r.Note.StartsWith(PosFinanceSyncHelper.CustomerPaymentMarker))
                .Select(r => IdAfter(r.Note, PosFinanceSyncHelper.CustomerPaymentMarker))
                .Where(id => id.HasValue).Select(id => id!.Value).Distinct().ToList();
            paymentOrder = await dbContext.PosCustomerPayments.AsNoTracking()
                .Where(p => p.StoreId == storeId && payIds.Contains(p.Id))
                .ToDictionaryAsync(p => p.Id, p => p.SaleOrderId);
            // Chỉ hỏi các đơn có phiếu trong ngày có thuộc phạm vi người xem không.
            var candidates = rows.Where(r => r.Note.StartsWith(PosFinanceSyncHelper.CustomerReturnMarker))
                .Select(r => IdAfter(r.Note, PosFinanceSyncHelper.CustomerReturnMarker))
                .Concat(paymentOrder.Values)
                .Where(id => id.HasValue).Select(id => id!.Value).Distinct().ToList();
            scope = (await viewerOrderIds.Where(id => candidates.Contains(id)).ToListAsync()).ToHashSet();
        }

        bool InScope(string note)
        {
            if (scope == null) return true;
            Guid? orderId = note.StartsWith(PosFinanceSyncHelper.CustomerReturnMarker)
                ? IdAfter(note, PosFinanceSyncHelper.CustomerReturnMarker)
                : IdAfter(note, PosFinanceSyncHelper.CustomerPaymentMarker) is Guid pid
                    ? paymentOrder.GetValueOrDefault(pid)
                    : null;
            return orderId.HasValue && scope.Contains(orderId.Value);
        }

        var debt = rows.Where(r => r.Type == CashTransactionType.Income
                                   && r.Note.StartsWith(PosFinanceSyncHelper.CustomerPaymentMarker) && InScope(r.Note)).ToList();
        var refund = rows.Where(r => r.Type == CashTransactionType.Expense
                                     && r.Note.StartsWith(PosFinanceSyncHelper.CustomerReturnMarker) && InScope(r.Note)).ToList();
        return (debt.Sum(r => r.Amount),
            debt.Where(r => r.PaymentMethod == PaymentMethodType.Cash).Sum(r => r.Amount),
            refund.Sum(r => r.Amount),
            refund.Where(r => r.PaymentMethod == PaymentMethodType.Cash).Sum(r => r.Amount));
    }

    internal static Guid? ParseSaleOrderIdFromMarker(string? note)
    {
        if (string.IsNullOrEmpty(note)) return null;
        var prefix = PosFinanceSyncHelper.SaleMarker;
        if (!note.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) return null;
        var rest = note[prefix.Length..];
        var pipe = rest.IndexOf('|');
        var idPart = pipe >= 0 ? rest[..pipe] : rest;
        return Guid.TryParse(idPart, out var id) ? id : null;
    }

    private static IQueryable<PosSaleOrder> ApplyStaffFilter(
        IQueryable<PosSaleOrder> query,
        string? staffEmail,
        Guid? soldByEmployeeId,
        string filterBy)
    {
        // Guid.Empty = «Chưa gắn nhân viên»: đơn không gắn hồ sơ NV (chủ quán tự bán…) — trước đây không lọc ra được.
        if (soldByEmployeeId == Guid.Empty &&
            !filterBy.Equals("createdBy", StringComparison.OrdinalIgnoreCase))
            return query.Where(o => o.SoldByEmployeeId == null);
        // Ưu tiên SoldByEmployeeId khi có — khớp hồ sơ NV, không so tên với email.
        if (soldByEmployeeId.HasValue &&
            !filterBy.Equals("createdBy", StringComparison.OrdinalIgnoreCase))
            return query.Where(o => o.SoldByEmployeeId == soldByEmployeeId);

        if (string.IsNullOrWhiteSpace(staffEmail)) return query;
        if (filterBy.Equals("createdBy", StringComparison.OrdinalIgnoreCase))
            return query.Where(o => o.CreatedBy == staffEmail);

        // soldBy: tên NV hoặc email đăng nhập (CreatedBy)
        return query.Where(o => o.SoldBy == staffEmail || o.CreatedBy == staffEmail);
    }

    private async Task<string?> ResolveEmployeeDisplayNameAsync(Guid storeId, Guid employeeId)
    {
        var emp = await dbContext.Employees.AsNoTracking()
            .Where(e => e.Id == employeeId && e.StoreId == storeId && e.Deleted == null)
            .Select(e => new { Name = (e.LastName + " " + e.FirstName).Trim(), e.CompanyEmail })
            .FirstOrDefaultAsync();
        if (emp == null) return null;
        return !string.IsNullOrWhiteSpace(emp.Name) ? emp.Name : emp.CompanyEmail;
    }

    private async Task<string?> ResolveStaffDisplayNameAsync(Guid storeId, string email)
    {
        var map = await ResolveStaffDisplayNamesAsync(storeId, [email]);
        return map.GetValueOrDefault(email);
    }

    private async Task<Dictionary<string, string>> ResolveStaffDisplayNamesAsync(
        Guid storeId, IEnumerable<string> emails)
    {
        var list = emails.Where(e => !string.IsNullOrWhiteSpace(e)).Distinct().ToList();
        if (list.Count == 0) return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        var employees = await dbContext.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null &&
                        list.Contains(e.CompanyEmail))
            .Select(e => new { e.CompanyEmail, Name = (e.LastName + " " + e.FirstName).Trim() })
            .ToListAsync();

        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var e in employees)
        {
            if (!string.IsNullOrWhiteSpace(e.CompanyEmail) && !string.IsNullOrWhiteSpace(e.Name))
                result[e.CompanyEmail] = e.Name;
        }
        return result;
    }

    private sealed record DepositEodBlock(
        decimal Collected,
        decimal Refunded,
        decimal Forfeited,
        decimal HeldOutstanding,
        decimal AppliedInPeriod,
        decimal CollectedCash,
        decimal RefundedCash,
        List<object> CollectedByPayment);

    private static string CashPayLabel(PaymentMethodType method) => method switch
    {
        PaymentMethodType.Cash => "Tiền mặt",
        PaymentMethodType.BankTransfer => "Chuyển khoản",
        PaymentMethodType.VietQR => "VietQR",
        PaymentMethodType.Card => "Thẻ",
        PaymentMethodType.EWallet => "Ví điện tử",
        _ => "Khác",
    };

    private async Task<DepositEodBlock> LoadDepositEndOfDayAsync(
        Guid storeId,
        DateTime fromDt,
        DateTime toDt,
        string? staffEmail,
        Guid? soldByEmployeeId,
        string filterBy)
    {
        Guid? userId = null;
        string? email = staffEmail?.Trim();
        if (soldByEmployeeId.HasValue &&
            !filterBy.Equals("createdBy", StringComparison.OrdinalIgnoreCase))
        {
            var emp = await dbContext.Employees.AsNoTracking()
                .Where(e => e.Id == soldByEmployeeId && e.Deleted == null)
                .Select(e => new { e.ApplicationUserId, e.CompanyEmail })
                .FirstOrDefaultAsync();
            userId = emp?.ApplicationUserId;
            if (string.IsNullOrWhiteSpace(email))
                email = emp?.CompanyEmail;
        }
        else if (!string.IsNullOrWhiteSpace(email))
        {
            userId = await dbContext.Users.AsNoTracking()
                .Where(u => u.Email == email)
                .Select(u => (Guid?)u.Id)
                .FirstOrDefaultAsync();
        }

        var cashQ = dbContext.CashTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext())
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive
                && c.Status == CashTransactionStatus.Completed
                && c.InternalNote != null
                && c.TransactionDate >= fromDt.AddHours(7) && c.TransactionDate < toDt.AddHours(7) /* phiếu thu chi lưu giờ VN */
                && (c.InternalNote.StartsWith(PosFinanceSyncHelper.ReservationDepositMarker)
                    || c.InternalNote.StartsWith(PosFinanceSyncHelper.ReservationDepositRefundMarker)));
        if (userId.HasValue)
            cashQ = cashQ.Where(c => c.CreatedByUserId == userId);

        var cashRows = await cashQ
            .Select(c => new { c.Type, c.Amount, c.PaymentMethod, c.InternalNote })
            .ToListAsync();

        var collectedRows = cashRows
            .Where(c => c.Type == CashTransactionType.Income
                && (c.InternalNote ?? "").StartsWith(PosFinanceSyncHelper.ReservationDepositMarker))
            .ToList();
        var refundRows = cashRows
            .Where(c => c.Type == CashTransactionType.Expense
                && (c.InternalNote ?? "").StartsWith(PosFinanceSyncHelper.ReservationDepositRefundMarker))
            .ToList();

        var bookQ = dbContext.PosResourceReservations.AsNoTracking()
            .Where(x => x.StoreId == storeId);
        if (!string.IsNullOrWhiteSpace(email))
            bookQ = bookQ.Where(x => x.CreatedBy == email || x.UpdatedBy == email);

        var bookings = await bookQ
            .Select(x => new
            {
                x.DepositPaid,
                x.DepositStatus,
                x.Deleted,
                x.Status,
                x.UpdatedAt,
                x.DepositPaidAt,
            })
            .ToListAsync();

        var forfeited = bookings
            .Where(x => x.DepositStatus == PosReservationDepositStatus.Forfeited
                && x.UpdatedAt != null && x.UpdatedAt >= fromDt && x.UpdatedAt < toDt)
            .Sum(x => x.DepositPaid);
        var held = bookings
            .Where(x => x.Deleted == null
                && x.Status == PosResourceReservationStatus.Booked
                && x.DepositStatus == PosReservationDepositStatus.Held)
            .Sum(x => x.DepositPaid);
        var applied = bookings
            .Where(x => x.DepositStatus == PosReservationDepositStatus.Applied
                && x.UpdatedAt != null && x.UpdatedAt >= fromDt && x.UpdatedAt < toDt)
            .Sum(x => x.DepositPaid);

        var byPay = collectedRows
            .GroupBy(c => c.PaymentMethod)
            .Select(g => (object)new
            {
                paymentMethod = CashPayLabel(g.Key),
                total = g.Sum(x => x.Amount),
                count = g.Count(),
            })
            .ToList();

        static bool IsCash(PaymentMethodType m) => m == PaymentMethodType.Cash;

        return new DepositEodBlock(
            collectedRows.Sum(x => x.Amount),
            refundRows.Sum(x => x.Amount),
            forfeited,
            held,
            applied,
            collectedRows.Where(x => IsCash(x.PaymentMethod)).Sum(x => x.Amount),
            refundRows.Where(x => IsCash(x.PaymentMethod)).Sum(x => x.Amount),
            byPay);
    }
}
