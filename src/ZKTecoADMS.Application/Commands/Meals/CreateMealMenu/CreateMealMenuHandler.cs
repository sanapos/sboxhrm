using ZKTecoADMS.Application.DTOs.Meals;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;
using Mapster;

namespace ZKTecoADMS.Application.Commands.Meals.CreateMealMenu;

public class CreateMealMenuHandler(
    IRepository<MealMenu> menuRepository,
    IRepository<MealSession> sessionRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<CreateMealMenuCommand, AppResponse<MealMenuDto>>
{
    public async Task<AppResponse<MealMenuDto>> Handle(CreateMealMenuCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var menu = new MealMenu
            {
                Date = request.Date.Date,
                DayOfWeek = request.Date.DayOfWeek,
                MealSessionId = request.MealSessionId,
                Note = request.Note,
                StoreId = request.StoreId,
                IsActive = true,
                Items = request.Items.Select((item, index) => new MealMenuItem
                {
                    DishName = item.DishName,
                    Description = item.Description,
                    Category = item.Category,
                    SortOrder = item.SortOrder > 0 ? item.SortOrder : index
                }).ToList()
            };

            await menuRepository.AddAsync(menu, cancellationToken);

            var result = menu.Adapt<MealMenuDto>();

            // Notify all employees about new menu
            var session = await sessionRepository.GetSingleAsync(
                s => s.Id == request.MealSessionId, cancellationToken: cancellationToken);
            var sessionName = session?.Name ?? "";
            var dishNames = string.Join(", ", request.Items.Select(i => i.DishName).Take(3));
            if (request.Items.Count > 3) dishNames += "...";

            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: null,
                    type: NotificationType.Info,
                    title: $"🍽️ Thực đơn {sessionName} - {request.Date:dd/MM}",
                    message: $"Thực đơn mới: {dishNames}",
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
