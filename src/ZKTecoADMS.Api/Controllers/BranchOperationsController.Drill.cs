using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// «Số này từ đâu ra» cho Tổng quan 1 chi nhánh (reports/overview/{branchId}): danh sách đơn, phiếu thu chi,
/// phiếu lương, hàng tồn đứng sau từng ô số. Bộ lọc chép đúng từ <see cref="ComputeKpisAsync"/> để tổng khớp ô.
/// </summary>
public partial class BranchOperationsController
{
    private const int DrillMaxRows = 500;

    private async Task<string?> DrillDenyAsync(Guid storeId, Guid branchId)
    {
        if (!branchCtx.StoreUsesBranches || !branchCtx.CanAccess(branchId))
            return "Bạn không có quyền xem chi nhánh này";
        var all = await BranchStockService.GetStoreBranchesAsync(db, storeId);
        return all.Any(x => x.Id == branchId) ? null : "Không tìm thấy chi nhánh";
    }

    /// <summary>Đơn hoàn tất của chi nhánh trong kỳ — doanh thu (Σ Total), số đơn, giá vốn / lãi gộp từng đơn.</summary>
    [HttpGet("drill/orders/{branchId:guid}")]
    [RequireModulePermission("PosReportPnl", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> DrillOrders(Guid branchId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        if (await DrillDenyAsync(storeId, branchId) is { } deny) return Ok(AppResponse<object>.Fail(deny));
        var (fromUtc, toUtc, _, _, _) = await RangeAsync(storeId, from, to);
        var hq = branchCtx.HeadquarterBranchId ?? Guid.Empty;

        var orders = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive && o.Status == PosSaleOrderStatus.Completed &&
                        (o.SaleDate ?? o.CreatedAt) >= fromUtc && (o.SaleDate ?? o.CreatedAt) < toUtc &&
                        (o.BranchId ?? hq) == branchId)
            .OrderByDescending(o => o.SaleDate ?? o.CreatedAt)
            .Select(o => new { o.Id, o.OrderNo, At = o.SaleDate ?? o.CreatedAt, o.Total, o.CustomerName, o.SoldBy, o.PaymentMethod })
            .ToListAsync();
        var cogs = await PosReportMoney.CogsByOrderAsync(db, storeId, orders.Select(o => o.Id).ToList());

        var revenue = orders.Sum(o => o.Total);
        var totalCogs = orders.Sum(o => cogs.GetValueOrDefault(o.Id));
        return Ok(AppResponse<object>.Success(new
        {
            count = orders.Count,
            revenue,
            cogs = totalCogs,
            grossProfit = revenue - totalCogs,
            truncated = orders.Count > DrillMaxRows,
            items = orders.Take(DrillMaxRows).Select(o =>
            {
                var c = cogs.GetValueOrDefault(o.Id);
                return new
                {
                    id = o.Id,
                    orderNo = o.OrderNo,
                    saleAt = o.At,
                    total = o.Total,
                    cogs = c,
                    profit = o.Total - c,
                    customerName = o.CustomerName,
                    soldBy = o.SoldBy,
                    paymentMethod = o.PaymentMethod,
                };
            }).ToList(),
        }));
    }

    /// <summary>
    /// Phiếu thu chi của chi nhánh đứng sau ô «Chi phí» (kind=expense; phiếu thu hoàn ứng công tác ghi số âm)
    /// hoặc «Thu khác» (kind=otherIncome) — cùng điều kiện loại trừ phiếu POS tự sinh / phiếu lương như KPI.
    /// </summary>
    [HttpGet("drill/cash/{branchId:guid}")]
    [RequireModulePermission("PosReportPnl", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> DrillCash(Guid branchId, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] string kind = "expense")
    {
        var storeId = RequiredStoreId;
        if (await DrillDenyAsync(storeId, branchId) is { } deny) return Ok(AppResponse<object>.Fail(deny));
        var (fromUtc, toUtc, _, _, _) = await RangeAsync(storeId, from, to);
        var hq = branchCtx.HeadquarterBranchId ?? Guid.Empty;
        var cashFrom = fromUtc.AddHours(7);
        var cashTo = toUtc.AddHours(7);

        var cash = await db.CashTransactions.AsNoTracking()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive && c.Status == CashTransactionStatus.Completed &&
                        c.TransactionDate >= cashFrom && c.TransactionDate < cashTo && (c.BranchId ?? hq) == branchId)
            .OrderByDescending(c => c.TransactionDate)
            .Select(c => new
            {
                c.Id, c.TransactionCode, c.TransactionDate, c.Type, c.Amount, c.Description, c.PaymentMethod, c.ContactName,
                Note = c.InternalNote ?? "", Source = c.SourceType ?? "",
                Category = c.Category != null ? c.Category.Name : null,
            })
            .ToListAsync();

        // Chép từ ComputeKpisAsync.
        bool IsPos(string note, string source, string? category) =>
            source.StartsWith("pos_", StringComparison.OrdinalIgnoreCase)
            || PosMarkers.Any(m => note.StartsWith(m, StringComparison.OrdinalIgnoreCase))
            || category is "Bán hàng" or "Thu nợ khách" or "Cọc đặt chỗ" or "Thu trả hàng NCC" or "Thu hộ COD"
                or "Nhập hàng" or "Trả hàng khách" or "Hoàn cọc đặt chỗ";
        bool IsPayroll(string note, string source) =>
            source is CashSources.Payslip or CashSources.Advance
            || note.StartsWith("phiếu lương #", StringComparison.OrdinalIgnoreCase);

        var wantIncome = string.Equals(kind, "otherIncome", StringComparison.OrdinalIgnoreCase);
        var rows = cash
            .Where(c => wantIncome
                ? c.Type == CashTransactionType.Income && c.Source != CashSources.TripRefund
                  && c.Category != PosPnlExtras.ForfeitedDepositCategory
                  && !IsPos(c.Note, c.Source, c.Category) && !IsPayroll(c.Note, c.Source)
                : (c.Type == CashTransactionType.Expense && c.Category != PosPnlExtras.AssetPurchaseCategory
                   && !IsPos(c.Note, c.Source, c.Category) && !IsPayroll(c.Note, c.Source))
                  || (c.Type == CashTransactionType.Income && c.Source == CashSources.TripRefund))
            .Select(c => new
            {
                id = c.Id,
                transactionCode = c.TransactionCode,
                transactionDate = c.TransactionDate,
                type = c.Type.ToString(),
                // Hoàn ứng công tác làm giảm chi phí → số âm trong danh sách chi phí.
                amount = !wantIncome && c.Type == CashTransactionType.Income ? -c.Amount : c.Amount,
                description = c.Description,
                category = c.Category,
                paymentMethod = c.PaymentMethod.ToString(),
                contactName = c.ContactName,
            })
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            count = rows.Count,
            total = rows.Sum(r => r.amount),
            truncated = rows.Count > DrillMaxRows,
            items = rows.Take(DrillMaxRows).ToList(),
        }));
    }

    /// <summary>Phiếu lương (không hủy) của nhân viên thuộc chi nhánh, tháng nằm trong kỳ — lương gộp × tỷ lệ ngày của tháng trong kỳ.</summary>
    [HttpGet("drill/payroll/{branchId:guid}")]
    [RequireModulePermission("PosReportPnl", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> DrillPayroll(Guid branchId, [FromQuery] DateTime? from, [FromQuery] DateTime? to)
    {
        var storeId = RequiredStoreId;
        if (await DrillDenyAsync(storeId, branchId) is { } deny) return Ok(AppResponse<object>.Fail(deny));
        var (_, _, fromVn, toVn, _) = await RangeAsync(storeId, from, to);
        var hq = branchCtx.HeadquarterBranchId ?? Guid.Empty;

        var monthShare = new Dictionary<(int, int), decimal>();
        for (var d = new DateTime(fromVn.Year, fromVn.Month, 1); d <= toVn; d = d.AddMonths(1))
        {
            var mStart = d < fromVn.Date ? fromVn.Date : d;
            var mEndEx = d.AddMonths(1) > toVn.Date.AddDays(1) ? toVn.Date.AddDays(1) : d.AddMonths(1);
            monthShare[(d.Year, d.Month)] = (decimal)(mEndEx - mStart).Days / DateTime.DaysInMonth(d.Year, d.Month);
        }
        var years = monthShare.Keys.Select(m => m.Item1).Distinct().ToList();
        var slips = (await db.Payslips.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null && p.Status != PayslipStatus.Cancelled && years.Contains(p.Year))
                .Select(p => new
                {
                    p.Id, p.Year, p.Month, p.GrossSalary, EmpBranch = p.Employee.BranchId,
                    Name = (p.Employee.LastName + " " + p.Employee.FirstName).Trim(),
                    p.Status,
                })
                .ToListAsync())
            .Where(p => (p.EmpBranch ?? hq) == branchId && monthShare.ContainsKey((p.Year, p.Month)))
            .Select(p =>
            {
                var share = monthShare[(p.Year, p.Month)];
                return new
                {
                    id = p.Id,
                    employeeName = p.Name,
                    year = p.Year,
                    month = p.Month,
                    status = p.Status.ToString(),
                    grossSalary = p.GrossSalary,
                    sharePct = Math.Round(share * 100, 1),
                    amount = p.GrossSalary * share,
                };
            })
            .OrderBy(p => p.year).ThenBy(p => p.month).ThenByDescending(p => p.amount)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            count = slips.Count,
            total = Math.Round(slips.Sum(p => p.amount), 0),
            truncated = slips.Count > DrillMaxRows,
            items = slips.Take(DrillMaxRows).ToList(),
        }));
    }

    /// <summary>Giá trị tồn chi nhánh từng mặt hàng: max(tồn, 0) × giá vốn (hàng hóa, cấp sản phẩm) — như KPI «Giá trị tồn kho».</summary>
    [HttpGet("drill/stock/{branchId:guid}")]
    [RequireModulePermission("PosReportPnl", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> DrillStock(Guid branchId, [FromQuery] bool outOfStock = false)
    {
        var storeId = RequiredStoreId;
        if (await DrillDenyAsync(storeId, branchId) is { } deny) return Ok(AppResponse<object>.Fail(deny));
        var prods = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.ProductType == PosProductType.Goods)
            .Select(p => new { p.Id, p.Name, p.ProductCode, p.BaseUnitName, p.CostPrice })
            .ToListAsync();
        var qty = await BranchStockService.GetBranchQtyAsync(db, storeId, branchId, branchCtx.HeadquarterBranchId);
        var rows = prods
            .Select(p =>
            {
                var q = qty.GetValueOrDefault((p.Id, (Guid?)null));
                return new
                {
                    id = p.Id,
                    name = p.Name,
                    productCode = p.ProductCode,
                    unitName = p.BaseUnitName,
                    qty = q,
                    costPrice = p.CostPrice,
                    stockValue = Math.Max(0, q) * p.CostPrice,
                };
            })
            // Ô «Giá trị tồn kho»: chỉ hàng còn tồn có giá trị; ô «mặt hàng hết»: tồn ≤ 0 (như Overview).
            .Where(p => outOfStock ? p.qty <= 0 : p.stockValue != 0)
            .OrderByDescending(p => p.stockValue).ThenBy(p => p.name)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            count = rows.Count,
            total = rows.Sum(r => r.stockValue),
            truncated = rows.Count > DrillMaxRows,
            items = rows.Take(DrillMaxRows).ToList(),
        }));
    }
}
