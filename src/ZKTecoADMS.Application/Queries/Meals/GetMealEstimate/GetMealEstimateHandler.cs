using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Meals;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Meals.GetMealEstimate;

public class GetMealEstimateHandler(
    IRepository<MealSession> mealSessionRepository,
    IRepository<Shift> shiftRepository,
    IRepository<ShiftTemplate> shiftTemplateRepository,
    IRepository<MealRecord> mealRecordRepository,
    IRepository<MealRegistration> registrationRepository
) : IQueryHandler<GetMealEstimateQuery, AppResponse<MealSummaryDto>>
{
    public async Task<AppResponse<MealSummaryDto>> Handle(GetMealEstimateQuery request, CancellationToken cancellationToken)
    {
        var date = request.Date.Date;

        var sessions = await mealSessionRepository.GetAllWithIncludeAsync(
            filter: s => s.StoreId == request.StoreId && s.IsActive,
            includes: q => q.Include(s => s.MealSessionShifts),
            cancellationToken: cancellationToken);

        var dayShifts = await shiftRepository.GetAllAsync(
            s => s.StoreId == request.StoreId &&
                 s.StartTime.Date == date &&
                 s.Status == ShiftStatus.Approved &&
                 s.CheckInAttendanceId != null,
            cancellationToken: cancellationToken);

        var estimates = new List<MealEstimateDto>();

        foreach (var session in sessions)
        {
            var linkedShiftTemplateIds = session.MealSessionShifts.Select(ms => ms.ShiftTemplateId).ToList();
            List<ShiftTemplate> linkedTemplates = [];
            if (linkedShiftTemplateIds.Count > 0)
            {
                linkedTemplates = await shiftTemplateRepository.GetAllAsync(
                    t => linkedShiftTemplateIds.Contains(t.Id),
                    cancellationToken: cancellationToken);
            }

            var estimatedCount = dayShifts
                .Where(s => ShiftQualifiesForMealSession(s, session, linkedTemplates))
                .Select(s => s.EmployeeUserId)
                .Distinct()
                .Count();

            // Count actual meal records for this session today
            var actualCount = await mealRecordRepository.CountAsync(
                r => r.StoreId == request.StoreId &&
                     r.MealSessionId == session.Id &&
                     r.Date == date,
                cancellationToken);

            // Count registrations for this session today
            var registeredCount = await registrationRepository.CountAsync(
                r => r.StoreId == request.StoreId &&
                     r.MealSessionId == session.Id &&
                     r.Date == date &&
                     r.IsRegistered,
                cancellationToken);

            estimates.Add(new MealEstimateDto
            {
                MealSessionId = session.Id,
                MealSessionName = session.Name,
                StartTime = session.StartTime,
                EndTime = session.EndTime,
                PricePerMeal = session.PricePerMeal,
                EstimatedCount = estimatedCount,
                ActualCount = actualCount,
                RegisteredCount = registeredCount,
            });
        }

        var summary = new MealSummaryDto
        {
            Date = date,
            Sessions = estimates,
            TotalEstimated = estimates.Sum(e => e.EstimatedCount),
            TotalActual = estimates.Sum(e => e.ActualCount)
        };

        return AppResponse<MealSummaryDto>.Success(summary);
    }

    private static bool ShiftQualifiesForMealSession(
        Shift shift,
        MealSession session,
        List<ShiftTemplate> linkedTemplates)
    {
        var shiftStart = shift.StartTime.TimeOfDay;
        var shiftEnd = shift.EndTime.TimeOfDay;
        if (!MealTimeHelper.TimeRangesOverlap(shiftStart, shiftEnd, session.StartTime, session.EndTime))
            return false;

        if (linkedTemplates.Count == 0)
            return true;

        return linkedTemplates.Any(t =>
            MealTimeHelper.TimeRangesOverlap(shiftStart, shiftEnd, t.StartTime, t.EndTime));
    }
}
