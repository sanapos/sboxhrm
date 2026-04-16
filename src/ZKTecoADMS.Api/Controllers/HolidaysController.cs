using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/settings/[controller]")]
public class HolidaysController(IRepository<Holiday> repository) : AuthenticatedControllerBase
{
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<HolidayDto>>>> GetHolidays([FromQuery] int? year = null)
    {
        var targetYear = year ?? DateTime.Now.Year;
        var storeId = RequiredStoreId;
        
        // Filter by StoreId for multi-tenant data isolation
        var holidays = await repository.GetAllAsync(
            filter: h => h.StoreId == storeId && h.Date.Year == targetYear,
            orderBy: q => q.OrderBy(h => h.Date));
        
        var dtos = holidays.Select(h => new HolidayDto
        {
            Id = h.Id,
            Name = h.Name,
            Date = h.Date,
            Description = h.Description,
            IsRecurring = h.IsRecurring,
            Region = h.Region,
            SalaryRate = h.SalaryRate,
            Category = h.Category,
            EmployeeIds = string.IsNullOrEmpty(h.EmployeeIds) ? null : JsonSerializer.Deserialize<List<string>>(h.EmployeeIds)
        }).ToList();
        
        return Ok(AppResponse<List<HolidayDto>>.Success(dtos));
    }

    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<HolidayDto>>> GetHoliday(Guid id)
    {
        var storeId = RequiredStoreId;
        
        // Filter by StoreId for multi-tenant data isolation
        var holiday = await repository.GetSingleAsync(
            h => h.Id == id && h.StoreId == storeId);
        if (holiday == null)
        {
            return Ok(AppResponse<HolidayDto>.Error("Holiday not found"));
        }
        
        var dto = new HolidayDto
        {
            Id = holiday.Id,
            Name = holiday.Name,
            Date = holiday.Date,
            Description = holiday.Description,
            IsRecurring = holiday.IsRecurring,
            Region = holiday.Region,
            SalaryRate = holiday.SalaryRate,
            Category = holiday.Category,
            EmployeeIds = string.IsNullOrEmpty(holiday.EmployeeIds) ? null : JsonSerializer.Deserialize<List<string>>(holiday.EmployeeIds)
        };
        
        return Ok(AppResponse<HolidayDto>.Success(dto));
    }

    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<HolidayDto>>> CreateHoliday([FromBody] CreateHolidayRequest request)
    {
        var storeId = RequiredStoreId;
        
        var holiday = new Holiday
        {
            StoreId = storeId,
            Name = request.Name,
            Date = request.Date,
            Description = request.Description,
            IsRecurring = request.IsRecurring,
            IsActive = true,
            Region = request.Region ?? "Vietnam",
            SalaryRate = request.SalaryRate,
            Category = request.Category,
            EmployeeIds = request.EmployeeIds != null && request.EmployeeIds.Count > 0 ? JsonSerializer.Serialize(request.EmployeeIds) : null
        };
        
        await repository.AddAsync(holiday);
        
        var dto = new HolidayDto
        {
            Id = holiday.Id,
            Name = holiday.Name,
            Date = holiday.Date,
            Description = holiday.Description,
            IsRecurring = holiday.IsRecurring,
            Region = holiday.Region,
            SalaryRate = holiday.SalaryRate,
            Category = holiday.Category,
            EmployeeIds = string.IsNullOrEmpty(holiday.EmployeeIds) ? null : JsonSerializer.Deserialize<List<string>>(holiday.EmployeeIds)
        };
        
        return Ok(AppResponse<HolidayDto>.Success(dto));
    }

    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<HolidayDto>>> UpdateHoliday(Guid id, [FromBody] UpdateHolidayRequest request)
    {
        var storeId = RequiredStoreId;
        
        // Filter by StoreId for multi-tenant data isolation
        var holiday = await repository.GetSingleAsync(
            h => h.Id == id && h.StoreId == storeId);
        if (holiday == null)
        {
            return Ok(AppResponse<HolidayDto>.Error("Holiday not found"));
        }
        
        holiday.Name = request.Name;
        holiday.Date = request.Date;
        holiday.Description = request.Description;
        holiday.IsRecurring = request.IsRecurring;
        holiday.Region = request.Region ?? holiday.Region;
        holiday.SalaryRate = request.SalaryRate;
        holiday.Category = request.Category;
        holiday.EmployeeIds = request.EmployeeIds != null && request.EmployeeIds.Count > 0 ? JsonSerializer.Serialize(request.EmployeeIds) : null;
        
        await repository.UpdateAsync(holiday);
        
        var dto = new HolidayDto
        {
            Id = holiday.Id,
            Name = holiday.Name,
            Date = holiday.Date,
            Description = holiday.Description,
            IsRecurring = holiday.IsRecurring,
            Region = holiday.Region,
            SalaryRate = holiday.SalaryRate,
            Category = holiday.Category,
            EmployeeIds = string.IsNullOrEmpty(holiday.EmployeeIds) ? null : JsonSerializer.Deserialize<List<string>>(holiday.EmployeeIds)
        };
        
        return Ok(AppResponse<HolidayDto>.Success(dto));
    }

    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteHoliday(Guid id)
    {
        var storeId = RequiredStoreId;
        
        // Filter by StoreId for multi-tenant data isolation
        var holiday = await repository.GetSingleAsync(
            h => h.Id == id && h.StoreId == storeId);
        if (holiday == null)
        {
            return Ok(AppResponse<bool>.Error("Holiday not found"));
        }
        
        await repository.DeleteAsync(holiday);
        return Ok(AppResponse<bool>.Success(true));
    }
}

public class HolidayDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public DateTime Date { get; set; }
    public string? Description { get; set; }
    public bool IsRecurring { get; set; }
    public string? Region { get; set; }
    public double SalaryRate { get; set; } = 3.0;
    public string Category { get; set; } = "Ngày nghỉ chính thức";
    public List<string>? EmployeeIds { get; set; }
}

public class CreateHolidayRequest
{
    public string Name { get; set; } = string.Empty;
    public DateTime Date { get; set; }
    public string? Description { get; set; }
    public bool IsRecurring { get; set; } = true;
    public string? Region { get; set; }
    public double SalaryRate { get; set; } = 3.0;
    public string Category { get; set; } = "Ngày nghỉ chính thức";
    public List<string>? EmployeeIds { get; set; }
}

public class UpdateHolidayRequest
{
    public string Name { get; set; } = string.Empty;
    public DateTime Date { get; set; }
    public string? Description { get; set; }
    public bool IsRecurring { get; set; }
    public string? Region { get; set; }
    public double SalaryRate { get; set; } = 3.0;
    public string Category { get; set; } = "Ngày nghỉ chính thức";
    public List<string>? EmployeeIds { get; set; }
}
