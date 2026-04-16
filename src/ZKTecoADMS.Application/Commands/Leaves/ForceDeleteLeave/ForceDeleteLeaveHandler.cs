namespace ZKTecoADMS.Application.Commands.Leaves.ForceDeleteLeave;

public class ForceDeleteLeaveHandler(IRepository<Leave> leaveRepository)
    : ICommandHandler<ForceDeleteLeaveCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(ForceDeleteLeaveCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var leave = await leaveRepository.GetSingleAsync(
                filter: l => l.Id == request.LeaveId && l.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            if (leave == null)
            {
                return AppResponse<bool>.Error("Leave not found");
            }

            // Only owner or manager can force-delete
            if (!request.IsManager && leave.EmployeeUserId != request.ApplicationUserId)
            {
                return AppResponse<bool>.Error("You are not authorized to delete this leave request");
            }

            await leaveRepository.DeleteAsync(leave, cancellationToken);

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}
