using System.Text.Json;
using ZKTecoADMS.Application.DTOs.Allowances;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Allowances;

// Helper to parse the JSON-serialised employee user-id list and notify each.
internal static class AllowanceNotificationHelper
{
    /// <summary>
    /// Tài khoản (ApplicationUser) của nhân viên hưởng phụ cấp. <c>Allowance.EmployeeIds</c> lưu mã Employee.Id
    /// (màn Phụ cấp chọn từ danh sách nhân viên; bộ máy tính lương còn khớp theo mã NV) — trước đây đọc thẳng như
    /// mã tài khoản nên không ai nhận được thông báo. Trống = áp dụng mọi nhân viên → mọi NV đang làm có tài khoản.
    /// </summary>
    public static async Task<HashSet<Guid>> ResolveUserIdsAsync(
        IRepository<Employee> employeeRepository, Guid storeId, string? employeeIdsJson, CancellationToken ct)
    {
        List<string>? list = null;
        if (!string.IsNullOrWhiteSpace(employeeIdsJson))
        {
            try { list = JsonSerializer.Deserialize<List<string>>(employeeIdsJson); } catch { list = null; }
            if (list == null || list.Count == 0) return [];
        }

        var employees = await employeeRepository.GetAllAsync(
            filter: e => e.StoreId == storeId && e.Deleted == null
                && e.WorkStatus != EmployeeWorkStatus.Resigned && e.ApplicationUserId != null,
            cancellationToken: ct);
        if (list == null)
            return employees.Select(e => e.ApplicationUserId!.Value).ToHashSet();

        var keys = list.Select(x => x.Trim().ToLowerInvariant()).ToHashSet();
        return employees
            .Where(e => keys.Contains(e.Id.ToString().ToLowerInvariant())
                || keys.Contains(e.ApplicationUserId!.Value.ToString().ToLowerInvariant())
                || (!string.IsNullOrEmpty(e.EmployeeCode) && keys.Contains(e.EmployeeCode.Trim().ToLowerInvariant())))
            .Select(e => e.ApplicationUserId!.Value)
            .ToHashSet();
    }

    /// <summary>«500.000đ» (VND) — trước đây in mã «500.000 VND». Tiền tệ khác giữ mã.</summary>
    public static string Money(decimal amount, string? currency) =>
        string.IsNullOrWhiteSpace(currency) || string.Equals(currency.Trim(), "VND", StringComparison.OrdinalIgnoreCase)
            ? $"{amount:N0}đ"
            : $"{amount:N0} {currency.Trim()}";

    /// <summary>Đơn vị tính theo loại phụ cấp: «/tháng», «/ngày công»…</summary>
    public static string Unit(AllowanceType type) => type switch
    {
        AllowanceType.Fixed => "/tháng",
        AllowanceType.Daily => "/ngày công",
        AllowanceType.Hourly => "/giờ",
        AllowanceType.PerEvent => "/lần",
        AllowanceType.PerShift => "/ca",
        _ => string.Empty,
    };

    /// <summary>«500.000đ/tháng».</summary>
    public static string Describe(decimal amount, string? currency, AllowanceType type) =>
        $"{Money(amount, currency)}{Unit(type)}";
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
    List<string>? EmployeeIds,
    List<string>? ShiftIds,
    decimal? MinWorkPercent = null,
    decimal? MinWorkHours = null) : ICommand<AppResponse<AllowanceDto>>;

