using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Infrastructure.Services;

public class MealRecordService(
    IRepository<MealRecord> mealRecordRepository,
    IRepository<MealSession> mealSessionRepository,
    IRepository<Shift> shiftRepository,
    IRepository<DeviceUser> deviceUserRepository,
    ISystemNotificationService notificationService,
    ILogger<MealRecordService> logger
) : IMealRecordService
{
    public async Task ProcessMealAttendancesAsync(List<Attendance> attendances, Device device)
    {
        if (!device.StoreId.HasValue) return;

        var storeId = device.StoreId.Value;

        // Get active meal sessions for this store
        var mealSessions = await mealSessionRepository.GetAllAsync(
            filter: s => s.StoreId == storeId && s.IsActive);

        if (mealSessions.Count == 0)
        {
            logger.LogWarning("No active meal sessions found for store {StoreId}", storeId);
            return;
        }

        foreach (var attendance in attendances)
        {
            try
            {
                var mealTime = attendance.AttendanceTime;
                var timeOfDay = mealTime.TimeOfDay;

                // Find matching meal session by time
                var matchingSession = mealSessions.FirstOrDefault(s =>
                    timeOfDay >= s.StartTime && timeOfDay <= s.EndTime);

                if (matchingSession == null)
                {
                    // If no exact match, find closest session
                    matchingSession = mealSessions
                        .OrderBy(s => Math.Abs((timeOfDay - s.StartTime).TotalMinutes))
                        .First();
                    logger.LogWarning("No exact meal session match for time {Time}, using closest: {SessionName}",
                        timeOfDay, matchingSession.Name);
                }

                // Find the employee's user ID via DeviceUser mapping
                Guid? employeeUserId = null;
                if (!string.IsNullOrWhiteSpace(attendance.PIN))
                {
                    var deviceUser = await deviceUserRepository.GetSingleAsync(
                        du => du.Pin == attendance.PIN && du.DeviceId == device.Id,
                        includeProperties: ["Employee"]);
                    employeeUserId = deviceUser?.Employee?.ApplicationUserId;
                }

                if (!employeeUserId.HasValue)
                {
                    logger.LogWarning("Cannot find employee for PIN {PIN} on device {DeviceId}", attendance.PIN, device.Id);
                    continue;
                }

                // Check duplicate: same employee, same session, same date
                var date = mealTime.Date;
                var exists = await mealRecordRepository.ExistsAsync(
                    r => r.EmployeeUserId == employeeUserId.Value &&
                         r.MealSessionId == matchingSession.Id &&
                         r.Date == date);

                if (exists)
                {
                    logger.LogInformation("Meal record already exists for employee {UserId} session {Session} on {Date}",
                        employeeUserId, matchingSession.Name, date);
                    continue;
                }

                // Find current shift for this employee
                Guid? shiftId = null;
                var shift = await shiftRepository.GetSingleAsync(
                    s => s.EmployeeUserId == employeeUserId.Value &&
                         s.StoreId == storeId &&
                         s.StartTime.Date == date &&
                         s.Status == ShiftStatus.Approved);
                shiftId = shift?.Id;

                var mealRecord = new MealRecord
                {
                    AttendanceId = attendance.Id != Guid.Empty ? attendance.Id : null,
                    EmployeeUserId = employeeUserId.Value,
                    PIN = attendance.PIN,
                    MealSessionId = matchingSession.Id,
                    MealTime = mealTime,
                    Date = date,
                    ShiftId = shiftId,
                    DeviceId = device.Id,
                    StoreId = storeId
                };

                await mealRecordRepository.AddAsync(mealRecord);
                logger.LogInformation("Created meal record for employee {UserId}, session {Session}, time {Time}",
                    employeeUserId, matchingSession.Name, mealTime);

                // Notify employee about successful meal check-in
                try
                {
                    await notificationService.CreateAndSendAsync(
                        targetUserId: employeeUserId.Value,
                        type: NotificationType.Success,
                        title: "Chấm cơm thành công",
                        message: $"Đã ghi nhận {matchingSession.Name} lúc {mealTime:HH:mm}",
                        relatedEntityId: mealRecord.Id,
                        relatedEntityType: "MealRecord",
                        categoryCode: "meal",
                        storeId: storeId);
                }
                catch (Exception notifEx)
                {
                    logger.LogWarning(notifEx, "Failed to send meal notification for employee {UserId}", employeeUserId);
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Error processing meal attendance for PIN {PIN}", attendance.PIN);
            }
        }
    }
}
