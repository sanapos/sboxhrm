namespace ZKTecoADMS.Application.Interfaces;

/// <summary>Gỡ mọi FK trỏ tới AttendanceLogs trước khi xóa.</summary>
public interface IAttendanceDeletePreparer
{
    Task PrepareForDeleteAsync(Guid attendanceId, CancellationToken cancellationToken = default);
}
