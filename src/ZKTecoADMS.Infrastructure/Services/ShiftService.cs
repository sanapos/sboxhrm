using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Infrastructure.Services;

public class ShiftService(
    IRepository<Shift> repository,
    UserManager<ApplicationUser> userManager,
    IRepository<DeviceUser> employeeRepository,
    IRepository<Attendance> attendanceRepository,
    ILogger<ShiftService> logger) : IShiftService
{
    public async Task<Shift?> GetShiftByIdAsync(Guid storeId, Guid id, CancellationToken cancellationToken = default)
    {
        return await repository.GetSingleAsync(
            s => s.Id == id && s.StoreId == storeId,
            includeProperties: [nameof(Shift.EmployeeUser)],
            cancellationToken: cancellationToken);
    }

    public async Task<List<Shift>> GetShiftsByManagerAsync(Guid managerId, CancellationToken cancellationToken = default)
    {
        var shifts = await repository.GetAllAsync(
            filter: s => s.EmployeeUser != null && s.EmployeeUser.ManagerId == managerId,
            orderBy: query => query.OrderByDescending(s => s.CreatedAt),
            includeProperties: new[] { nameof(Shift.EmployeeUser) },
            cancellationToken: cancellationToken);

        return shifts.ToList();
    }

    public async Task<List<Shift>> GetPendingShiftsAsync(CancellationToken cancellationToken = default)
    {
        var shifts = await repository.GetAllAsync(
            filter: s => s.Status == ShiftStatus.Pending,
            orderBy: query => query.OrderBy(s => s.StartTime),
            includeProperties: new[] { nameof(Shift.EmployeeUser) },
            cancellationToken: cancellationToken);

        return shifts.ToList();
    }

    public async Task<Shift> ApproveShiftAsync(Guid storeId, Guid shiftId, Guid approvedByUserId, CancellationToken cancellationToken = default)
    {
        var shift = await GetShiftByIdAsync(storeId, shiftId, cancellationToken);
        if (shift == null)
        {
            throw new InvalidOperationException($"Shift with ID {shiftId} not found");
        }

        if (shift.Status != ShiftStatus.Pending)
        {
            throw new InvalidOperationException($"Cannot approve shift with status {shift.Status}");
        }

        // Verify the approver exists
        var approver = await userManager.FindByIdAsync(approvedByUserId.ToString());
        if (approver == null)
        {
            throw new InvalidOperationException($"Approver with ID {approvedByUserId} not found");
        }

        shift.Status = ShiftStatus.Approved;
        shift.RejectionReason = null;

        await repository.UpdateAsync(shift, cancellationToken);
        
        logger.LogInformation(
            "Shift {ShiftId} approved by user {ApprovedByUserId}",
            shiftId,
            approvedByUserId);

        return shift;
    }

    public async Task<Shift> RejectShiftAsync(Guid storeId, Guid shiftId, Guid rejectedByUserId, string rejectionReason, CancellationToken cancellationToken = default)
    {
        var shift = await GetShiftByIdAsync(storeId, shiftId, cancellationToken);
        if (shift == null)
        {
            throw new InvalidOperationException($"Shift with ID {shiftId} not found");
        }

        if (shift.Status != ShiftStatus.Pending)
        {
            throw new InvalidOperationException($"Cannot reject shift with status {shift.Status}");
        }

        if (string.IsNullOrWhiteSpace(rejectionReason))
        {
            throw new ArgumentException("Rejection reason is required", nameof(rejectionReason));
        }

        // Verify the rejector exists
        var rejector = await userManager.FindByIdAsync(rejectedByUserId.ToString());
        if (rejector == null)
        {
            throw new InvalidOperationException($"Rejector with ID {rejectedByUserId} not found");
        }

        shift.Status = ShiftStatus.Rejected;
        shift.RejectionReason = rejectionReason;

        await repository.UpdateAsync(shift, cancellationToken);
        
        logger.LogInformation(
            "Shift {ShiftId} rejected by user {RejectedByUserId}. Reason: {RejectionReason}",
            shiftId,
            rejectedByUserId,
            rejectionReason);

        return shift;
    }

    public async Task<Shift> UpdateShiftAsync(Guid storeId, Guid shiftId, Guid updatedByUserId, DateTime? checkInTime, DateTime? checkOutTime, CancellationToken cancellationToken = default)
    {
        var shift = await repository.GetSingleAsync(
            s => s.Id == shiftId && s.StoreId == storeId,
            includeProperties: [nameof(Shift.EmployeeUser), nameof(Shift.CheckInAttendance), nameof(Shift.CheckOutAttendance)],
            cancellationToken: cancellationToken);
            
        if (shift == null)
        {
            throw new InvalidOperationException($"Shift with ID {shiftId} not found");
        }
        

        // Validate that check-out is after check-in
        if (checkInTime.HasValue && checkOutTime.HasValue && checkOutTime.Value <= checkInTime.Value)
        {
            throw new InvalidOperationException("Check-out time must be after check-in time");
        }

        // Get employee to find PIN
        var employee = await employeeRepository.GetSingleAsync(
            e => e.DeviceId == shift.EmployeeUserId,
            cancellationToken: cancellationToken);

        if (employee == null)
        {
            throw new InvalidOperationException($"Employee not found for user {shift.EmployeeUserId}");
        }

        // Update or create check-in attendance
        if (checkInTime.HasValue)
        {
            if (shift.CheckInAttendance != null)
            {
                // Update existing check-in
                shift.CheckInAttendance.AttendanceTime = checkInTime.Value;
                await attendanceRepository.UpdateAsync(shift.CheckInAttendance, cancellationToken);
            }
            else
            {
                // Create new check-in attendance
                var checkInAttendance = new Attendance
                {
                    Id = Guid.NewGuid(),
                    EmployeeId = employee.Id,
                    PIN = employee.Pin,
                    AttendanceTime = checkInTime.Value,
                    DeviceId = employee.DeviceId,
                    VerifyMode = VerifyModes.Password, // Manual entry by manager
                    AttendanceState = AttendanceStates.CheckIn
                };
                await attendanceRepository.AddAsync(checkInAttendance, cancellationToken);
                shift.CheckInAttendanceId = checkInAttendance.Id;
            }
        }

        // Update or create check-out attendance
        if (checkOutTime.HasValue)
        {
            if (shift.CheckOutAttendance != null)
            {
                // Update existing check-out
                shift.CheckOutAttendance.AttendanceTime = checkOutTime.Value;
                await attendanceRepository.UpdateAsync(shift.CheckOutAttendance, cancellationToken);
            }
            else
            {
                // Create new check-out attendance
                var checkOutAttendance = new Attendance
                {
                    Id = Guid.NewGuid(),
                    EmployeeId = employee.Id,
                    PIN = employee.Pin,
                    AttendanceTime = checkOutTime.Value,
                    DeviceId = employee.DeviceId,
                    VerifyMode = VerifyModes.Password, // Manual entry by manager
                    AttendanceState = AttendanceStates.CheckOut
                };
                await attendanceRepository.AddAsync(checkOutAttendance, cancellationToken);
                shift.CheckOutAttendanceId = checkOutAttendance.Id;
            }
        }

        await repository.UpdateAsync(shift, cancellationToken);
        
        logger.LogInformation(
            "Shift {ShiftId} times updated by user {UpdatedByUserId}. CheckIn: {CheckInTime}, CheckOut: {CheckOutTime}",
            shiftId,
            updatedByUserId,
            checkInTime,
            checkOutTime);

        return shift;
    }

    public async Task<(Shift? CurrentShift, Shift? NextShift)> GetTodayShiftAndNextShiftAsync(Guid employeeUserId, CancellationToken cancellationToken = default)
    {
        var currentShift = await repository.GetSingleAsync(
            s => s.EmployeeUserId == employeeUserId &&
                 s.StartTime.Date == DateTime.Now.Date &&
                 s.Status == ShiftStatus.Approved,
            includeProperties: [nameof(Shift.CheckInAttendance), nameof(Shift.CheckOutAttendance)],
            cancellationToken: cancellationToken);

        var nextShift = await repository.GetFirstOrDefaultAsync(
            s => s.StartTime,
            filter: s => s.EmployeeUserId == employeeUserId &&
                 s.StartTime > DateTime.Now &&
                 s.Status == ShiftStatus.Approved,
            includeProperties: [nameof(Shift.CheckInAttendance), nameof(Shift.CheckOutAttendance)],
            cancellationToken: cancellationToken);

        return (currentShift, nextShift);
    }

    public async Task<Shift?> GetShiftByDateAsync(Guid employeeUserId, DateTime date, CancellationToken cancellationToken = default)
    {
        return await repository.GetSingleAsync(
            s => s.EmployeeUserId == employeeUserId &&
                 s.StartTime.Date == date.Date &&
                 s.Status == ShiftStatus.Approved,
            cancellationToken: cancellationToken);
    }
}
