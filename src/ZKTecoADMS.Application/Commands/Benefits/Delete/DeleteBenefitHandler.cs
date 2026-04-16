using ZKTecoADMS.Application.Commands.Benefits.Delete;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Benefits.Delete;

public class DeleteBenefitHandler(
    IRepository<Benefit> repository,
    ISystemNotificationService notificationService) 
    : ICommandHandler<DeleteBenefitCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteBenefitCommand request, CancellationToken cancellationToken)
    {
        // Filter by StoreId for multi-tenant data isolation
        var salaryProfile = await repository.GetSingleAsync(
            b => b.Id == request.Id && b.StoreId == request.StoreId,
            includeProperties: [nameof(Benefit.EmployeeBenefits)],
            cancellationToken: cancellationToken);
        if (salaryProfile == null)
        {
            return AppResponse<bool>.Error("Benefit profile not found");
        }

        if (salaryProfile.EmployeeBenefits.Count > 0)
        {
            return  AppResponse<bool>.Error("Cannot delete benefit profile assigned to employees");
        }

        var profileName = salaryProfile.Name;
        var deleted = await repository.DeleteByIdAsync(request.Id, cancellationToken);

        if (deleted)
        {
            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: null,
                    type: NotificationType.Warning,
                    title: "Xóa bảng lương",
                    message: $"Bảng lương \"{profileName}\" đã bị xóa",
                    relatedEntityType: "Benefit",
                    categoryCode: "salary",
                    storeId: request.StoreId);
            }
            catch { }
        }

        return deleted 
            ? AppResponse<bool>.Success(true) 
            : AppResponse<bool>.Error("Failed to delete salary profile");
    }
}
