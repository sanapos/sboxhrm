using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Transaction + khóa cho thao tác bàn — xem <see cref="PosFloorOpGuard"/>.</summary>
public partial class PosSellIndustryController
{
    /// <summary>Đang trong thao tác bàn: thông báo realtime gửi sau khi commit (máy khác tải lại thấy dữ liệu mới).</summary>
    List<Action>? _deferredFloorNotify;

    PosDraftLockHelper.LockActor FloorActor(string? deviceId, string? deviceName)
    {
        var display = string.IsNullOrWhiteSpace(CurrentUserEmail)
            ? CurrentUserId.ToString("N")[..8]
            : CurrentUserEmail!;
        return new PosDraftLockHelper.LockActor(CurrentUserId, EmployeeId, display, deviceId, deviceName);
    }

    /// <summary>
    /// Chạy thao tác bàn trong 1 transaction, các thao tác bàn cùng cửa hàng chạy lần lượt. Trả lỗi → rollback
    /// hết (trước đây lưu 2–3 lần rời rạc: lỗi giữa chừng để lại bàn ma / đơn tách rỗng / đặt bàn đã hủy).
    /// </summary>
    async Task<ActionResult<AppResponse<object>>> RunFloorOpAsync(
        Guid storeId, Func<Task<ActionResult<AppResponse<object>>>> body)
    {
        if (!PosFloorOpGuard.IsPostgres(db)) return await body();
        var notifies = new List<Action>();
        _deferredFloorNotify = notifies;
        ActionResult<AppResponse<object>> result;
        try
        {
            await using var tx = await db.Database.BeginTransactionAsync();
            try
            {
                await PosFloorOpGuard.LockStoreFloorAsync(db, storeId);
                result = await body();
                if (IsSuccessResult(result)) await tx.CommitAsync();
                else await tx.RollbackAsync();
            }
            catch (Exception ex) when (PosFloorOpGuard.IsRace(ex))
            {
                await tx.RollbackAsync();
                return Conflict(AppResponse<object>.Fail(PosFloorOpGuard.ChangedMessage));
            }
        }
        finally
        {
            _deferredFloorNotify = null;
        }
        if (IsSuccessResult(result))
            foreach (var notify in notifies) notify();
        return result;
    }

    static bool IsSuccessResult(ActionResult<AppResponse<object>> result) =>
        result.Result is ObjectResult { StatusCode: >= 200 and < 300 }
        || (result.Result == null && result.Value != null);
}
