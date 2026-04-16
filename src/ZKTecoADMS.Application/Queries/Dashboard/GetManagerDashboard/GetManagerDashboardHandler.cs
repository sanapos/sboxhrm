using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.DTOs.Dashboard;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Dashboard.GetManagerDashboard;

public class GetManagerDashboardHandler(
    IRepository<Shift> shiftRepository,
    IRepository<Leave> leaveRepository,
    IRepository<Attendance> attendanceRepository,
    UserManager<ApplicationUser> userManager,
    ILogger<GetManagerDashboardHandler> logger
) : IQueryHandler<GetManagerDashboardQuery, AppResponse<ManagerDashboardDto>>
{
    public async Task<AppResponse<ManagerDashboardDto>> Handle(GetManagerDashboardQuery request, CancellationToken cancellationToken)
    {
        try
        {
            var startOfDay = request.Date.Date;
            var endOfDay = startOfDay.AddDays(1).AddTicks(-1);

            // Get all employees managed by this manager
            var managedUsers = await userManager.Users
                .Include(u => u.Employee)
                .Where(u => u.ManagerId == request.ManagerUserId)
                .ToListAsync(cancellationToken);

            // If user is Admin/SuperAdmin and has no direct managed employees, get all employees in the same Store
            var isAdmin = request.UserRole.Equals(nameof(Roles.Admin), StringComparison.OrdinalIgnoreCase)
                       || request.UserRole.Equals(nameof(Roles.SuperAdmin), StringComparison.OrdinalIgnoreCase);

            if (!managedUsers.Any() && isAdmin && request.StoreId.HasValue)
            {
                managedUsers = await userManager.Users
                    .Include(u => u.Employee)
                    .Where(u => u.StoreId == request.StoreId.Value && u.Id != request.ManagerUserId)
                    .ToListAsync(cancellationToken);
            }

            var managedUserIds = managedUsers.Select(e => e.Id).ToList();

            if (!managedUserIds.Any())
            {
                return AppResponse<ManagerDashboardDto>.Success(new ManagerDashboardDto
                {
                    AttendanceRate = new AttendanceRateDto()
                });
            }

            // Build a lookup for department from Employee entity
            var userDepartmentMap = managedUsers
                .Where(u => u.Employee != null && !string.IsNullOrEmpty(u.Employee.Department))
                .ToDictionary(u => u.Id, u => u.Employee!.Department!);

            // Get all shifts for today for managed employees  
            var todayShifts = (await shiftRepository.GetAllAsync(
                filter: s => managedUserIds.Contains(s.EmployeeUserId) &&
                           s.StartTime >= startOfDay &&
                           s.StartTime <= endOfDay &&
                           s.Status == ShiftStatus.Approved,
                includeProperties: new[] { "ApplicationUser", "ApplicationUser.Employee" },
                cancellationToken: cancellationToken)).ToList();

            // Get all approved leaves for today that are associated with shifts
            var leavesForToday = (await leaveRepository.GetAllAsync(
                filter: l => l.Status == LeaveStatus.Approved &&
                           l.StartDate <= endOfDay &&
                           l.EndDate >= startOfDay &&
                           managedUserIds.Contains(l.EmployeeUserId),
                includeProperties: new[] { "EmployeeUser", "EmployeeUser.Employee", "Shift" },
                cancellationToken: cancellationToken))
                .ToList();

            // Get all employees for the managed users to map attendance
            var employeeIdToUserIdMap = managedUsers
                .Where(u => u.Employee != null)
                .ToDictionary(u => u.Employee!.Id, u => u.Id);

            // Get attendances for today
            var attendances = (await attendanceRepository.GetAllAsync(
                filter: a => a.EmployeeId != null && employeeIdToUserIdMap.Keys.Contains(a.EmployeeId.Value) &&
                           a.AttendanceTime >= startOfDay &&
                           a.AttendanceTime <= endOfDay,
                includeProperties: new[] { "Employee" },
                orderBy: q => q.OrderBy(a => a.AttendanceTime),
                cancellationToken: cancellationToken)).ToList();

            // Group attendances by employee to find first check-in and map to ApplicationUser
            var attendancesByUser = new Dictionary<Guid, List<Attendance>>();
            foreach (var attendance in attendances)
            {
                if (attendance.EmployeeId.HasValue && employeeIdToUserIdMap.TryGetValue(attendance.EmployeeId.Value, out var userId))
                {
                    if (!attendancesByUser.ContainsKey(userId))
                    {
                        attendancesByUser[userId] = new List<Attendance>();
                    }
                    attendancesByUser[userId].Add(attendance);
                }
            }

            var employeeCheckIns = attendancesByUser
                .ToDictionary(
                    kvp => kvp.Key,
                    kvp => kvp.Value.OrderBy(a => a.AttendanceTime).First()
                );

            var employeeCheckOuts = attendancesByUser
                .ToDictionary(
                    kvp => kvp.Key,
                    kvp => kvp.Value.OrderByDescending(a => a.AttendanceTime).First()
                );

            // Build employees on leave list
            var employeesOnLeave = leavesForToday.Select(l => new EmployeeOnLeaveDto
            {
                EmployeeUserId = l.EmployeeUserId,
                FullName = GetFullName(l.EmployeeUser),
                Email = l.EmployeeUser.Email ?? "",
                LeaveId = l.Id,
                LeaveType = l.Type.ToString(),
                LeaveStartDate = l.StartDate,
                LeaveEndDate = l.EndDate,
                IsFullDay = l.IsHalfShift == false,
                Reason = l.Reason,
                ShiftId = l.ShiftId,
                ShiftStartTime = l.Shift != null ? startOfDay.Date.Add(l.Shift.StartTime) : l.StartDate,
                ShiftEndTime = l.Shift != null ? startOfDay.Date.Add(l.Shift.EndTime) : l.EndDate
            }).ToList();

            var onLeaveUserIds = employeesOnLeave.Select(e => e.EmployeeUserId).ToHashSet();

            // Build late employees list (checked in but late, excluding those on leave)
            var lateEmployees = new List<LateDeviceUserDto>();
            foreach (var shift in todayShifts.Where(s => !onLeaveUserIds.Contains(s.EmployeeUserId)))
            {
                if (employeeCheckIns.TryGetValue(shift.EmployeeUserId, out var checkIn))
                {
                    if (checkIn.AttendanceTime > shift.StartTime)
                    {
                        lateEmployees.Add(new LateDeviceUserDto
                        {
                            EmployeeUserId = shift.EmployeeUserId,
                            FullName = GetFullName(shift.EmployeeUser),
                            Email = shift.EmployeeUser.Email ?? "",
                            ShiftId = shift.Id,
                            ShiftStartTime = shift.StartTime,
                            ActualCheckInTime = checkIn.AttendanceTime,
                            LateBy = checkIn.AttendanceTime - shift.StartTime,
                            Department = userDepartmentMap.GetValueOrDefault(shift.EmployeeUserId, "")
                        });
                    }
                }
            }

            // Build absent employees list (no check-in and not on leave)
            var checkedInUserIds = employeeCheckIns.Keys.ToHashSet();
            var absentEmployees = todayShifts
                .Where(s => !onLeaveUserIds.Contains(s.EmployeeUserId) &&
                           !checkedInUserIds.Contains(s.EmployeeUserId))
                .Select(s => new AbsentDeviceUserDto
                {
                    EmployeeUserId = s.EmployeeUserId,
                    FullName = GetFullName(s.EmployeeUser),
                    Email = s.EmployeeUser.Email ?? "",
                    ShiftId = s.Id,
                    ShiftStartTime = s.StartTime,
                    ShiftEndTime = s.EndTime,
                    Department = userDepartmentMap.GetValueOrDefault(s.EmployeeUserId, "")
                })
                .ToList();

            // Build today employees list (all employees with shifts)
            var todayEmployees = todayShifts.Select(s =>
            {
                string status;
                DateTime? checkInTime = null;
                DateTime? checkOutTime = null;

                if (onLeaveUserIds.Contains(s.EmployeeUserId))
                {
                    status = "On Leave";
                }
                else if (employeeCheckIns.TryGetValue(s.EmployeeUserId, out var checkIn))
                {
                    checkInTime = checkIn.AttendanceTime;
                    if (employeeCheckOuts.TryGetValue(s.EmployeeUserId, out var checkOut))
                    {
                        checkOutTime = checkOut.AttendanceTime;
                    }
                    
                    status = checkIn.AttendanceTime > s.StartTime ? "Late" : "Present";
                }
                else
                {
                    status = "Absent";
                }

                return new TodayDeviceUserDto
                {
                    EmployeeUserId = s.EmployeeUserId,
                    FullName = GetFullName(s.EmployeeUser),
                    Email = s.EmployeeUser.Email ?? "",
                    ShiftId = s.Id,
                    ShiftStartTime = s.StartTime,
                    ShiftEndTime = s.EndTime,
                    Status = status,
                    CheckInTime = checkInTime,
                    CheckOutTime = checkOutTime,
                    Department = userDepartmentMap.GetValueOrDefault(s.EmployeeUserId, "")
                };
            }).ToList();

            // Calculate attendance rate
            var totalEmployeesWithShift = todayShifts.Count;
            var presentEmployees = checkedInUserIds.Count - lateEmployees.Count;
            var lateCount = lateEmployees.Count;
            var absentCount = absentEmployees.Count;
            var onLeaveCount = employeesOnLeave.Count;

            var attendanceRate = new AttendanceRateDto
            {
                TotalEmployeesWithShift = totalEmployeesWithShift,
                PresentEmployees = presentEmployees,
                LateEmployees = lateCount,
                AbsentEmployees = absentCount,
                OnLeaveEmployees = onLeaveCount,
                AttendancePercentage = totalEmployeesWithShift > 0
                    ? Math.Round((double)(checkedInUserIds.Count) / totalEmployeesWithShift * 100, 2)
                    : 0,
                PunctualityPercentage = totalEmployeesWithShift > 0
                    ? Math.Round((double)presentEmployees / totalEmployeesWithShift * 100, 2)
                    : 0
            };

            var result = new ManagerDashboardDto
            {
                EmployeesOnLeave = employeesOnLeave,
                AbsentEmployees = absentEmployees,
                LateEmployees = lateEmployees.OrderByDescending(e => e.LateBy).ToList(),
                TodayEmployees = todayEmployees.OrderBy(e => e.FullName).ToList(),
                AttendanceRate = attendanceRate
            };

            return AppResponse<ManagerDashboardDto>.Success(result);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error retrieving manager dashboard data for manager {ManagerId} on {Date}", 
                request.ManagerUserId, request.Date);
            return AppResponse<ManagerDashboardDto>.Fail("An error occurred while retrieving dashboard data");
        }
    }

    private static string GetFullName(ApplicationUser user)
    {
        if (!string.IsNullOrEmpty(user.FirstName) || !string.IsNullOrEmpty(user.LastName))
        {
            return $"{user.LastName} {user.FirstName}".Trim();
        }
        return user.Email ?? "Unknown";
    }
}
