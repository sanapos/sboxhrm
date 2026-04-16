using System.Text.Json;
using ZKTecoADMS.Application.DTOs.ShiftSalaryLevels;

namespace ZKTecoADMS.Application.Commands.ShiftSalaryLevels;

// Create ShiftSalaryLevel Command
public record CreateShiftSalaryLevelCommand(
    Guid StoreId,
    Guid ShiftTemplateId,
    string LevelName,
    int SortOrder,
    string? RateType,
    decimal FixedRate,
    decimal HourlyRate,
    decimal Multiplier,
    decimal ShiftAllowance,
    bool IsNightShift,
    List<string>? EmployeeIds,
    string? Description) : ICommand<AppResponse<ShiftSalaryLevelDto>>;

public class CreateShiftSalaryLevelHandler(
    IRepository<ShiftSalaryLevel> repository
) : ICommandHandler<CreateShiftSalaryLevelCommand, AppResponse<ShiftSalaryLevelDto>>
{
    public async Task<AppResponse<ShiftSalaryLevelDto>> Handle(CreateShiftSalaryLevelCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var entity = new ShiftSalaryLevel
            {
                ShiftTemplateId = request.ShiftTemplateId,
                LevelName = request.LevelName,
                SortOrder = request.SortOrder,
                RateType = request.RateType ?? "fixed",
                FixedRate = request.FixedRate,
                HourlyRate = request.HourlyRate,
                Multiplier = request.Multiplier,
                ShiftAllowance = request.ShiftAllowance,
                IsNightShift = request.IsNightShift,
                EmployeeIds = request.EmployeeIds != null && request.EmployeeIds.Count > 0
                    ? JsonSerializer.Serialize(request.EmployeeIds)
                    : null,
                Description = request.Description,
                IsActive = true,
                StoreId = request.StoreId
            };

            var created = await repository.AddAsync(entity, cancellationToken);

            return AppResponse<ShiftSalaryLevelDto>.Success(created.Adapt<ShiftSalaryLevelDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<ShiftSalaryLevelDto>.Error(ex.Message);
        }
    }
}

// Update ShiftSalaryLevel Command
public record UpdateShiftSalaryLevelCommand(
    Guid StoreId,
    Guid Id,
    string LevelName,
    int SortOrder,
    string? RateType,
    decimal FixedRate,
    decimal HourlyRate,
    decimal Multiplier,
    decimal ShiftAllowance,
    bool IsNightShift,
    List<string>? EmployeeIds,
    string? Description,
    bool IsActive) : ICommand<AppResponse<ShiftSalaryLevelDto>>;

public class UpdateShiftSalaryLevelHandler(
    IRepository<ShiftSalaryLevel> repository
) : ICommandHandler<UpdateShiftSalaryLevelCommand, AppResponse<ShiftSalaryLevelDto>>
{
    public async Task<AppResponse<ShiftSalaryLevelDto>> Handle(UpdateShiftSalaryLevelCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var entity = await repository.GetSingleAsync(
                e => e.Id == request.Id && e.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (entity == null)
            {
                return AppResponse<ShiftSalaryLevelDto>.Error("Shift salary level not found");
            }

            entity.LevelName = request.LevelName;
            entity.SortOrder = request.SortOrder;
            entity.RateType = request.RateType ?? "fixed";
            entity.FixedRate = request.FixedRate;
            entity.HourlyRate = request.HourlyRate;
            entity.Multiplier = request.Multiplier;
            entity.ShiftAllowance = request.ShiftAllowance;
            entity.IsNightShift = request.IsNightShift;
            entity.EmployeeIds = request.EmployeeIds != null && request.EmployeeIds.Count > 0
                ? JsonSerializer.Serialize(request.EmployeeIds)
                : null;
            entity.Description = request.Description;
            entity.IsActive = request.IsActive;

            var updated = await repository.UpdateAsync(entity, cancellationToken);
            if (!updated)
            {
                return AppResponse<ShiftSalaryLevelDto>.Error("Không thể lưu mức lương ca vào database");
            }

            var saved = await repository.GetSingleAsync(
                e => e.Id == request.Id && e.StoreId == request.StoreId,
                cancellationToken: cancellationToken);

            return AppResponse<ShiftSalaryLevelDto>.Success(saved!.Adapt<ShiftSalaryLevelDto>());
        }
        catch (Exception ex)
        {
            return AppResponse<ShiftSalaryLevelDto>.Error(ex.Message);
        }
    }
}

// Delete ShiftSalaryLevel Command
public record DeleteShiftSalaryLevelCommand(Guid StoreId, Guid Id) : ICommand<AppResponse<bool>>;

public class DeleteShiftSalaryLevelHandler(
    IRepository<ShiftSalaryLevel> repository
) : ICommandHandler<DeleteShiftSalaryLevelCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteShiftSalaryLevelCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var entity = await repository.GetSingleAsync(
                e => e.Id == request.Id && e.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (entity == null)
            {
                return AppResponse<bool>.Error("Shift salary level not found");
            }

            await repository.DeleteAsync(entity, cancellationToken);

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}
