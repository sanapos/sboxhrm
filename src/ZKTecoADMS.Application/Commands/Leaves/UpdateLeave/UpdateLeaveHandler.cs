using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Leaves;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Leaves.UpdateLeave;

public class UpdateLeaveHandler(
    IRepository<Leave> leaveRepository,
    IRepository<ShiftTemplate> shiftTemplateRepository,
    DbContext dbContext
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

            // Update leave properties
            leave.ShiftId = shiftTemplate.Id;
            leave.ShiftIds = request.ShiftIds != null && request.ShiftIds.Count > 0
                ? new List<Guid>(request.ShiftIds)
                : new List<Guid> { shiftTemplate.Id };
            leave.StartDate = request.StartDate;
            leave.EndDate = request.EndDate;
            leave.Type = request.Type;
            leave.IsHalfShift = request.IsHalfShift;
            leave.Reason = request.Reason;
            leave.ReplacementEmployeeId = request.ReplacementEmployeeId;
            leave.EmployeeId = request.EmployeeId;
            leave.UpdatedAt = DateTime.Now;

            // Managers can update status
            if (request.IsManager && request.Status.HasValue)
            {
                leave.Status = request.Status.Value;
            }

            await leaveRepository.UpdateAsync(leave, cancellationToken);

            // Force update ShiftIds via raw SQL (workaround for EF Core/Npgsql array issue)
            var shiftIds = leave.ShiftIds;
            if (shiftIds.Count > 0)
            {
                var shiftIdsArray = shiftIds.ToArray();
                await dbContext.Database.ExecuteSqlRawAsync(
                    @"UPDATE ""Leaves"" SET ""ShiftIds"" = {0} WHERE ""Id"" = {1}",
                    shiftIdsArray, leave.Id);
            }
            
            var leaveDto = leave.Adapt<LeaveDto>();
            
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
