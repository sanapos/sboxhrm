using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosReportsController
{
    /// <summary>
    /// Nguyên vật liệu: đã dùng bao nhiêu theo định lượng (cho món nào, tốn bao nhiêu), còn đủ mấy ngày,
    /// nhập / hủy trong kỳ, món bán mà chưa khai định lượng; kết luận xanh / vàng / đỏ + việc nên làm.
    /// </summary>
    [HttpGet("materials/summary")]
    [RequireModulePermission("PosReportStock", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetMaterialsSummary(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 7);
        var orderIds = await CompletedOrderIdsAsync(storeId, fromDt, toDt);
        var r = await PosMaterialReport.BuildAsync(dbContext, storeId,
            dbContext.PosStockTransactions.AsNoTracking().ApplyBranchScope(HttpContext.BranchContext()),
            fromDt, toDt, orderIds, HttpContext.RequestAborted);
        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            r.Verdict, r.VerdictText, r.VerdictDetail, r.Days, r.Summary,
            r.Materials, r.Daily, r.TopDishes, r.NoRecipeDishes, r.Recommendations,
        }));
    }

    /// <summary>Topping: % ly có thêm topping, doanh thu / lãi topping, topping bán chạy, món hay thêm topping.</summary>
    [HttpGet("toppings/summary")]
    [RequireModulePermission("PosReportSoldGoods", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetToppingsSummary(
        [FromQuery] DateTime? from,
        [FromQuery] DateTime? to,
        [FromQuery] int? dayStartHour = null)
    {
        var storeId = RequiredStoreId;
        var hour = await ResolveReportDayStartHourAsync(storeId, dayStartHour);
        var (fromDt, toDt, fromVn, toVnEx) = ResolvePosRange(from, to, hour, defaultLookbackDays: 7);
        var orderIds = await CompletedOrderIdsAsync(storeId, fromDt, toDt);
        var r = await PosToppingReport.BuildAsync(dbContext, storeId, orderIds, HttpContext.RequestAborted);
        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn.Date,
            to = toVnEx.AddDays(-1).Date,
            r.Verdict, r.VerdictText, r.VerdictDetail, r.Summary,
            r.Toppings, r.Dishes, r.Daily, r.Recommendations,
        }));
    }

    /// <summary>Đơn hoàn tất trong kỳ theo phạm vi người xem (chi nhánh / nhân viên) — như Hàng hóa bán ra.</summary>
    private Task<List<Guid>> CompletedOrderIdsAsync(Guid storeId, DateTime fromDt, DateTime toDt) =>
        ScopeOrdersForViewer(dbContext.PosSaleOrders.AsNoTracking()
                .Where(o => o.StoreId == storeId && o.Deleted == null && o.IsActive &&
                            o.Status == PosSaleOrderStatus.Completed &&
                            (o.SaleDate ?? o.CreatedAt) >= fromDt &&
                            (o.SaleDate ?? o.CreatedAt) < toDt))
            .Select(o => o.Id)
            .ToListAsync();
}
