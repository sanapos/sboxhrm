using ZKTecoADMS.Application.DTOs.Shifts;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.ShiftTemplates.UpdateShiftTemplate;

public class UpdateShiftTemplateHandler(IRepository<ShiftTemplate> repository) 
    : ICommandHandler<UpdateShiftTemplateCommand, AppResponse<ShiftTemplateDto>>
{
    public async Task<AppResponse<ShiftTemplateDto>> Handle(UpdateShiftTemplateCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var template = await repository.GetSingleAsync(
                t => t.Id == request.Id,
                includeProperties: new[] { nameof(ShiftTemplate.Manager) },
                cancellationToken: cancellationToken);
            
            if (template == null)
            {
                return AppResponse<ShiftTemplateDto>.Error("Shift template not found");
            }

            template.Name = request.Name;
            template.Code = request.Code;
            template.StartTime = request.StartTime;
            template.EndTime = request.EndTime;
            template.MaximumAllowedLateMinutes = request.MaximumAllowedLateMinutes;
            template.MaximumAllowedEarlyLeaveMinutes = request.MaximumAllowedEarlyLeaveMinutes;
            template.BreakTimeMinutes = request.BreakTimeMinutes;
            template.LunchBreakStartTime = request.LunchBreakStartTime;
            template.LunchBreakEndTime = request.LunchBreakEndTime;
            template.EarlyCheckInMinutes = request.EarlyCheckInMinutes;
            template.LateGraceMinutes = request.LateGraceMinutes;
            template.EarlyLeaveGraceMinutes = request.EarlyLeaveGraceMinutes;
            template.OvertimeMinutesThreshold = request.OvertimeMinutesThreshold;
            template.EarlyOvertimeMinutesThreshold = request.EarlyOvertimeMinutesThreshold;
            template.ShiftType = request.ShiftType;
            template.Description = request.Description;
            template.IsActive = request.IsActive;

            await repository.UpdateAsync(template, cancellationToken);
            
            var templateDto = new ShiftTemplateDto
            {
                Id = template.Id,
                ManagerId = template.ManagerId,
                ManagerName = template.Manager?.UserName ?? string.Empty,
                Name = template.Name,
                Code = template.Code,
                StartTime = template.StartTime,
                EndTime = template.EndTime,
                MaximumAllowedLateMinutes = template.MaximumAllowedLateMinutes,
                MaximumAllowedEarlyLeaveMinutes = template.MaximumAllowedEarlyLeaveMinutes,
                BreakTimeMinutes = template.BreakTimeMinutes,
                LunchBreakStartTime = template.LunchBreakStartTime,
                LunchBreakEndTime = template.LunchBreakEndTime,
                EarlyCheckInMinutes = template.EarlyCheckInMinutes,
                LateGraceMinutes = template.LateGraceMinutes,
                EarlyLeaveGraceMinutes = template.EarlyLeaveGraceMinutes,
                OvertimeMinutesThreshold = template.OvertimeMinutesThreshold,
                EarlyOvertimeMinutesThreshold = template.EarlyOvertimeMinutesThreshold,
                ShiftType = template.ShiftType,
                Description = template.Description,
                IsActive = template.IsActive,
                CreatedAt = template.CreatedAt,
                UpdatedAt = template.UpdatedAt
            };

            return AppResponse<ShiftTemplateDto>.Success(templateDto);
        }
        catch (ArgumentException ex)
        {
            return AppResponse<ShiftTemplateDto>.Error(ex.Message);
        }
    }
}
