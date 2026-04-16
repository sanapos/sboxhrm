using ZKTecoADMS.Application.DTOs.Meals;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;
using Mapster;

namespace ZKTecoADMS.Application.Commands.Meals.CreateMealSession;

public class CreateMealSessionHandler(
    IRepository<MealSession> mealSessionRepository,
    IRepository<MealSessionShift> mealSessionShiftRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<CreateMealSessionCommand, AppResponse<MealSessionDto>>
{
    public async Task<AppResponse<MealSessionDto>> Handle(CreateMealSessionCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var mealSession = new MealSession
            {
                Name = request.Name,
                StartTime = request.StartTime,
                EndTime = request.EndTime,
                Description = request.Description,
                StoreId = request.StoreId,
                IsActive = true
            };

            await mealSessionRepository.AddAsync(mealSession, cancellationToken);

            if (request.ShiftTemplateIds.Count > 0)
            {
                var shifts = request.ShiftTemplateIds.Select(stId => new MealSessionShift
                {
                    MealSessionId = mealSession.Id,
                    ShiftTemplateId = stId
                }).ToList();

                await mealSessionShiftRepository.AddRangeAsync(shifts, cancellationToken);
            }

            var result = mealSession.Adapt<MealSessionDto>();

            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: null,
                    type: NotificationType.Info,
                    title: "Buổi ăn mới",
                    message: $"Đã thêm buổi ăn \"{mealSession.Name}\" ({mealSession.StartTime:hh\\:mm} - {mealSession.EndTime:hh\\:mm})",
                    relatedEntityId: mealSession.Id,
                    relatedEntityType: "MealSession",
                    categoryCode: "meal",
                    storeId: request.StoreId);
            }
            catch { /* notification failure should not block main flow */ }

            return AppResponse<MealSessionDto>.Success(result);
        }
        catch (Exception ex)
        {
            return AppResponse<MealSessionDto>.Error(ex.Message);
        }
    }
}
