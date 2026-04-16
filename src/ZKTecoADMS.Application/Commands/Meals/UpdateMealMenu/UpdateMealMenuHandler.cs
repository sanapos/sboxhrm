using ZKTecoADMS.Application.DTOs.Meals;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;
using Mapster;

namespace ZKTecoADMS.Application.Commands.Meals.UpdateMealMenu;

public class UpdateMealMenuHandler(
    IRepository<MealMenu> menuRepository,
    IRepository<MealMenuItem> itemRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<UpdateMealMenuCommand, AppResponse<MealMenuDto>>
{
    public async Task<AppResponse<MealMenuDto>> Handle(UpdateMealMenuCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var menu = await menuRepository.GetSingleAsync(
                m => m.Id == request.Id && m.StoreId == request.StoreId,
                includeProperties: ["Items"],
                cancellationToken: cancellationToken);

            if (menu == null)
                return AppResponse<MealMenuDto>.Error("Menu not found");

            menu.Note = request.Note;

            // Remove old items
            foreach (var item in menu.Items.ToList())
                await itemRepository.DeleteAsync(item, cancellationToken);

            // Add new items
            menu.Items = request.Items.Select((item, index) => new MealMenuItem
            {
                MealMenuId = menu.Id,
                DishName = item.DishName,
                Description = item.Description,
                Category = item.Category,
                SortOrder = item.SortOrder > 0 ? item.SortOrder : index
            }).ToList();

            await menuRepository.UpdateAsync(menu, cancellationToken);

            var result = menu.Adapt<MealMenuDto>();

            var dishNames = string.Join(", ", request.Items.Select(i => i.DishName).Take(3));
            if (request.Items.Count > 3) dishNames += "...";

            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: null,
                    type: NotificationType.Info,
                    title: "Cập nhật thực đơn",
                    message: $"Thực đơn ngày {menu.Date:dd/MM} đã cập nhật: {dishNames}",
                    relatedEntityId: menu.Id,
                    relatedEntityType: "MealMenu",
                    categoryCode: "meal",
                    storeId: request.StoreId);
            }
            catch { /* notification failure should not block main flow */ }

            return AppResponse<MealMenuDto>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<MealMenuDto>.Error(ex.Message);
        }
    }
}
