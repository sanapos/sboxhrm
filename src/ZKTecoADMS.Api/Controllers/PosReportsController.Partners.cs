using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosReportsController
{
    /// <summary>Công nợ NCC + aging theo phiếu nhập chưa trả đủ.</summary>
    [HttpGet("supplier-debt")]
    [RequireModulePermission("PosReportDebt", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> SupplierDebtReport(
        [FromQuery] string? search,
        [FromQuery] decimal? debtFrom,
        [FromQuery] decimal? debtTo,
        [FromQuery] bool includeZeroDebt = false)
    {
        var storeId = RequiredStoreId;
        var q = dbContext.PosSuppliers.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null && s.IsActive);
        if (!includeZeroDebt) q = q.Where(s => s.CurrentDebt > 0);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(x =>
                x.Name.ToLower().Contains(s) ||
                x.SupplierCode.ToLower().Contains(s) ||
                (x.Phone != null && x.Phone.Contains(s)));
        }
        if (debtFrom.HasValue) q = q.Where(x => x.CurrentDebt >= debtFrom);
        if (debtTo.HasValue) q = q.Where(x => x.CurrentDebt <= debtTo);

        var suppliers = await q
            .OrderByDescending(x => x.CurrentDebt)
            .ThenBy(x => x.Name)
            .Select(x => new
            {
                x.Id,
                x.SupplierCode,
                x.Name,
                x.Phone,
                x.TotalPurchase,
                x.CurrentDebt,
                groupName = x.Group != null ? x.Group.Name : null,
            })
            .ToListAsync();

        var supplierIds = suppliers.Select(x => x.Id).ToList();
        var unpaid = supplierIds.Count == 0
            ? []
            : await dbContext.PosStockReceipts.AsNoTracking()
                .Where(r => r.StoreId == storeId && r.Deleted == null &&
                            r.Status == PosPurchaseReceiptStatus.Completed &&
                            r.SupplierId != null && supplierIds.Contains(r.SupplierId.Value) &&
                            r.TotalCost + r.TotalVat - r.DiscountAmount > r.PaidAmount)
                .Select(r => new
                {
                    SupplierId = r.SupplierId!.Value,
                    Due = r.TotalCost + r.TotalVat - r.DiscountAmount - r.PaidAmount,
                    BizAt = r.ImportDate ?? r.CreatedAt,
                })
                .ToListAsync();

        var today = DateTime.UtcNow.Date;
        static int Bucket(DateTime bizAt, DateTime todayUtc)
        {
            var days = (todayUtc - bizAt.Date).Days;
            if (days <= 30) return 0;
            if (days <= 60) return 1;
            if (days <= 90) return 2;
            return 3;
        }

        var items = suppliers.Select(s =>
        {
            var rows = unpaid.Where(x => x.SupplierId == s.Id).ToList();
            decimal SumB(int b) => rows.Where(x => Bucket(x.BizAt, today) == b).Sum(x => x.Due);
            return new
            {
                s.Id,
                s.SupplierCode,
                s.Name,
                s.Phone,
                s.TotalPurchase,
                s.CurrentDebt,
                s.groupName,
                openReceiptCount = rows.Count,
                openReceiptDebt = rows.Sum(x => x.Due),
                debt0To30 = SumB(0),
                debt31To60 = SumB(1),
                debt61To90 = SumB(2),
                debtOver90 = SumB(3),
            };
        }).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            totalSuppliers = items.Count,
            sumDebt = items.Sum(x => x.CurrentDebt),
            sumOpenReceiptDebt = items.Sum(x => x.openReceiptDebt),
            sumDebt0To30 = items.Sum(x => x.debt0To30),
            sumDebt31To60 = items.Sum(x => x.debt31To60),
            sumDebt61To90 = items.Sum(x => x.debt61To90),
            sumDebtOver90 = items.Sum(x => x.debtOver90),
            items,
        }));
    }

    /// <summary>Nhập / trả NCC theo kỳ.</summary>
    [HttpGet("purchases/summary")]
    [RequireModulePermission("PosReportPurchases", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetPurchasesSummary(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] Guid? supplierId = null,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var receiptQ = dbContext.PosStockReceipts.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null &&
                        r.Status == PosPurchaseReceiptStatus.Completed &&
                        (r.ImportDate ?? r.CreatedAt) >= fromDt &&
                        (r.ImportDate ?? r.CreatedAt) < toDt);
        if (supplierId.HasValue) receiptQ = receiptQ.Where(r => r.SupplierId == supplierId);

        var receipts = await receiptQ
            .OrderByDescending(r => r.ImportDate ?? r.CreatedAt)
            .Select(r => new
            {
                r.Id,
                r.ReceiptNo,
                date = r.ImportDate ?? r.CreatedAt,
                supplierId = r.SupplierId,
                supplierName = r.Supplier != null ? r.Supplier.Name : null,
                r.TotalQty,
                r.TotalCost,
                r.TotalVat,
                r.DiscountAmount,
                r.PaidAmount,
                grandTotal = r.TotalCost + r.TotalVat - r.DiscountAmount,
                r.PurchaseOrderNo,
                r.InputInvoiceNo,
                status = r.Status.ToString(),
            })
            .ToListAsync();

        var returnQ = dbContext.PosPurchaseReturns.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null &&
                        r.Status == PosPurchaseReturnStatus.Completed &&
                        (r.ReturnDate ?? r.CreatedAt) >= fromDt &&
                        (r.ReturnDate ?? r.CreatedAt) < toDt);
        if (supplierId.HasValue) returnQ = returnQ.Where(r => r.SupplierId == supplierId);

        var returns = await returnQ
            .OrderByDescending(r => r.ReturnDate ?? r.CreatedAt)
            .Select(r => new
            {
                r.Id,
                r.ReturnNo,
                date = r.ReturnDate ?? r.CreatedAt,
                supplierId = r.SupplierId,
                supplierName = r.Supplier != null ? r.Supplier.Name : null,
                r.TotalQty,
                r.TotalAmount,
                r.DiscountAmount,
                r.RefundDue,
                r.RefundReceived,
                status = r.Status.ToString(),
            })
            .ToListAsync();

        var paidInPeriod = await dbContext.PosSupplierPayments.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null &&
                        p.PaidAt >= fromDt && p.PaidAt < toDt &&
                        (!supplierId.HasValue || p.SupplierId == supplierId))
            .SumAsync(p => (decimal?)p.Amount) ?? 0;

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            receiptCount = receipts.Count,
            receiptQty = receipts.Sum(x => x.TotalQty),
            receiptAmount = receipts.Sum(x => x.grandTotal),
            receiptVat = receipts.Sum(x => x.TotalVat),
            paidInPeriod,
            returnCount = returns.Count,
            returnQty = returns.Sum(x => x.TotalQty),
            returnAmount = returns.Sum(x => x.TotalAmount),
            receipts,
            returns,
        }));
    }

    /// <summary>
    /// Đặt chỗ / cọc theo kỳ.
    /// dateBasis=usage (mặc định): lọc theo ngày khách dùng bàn (ReservedAt).
    /// dateBasis=created: lọc theo ngày nhân viên nhận lịch (CreatedAt) — cọc thu hôm nay vẫn vào két ngày thu.
    /// </summary>
    [HttpGet("reservations/summary")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetReservationsSummary(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] string? status = null,
        [FromQuery] int? dayStartHour = null,
        [FromQuery] string? dateBasis = "usage")
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 30);

        var byCreated = string.Equals(dateBasis, "created", StringComparison.OrdinalIgnoreCase)
            || string.Equals(dateBasis, "booked", StringComparison.OrdinalIgnoreCase)
            || string.Equals(dateBasis, "dat", StringComparison.OrdinalIgnoreCase);

        var query = dbContext.PosResourceReservations.AsNoTracking()
            .Where(x => x.StoreId == storeId);
        query = byCreated
            ? query.Where(x => x.CreatedAt >= fromDt && x.CreatedAt < toDt)
            : query.Where(x => x.ReservedAt >= fromDt && x.ReservedAt < toDt);

        if (!string.IsNullOrWhiteSpace(status) &&
            Enum.TryParse<PosResourceReservationStatus>(status, true, out var st))
            query = query.Where(x => x.Status == st);

        var ordered = byCreated
            ? query.OrderByDescending(x => x.CreatedAt)
            : query.OrderByDescending(x => x.ReservedAt);

        var rows = await ordered
            .Select(x => new
            {
                x.Id,
                x.ReservedAt,
                x.ReservedUntil,
                x.CreatedAt,
                x.GuestCount,
                x.CustomerName,
                x.Phone,
                resourceName = x.Resource != null ? x.Resource.Name : "",
                resourceCode = x.Resource != null ? x.Resource.Code : "",
                status = x.Status.ToString(),
                x.DepositAmount,
                x.DepositPaid,
                depositStatus = x.DepositStatus.ToString(),
                depositPaymentMethod = x.DepositPaymentMethod,
                x.Note,
                x.Occasion,
                x.SpecialRequest,
            })
            .ToListAsync();

        static string StatusVi(string s) => s switch
        {
            "Booked" => "Đã đặt",
            "Seated" => "Đã nhận",
            "Cancelled" => "Hủy",
            "NoShow" => "Không đến",
            _ => s,
        };

        static string DepositVi(string s) => s switch
        {
            "Held" => "Đang giữ",
            "Applied" => "Đã trừ HĐ",
            "Refunded" => "Đã hoàn",
            "Forfeited" => "Mất cọc",
            "None" => "Chưa thu",
            _ => s,
        };

        static string OccasionVi(string? s) => (s ?? "").ToLowerInvariant() switch
        {
            "birthday" => "Sinh nhật",
            "party" => "Liên hoan",
            "reunion" => "Họp lớp",
            "partner" => "Gặp đối tác",
            "other" => "Khác",
            "" => "",
            _ => s!,
        };

        var advanceCount = rows.Count(x =>
            ReservationVnDate(x.CreatedAt) < ReservationVnDate(x.ReservedAt));
        var useLaterCount = rows.Count(x =>
            x.status == "Booked" && x.ReservedAt >= toDt);

        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            dateBasis = byCreated ? "created" : "usage",
            bookedCount = rows.Count(x => x.status == "Booked"),
            seatedCount = rows.Count(x => x.status == "Seated"),
            cancelledCount = rows.Count(x => x.status == "Cancelled"),
            noShowCount = rows.Count(x => x.status == "NoShow"),
            advanceCount,
            useLaterCount,
            depositHeld = rows.Where(x => x.depositStatus == "Held").Sum(x => x.DepositPaid),
            depositApplied = rows.Where(x => x.depositStatus == "Applied").Sum(x => x.DepositPaid),
            depositForfeited = rows.Where(x => x.depositStatus == "Forfeited").Sum(x => x.DepositPaid),
            depositRefunded = rows.Where(x => x.depositStatus == "Refunded").Sum(x => x.DepositPaid),
            items = rows.Select(x => new
            {
                x.Id,
                x.ReservedAt,
                x.ReservedUntil,
                x.CreatedAt,
                x.GuestCount,
                x.CustomerName,
                x.Phone,
                x.resourceName,
                x.resourceCode,
                x.status,
                statusLabel = StatusVi(x.status),
                x.DepositAmount,
                x.DepositPaid,
                x.depositStatus,
                depositStatusLabel = DepositVi(x.depositStatus),
                x.depositPaymentMethod,
                x.Note,
                x.Occasion,
                occasionLabel = OccasionVi(x.Occasion),
                x.SpecialRequest,
            }).ToList(),
        }));
    }

    static DateTime ReservationVnDate(DateTime utc)
    {
        var u = utc.Kind == DateTimeKind.Utc ? utc : DateTime.SpecifyKind(utc, DateTimeKind.Utc);
        return u.AddHours(7).Date;
    }
}
