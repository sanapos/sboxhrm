using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.Meals.DeleteMealSession;

public class DeleteMealSessionHandler(
    IRepository<MealSession> repository,
    ISystemNotificationService notificationService
) : ICommandHandler<DeleteMealSessionCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteMealSessionCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var session = await repository.GetSingleAsync(
                s => s.Id == request.Id && s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            if (session == null)
                return AppResponse<bool>.Error("Meal session not found");

            var sessionName = session.Name;
            await repository.DeleteAsync(session, cancellationToken);

            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: null,
                    type: NotificationType.Warning,
                    title: "Xoá buổi ăn",
                    message: $"Buổi ăn \"{sessionName}\" đã bị xoá",
                    relatedEntityType: "MealSession",
                    categoryCode: "meal",
                    storeId: request.StoreId);
            }
            catch { /* notification failure should not block main flow */ }

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}
