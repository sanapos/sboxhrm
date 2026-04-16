using System.Text.Json;
using ZKTecoADMS.Application.DTOs.Allowances;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Allowances;

// Create Allowance Command
public record CreateAllowanceCommand(
    Guid StoreId,
    string Name,
    string? Code,
    string? Description,
    AllowanceType Type,
    decimal Amount,
    string? Currency,
    bool IsTaxable,
    bool IsInsuranceApplicable,
    DateTime? StartDate,
    DateTime? EndDate,
    List<string>? EmployeeIds) : ICommand<AppResponse<AllowanceDto>>;

public class CreateAllowanceHandler(
    IRepository<Allowance> allowanceRepository
) : ICommandHandler<CreateAllowanceCommand, AppResponse<AllowanceDto>>
{
    public async Task<AppResponse<AllowanceDto>> Handle(CreateAllowanceCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var allowance = new Allowance
            {
                StoreId = request.StoreId,
                Name = request.Name,
                Code = request.Code,
                Description = request.Description,
                Type = request.Type,
                Amount = request.Amount,
                Currency = request.Currency ?? "VND",
                IsTaxable = request.IsTaxable,
                IsInsuranceApplicable = request.IsInsuranceApplicable,
                IsActive = true,
                StartDate = request.StartDate,
                EndDate = request.EndDate,
                EmployeeIds = request.EmployeeIds != null && request.EmployeeIds.Count > 0 ? JsonSerializer.Serialize(request.EmployeeIds) : null
            };

            var created = await allowanceRepository.AddAsync(allowance, cancellationToken);
            var dto = created.Adapt<AllowanceDto>();
            dto.EmployeeIds = string.IsNullOrEmpty(created.EmployeeIds) ? null : JsonSerializer.Deserialize<List<string>>(created.EmployeeIds);
            return AppResponse<AllowanceDto>.Success(dto);
        }
        catch (Exception ex)
        {
            return AppResponse<AllowanceDto>.Error(ex.Message);
        }
    }
}

// Update Allowance Command
public record UpdateAllowanceCommand(
    Guid StoreId,
    Guid Id,
    string Name,
    string? Code,
    string? Description,
    AllowanceType Type,
    decimal Amount,
    string? Currency,
    bool IsTaxable,
    bool IsInsuranceApplicable,
    bool IsActive,
    DateTime? StartDate,
    DateTime? EndDate,
    List<string>? EmployeeIds) : ICommand<AppResponse<AllowanceDto>>;

public class UpdateAllowanceHandler(
    IRepository<Allowance> allowanceRepository
) : ICommandHandler<UpdateAllowanceCommand, AppResponse<AllowanceDto>>
{
    public async Task<AppResponse<AllowanceDto>> Handle(UpdateAllowanceCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var allowance = await allowanceRepository.GetSingleAsync(
                a => a.Id == request.Id && a.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (allowance == null)
            {
                return AppResponse<AllowanceDto>.Error("Allowance not found");
            }

            allowance.Name = request.Name;
            allowance.Code = request.Code;
            allowance.Description = request.Description;
            allowance.Type = request.Type;
            allowance.Amount = request.Amount;
            allowance.Currency = request.Currency;
            allowance.IsTaxable = request.IsTaxable;
            allowance.IsInsuranceApplicable = request.IsInsuranceApplicable;
            allowance.IsActive = request.IsActive;
            allowance.StartDate = request.StartDate;
            allowance.EndDate = request.EndDate;
            allowance.EmployeeIds = request.EmployeeIds != null && request.EmployeeIds.Count > 0 ? JsonSerializer.Serialize(request.EmployeeIds) : null;

            await allowanceRepository.UpdateAsync(allowance, cancellationToken);
            var dto = allowance.Adapt<AllowanceDto>();
            dto.EmployeeIds = string.IsNullOrEmpty(allowance.EmployeeIds) ? null : JsonSerializer.Deserialize<List<string>>(allowance.EmployeeIds);
            return AppResponse<AllowanceDto>.Success(dto);
        }
        catch (Exception ex)
        {
            return AppResponse<AllowanceDto>.Error(ex.Message);
        }
    }
}

// Delete Allowance Command
public record DeleteAllowanceCommand(Guid StoreId, Guid Id) : ICommand<AppResponse<bool>>;

public class DeleteAllowanceHandler(
    IRepository<Allowance> allowanceRepository
) : ICommandHandler<DeleteAllowanceCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(DeleteAllowanceCommand request, CancellationToken cancellationToken)
    {
        try
        {
            var allowance = await allowanceRepository.GetSingleAsync(
                a => a.Id == request.Id && a.StoreId == request.StoreId,
                cancellationToken: cancellationToken);
            if (allowance == null)
            {
                return AppResponse<bool>.Error("Allowance not found");
            }

            await allowanceRepository.DeleteAsync(allowance, cancellationToken);
            
            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}
