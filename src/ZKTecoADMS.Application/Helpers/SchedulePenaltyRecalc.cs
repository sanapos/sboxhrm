using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Xếp / sửa / xóa ca cho ngày đã qua (hoặc hôm nay): phiếu phạt đi trễ / về sớm chỉ tự tạo lúc chấm công,
/// nên ca xếp sau khi nhân viên đã chấm thì không có phiếu. Tính lại phạt các ngày bị đổi lịch
/// (hủy phiếu chờ duyệt cũ của ngày đó rồi tạo lại theo ca mới).
/// </summary>
public static class SchedulePenaltyRecalc
{
    /// <summary>Tối đa số (nhân viên, ngày) tính lại trong một lần — sao chép lịch nhiều tuần không làm chậm request.</summary>
    public const int MaxItems = 300;

    public static async Task RunAsync(
        IAttendanceService attendanceService,
        Guid storeId,
        IEnumerable<(Guid EmployeeId, DateTime Date)> items,
        CancellationToken cancellationToken = default)
    {
        var today = VnTimeHelper.NowVn().Date;
        var todo = items
            .Select(x => (x.EmployeeId, Date: x.Date.Date))
            .Where(x => x.EmployeeId != Guid.Empty && x.Date <= today)
            .Distinct()
            .OrderByDescending(x => x.Date)
            .Take(MaxItems)
            .ToList();
        foreach (var (employeeId, date) in todo)
        {
            try
            {
                await attendanceService.RecalculatePenaltiesForEmployeeDateAsync(storeId, employeeId, date, cancellationToken);
            }
            catch
            {
                // Lỗi tính phạt không chặn việc lưu lịch.
            }
        }
    }
}
