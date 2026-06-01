using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Constants;

/// <summary>
/// ATTLOGStamp cho máy ADMS: full sync (0) chỉ khi admin đã xếp lệnh SyncAttendances;
/// còn lại chỉ nhận chấm công mới hơn stamp.
/// </summary>
public static class AttendanceLogStampResolver
{
    public static async Task<string> ResolveAsync(
        IRepository<Attendance> attendanceRepository,
        Guid deviceId,
        bool fullSyncRequested,
        CancellationToken cancellationToken = default)
    {
        if (fullSyncRequested)
        {
            return "0";
        }

        var lastAttendance = await attendanceRepository.GetLastOrDefaultAsync(
            keySelector: a => a.AttendanceTime,
            filter: a => a.DeviceId == deviceId,
            cancellationToken: cancellationToken);

        if (lastAttendance != null)
        {
            return lastAttendance.AttendanceTime.ToString(DameTimeFormats.DeviceDateTimeFormat);
        }

        // Server chưa có log — không dùng 0 (tránh máy upload toàn bộ lịch sử).
        // Chỉ nhận chấm từ thời điểm hiện tại (giờ VN).
        return DateTime.UtcNow.AddHours(7).ToString(DameTimeFormats.DeviceDateTimeFormat);
    }
}
