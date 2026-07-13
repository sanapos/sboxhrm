using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.Meals.DeleteMealMenu;

public class DeleteMealMenuHandler(
    IRepository<MealMenu> menuRepository,
    IRepository<MealMenuItem> itemRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<DeleteMealMenuCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteMealMenuCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var menu = await menuRepository.GetSingleAsync(
                m => m.Id == request.Id && m.StoreId == request.StoreId,
                includeProperties: ["Items", "MealSession"],
                cancellationToken: cancellationToken);

            if (menu == null)
                return AppResponse<bool>.Error("Menu not found");

            var sessionName = menu.MealSession?.Name ?? "";
            var menuDate = menu.Date;

            // Delete items first
            foreach (var item in menu.Items.ToList())
                await itemRepository.DeleteAsync(item, cancellationToken);

            await menuRepository.DeleteAsync(menu, cancellationToken);

            try
            {
                await notificationService.CreateAndSendToStoreEmployeesAsync(
                    request.StoreId,
                    NotificationType.Warning,
                    title: "Xoá thực đơn",
                    message: $"Thực đơn {sessionName} ngày {menuDate:dd/MM} đã bị xoá",
                    relatedEntityType: "MealMenu",
                    categoryCode: "meal");
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