public class CreateAllowanceHandler(
    IRepository<Allowance> allowanceRepository,
    IRepository<Employee> employeeRepository,
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
                EmployeeIds = request.EmployeeIds != null && request.EmployeeIds.Count > 0 ? JsonSerializer.Serialize(request.EmployeeIds) : null,
                ShiftIds = request.ShiftIds != null && request.ShiftIds.Count > 0 ? JsonSerializer.Serialize(request.ShiftIds) : null,
                MinWorkPercent = AllowanceWorkRule.Percent(request.Type, request.MinWorkPercent),
                MinWorkHours = AllowanceWorkRule.Hours(request.Type, request.MinWorkPercent, request.MinWorkHours),
            };

            var created = await allowanceRepository.AddAsync(allowance, cancellationToken);
            var dto = created.Adapt<AllowanceDto>();
            dto.EmployeeIds = string.IsNullOrEmpty(created.EmployeeIds) ? null : JsonSerializer.Deserialize<List<string>>(created.EmployeeIds);
            dto.ShiftIds = string.IsNullOrEmpty(created.ShiftIds) ? null : JsonSerializer.Deserialize<List<string>>(created.ShiftIds);

            // Notify each targeted employee that a new allowance applies to them.
            try
            {
                var userIds = created.IsActive
                    ? (await AllowanceNotificationHelper.ResolveUserIdsAsync(
                        employeeRepository, request.StoreId, created.EmployeeIds, cancellationToken)).ToList()
                    : new List<Guid>();
                if (userIds.Count > 0)
                {
                    await notificationService.CreateAndSendToUsersAsync(
                        userIds, NotificationType.Info,
                        $"Phụ cấp mới: {created.Name}",
                        $"Bạn được hưởng {AllowanceNotificationHelper.Describe(created.Amount, created.Currency, created.Type)}",
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
    List<string>? EmployeeIds,
    List<string>? ShiftIds,
    decimal? MinWorkPercent = null,
    decimal? MinWorkHours = null) : ICommand<AppResponse<AllowanceDto>>;

public class UpdateAllowanceHandler(
    IRepository<Allowance> allowanceRepository,
    IRepository<Employee> employeeRepository,
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

            var previousUserIds = await AllowanceNotificationHelper.ResolveUserIdsAsync(
                employeeRepository, request.StoreId, allowance.EmployeeIds, cancellationToken);
            var previousText = AllowanceNotificationHelper.Describe(allowance.Amount, allowance.Currency, allowance.Type);
            var previousActive = allowance.IsActive;

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
            allowance.ShiftIds = request.ShiftIds != null && request.ShiftIds.Count > 0 ? JsonSerializer.Serialize(request.ShiftIds) : null;
            allowance.MinWorkPercent = AllowanceWorkRule.Percent(request.Type, request.MinWorkPercent);
            allowance.MinWorkHours = AllowanceWorkRule.Hours(request.Type, request.MinWorkPercent, request.MinWorkHours);

            await allowanceRepository.UpdateAsync(allowance, cancellationToken);
            var dto = allowance.Adapt<AllowanceDto>();
            dto.EmployeeIds = string.IsNullOrEmpty(allowance.EmployeeIds) ? null : JsonSerializer.Deserialize<List<string>>(allowance.EmployeeIds);
            dto.ShiftIds = string.IsNullOrEmpty(allowance.ShiftIds) ? null : JsonSerializer.Deserialize<List<string>>(allowance.ShiftIds);

            // Trước đây gửi chung «đã được cập nhật» cho cả NV cũ + mới — kể cả người vừa bị gỡ khỏi phụ cấp.
            // Nay tách: bị gỡ (hoặc phụ cấp tắt) → «đã dừng»; mới được gán → «Phụ cấp mới»; vẫn hưởng → mức hiện tại.
            try
            {
                var currentUserIds = await AllowanceNotificationHelper.ResolveUserIdsAsync(
                    employeeRepository, request.StoreId, allowance.EmployeeIds, cancellationToken);
                var currentText = AllowanceNotificationHelper.Describe(allowance.Amount, allowance.Currency, allowance.Type);

                var stopped = previousActive
                    ? previousUserIds.Where(id => !currentUserIds.Contains(id)).ToList()
                    : new List<Guid>();
                var added = new List<Guid>();
                var kept = new List<Guid>();
                if (allowance.IsActive)
                {
                    // Phụ cấp vừa bật lại: mọi người đang được gán coi như mới được hưởng.
                    added = currentUserIds.Where(id => !previousActive || !previousUserIds.Contains(id)).ToList();
                    kept = previousActive
                        ? currentUserIds.Where(id => previousUserIds.Contains(id)).ToList()
                        : new List<Guid>();
                }
                else if (previousActive)
                {
                    stopped = stopped.Concat(currentUserIds).Distinct().ToList();
                }

                if (stopped.Count > 0)
                {
                    await notificationService.CreateAndSendToUsersAsync(
                        stopped, NotificationType.Warning,
                        $"Phụ cấp đã dừng: {allowance.Name}",
                        "Phụ cấp này không còn áp dụng cho bạn",
                        relatedEntityId: allowance.Id, relatedEntityType: "Allowance",
                        categoryCode: "allowance", storeId: request.StoreId);
                }

                if (added.Count > 0)
                {
                    await notificationService.CreateAndSendToUsersAsync(
                        added, NotificationType.Info,
                        $"Phụ cấp mới: {allowance.Name}",
                        $"Bạn được hưởng {currentText}",
                        relatedEntityId: allowance.Id, relatedEntityType: "Allowance",
                        categoryCode: "allowance", storeId: request.StoreId);
                }

                // Mức không đổi (chỉ sửa tên / mô tả…) thì không báo — phụ cấp «tất cả nhân viên» từng làm cả
                // cửa hàng nhận thông báo vô ích.
                if (kept.Count > 0 && currentText != previousText)
                {
                    await notificationService.CreateAndSendToUsersAsync(
                        kept, NotificationType.Info,
                        $"Phụ cấp đã cập nhật: {allowance.Name}",
                        $"Nay {currentText} (trước {previousText})",
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
    IRepository<Employee> employeeRepository,
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

            var affectedUserIds = allowance.IsActive
                ? (await AllowanceNotificationHelper.ResolveUserIdsAsync(
                    employeeRepository, request.StoreId, allowance.EmployeeIds, cancellationToken)).ToList()
                : new List<Guid>();
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
                        "Phụ cấp này không còn áp dụng cho bạn",
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

/// <summary>Chuẩn hóa điều kiện nhận phụ cấp: chỉ cho loại theo ngày / theo ca; chọn % thì bỏ số giờ.</summary>
public static class AllowanceWorkRule
{
    private static bool Applies(AllowanceType t) => t is AllowanceType.Daily or AllowanceType.PerShift;

    public static decimal? Percent(AllowanceType type, decimal? percent) =>
        Applies(type) && percent is > 0 ? Math.Min(100, Math.Round(percent.Value, 2)) : null;

    public static decimal? Hours(AllowanceType type, decimal? percent, decimal? hours) =>
        Applies(type) && percent is not > 0 && hours is > 0 ? Math.Min(24, Math.Round(hours.Value, 2)) : null;
}
