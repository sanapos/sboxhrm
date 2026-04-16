using Microsoft.AspNetCore.Identity;
using ZKTecoADMS.Application.DTOs.Shifts;

namespace ZKTecoADMS.Application.Queries.ShiftTemplates.GetShiftTemplates;

public class GetShiftTemplatesHandler(
    IRepository<ShiftTemplate> repository,
    UserManager<ApplicationUser> userManager
    ) : IQueryHandler<GetShiftTemplatesQuery, AppResponse<List<ShiftTemplateDto>>>
{
    public async Task<AppResponse<List<ShiftTemplateDto>>> Handle(GetShiftTemplatesQuery request, CancellationToken cancellationToken)
    {
        IEnumerable<ShiftTemplate> templates;
        
        // All users in the same store see all shift templates in the store
        templates = await repository.GetAllAsync(
            filter: t => t.StoreId == request.StoreId,
            orderBy: query => query.OrderByDescending(t => t.CreatedAt),
            includeProperties: new[] { nameof(ShiftTemplate.Manager) },
            cancellationToken: cancellationToken);
        
        var templateDtos = templates.Select(t => new ShiftTemplateDto
        {
            Id = t.Id,
            ManagerId = t.ManagerId,
            ManagerName = t.Manager?.UserName ?? string.Empty,
            Name = t.Name,
            Code = t.Code,
            StartTime = t.StartTime,
            EndTime = t.EndTime,
            MaximumAllowedLateMinutes = t.MaximumAllowedLateMinutes,
            MaximumAllowedEarlyLeaveMinutes = t.MaximumAllowedEarlyLeaveMinutes,
            BreakTimeMinutes = t.BreakTimeMinutes,
            EarlyCheckInMinutes = t.EarlyCheckInMinutes,
            LateGraceMinutes = t.LateGraceMinutes,
            EarlyLeaveGraceMinutes = t.EarlyLeaveGraceMinutes,
            OvertimeMinutesThreshold = t.OvertimeMinutesThreshold,
            ShiftType = t.ShiftType,
            Description = t.Description,
            IsActive = t.IsActive,
            CreatedAt = t.CreatedAt,
            UpdatedAt = t.UpdatedAt
        }).ToList();

        return AppResponse<List<ShiftTemplateDto>>.Success(templateDtos);
    }
}
