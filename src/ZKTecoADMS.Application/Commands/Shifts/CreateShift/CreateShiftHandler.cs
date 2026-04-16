using ZKTecoADMS.Application.DTOs.Shifts;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Shifts.CreateShift;

public class CreateShiftHandler(IRepository<Shift> shiftRepository, ISystemNotificationService notificationService) 
    : ICommandHandler<CreateShiftCommand, AppResponse<ShiftDto>>
{
    public async Task<AppResponse<ShiftDto>> Handle(CreateShiftCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var workingDates = request.WorkingDays.Select(i => i.StartTime.Date);
            var existingShifts = await shiftRepository.GetAllAsync(
                s => s.StoreId == request.StoreId &&
                     s.EmployeeUserId == request.EmployeeUserId &&
                     workingDates.Contains(s.StartTime.Date) &&
                     s.Status == ShiftStatus.Approved,
                cancellationToken: cancellationToken);

            if (existingShifts.Any())
            {
                return AppResponse<ShiftDto>.Error("Only one approved shift is allowed per day for an employee. Existing conflicting dates: " +
                    string.Join(", ", existingShifts.Select(s => s.StartTime.Date.ToString("yyyy-MM-dd"))));
            }

            var shifts = request.WorkingDays.Select(day =>
            {
                return new Shift
                {
                    StoreId = request.StoreId,
                    EmployeeUserId = request.EmployeeUserId,
                    StartTime = day.StartTime,
                    EndTime = day.EndTime,
                    MaximumAllowedLateMinutes = request.MaximumAllowedLateMinutes,
                    MaximumAllowedEarlyLeaveMinutes = request.MaximumAllowedEarlyLeaveMinutes,
                    BreakTimeMinutes = request.BreakTimeMinutes,
                    Description = request.IsManager ? "Assigned by manager. " + request.Description : request.Description,
                    Status = request.IsManager ? ShiftStatus.Approved : ShiftStatus.Pending,
                    IsActive = true
                };
            }).ToList();


            var createdShift = await shiftRepository.AddRangeAsync(shifts, cancellationToken);
            var shiftDto = createdShift.Adapt<ShiftDto>();

            // Notify employee when manager assigns shift
            try
            {
                if (request.IsManager)
                {
                    var dateRange = shifts.Count == 1
                        ? shifts[0].StartTime.ToString("dd/MM/yyyy")
                        : $"{shifts.Min(s => s.StartTime):dd/MM/yyyy} - {shifts.Max(s => s.StartTime):dd/MM/yyyy}";
                    await notificationService.CreateAndSendAsync(
                        request.EmployeeUserId, NotificationType.Info,
                        "Ca làm việc mới",
                        $"Bạn được phân ca làm việc: {dateRange}",
                        relatedEntityId: shifts.First().Id, relatedEntityType: "Shift",
                        categoryCode: "attendance", storeId: request.StoreId);
                }
            }
            catch { /* Notification failure should not affect main operation */ }
            
            return AppResponse<ShiftDto>.Success(shiftDto);
        }

        catch (Exception ex)
        {
            return AppResponse<ShiftDto>.Error(ex.Message);
        }
    }
}
