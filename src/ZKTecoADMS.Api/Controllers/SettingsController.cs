using System.Globalization;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.Settings;
using ZKTecoADMS.Application.Queries.Settings;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Settings;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SettingsController(IMediator mediator, ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    // Salary Settings (general work config — stored in AppSettings per store)
    [HttpGet("salary")]
    [Authorize]
    [RequireAnyModulePermission(ModulePermissionAction.View, "SalarySettings", "SystemSettings")]
    public async Task<IActionResult> GetSalarySettings()
    {
        var storeId = CurrentStoreId;
        if (!storeId.HasValue)
        {
            return Ok(AppResponse<object>.Success(DefaultSalarySettingsDto()));
        }

        var keys = SalarySettingKeys;
        var settings = await dbContext.AppSettings
            .AsNoTracking()
            .Where(s => s.StoreId == storeId.Value && keys.Contains(s.Key))
            .ToListAsync();
        var map = settings.ToDictionary(s => s.Key, s => s.Value);

        return Ok(AppResponse<object>.Success(new
        {
            standardWorkHours = ParseDouble(map, "standard_work_hours", 8),
            standardWorkDays = ParseInt(map, "standard_work_days", 26),
            lunchBreakMinutes = ParseInt(map, "lunch_break_minutes", 60),
            minHoursForWorkDay = ParseDouble(map, "min_hours_for_work_day", 0),
            minWorkDayPercent = ParseMinWorkDayPercent(map),
            minHalfDayHours = ParseDouble(map, "min_half_day_hours", 1),
            decimalWorkDayEnabled = ParseBool(map, "decimal_work_day_enabled", false),
            workStartTime = map.GetValueOrDefault("work_start_time") ?? "08:30",
            workEndTime = map.GetValueOrDefault("work_end_time") ?? "18:00",
            overtimeRate = ParseDouble(map, "overtime_rate", 1.5),
            weekendRate = ParseDouble(map, "weekend_rate", 2.0),
            holidayRate = ParseDouble(map, "holiday_rate", 3.0),
            travelSalaryMode = map.GetValueOrDefault("travel_salary_mode") ?? "base_per_8h",
            travelFixedHourlyRate = ParseDouble(map, "travel_fixed_hourly_rate", 0),
        }));
    }

    [HttpPut("salary")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "SalarySettings", "SystemSettings")]
    public async Task<IActionResult> UpdateSalarySettings([FromBody] UpdateSalarySettingsRequest request)
    {
        var storeId = CurrentStoreId;
        if (!storeId.HasValue)
            return BadRequest(AppResponse<object>.Fail("Yêu cầu đăng nhập theo cửa hàng"));

        await UpsertStoreSettingAsync(storeId.Value, "standard_work_hours",
            request.StandardWorkHours?.ToString() ?? "8", "Số giờ công chuẩn/ngày");
        await UpsertStoreSettingAsync(storeId.Value, "standard_work_days",
            request.StandardWorkDays?.ToString() ?? "26", "Số ngày công chuẩn/tháng");
        await UpsertStoreSettingAsync(storeId.Value, "lunch_break_minutes",
            request.LunchBreakMinutes?.ToString() ?? "60", "Nghỉ trưa (phút)");
        if (request.MinHoursForWorkDay.HasValue)
        {
            await UpsertStoreSettingAsync(storeId.Value, "min_hours_for_work_day",
                request.MinHoursForWorkDay.Value.ToString(CultureInfo.InvariantCulture),
                "Số giờ tối thiểu để tính 1 công (legacy)");
        }
        if (request.MinWorkDayPercent.HasValue)
        {
            var pct = Math.Clamp(request.MinWorkDayPercent.Value, 1, 100);
            await UpsertStoreSettingAsync(storeId.Value, "min_work_day_percent",
                pct.ToString(CultureInfo.InvariantCulture),
                "% giờ chuẩn trong ngày để đủ 1 công");
        }
        if (request.MinHalfDayHours.HasValue)
        {
            var half = Math.Clamp(request.MinHalfDayHours.Value, 0, 24);
            await UpsertStoreSettingAsync(storeId.Value, "min_half_day_hours",
                half.ToString(CultureInfo.InvariantCulture),
                "Giờ tối thiểu để tính nửa công / có công");
        }
        if (request.DecimalWorkDayEnabled.HasValue)
        {
            await UpsertStoreSettingAsync(storeId.Value, "decimal_work_day_enabled",
                request.DecimalWorkDayEnabled.Value ? "true" : "false",
                "Tính công theo thập phân (0.1–1.0)");
        }
        await UpsertStoreSettingAsync(storeId.Value, "work_start_time",
            request.WorkStartTime ?? "08:30", "Giờ vào ca mặc định");
        await UpsertStoreSettingAsync(storeId.Value, "work_end_time",
            request.WorkEndTime ?? "18:00", "Giờ ra ca mặc định");
        await UpsertStoreSettingAsync(storeId.Value, "overtime_rate",
            (request.OvertimeRate ?? 1.5).ToString(CultureInfo.InvariantCulture), "Hệ số tăng ca ngày thường");
        await UpsertStoreSettingAsync(storeId.Value, "weekend_rate",
            (request.WeekendRate ?? 2.0).ToString(CultureInfo.InvariantCulture), "Hệ số tăng ca cuối tuần / ngày nghỉ");
        await UpsertStoreSettingAsync(storeId.Value, "holiday_rate",
            (request.HolidayRate ?? 3.0).ToString(CultureInfo.InvariantCulture), "Hệ số tăng ca ngày lễ");
        if (!string.IsNullOrWhiteSpace(request.TravelSalaryMode))
        {
            await UpsertStoreSettingAsync(storeId.Value, "travel_salary_mode",
                request.TravelSalaryMode.Trim().ToLowerInvariant(),
                "Cách tính lương giờ đi đường (off|fixed|base_per_8h|completion_per_8h|base_plus_completion_per_8h)");
        }
        if (request.TravelFixedHourlyRate.HasValue)
        {
            await UpsertStoreSettingAsync(storeId.Value, "travel_fixed_hourly_rate",
                request.TravelFixedHourlyRate.Value.ToString(CultureInfo.InvariantCulture),
                "Lương giờ đi đường cố định (VNĐ/giờ)");
        }

        await dbContext.SaveChangesAsync();
        return await GetSalarySettings();
    }

    private static readonly string[] SalarySettingKeys =
    [
        "standard_work_hours", "standard_work_days", "lunch_break_minutes",
        "min_hours_for_work_day", "min_work_day_percent", "min_half_day_hours", "decimal_work_day_enabled",
        "work_start_time", "work_end_time",
        "overtime_rate", "weekend_rate", "holiday_rate",
        "travel_salary_mode", "travel_fixed_hourly_rate"
    ];

    private static double ParseMinWorkDayPercent(Dictionary<string, string> map)
    {
        if (map.TryGetValue("min_work_day_percent", out var pctStr) &&
            double.TryParse(pctStr, NumberStyles.Any, CultureInfo.InvariantCulture, out var pct) &&
            pct > 0)
        {
            return Math.Clamp(pct, 1, 100);
        }
        // Migrate legacy hours → % trên chuẩn 8h
        if (map.TryGetValue("min_hours_for_work_day", out var hoursStr) &&
            double.TryParse(hoursStr, NumberStyles.Any, CultureInfo.InvariantCulture, out var hours) &&
            hours > 0 && hours <= 24)
        {
            return Math.Clamp(hours / 8.0 * 100.0, 1, 100);
        }
        return 80;
    }

    private static object DefaultSalarySettingsDto() => new
    {
        standardWorkHours = 8,
        standardWorkDays = 26,
        lunchBreakMinutes = 60,
        minHoursForWorkDay = 0,
        minWorkDayPercent = 80,
        minHalfDayHours = 1,
        decimalWorkDayEnabled = false,
        workStartTime = "08:30",
        workEndTime = "18:00",
        overtimeRate = 1.5,
        weekendRate = 2.0,
        holidayRate = 3.0,
        travelSalaryMode = "base_per_8h",
        travelFixedHourlyRate = 0,
    };

    private static double ParseDouble(IReadOnlyDictionary<string, string?> map, string key, double fallback) =>
        map.TryGetValue(key, out var v) &&
        double.TryParse(v, NumberStyles.Any, CultureInfo.InvariantCulture, out var d)
            ? d
            : fallback;

    private static int ParseInt(IReadOnlyDictionary<string, string?> map, string key, int fallback) =>
        map.TryGetValue(key, out var v) && int.TryParse(v, out var i) ? i : fallback;

    private static bool ParseBool(IReadOnlyDictionary<string, string?> map, string key, bool fallback) =>
        map.TryGetValue(key, out var v) && bool.TryParse(v, out var b) ? b : fallback;

    private async Task UpsertStoreSettingAsync(Guid storeId, string key, string value, string description)
    {
        var setting = await dbContext.AppSettings.AsTracking()
            .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Key == key);
        if (setting == null)
        {
            setting = new AppSettings
            {
                Id = Guid.NewGuid(),
                Key = key,
                Value = value,
                Description = description,
                Group = "Salary",
                DataType = "string",
                StoreId = storeId,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = CurrentUserId.ToString(),
            };
            dbContext.AppSettings.Add(setting);
        }
        else
        {
            setting.Value = value;
            setting.Description = description;
            setting.LastModified = DateTime.UtcNow;
            setting.LastModifiedBy = CurrentUserId.ToString();
        }
    }

    public class UpdateSalarySettingsRequest
    {
        public double? StandardWorkHours { get; set; }
        public int? StandardWorkDays { get; set; }
        public int? LunchBreakMinutes { get; set; }
        /// <summary>Legacy: số giờ tối thiểu tuyệt đối (đã thay bằng MinWorkDayPercent).</summary>
        public double? MinHoursForWorkDay { get; set; }
        /// <summary>% giờ chuẩn NV trong ngày để đủ 1 công (mặc định 80).</summary>
        public double? MinWorkDayPercent { get; set; }
        /// <summary>Giờ tối thiểu để tính nửa công / có công (mặc định 1).</summary>
        public double? MinHalfDayHours { get; set; }
        /// <summary>Tính công thập phân 0.1–1.0 (làm tròn gần nhất; tắt ngưỡng %).</summary>
        public bool? DecimalWorkDayEnabled { get; set; }
        public string? WorkStartTime { get; set; }
        public string? WorkEndTime { get; set; }
        public double? OvertimeRate { get; set; }
        public double? WeekendRate { get; set; }
        public double? HolidayRate { get; set; }
        /// <summary>off | fixed | base_per_8h | completion_per_8h | base_plus_completion_per_8h</summary>
        public string? TravelSalaryMode { get; set; }
        public double? TravelFixedHourlyRate { get; set; }
    }

    // Penalty Settings
    [HttpGet("penalty")]
    [Authorize]
    [RequireModulePermission("PenaltySetup", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PenaltySettingDto>>> GetPenaltySettings()
    {
        var result = await mediator.Send(new GetOrCreatePenaltySettingsCommand(RequiredStoreId));
        return Ok(result);
    }

    [HttpPut("penalty")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequireModulePermission("PenaltySetup", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<PenaltySettingDto>>> UpdatePenaltySettings([FromBody] UpdatePenaltySettingDto request)
    {
        var command = new UpdatePenaltySettingsCommand(
            RequiredStoreId,
            request.LateMinutes1, request.LatePenalty1,
            request.LateMinutes2, request.LatePenalty2,
            request.LateMinutes3, request.LatePenalty3,
            request.EarlyMinutes1, request.EarlyPenalty1,
            request.EarlyMinutes2, request.EarlyPenalty2,
            request.EarlyMinutes3, request.EarlyPenalty3,
            request.RepeatCount1, request.RepeatPenalty1,
            request.RepeatCount2, request.RepeatPenalty2,
            request.RepeatCount3, request.RepeatPenalty3,
            request.ForgotCheckPenalty,
            request.UnauthorizedLeavePenalty,
            request.ViolationPenalty);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    // Insurance Settings
    [HttpGet("insurance")]
    [Authorize]
    [RequireModulePermission("Insurance", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<InsuranceSettingDto>>> GetInsuranceSettings()
    {
        var query = new GetInsuranceSettingsQuery(RequiredStoreId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPut("insurance")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequireModulePermission("Insurance", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<InsuranceSettingDto>>> UpdateInsuranceSettings([FromBody] UpdateInsuranceSettingDto request)
    {
        var command = new UpdateInsuranceSettingsCommand(
            RequiredStoreId,
            request.BaseSalary,
            request.MinSalaryRegion1,
            request.MinSalaryRegion2,
            request.MinSalaryRegion3,
            request.MinSalaryRegion4,
            request.MaxInsuranceSalary,
            request.BhxhEmployeeRate, request.BhxhEmployerRate,
            request.BhytEmployeeRate, request.BhytEmployerRate,
            request.BhtnEmployeeRate, request.BhtnEmployerRate,
            request.UnionFeeEmployeeRate, request.UnionFeeEmployerRate,
            request.DefaultRegion);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    // Tax Settings
    [HttpGet("tax")]
    [Authorize]
    [RequireModulePermission("Tax", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<TaxSettingDto>>> GetTaxSettings()
    {
        var query = new GetTaxSettingsQuery(RequiredStoreId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPut("tax")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequireModulePermission("Tax", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TaxSettingDto>>> UpdateTaxSettings([FromBody] UpdateTaxSettingDto request)
    {
        var command = new UpdateTaxSettingsCommand(
            RequiredStoreId,
            request.PersonalDeduction,
            request.DependentDeduction,
            request.TaxBracket1Max, request.TaxRate1,
            request.TaxBracket2Max, request.TaxRate2,
            request.TaxBracket3Max, request.TaxRate3,
            request.TaxBracket4Max, request.TaxRate4,
            request.TaxBracket5Max, request.TaxRate5,
            request.TaxBracket6Max, request.TaxRate6,
            request.TaxRate7);
        
        var result = await mediator.Send(command);
        return Ok(result);
    }

    // Calculate Tax
    [HttpPost("tax/calculate")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Tax", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TaxCalculationDto>>> CalculateTax([FromBody] CalculateTaxDto request)
    {
        var query = new CalculateTaxQuery(
            RequiredStoreId,
            request.GrossIncome,
            request.InsuranceSalary,
            request.NumberOfDependents);
        
        var result = await mediator.Send(query);
        return Ok(result);
    }

    // Employee Tax Deductions
    [HttpGet("tax/employee-deductions")]
    [Authorize]
    [RequireModulePermission("Tax", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<EmployeeTaxDeductionDto>>>> GetEmployeeTaxDeductions()
    {
        var query = new GetEmployeeTaxDeductionsQuery(RequiredStoreId, CurrentUserId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPut("tax/employee-deductions")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    [RequireModulePermission("Tax", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<EmployeeTaxDeductionDto>>> UpdateEmployeeTaxDeduction([FromBody] CreateOrUpdateEmployeeTaxDeductionDto request)
    {
        var command = new CreateOrUpdateEmployeeTaxDeductionCommand(
            RequiredStoreId,
            request.EmployeeId,
            request.NumberOfDependents,
            request.MandatoryInsurance,
            request.OtherExemptions,
            request.DependentRegistrationFormUrl,
            request.DependentDocumentsJson);

        var result = await mediator.Send(command);
        return Ok(result);
    }

    // App Settings (Thiết lập hệ thống)
    [HttpGet("app/{key}")]
    [Authorize]
    [RequireAnyModulePermission(ModulePermissionAction.View, "SystemSettings", "SalarySettings")]
    public async Task<ActionResult<AppResponse<AppSettingsDto>>> GetAppSetting(string key)
    {
        var storeId = CurrentStoreId;
        AppSettings? setting;
        if (storeId.HasValue)
            setting = await dbContext.AppSettings.FirstOrDefaultAsync(s => s.StoreId == storeId.Value && s.Key == key);
        else
            setting = await dbContext.AppSettings.FirstOrDefaultAsync(s => s.Key == key);
        if (setting == null)
        {
            return Ok(AppResponse<AppSettingsDto>.Success(new AppSettingsDto(
                Guid.Empty, key, string.Empty, null,
                "system", "string", 0, false, null)));
        }

        var dto = new AppSettingsDto(
            setting.Id, setting.Key, setting.Value, setting.Description,
            setting.Group, setting.DataType, setting.DisplayOrder,
            setting.IsPublic, setting.LastModified);

        return Ok(AppResponse<AppSettingsDto>.Success(dto));
    }

    [HttpPost("app")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "SystemSettings", "SalarySettings")]
    public async Task<ActionResult<AppResponse<AppSettingsDto>>> UpsertAppSetting([FromBody] UpsertAppSettingRequest request)
    {
        var storeId = CurrentStoreId;
        AppSettings? setting;
        if (storeId.HasValue)
            setting = await dbContext.AppSettings.AsTracking().FirstOrDefaultAsync(s => s.StoreId == storeId.Value && s.Key == request.Key);
        else
            setting = await dbContext.AppSettings.AsTracking().FirstOrDefaultAsync(s => s.Key == request.Key);

        if (setting == null)
        {
            setting = new AppSettings
            {
                Id = Guid.NewGuid(),
                Key = request.Key,
                Value = request.Value,
                Description = request.Description,
                Group = request.Group,
                DataType = request.DataType,
                DisplayOrder = request.DisplayOrder,
                IsPublic = request.IsPublic,
                StoreId = storeId,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = CurrentUserId.ToString()
            };
            dbContext.AppSettings.Add(setting);
        }
        else
        {
            setting.Value = request.Value;
            setting.Description = request.Description;
            setting.Group = request.Group;
            setting.DataType = request.DataType;
            setting.DisplayOrder = request.DisplayOrder;
            setting.IsPublic = request.IsPublic;
            setting.LastModified = DateTime.UtcNow;
            setting.LastModifiedBy = CurrentUserId.ToString();
        }

        await dbContext.SaveChangesAsync();

        var dto = new AppSettingsDto(
            setting.Id, setting.Key, setting.Value, setting.Description,
            setting.Group, setting.DataType, setting.DisplayOrder,
            setting.IsPublic, setting.LastModified);

        return Ok(AppResponse<AppSettingsDto>.Success(dto));
    }

    /// <summary>
    /// Lấy danh sách module được phép của cửa hàng hiện tại (dựa trên gói dịch vụ)
    /// </summary>
    [HttpGet("my-modules")]
    [Authorize]
    public async Task<ActionResult<AppResponse<List<string>>>> GetMyModules()
    {
        var storeId = CurrentStoreId;
        if (storeId == null)
        {
            return Ok(AppResponse<List<string>>.Success(new List<string>()));
        }

        var modules = await StorePackageHelper.ResolveAllowedModulesAsync(dbContext, storeId.Value);
        return Ok(AppResponse<List<string>>.Success(modules));
    }
}

