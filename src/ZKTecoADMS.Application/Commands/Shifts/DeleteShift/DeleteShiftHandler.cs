using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Shifts.DeleteShift;

public class DeleteShiftHandler(IRepository<Shift> repository) 
    : ICommandHandler<DeleteShiftCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteShiftCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var shift = await repository.GetSingleAsync(
                s => s.Id == request.Id && s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            
            if (shift == null)
            {
                return AppResponse<bool>.Error("Shift not found");
            }

            // Only allow deletion of pending shifts
            if (shift.Status != ShiftStatus.Pending)
            {
                return AppResponse<bool>.Error($"Cannot delete shift with status {shift.Status}");
            }

            await repository.DeleteAsync(shift, cancellationToken);
            
            return AppResponse<bool>.Success(true);
        }
        catch (InvalidOperationException ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}
