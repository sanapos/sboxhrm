using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Meals;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Meals.GetMealEstimate;

public class GetMealEstimateHandler(
    IRepository<MealSession> mealSessionRepository,
    IRepository<Shift> shiftRepository,
    IRepository<MealRecord> mealRecordRepository
) : IQueryHandler<GetMealEstimateQuery, AppResponse<MealSummaryDto>>
{
    public async Task<AppResponse<MealSummaryDto>> Handle(GetMealEstimateQuery request, CancellationToken cancellationToken)
    {
        var date = request.Date.Date;

        // Get all active meal sessions for this store
        var sessions = await mealSessionRepository.GetAllWithIncludeAsync(
            filter: s => s.StoreId == request.StoreId && s.IsActive,
            includes: q => q.Include(s => s.MealSessionShifts),
            cancellationToken: cancellationToken);

        var estimates = new List<MealEstimateDto>();

        foreach (var session in sessions)
        {
            // Count employees that checked in for shifts linked to this meal session
            var linkedShiftTemplateIds = session.MealSessionShifts.Select(ms => ms.ShiftTemplateId).ToList();
            
            int estimatedCount = 0;
            if (linkedShiftTemplateIds.Count > 0)
            {
                // Count shifts on this date that are approved and linked to meal session
                estimatedCount = await shiftRepository.CountAsync(
                    s => s.StoreId == request.StoreId &&
                         s.StartTime.Date == date &&
                         s.Status == ShiftStatus.Approved &&
                         s.CheckInAttendanceId != null,
                    cancellationToken);
            }
            else
            {
                // If no shift templates linked, count all checked-in shifts for the day 
                estimatedCount = await shiftRepository.CountAsync(
                    s => s.StoreId == request.StoreId &&
                         s.StartTime.Date == date &&
                         s.Status == ShiftStatus.Approved &&
                         s.CheckInAttendanceId != null,
                    cancellationToken);
            }

            // Count actual meal records for this session today
            var actualCount = await mealRecordRepository.CountAsync(
                r => r.StoreId == request.StoreId &&
                     r.MealSessionId == session.Id &&
                     r.Date == date,
                cancellationToken);

            estimates.Add(new MealEstimateDto
            {
                MealSessionId = session.Id,
                MealSessionName = session.Name,
                StartTime = session.StartTime,
                EndTime = session.EndTime,
                EstimatedCount = estimatedCount,
                ActualCount = actualCount
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
}
