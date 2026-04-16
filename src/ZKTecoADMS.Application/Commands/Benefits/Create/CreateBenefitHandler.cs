using ZKTecoADMS.Application.DTOs.Benefits;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Benefits.Create;

public class CreateSalaryProfileHandler(
    IRepository<Benefit> repository,
    ISystemNotificationService notificationService
    ) : ICommandHandler<CreateBenefitCommand, AppResponse<BenefitDto>>
{
    public async Task<AppResponse<BenefitDto>> Handle(CreateBenefitCommand request, CancellationToken cancellationToken)
    {
        // Check if name is unique within the store
        var isUnique = await repository.ExistsAsync(b => b.StoreId == request.StoreId && b.Name == request.Name, cancellationToken);
        if (isUnique)
        {
            return AppResponse<BenefitDto>.Error($"A salary profile with the name '{request.Name}' already exists");
        }

        var salaryProfile = request.Adapt<Benefit>();
        salaryProfile.StoreId = request.StoreId;
        salaryProfile.IsActive = true;

        await repository.AddAsync(salaryProfile, cancellationToken);

        var dto = salaryProfile.Adapt<BenefitDto>();

        try
        {
            await notificationService.CreateAndSendAsync(
                targetUserId: null,
                type: NotificationType.Info,
                title: "Bảng lương mới",
                message: $"Đã tạo bảng lương \"{request.Name}\"",
                relatedEntityId: salaryProfile.Id,
                relatedEntityType: "Benefit",
                categoryCode: "salary",
                storeId: request.StoreId);
        }
        catch { }

        return AppResponse<BenefitDto>.Success(dto);
    }
}
