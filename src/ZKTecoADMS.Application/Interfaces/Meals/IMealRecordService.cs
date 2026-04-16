using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Service xử lý chấm cơm - tạo MealRecord khi nhân viên quẹt thẻ trên máy chấm cơm
/// </summary>
public interface IMealRecordService
{
    /// <summary>
    /// Xử lý attendance records từ máy chấm cơm: tạo MealRecord tương ứng
    /// </summary>
    Task ProcessMealAttendancesAsync(List<Attendance> attendances, Device device);
}
