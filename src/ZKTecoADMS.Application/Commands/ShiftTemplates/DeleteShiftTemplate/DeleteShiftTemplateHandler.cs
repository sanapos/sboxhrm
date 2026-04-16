using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.ShiftTemplates.DeleteShiftTemplate;

public class DeleteShiftTemplateHandler(IRepository<ShiftTemplate> repository) 
    : ICommandHandler<DeleteShiftTemplateCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteShiftTemplateCommand request, CancellationToken cancellationToken)
    {
        var template = await repository.GetSingleAsync(
            t => t.Id == request.Id,
            cancellationToken: cancellationToken);
        
        if (template == null)
        {
            return AppResponse<bool>.Error("Shift template not found");
        }

        await repository.DeleteAsync(template, cancellationToken);
        
        return AppResponse<bool>.Success(true);
    }
}
