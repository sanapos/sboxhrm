using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Gỡ FK bằng SQL trực tiếp (không phụ thuộc EF tracking / query filter).
/// </summary>
public sealed class AttendanceDeletePreparer(ZKTecoDbContext db) : IAttendanceDeletePreparer
{
    public async Task PrepareForDeleteAsync(Guid attendanceId, CancellationToken cancellationToken = default)
    {
        // Thứ tự: phiếu chỉnh công & phạt trước, rồi ca/ăn.
        await db.Database.ExecuteSqlRawAsync(
            """
            UPDATE "AttendanceCorrectionRequests" SET "AttendanceId" = NULL WHERE "AttendanceId" = {0};
            UPDATE "PenaltyTickets" SET "AttendanceId" = NULL WHERE "AttendanceId" = {0};
            UPDATE "MealRecords" SET "AttendanceId" = NULL WHERE "AttendanceId" = {0};
            UPDATE "Shifts" SET "CheckInAttendanceId" = NULL WHERE "CheckInAttendanceId" = {0};
            UPDATE "Shifts" SET "CheckOutAttendanceId" = NULL WHERE "CheckOutAttendanceId" = {0};
            """,
            attendanceId);

        // Cột legacy nếu có bản ghi mobile gắn log (không chặn DELETE nhưng giữ sạch).
        try
        {
            await db.Database.ExecuteSqlRawAsync(
                """
                UPDATE "AttendanceLogs" SET "MobileAttendanceRecordId" = NULL
                WHERE "Id" = {0};
                """,
                attendanceId);
        }
        catch
        {
            // Cột có thể không tồn tại trên DB cũ — bỏ qua.
        }
    }
}
