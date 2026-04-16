using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.Settings;
using ZKTecoADMS.Application.Queries.Settings;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Settings;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SettingsController(IMediator mediator, ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    // Salary Settings (general work config)
    [HttpGet("salary")]
    [Authorize]
    public IActionResult GetSalarySettings()
    {
        return Ok(AppResponse<object>.Success(new
        {
            standardWorkHours = 8,
            lunchBreakMinutes = 60,
            workStartTime = "08:30",
            workEndTime = "18:00",
            overtimeRate = 1.5,
            weekendRate = 2.0,
            holidayRate = 3.0
        }));
    }

    // Penalty Settings
    [HttpGet("penalty")]
    [Authorize]
    public async Task<ActionResult<AppResponse<PenaltySettingDto>>> GetPenaltySettings()
    {
        var query = new GetPenaltySettingsQuery(RequiredStoreId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPut("penalty")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
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
    public async Task<ActionResult<AppResponse<InsuranceSettingDto>>> GetInsuranceSettings()
    {
        var query = new GetInsuranceSettingsQuery(RequiredStoreId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPut("insurance")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
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
    public async Task<ActionResult<AppResponse<TaxSettingDto>>> GetTaxSettings()
    {
        var query = new GetTaxSettingsQuery(RequiredStoreId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPut("tax")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
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
    public async Task<ActionResult<AppResponse<List<EmployeeTaxDeductionDto>>>> GetEmployeeTaxDeductions()
    {
        var query = new GetEmployeeTaxDeductionsQuery(RequiredStoreId, CurrentUserId);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    [HttpPut("tax/employee-deductions")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    public async Task<ActionResult<AppResponse<EmployeeTaxDeductionDto>>> UpdateEmployeeTaxDeduction([FromBody] CreateOrUpdateEmployeeTaxDeductionDto request)
    {
        var command = new CreateOrUpdateEmployeeTaxDeductionCommand(
            RequiredStoreId,
            request.EmployeeId,
            request.NumberOfDependents,
            request.MandatoryInsurance,
            request.OtherExemptions);

        var result = await mediator.Send(command);
        return Ok(result);
    }

    // App Settings (Thiết lập hệ thống)
    [HttpGet("app/{key}")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    public async Task<ActionResult<AppResponse<AppSettingsDto>>> GetAppSetting(string key)
    {
        var storeId = RequiredStoreId;
        var setting = await dbContext.AppSettings.FirstOrDefaultAsync(s => s.StoreId == storeId && s.Key == key);
        if (setting == null)
            return NotFound(AppResponse<AppSettingsDto>.Fail("Setting không tồn tại"));

        var dto = new AppSettingsDto(
            setting.Id, setting.Key, setting.Value, setting.Description,
            setting.Group, setting.DataType, setting.DisplayOrder,
            setting.IsPublic, setting.LastModified);

        return Ok(AppResponse<AppSettingsDto>.Success(dto));
    }

    [HttpPost("app")]
    [Authorize(Policy = PolicyNames.AtLeastAdmin)]
    public async Task<ActionResult<AppResponse<AppSettingsDto>>> UpsertAppSetting([FromBody] UpsertAppSettingRequest request)
    {
        var storeId = RequiredStoreId;
        var setting = await dbContext.AppSettings.AsTracking().FirstOrDefaultAsync(s => s.StoreId == storeId && s.Key == request.Key);

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
            // SuperAdmin/Agent không có store → trả rỗng (frontend sẽ hiểu là không giới hạn)
            return Ok(AppResponse<List<string>>.Success(new List<string>()));
        }

        var store = await dbContext.Stores
            .Include(s => s.ServicePackage)
            .FirstOrDefaultAsync(s => s.Id == storeId);

        if (store?.ServicePackage == null || string.IsNullOrEmpty(store.ServicePackage.AllowedModules))
        {
            // Store chưa gán gói dịch vụ → không giới hạn
            return Ok(AppResponse<List<string>>.Success(new List<string>()));
        }

        var modules = System.Text.Json.JsonSerializer.Deserialize<List<string>>(
            store.ServicePackage.AllowedModules) ?? new List<string>();

        return Ok(AppResponse<List<string>>.Success(modules));
    }
}
