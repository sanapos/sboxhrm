using System.Text.Json;
using ZKTecoADMS.Application.DTOs.Allowances;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Allowances;

// Helper to parse the JSON-serialised employee user-id list and notify each.
internal static class AllowanceNotificationHelper
{
    public static IEnumerable<Guid> ParseEmployeeUserIds(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) yield break;
        List<string>? list = null;
        try { list = JsonSerializer.Deserialize<List<string>>(json); } catch { yield break; }
        if (list == null) yield break;
        foreach (var s in list)
        {
            if (Guid.TryParse(s, out var g) && g != Guid.Empty) yield return g;
        }
    }
}

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
    IRepository<Allowance> allowanceRepository,
    ISystemNotificationService notificationService
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

            // Notify each targeted employee that a new allowance applies to them.
            try
            {
                var userIds = AllowanceNotificationHelper.ParseEmployeeUserIds(created.EmployeeIds).ToList();
                if (userIds.Count > 0)
                {
                    await notificationService.CreateAndSendToUsersAsync(
                        userIds, NotificationType.Info,
                        $"Phụ cấp mới: {created.Name}",
                        $"Bạn được hưởng phụ cấp {created.Name} với số tiền {created.Amount:N0} {created.Currency}.",
                        relatedEntityId: created.Id, relatedEntityType: "Allowance",
                        categoryCode: "allowance", storeId: request.StoreId);
                }
            }
            catch { /* best-effort */ }

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
    IRepository<Allowance> allowanceRepository,
    ISystemNotificationService notificationService
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

            var previousUserIds = AllowanceNotificationHelper.ParseEmployeeUserIds(allowance.EmployeeIds).ToHashSet();

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

            // Notify the union of previous + current targets that the allowance changed.
            try
            {
                var currentUserIds = AllowanceNotificationHelper.ParseEmployeeUserIds(allowance.EmployeeIds);
                var union = previousUserIds.Concat(currentUserIds).Distinct().ToList();
                if (union.Count > 0)
                {
                    await notificationService.CreateAndSendToUsersAsync(
                        union, NotificationType.Info,
                        $"Phụ cấp được cập nhật: {allowance.Name}",
                        $"Thông tin phụ cấp {allowance.Name} ({allowance.Amount:N0} {allowance.Currency}) đã được cập nhật.",
                        relatedEntityId: allowance.Id, relatedEntityType: "Allowance",
                        categoryCode: "allowance", storeId: request.StoreId);
                }
            }
            catch { /* best-effort */ }

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
    IRepository<Allowance> allowanceRepository,
    ISystemNotificationService notificationService
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

            var affectedUserIds = AllowanceNotificationHelper.ParseEmployeeUserIds(allowance.EmployeeIds).ToList();
            var allowanceName = allowance.Name;
            await allowanceRepository.DeleteAsync(allowance, cancellationToken);

            // Notify employees who were receiving this allowance that it was removed.
            try
            {
                if (affectedUserIds.Count > 0)
                {
                    await notificationService.CreateAndSendToUsersAsync(
                        affectedUserIds, NotificationType.Warning,
                        $"Phụ cấp đã bị xóa: {allowanceName}",
                        $"Phụ cấp {allowanceName} không còn được áp dụng cho bạn.",
                        relatedEntityId: request.Id, relatedEntityType: "Allowance",
                        categoryCode: "allowance", storeId: request.StoreId);
                }
            }
            catch { /* best-effort */ }

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error(ex.Message);
        }
    }
}
