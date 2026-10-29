using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosSalesController
{
    /// <summary>
    /// «Gửi thu ngân»: tài khoản Order (không có quyền thanh toán) báo đơn / bàn cần tính tiền. Máy POS của cửa hàng
    /// nhận ngay qua kênh sơ đồ bàn (máy có quyền thanh toán hiện thông báo), người có quyền thanh toán nhận thêm
    /// thông báo trong chuông. Không đổi tiền / trạng thái đơn.
    /// </summary>
    [HttpPost("{id:guid}/request-payment")]
    [RequireAnyActionOnModule("PosSell", ModulePermissionAction.Create, ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> RequestPayment(Guid id)
    {
        var storeId = RequiredStoreId;
        var order = await dbContext.PosSaleOrders.AsNoTracking()
            .Where(o => o.Id == id && o.StoreId == storeId && o.Deleted == null)
            .Select(o => new { o.Id, o.OrderNo, o.Status, o.Total, o.ServiceResourceId, o.ResourceSessionId })
            .FirstOrDefaultAsync();
        if (order == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đơn hàng"));
        if (order.Status != PosSaleOrderStatus.Draft)
            return BadRequest(AppResponse<object>.Fail("Đơn đã thanh toán hoặc đã hủy"));
        var hasLines = await dbContext.PosSaleOrderLines.AsNoTracking()
            .AnyAsync(l => l.SaleOrderId == id && l.Deleted == null);
        if (!hasLines)
            return BadRequest(AppResponse<object>.Fail("Đơn chưa có món — gọi món trước khi gửi thu ngân"));

        var table = order.ServiceResourceId is Guid rid
            ? await dbContext.PosServiceResources.AsNoTracking()
                .Where(r => r.Id == rid).Select(r => r.Name).FirstOrDefaultAsync()
            : null;
        var who = await dbContext.Users.AsNoTracking()
            .Where(u => u.Id == CurrentUserId)
            .Select(u => (u.LastName + " " + u.FirstName).Trim())
            .FirstOrDefaultAsync();
        if (string.IsNullOrWhiteSpace(who)) who = CurrentUserEmail;
        var place = string.IsNullOrWhiteSpace(table) ? $"Đơn {order.OrderNo}" : table!.Trim();
        var money = order.Total.ToString("#,##0", System.Globalization.CultureInfo.GetCultureInfo("vi-VN"));
        var message = $"{place} cần thanh toán · {money}đ · {who} gửi";

        PosFloorRealtimeHelper.Notify(hubContext, storeId, "paymentRequested",
            orderId: order.Id, resourceId: order.ServiceResourceId, sessionId: order.ResourceSessionId,
            tableName: table, message: message, orderNo: order.OrderNo, amount: order.Total);
        await PosNotificationHelper.NotifyPaymentRequestedAsync(
            notificationService, dbContext, storeId, order.Id, message, CurrentUserId);
        return Ok(AppResponse<object>.Success(new { orderId = order.Id, message }));
    }
}
