using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Leaves;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Leaves;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Leaves.UpdateLeave;

public class UpdateLeaveHandler(
    IRepository<Leave> leaveRepository,
    IRepository<ShiftTemplate> shiftTemplateRepository,
    DbContext dbContext,
    ISystemNotificationService notificationService,
    INotificationTargetResolver targetResolver,
    IAnnualLeaveBalanceService annualLeaveBalance
    ) : ICommandHandler<UpdateLeaveCommand, AppResponse<LeaveDto>>
{
    public async Task<AppResponse<LeaveDto>> Handle(UpdateLeaveCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var leave = await leaveRepository.GetSingleAsync(
                filter: l => l.Id == request.LeaveId && l.StoreId == request.StoreId,
                includeProperties: [nameof(Leave.EmployeeUser)],
                cancellationToken: cancellationToken);
            if (leave == null)
            {
                return AppResponse<LeaveDto>.Error("Đơn nghỉ phép không tồn tại");
            }

            // Permission check: Regular users can only edit their own pending leaves
            if (!request.IsManager)
            {
                if (leave.EmployeeUserId != request.CurrentUserId)
                {
                    return AppResponse<LeaveDto>.Error("Bạn chỉ có thể sửa đơn nghỉ phép của mình");
                }

                if (leave.Status != LeaveStatus.Pending)
                {
                    return AppResponse<LeaveDto>.Error("Chỉ có thể sửa đơn đang chờ duyệt");
                }
            }
            // Managers can edit any leave regardless of status

            var sickMode = request.SickLeaveMode ?? leave.SickLeaveMode;
            var legalError = LeaveLegalDefaults.Validate(request.Type, sickMode, request.BhxhDocumentNote);
            if (legalError != null)
                return AppResponse<LeaveDto>.Error(legalError);

            if (request.ShiftId == Guid.Empty)
            {
                return AppResponse<LeaveDto>.Error("Vui lòng chọn ca làm việc");
            }

            // Validate the new shift template
            var shiftTemplate = await shiftTemplateRepository.GetSingleAsync(
                filter: s => s.Id == request.ShiftId && s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (shiftTemplate == null)
            {
                return AppResponse<LeaveDto>.Error("Ca làm việc không hợp lệ hoặc không tồn tại");
            }

            if (!shiftTemplate.IsActive)
            {
                return AppResponse<LeaveDto>.Error("Ca làm việc đã bị vô hiệu hóa");
            }

            var shiftIds = request.ShiftIds != null && request.ShiftIds.Count > 0
                ? new List<Guid>(request.ShiftIds)
                : new List<Guid> { shiftTemplate.Id };

            var overlapping = await leaveRepository.GetAllAsync(
                filter: l => l.Id != leave.Id &&
                             l.EmployeeUserId == leave.EmployeeUserId &&
                             l.StoreId == request.StoreId &&
                             l.Status != LeaveStatus.Rejected &&
                             l.StartDate <= request.EndDate &&
                             l.EndDate >= request.StartDate,
                cancellationToken: cancellationToken);

            if (overlapping != null && overlapping.Any(l =>
                    LeaveShiftOverlap.ConflictsWith(l, request.StartDate, request.EndDate, shiftIds)))
            {
                return AppResponse<LeaveDto>.Error(
                    "Đã có đơn nghỉ phép trùng ngày và ca trong khoảng thời gian này.");
            }

            var wasApproved = leave.Status == LeaveStatus.Approved;
            var hadBalanceApplied = leave.AnnualBalanceApplied;

            // Update leave properties
            leave.ShiftId = shiftTemplate.Id;
            leave.ShiftIds = shiftIds;
            leave.StartDate = request.StartDate;
            leave.EndDate = request.EndDate;
            leave.Type = request.Type;
            leave.IsHalfShift = request.IsHalfShift;
            leave.Reason = request.Reason;
            leave.ReplacementEmployeeId = request.ReplacementEmployeeId;
            leave.EmployeeId = request.EmployeeId;
            leave.UpdatedAt = DateTime.UtcNow;

            // Managers can update status
            if (request.IsManager && request.Status.HasValue)
            {
                leave.Status = request.Status.Value;
            }

            if (request.IsManager && request.CountAsWork.HasValue)
            {
                leave.CountAsWork = request.CountAsWork.Value;
            }

            if (request.BhxhDocumentNote != null)
            {
                leave.BhxhDocumentNote = string.IsNullOrWhiteSpace(request.BhxhDocumentNote)
                    ? null
                    : request.BhxhDocumentNote.Trim();
            }

            LeaveLegalDefaults.Apply(leave, request.SickLeaveMode);

            if (wasApproved && hadBalanceApplied)
                await annualLeaveBalance.RestoreAsync(leave, cancellationToken);

            await leaveRepository.UpdateAsync(leave, cancellationToken);

            if (leave.Status == LeaveStatus.Approved)
            {
                var deduct = await annualLeaveBalance.TryApplyDeductionAsync(
                    leave, cancellationToken);
                if (!deduct.IsSuccess)
                    return AppResponse<LeaveDto>.Error(deduct.Message ?? "Không thể trừ phép năm.");
                await leaveRepository.UpdateAsync(leave, cancellationToken);
            }

            // Force update ShiftIds via raw SQL (workaround for EF Core/Npgsql array issue)
            if (shiftIds.Count > 0)
            {
                var shiftIdsArray = shiftIds.ToArray();
                await dbContext.Database.ExecuteSqlRawAsync(
                    @"UPDATE ""Leaves"" SET ""ShiftIds"" = {0} WHERE ""Id"" = {1}",
                    shiftIdsArray, leave.Id);
            }
            
            var leaveDto = leave.Adapt<LeaveDto>();

            // Notify per the org chart so managers/admins in the chain stay in the loop.
            // - Manager edited it: notify the employee + admin chain (so other approvers know)
            // - Employee edited it: notify dept managers (2 levels) + admins
            try
            {
                var dateRange = $"{leave.StartDate:dd/MM/yyyy} - {leave.EndDate:dd/MM/yyyy}";
                if (request.IsManager && leave.EmployeeUserId != request.CurrentUserId)
                {
                    var targets = await targetResolver.ResolveEmployeeAndManagersAsync(
                        leave.EmployeeUserId, request.StoreId, hierarchyLevels: 2, cancellationToken);
                    targets = targets.Where(id => id != request.CurrentUserId).ToList();
                    if (targets.Count > 0)
                    {
                        await notificationService.CreateAndSendToUsersAsync(
                            targets, NotificationType.Info,
                            "Đơn nghỉ phép đã được cập nhật",
                            $"Quản lý đã cập nhật đơn nghỉ phép ({dateRange}).",
                            relatedEntityId: leave.Id, relatedEntityType: "Leave",
                            fromUserId: request.CurrentUserId, categoryCode: "leave", storeId: request.StoreId);
                    }
                }
                else if (!request.IsManager)
                {
                    var targets = await targetResolver.ResolveManagersAsync(
                        leave.EmployeeUserId, request.StoreId, hierarchyLevels: 2, cancellationToken);
                    if (targets.Count > 0)
                    {
                        await notificationService.CreateAndSendToUsersAsync(
                            targets, NotificationType.Info,
                            "Đơn nghỉ phép đã được sửa",
                            $"Nhân viên đã chỉnh sửa đơn nghỉ phép ({dateRange}). Vui lòng kiểm tra lại.",
                            relatedEntityId: leave.Id, relatedEntityType: "Leave",
                            fromUserId: request.CurrentUserId, categoryCode: "leave", storeId: request.StoreId);
                    }
                }
            }
            catch { /* notification is best-effort */ }

            return AppResponse<LeaveDto>.Success(leaveDto);
        }
        catch (ArgumentException ex)
        {
            return AppResponse<LeaveDto>.Error(ex.Message);
        }
        catch (InvalidOperationException ex)
        {
            return AppResponse<LeaveDto>.Error(ex.Message);
        }
    }
}
