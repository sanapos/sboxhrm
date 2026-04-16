using ZKTecoADMS.Application.DTOs.Meals;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;
using Mapster;

namespace ZKTecoADMS.Application.Commands.Meals.UpdateMealSession;

public class UpdateMealSessionHandler(
    IRepository<MealSession> mealSessionRepository,
    IRepository<MealSessionShift> mealSessionShiftRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<UpdateMealSessionCommand, AppResponse<MealSessionDto>>
{
    public async Task<AppResponse<MealSessionDto>> Handle(UpdateMealSessionCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var session = await mealSessionRepository.GetSingleAsync(
                s => s.Id == request.Id && s.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            if (session == null)
                return AppResponse<MealSessionDto>.Error("Meal session not found");

            session.Name = request.Name;
            session.StartTime = request.StartTime;
            session.EndTime = request.EndTime;
            session.Description = request.Description;

            await mealSessionRepository.UpdateAsync(session, cancellationToken);

            // Update shift mappings
            var existingShifts = await mealSessionShiftRepository.GetAllAsync(
                s => s.MealSessionId == request.Id, cancellationToken: cancellationToken);

            foreach (var es in existingShifts)
                await mealSessionShiftRepository.DeleteAsync(es, cancellationToken);

            if (request.ShiftTemplateIds.Count > 0)
            {
                var newShifts = request.ShiftTemplateIds.Select(stId => new MealSessionShift
                {
                    MealSessionId = session.Id,
                    ShiftTemplateId = stId
                }).ToList();

                await mealSessionShiftRepository.AddRangeAsync(newShifts, cancellationToken);
            }

            var result = session.Adapt<MealSessionDto>();

            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: null,
                    type: NotificationType.Info,
                    title: "Cập nhật buổi ăn",
                    message: $"Buổi ăn \"{session.Name}\" đã được cập nhật ({session.StartTime:hh\\:mm} - {session.EndTime:hh\\:mm})",
                    relatedEntityId: session.Id,
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
