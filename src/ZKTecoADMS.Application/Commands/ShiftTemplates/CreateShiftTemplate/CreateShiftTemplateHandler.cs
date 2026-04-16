using ZKTecoADMS.Application.DTOs.Shifts;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.ShiftTemplates.CreateShiftTemplate;

public class CreateShiftTemplateHandler(IRepository<ShiftTemplate> repository) 
    : ICommandHandler<CreateShiftTemplateCommand, AppResponse<ShiftTemplateDto>>
{
    public async Task<AppResponse<ShiftTemplateDto>> Handle(CreateShiftTemplateCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var shiftTemplate = new ShiftTemplate
            {
                ManagerId = request.ManagerId,
                StoreId = request.StoreId,
                Name = request.Name,
                Code = request.Code,
                StartTime = request.StartTime,
                EndTime = request.EndTime,
                MaximumAllowedLateMinutes = request.MaximumAllowedLateMinutes,
                MaximumAllowedEarlyLeaveMinutes = request.MaximumAllowedEarlyLeaveMinutes,
                BreakTimeMinutes = request.BreakTimeMinutes,
                EarlyCheckInMinutes = request.EarlyCheckInMinutes,
                LateGraceMinutes = request.LateGraceMinutes,
                EarlyLeaveGraceMinutes = request.EarlyLeaveGraceMinutes,
                OvertimeMinutesThreshold = request.OvertimeMinutesThreshold,
                ShiftType = request.ShiftType,
                Description = request.Description,
                IsActive = request.IsActive
            };

            var createdTemplate = await repository.AddAsync(shiftTemplate, cancellationToken);
            
            // Load the manager relationship
            var templateWithManager = await repository.GetSingleAsync(
                t => t.Id == createdTemplate.Id,
                includeProperties: new[] { nameof(ShiftTemplate.Manager) },
                cancellationToken: cancellationToken);
            
            var templateDto = new ShiftTemplateDto
            {
                Id = templateWithManager!.Id,
                ManagerId = templateWithManager.ManagerId,
                ManagerName = templateWithManager.Manager?.UserName ?? string.Empty,
                Name = templateWithManager.Name,
                Code = templateWithManager.Code,
                StartTime = templateWithManager.StartTime,
                EndTime = templateWithManager.EndTime,
                MaximumAllowedLateMinutes = templateWithManager.MaximumAllowedLateMinutes,
                MaximumAllowedEarlyLeaveMinutes = templateWithManager.MaximumAllowedEarlyLeaveMinutes,
                BreakTimeMinutes = templateWithManager.BreakTimeMinutes,
                EarlyCheckInMinutes = templateWithManager.EarlyCheckInMinutes,
                LateGraceMinutes = templateWithManager.LateGraceMinutes,
                EarlyLeaveGraceMinutes = templateWithManager.EarlyLeaveGraceMinutes,
                OvertimeMinutesThreshold = templateWithManager.OvertimeMinutesThreshold,
                ShiftType = templateWithManager.ShiftType,
                Description = templateWithManager.Description,
                IsActive = templateWithManager.IsActive,
                CreatedAt = templateWithManager.CreatedAt,
                UpdatedAt = templateWithManager.UpdatedAt
            };

            return AppResponse<ShiftTemplateDto>.Success(templateDto);
        }
        catch (ArgumentException ex)
        {
            return AppResponse<ShiftTemplateDto>.Error(ex.Message);
        }
    }
}
