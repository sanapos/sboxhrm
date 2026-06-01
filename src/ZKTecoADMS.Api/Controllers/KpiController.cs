using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;
using MediatR;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Queries.Settings;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// API Controller quáº£n lÃ½ KPI Salary - TÃ­nh lÆ°Æ¡ng theo KPI káº¿t ná»‘i Google Sheet
/// </summary>
[ApiController]
[Route("api/kpi")]
[Authorize]
#pragma warning disable IDE0060,CA1823,CS9113 // Remove unused parameter
public class KpiController(
    ZKTecoDbContext dbContext,
    IKpiGoogleSheetService kpiSheetService,
    IRepository<Employee> employeeRepository,
    ILogger<KpiController> logger,
    IWebHostEnvironment env,
    ISystemNotificationService notificationService,
    IMediator mediator)
    : AuthenticatedControllerBase
#pragma warning restore IDE0060,CA1823,CS9113
{
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // KPI CONFIG CRUD
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Láº¥y danh sÃ¡ch cáº¥u hÃ¬nh KPI
    /// </summary>
    [HttpGet("configs")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<KpiConfigDto>>>> GetConfigs()
    {
        var storeId = CurrentStoreId;
        var query = storeId.HasValue
            ? dbContext.KpiConfigs.Where(c => c.StoreId == storeId.Value)
            : dbContext.KpiConfigs.AsQueryable();

        var configs = await query
            .Where(c => c.Deleted == null)
            .OrderBy(c => c.SortOrder)
            .Select(c => new KpiConfigDto
            {
                Id = c.Id,
                Code = c.Code,
                Name = c.Name,
                Description = c.Description,
                Type = c.Type,
                Unit = c.Unit,
                Weight = c.Weight,
                TargetValue = c.TargetValue,
                MinValue = c.MinValue,
                MaxValue = c.MaxValue,
                Frequency = c.Frequency,
                GoogleSheetColumnName = c.GoogleSheetColumnName,
                SortOrder = c.SortOrder,
                IsActive = c.IsActive
            })
            .ToListAsync();

        return Ok(AppResponse<List<KpiConfigDto>>.Success(configs));
    }

    /// <summary>
    /// Táº¡o cáº¥u hÃ¬nh KPI má»›i
    /// </summary>
    [HttpPost("configs")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("KPI", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<KpiConfigDto>>> CreateConfig([FromBody] CreateKpiConfigRequest request)
    {
        var storeId = RequiredStoreId;

        var config = new KpiConfig
        {
            Code = request.Code,
            Name = request.Name,
            Description = request.Description,
            Type = request.Type,
            Unit = request.Unit,
            Weight = request.Weight,
            TargetValue = request.TargetValue,
            MinValue = request.MinValue,
            MaxValue = request.MaxValue,
            Frequency = request.Frequency,
            GoogleSheetColumnName = request.GoogleSheetColumnName,
            SortOrder = request.SortOrder,
            StoreId = storeId,
            IsActive = true
        };

        dbContext.KpiConfigs.Add(config);
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<KpiConfigDto>.Success(MapConfigToDto(config)));
    }

    /// <summary>
    /// Cáº­p nháº­t cáº¥u hÃ¬nh KPI
    /// </summary>
    [HttpPut("configs/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("KPI", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<KpiConfigDto>>> UpdateConfig(Guid id, [FromBody] CreateKpiConfigRequest request)
    {
        var config = await dbContext.KpiConfigs.FindAsync(id);
        if (config == null) return NotFound(AppResponse<KpiConfigDto>.Fail("KhÃ´ng tÃ¬m tháº¥y cáº¥u hÃ¬nh KPI"));

        config.Code = request.Code;
        config.Name = request.Name;
        config.Description = request.Description;
        config.Type = request.Type;
        config.Unit = request.Unit;
        config.Weight = request.Weight;
        config.TargetValue = request.TargetValue;
        config.MinValue = request.MinValue;
        config.MaxValue = request.MaxValue;
        config.Frequency = request.Frequency;
        config.GoogleSheetColumnName = request.GoogleSheetColumnName;
        config.SortOrder = request.SortOrder;
        config.UpdatedAt = DateTime.UtcNow;

        dbContext.KpiConfigs.Update(config);
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<KpiConfigDto>.Success(MapConfigToDto(config)));
    }

    /// <summary>
    /// XÃ³a cáº¥u hÃ¬nh KPI (soft delete)
    /// </summary>
    [HttpDelete("configs/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("KPI", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteConfig(Guid id)
    {
        var config = await dbContext.KpiConfigs.FindAsync(id);
        if (config == null) return NotFound(AppResponse<bool>.Fail("KhÃ´ng tÃ¬m tháº¥y cáº¥u hÃ¬nh KPI"));

        config.Deleted = DateTime.UtcNow;
        config.DeletedBy = CurrentUserId.ToString();
        dbContext.KpiConfigs.Update(config);
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // KPI PERIOD CRUD
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Láº¥y danh sÃ¡ch ká»³ Ä‘Ã¡nh giÃ¡ KPI
    /// </summary>
    [HttpGet("periods")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<KpiPeriodDto>>>> GetPeriods([FromQuery] int? year)
    {
        var storeId = CurrentStoreId;
        var query = storeId.HasValue
            ? dbContext.KpiPeriods.Where(p => p.StoreId == storeId.Value)
            : dbContext.KpiPeriods.AsQueryable();

        if (year.HasValue)
            query = query.Where(p => p.Year == year.Value);

        var periods = await query
            .Where(p => p.Deleted == null)
            .OrderByDescending(p => p.Year).ThenByDescending(p => p.Month)
            .Select(p => new KpiPeriodDto
            {
                Id = p.Id,
                Name = p.Name,
                Year = p.Year,
                Month = p.Month,
                Quarter = p.Quarter,
                PeriodStart = p.PeriodStart,
                PeriodEnd = p.PeriodEnd,
                Frequency = p.Frequency,
                Status = p.Status,
                GoogleSpreadsheetId = p.GoogleSpreadsheetId,
                GoogleSheetName = p.GoogleSheetName,
                LastSyncedAt = p.LastSyncedAt,
                AutoSyncEnabled = p.AutoSyncEnabled,
                AutoSyncTimeSlots = p.AutoSyncTimeSlots,
                Notes = p.Notes,
                ResultCount = p.KpiResults.Count,
                SalaryCount = p.KpiSalaries.Count
            })
            .ToListAsync();

        return Ok(AppResponse<List<KpiPeriodDto>>.Success(periods));
    }

    /// <summary>
    /// Táº¡o ká»³ Ä‘Ã¡nh giÃ¡ KPI má»›i
    /// </summary>
    [HttpPost("periods")]
    [RequireModulePermission("KPI", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<KpiPeriodDto>>> CreatePeriod([FromBody] CreateKpiPeriodRequest request)
    {
        var storeId = RequiredStoreId;

        var period = new KpiPeriod
        {
            Name = request.Name,
            Year = request.Year,
            Month = request.Month,
            Quarter = request.Quarter,
            PeriodStart = request.PeriodStart,
            PeriodEnd = request.PeriodEnd,
            Frequency = request.Frequency,
            GoogleSpreadsheetId = request.GoogleSpreadsheetId,
            GoogleSheetName = request.GoogleSheetName,
            Notes = request.Notes,
            StoreId = storeId,
            Status = KpiPeriodStatus.Open,
            IsActive = true
        };

        dbContext.KpiPeriods.Add(period);
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<KpiPeriodDto>.Success(MapPeriodToDto(period)));
    }

    /// <summary>
    /// Cáº­p nháº­t ká»³ Ä‘Ã¡nh giÃ¡
    /// </summary>
    [HttpPut("periods/{id}")]
    [RequireModulePermission("KPI", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<KpiPeriodDto>>> UpdatePeriod(Guid id, [FromBody] CreateKpiPeriodRequest request)
    {
        var period = await dbContext.KpiPeriods.FindAsync(id);
        if (period == null) return NotFound(AppResponse<KpiPeriodDto>.Fail("KhÃ´ng tÃ¬m tháº¥y ká»³ Ä‘Ã¡nh giÃ¡"));

        period.Name = request.Name;
        period.Year = request.Year;
        period.Month = request.Month;
        period.Quarter = request.Quarter;
        period.PeriodStart = request.PeriodStart;
        period.PeriodEnd = request.PeriodEnd;
        period.Frequency = request.Frequency;
        period.GoogleSpreadsheetId = request.GoogleSpreadsheetId;
        period.GoogleSheetName = request.GoogleSheetName;
        period.Notes = request.Notes;
        period.UpdatedAt = DateTime.UtcNow;

        dbContext.KpiPeriods.Update(period);
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<KpiPeriodDto>.Success(MapPeriodToDto(period)));
    }

    /// <summary>
    /// Cáº­p nháº­t tráº¡ng thÃ¡i ká»³
    /// </summary>
    [HttpPut("periods/{id}/status")]
    [RequireModulePermission("KPI", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> UpdatePeriodStatus(Guid id, [FromBody] UpdateStatusRequest request)
    {
        var period = await dbContext.KpiPeriods.FindAsync(id);
        if (period == null) return NotFound(AppResponse<bool>.Fail("KhÃ´ng tÃ¬m tháº¥y ká»³ Ä‘Ã¡nh giÃ¡"));

        period.Status = request.Status;
        period.UpdatedAt = DateTime.UtcNow;
        dbContext.KpiPeriods.Update(period);
        await dbContext.SaveChangesAsync();

        // Notify employees when period is locked or calculated
        if (request.Status == KpiPeriodStatus.Locked || request.Status == KpiPeriodStatus.Calculated)
        {
            try
            {
                var statusLabel = request.Status == KpiPeriodStatus.Locked ? "Ä‘Ã£ khÃ³a" : "Ä‘Ã£ tÃ­nh lÆ°Æ¡ng";
                var empUserIds = await dbContext.KpiEmployeeTargets
                    .Where(t => t.KpiPeriodId == id && t.Deleted == null)
                    .Select(t => t.Employee.ApplicationUserId)
                    .Where(uid => uid != null)
                    .Distinct()
                    .ToListAsync();
                foreach (var uid in empUserIds)
                {
                    if (uid.HasValue && uid.Value != CurrentUserId)
                    {
                        await notificationService.CreateAndSendAsync(
                            uid.Value, NotificationType.Info,
                            "Ká»³ KPI cáº­p nháº­t",
                            $"Ká»³ Ä‘Ã¡nh giÃ¡ \"{period.Name}\" {statusLabel}",
                            relatedEntityType: "KpiPeriod",
                            fromUserId: CurrentUserId, categoryCode: "kpi", storeId: RequiredStoreId);
                    }
                }
            }
            catch { /* Notification failure should not affect main operation */ }
        }

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// XÃ³a ká»³ Ä‘Ã¡nh giÃ¡ (soft delete)
    /// </summary>
    [HttpDelete("periods/{id}")]
    [RequireModulePermission("KPI", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeletePeriod(Guid id)
    {
        var period = await dbContext.KpiPeriods.FindAsync(id);
        if (period == null) return NotFound(AppResponse<bool>.Fail("KhÃ´ng tÃ¬m tháº¥y ká»³ Ä‘Ã¡nh giÃ¡"));

        period.Deleted = DateTime.UtcNow;
        period.DeletedBy = CurrentUserId.ToString();
        dbContext.KpiPeriods.Update(period);
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // KPI BONUS RULES
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Láº¥y danh sÃ¡ch quy táº¯c thÆ°á»Ÿng KPI
    /// </summary>
    [HttpGet("bonus-rules")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<KpiBonusRuleDto>>>> GetBonusRules()
    {
        var storeId = CurrentStoreId;
        var query = storeId.HasValue
            ? dbContext.KpiBonusRules.Where(r => r.StoreId == storeId.Value)
            : dbContext.KpiBonusRules.AsQueryable();

        var rules = await query
            .Where(r => r.Deleted == null)
            .OrderBy(r => r.SortOrder)
            .Select(r => new KpiBonusRuleDto
            {
                Id = r.Id,
                Name = r.Name,
                MinScore = r.MinScore,
                MaxScore = r.MaxScore,
                BonusRate = r.BonusRate,
                Description = r.Description,
                SortOrder = r.SortOrder
            })
            .ToListAsync();

        return Ok(AppResponse<List<KpiBonusRuleDto>>.Success(rules));
    }

    /// <summary>
    /// LÆ°u danh sÃ¡ch quy táº¯c thÆ°á»Ÿng (thay tháº¿ toÃ n bá»™)
    /// </summary>
    [HttpPost("bonus-rules")]
    [RequireModulePermission("KPI", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<bool>>> SaveBonusRules([FromBody] List<SaveKpiBonusRuleRequest> requests)
    {
        var storeId = RequiredStoreId;

        // XÃ³a rules cÅ©
        var oldRules = await dbContext.KpiBonusRules
            .AsTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null)
            .ToListAsync();
        dbContext.KpiBonusRules.RemoveRange(oldRules);

        // ThÃªm rules má»›i
        for (int i = 0; i < requests.Count; i++)
        {
            var rule = new KpiBonusRule
            {
                Name = requests[i].Name,
                MinScore = requests[i].MinScore,
                MaxScore = requests[i].MaxScore,
                BonusRate = requests[i].BonusRate,
                Description = requests[i].Description,
                SortOrder = i,
                StoreId = storeId,
                IsActive = true
            };
            dbContext.KpiBonusRules.Add(rule);
        }

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // KPI RESULTS
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Láº¥y káº¿t quáº£ KPI theo ká»³. Khi khÃ´ng truyá»n periodId, máº·c Ä‘á»‹nh dÃ¹ng ká»³ KPI
    /// "Ä‘ang má»Ÿ" má»›i nháº¥t cá»§a store hiá»‡n táº¡i (náº¿u khÃ´ng cÃ³ ká»³ Open thÃ¬ láº¥y ká»³
    /// káº¿t thÃºc gáº§n nháº¥t). TrÆ°á»›c Ä‘Ã¢y client gá»i khÃ´ng kÃ¨m periodId luÃ´n nháº­n
    /// Guid.Empty â†’ tráº£ vá» 0 dÃ²ng â†’ block KPI trÃªn Dashboard luÃ´n rá»—ng.
    /// </summary>
    [HttpGet("results")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<KpiResultDto>>>> GetResults(
        [FromQuery] Guid? periodId = null,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        var storeId = RequiredStoreId;
        Guid effectivePeriodId;
        if (periodId.HasValue && periodId.Value != Guid.Empty)
        {
            effectivePeriodId = periodId.Value;
        }
        else
        {
            var fallbackPeriod = await dbContext.KpiPeriods
                .Where(p => p.StoreId == storeId && p.Deleted == null)
                // Æ¯u tiÃªn ká»³ Open má»›i nháº¥t theo PeriodStart, sau Ä‘Ã³ lÃ  ká»³ cÃ³ PeriodEnd gáº§n now nháº¥t.
                .OrderBy(p => p.Status == KpiPeriodStatus.Open ? 0 : 1)
                .ThenByDescending(p => p.PeriodStart)
                .Select(p => new { p.Id })
                .FirstOrDefaultAsync();
            if (fallbackPeriod == null)
            {
                return Ok(AppResponse<List<KpiResultDto>>.Success(new List<KpiResultDto>()));
            }
            effectivePeriodId = fallbackPeriod.Id;
        }

        var branchScope = await BranchQueryHelper.ResolveEmployeeScopeAsync(
            dbContext, storeId, branchId, includeChildBranches);

        var resultsQuery = dbContext.KpiResults
            .Include(r => r.Employee)
            .Include(r => r.KpiConfig)
            .Where(r => r.KpiPeriodId == effectivePeriodId && r.Deleted == null);
        if (branchScope != null)
        {
            if (branchScope.IsEmpty)
                return Ok(AppResponse<List<KpiResultDto>>.Success(new List<KpiResultDto>()));
            resultsQuery = resultsQuery.Where(r => branchScope.EmployeeIds.Contains(r.EmployeeId));
        }

        var results = await resultsQuery
            .OrderBy(r => r.Employee.EmployeeCode)
            .ThenBy(r => r.KpiConfig.SortOrder)
            .Select(r => new KpiResultDto
            {
                Id = r.Id,
                EmployeeId = r.EmployeeId,
                EmployeeCode = r.Employee.EmployeeCode ?? "",
                EmployeeName = (r.Employee.LastName ?? "") + " " + (r.Employee.FirstName ?? ""),
                KpiConfigId = r.KpiConfigId,
                KpiConfigName = r.KpiConfig.Name,
                KpiPeriodId = r.KpiPeriodId,
                ActualValue = r.ActualValue,
                TargetValue = r.TargetValue,
                CompletionRate = r.CompletionRate,
                WeightedScore = r.WeightedScore,
                Notes = r.Notes,
                Source = r.Source
            })
            .ToListAsync();

        return Ok(AppResponse<List<KpiResultDto>>.Success(results));
    }

    /// <summary>
    /// Nháº­p káº¿t quáº£ KPI thá»§ cÃ´ng
    /// </summary>
    [HttpPost("results")]
    [RequireModulePermission("KPI", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<bool>>> SaveResults([FromBody] SaveKpiResultsRequest request)
    {
        var storeId = RequiredStoreId;

        // Pre-load all needed data to avoid N+1
        var configIds = request.Results.Select(r => r.KpiConfigId).Distinct().ToList();
        var configs = await dbContext.KpiConfigs
            .Where(c => configIds.Contains(c.Id))
            .ToDictionaryAsync(c => c.Id);

        var existingResults = await dbContext.KpiResults
            .AsTracking()
            .Where(r => r.KpiPeriodId == request.PeriodId &&
                        request.Results.Select(x => x.EmployeeId).Contains(r.EmployeeId) &&
                        configIds.Contains(r.KpiConfigId))
            .ToListAsync();
        var existingLookup = existingResults.ToDictionary(r => (r.EmployeeId, r.KpiConfigId));

        foreach (var item in request.Results)
        {
            existingLookup.TryGetValue((item.EmployeeId, item.KpiConfigId), out var existing);

            if (!configs.TryGetValue(item.KpiConfigId, out var config)) continue;

            var targetValue = config.TargetValue;
            var completionRate = targetValue > 0 ? (item.ActualValue / targetValue * 100m) : 0;
            if (config.MaxValue.HasValue && completionRate > config.MaxValue.Value)
                completionRate = config.MaxValue.Value;
            var weightedScore = completionRate * config.Weight / 100m;

            if (existing != null)
            {
                existing.ActualValue = item.ActualValue;
                existing.TargetValue = targetValue;
                existing.CompletionRate = completionRate;
                existing.WeightedScore = weightedScore;
                existing.Notes = item.Notes;
                existing.Source = "Manual";
                existing.UpdatedAt = DateTime.UtcNow;
                dbContext.KpiResults.Update(existing);
            }
            else
            {
                var result = new KpiResult
                {
                    EmployeeId = item.EmployeeId,
                    KpiConfigId = item.KpiConfigId,
                    KpiPeriodId = request.PeriodId,
                    ActualValue = item.ActualValue,
                    TargetValue = targetValue,
                    CompletionRate = completionRate,
                    WeightedScore = weightedScore,
                    Notes = item.Notes,
                    Source = "Manual",
                    StoreId = storeId,
                    IsActive = true
                };
                dbContext.KpiResults.Add(result);
            }
        }

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // GOOGLE SHEET INTEGRATION
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Láº¥y danh sÃ¡ch sheet trong spreadsheet
    /// </summary>
    [HttpGet("sheets/names")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<string>>>> GetSheetNames([FromQuery] string spreadsheetId)
    {
        try
        {
            var names = await kpiSheetService.GetSheetNamesAsync(spreadsheetId);
            return Ok(AppResponse<List<string>>.Success(names));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to get sheet names");
            return Ok(AppResponse<List<string>>.Fail($"Lá»—i: {ex.Message}"));
        }
    }

    /// <summary>
    /// Láº¥y header cá»§a sheet (Ä‘á»ƒ mapping cá»™t KPI)
    /// </summary>
    [HttpGet("sheets/headers")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<string>>>> GetSheetHeaders(
        [FromQuery] string spreadsheetId, [FromQuery] string sheetName)
    {
        try
        {
            var headers = await kpiSheetService.GetSheetHeadersAsync(spreadsheetId, sheetName);
            return Ok(AppResponse<List<string>>.Success(headers));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to get sheet headers");
            return Ok(AppResponse<List<string>>.Fail($"Lá»—i: {ex.Message}"));
        }
    }

    /// <summary>
    /// Äá»“ng bá»™ dá»¯ liá»‡u KPI tá»« Google Sheet vÃ o há»‡ thá»‘ng
    /// </summary>
    [HttpPost("sheets/sync")]
    [RequireModulePermission("KPI", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<SyncKpiResult>>> SyncFromGoogleSheet([FromBody] SyncKpiFromSheetRequest request)
    {
        var storeId = RequiredStoreId;
        var syncResult = new SyncKpiResult();

        try
        {
            // 1. Äá»c dá»¯ liá»‡u tá»« Sheet
            var sheetRows = await kpiSheetService.ReadKpiDataAsync(
                request.SpreadsheetId, request.SheetName);

            if (sheetRows.Count == 0)
            {
                return Ok(AppResponse<SyncKpiResult>.Fail("KhÃ´ng cÃ³ dá»¯ liá»‡u KPI trong sheet"));
            }

            // 2. Láº¥y danh sÃ¡ch KPI configs Ä‘á»ƒ mapping cá»™t
            var kpiConfigs = await dbContext.KpiConfigs
                .Where(c => c.StoreId == storeId && c.Deleted == null && c.IsActive)
                .ToListAsync();

            // 3. Láº¥y danh sÃ¡ch nhÃ¢n viÃªn Ä‘á»ƒ matching
            var employees = await dbContext.Set<Employee>()
                .Where(e => e.StoreId == storeId && e.Deleted == null)
                .ToListAsync();

            // 4. Xá»­ lÃ½ tá»«ng dÃ²ng
            foreach (var row in sheetRows)
            {
                var employee = employees.FirstOrDefault(e =>
                    (e.EmployeeCode ?? "").Equals(row.EmployeeCode, StringComparison.OrdinalIgnoreCase));

                if (employee == null)
                {
                    syncResult.SkippedRows.Add($"KhÃ´ng tÃ¬m tháº¥y NV: {row.EmployeeCode} - {row.EmployeeName}");
                    continue;
                }

                foreach (var kpiConfig in kpiConfigs)
                {
                    // TÃ¬m giÃ¡ trá»‹ KPI trong dÃ²ng dá»±a trÃªn GoogleSheetColumnName
                    decimal? actualValue = null;
                    if (!string.IsNullOrEmpty(kpiConfig.GoogleSheetColumnName) &&
                        row.KpiValues.TryGetValue(kpiConfig.GoogleSheetColumnName, out var val))
                    {
                        actualValue = val;
                    }
                    // Fallback: tÃ¬m theo tÃªn KPI
                    else if (row.KpiValues.TryGetValue(kpiConfig.Name, out val))
                    {
                        actualValue = val;
                    }

                    if (!actualValue.HasValue) continue;

                    var targetValue = kpiConfig.TargetValue;
                    var completionRate = targetValue > 0 ? (actualValue.Value / targetValue * 100m) : 0;
                    if (kpiConfig.MaxValue.HasValue && completionRate > kpiConfig.MaxValue.Value)
                        completionRate = kpiConfig.MaxValue.Value;
                    var weightedScore = completionRate * kpiConfig.Weight / 100m;

                    // Upsert
                    var existing = await dbContext.KpiResults
                        .AsTracking()
                        .FirstOrDefaultAsync(r =>
                            r.EmployeeId == employee.Id &&
                            r.KpiConfigId == kpiConfig.Id &&
                            r.KpiPeriodId == request.PeriodId);

                    if (existing != null)
                    {
                        existing.ActualValue = actualValue.Value;
                        existing.TargetValue = targetValue;
                        existing.CompletionRate = completionRate;
                        existing.WeightedScore = weightedScore;
                        existing.Source = "GoogleSheet";
                        existing.UpdatedAt = DateTime.UtcNow;
                        dbContext.KpiResults.Update(existing);
                        syncResult.UpdatedCount++;
                    }
                    else
                    {
                        var result = new KpiResult
                        {
                            EmployeeId = employee.Id,
                            KpiConfigId = kpiConfig.Id,
                            KpiPeriodId = request.PeriodId,
                            ActualValue = actualValue.Value,
                            TargetValue = targetValue,
                            CompletionRate = completionRate,
                            WeightedScore = weightedScore,
                            Source = "GoogleSheet",
                            StoreId = storeId,
                            IsActive = true
                        };
                        dbContext.KpiResults.Add(result);
                        syncResult.CreatedCount++;
                    }
                }

                syncResult.ProcessedEmployees++;
            }

            // Cáº­p nháº­t thá»i gian sync cho period
            var period = await dbContext.KpiPeriods.FindAsync(request.PeriodId);
            if (period != null)
            {
                period.LastSyncedAt = DateTime.UtcNow;
                period.GoogleSpreadsheetId = request.SpreadsheetId;
                period.GoogleSheetName = request.SheetName;
                dbContext.KpiPeriods.Update(period);
            }

            await dbContext.SaveChangesAsync();

            syncResult.TotalRows = sheetRows.Count;
            syncResult.Success = true;

            return Ok(AppResponse<SyncKpiResult>.Success(syncResult));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to sync KPI data from Google Sheet");
            return Ok(AppResponse<SyncKpiResult>.Fail($"Lá»—i Ä‘á»“ng bá»™: {ex.Message}"));
        }
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // KPI SALARY CALCULATION
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// TÃ­nh lÆ°Æ¡ng KPI cho toÃ n bá»™ nhÃ¢n viÃªn trong ká»³
    /// </summary>
    [HttpPost("salary/calculate")]
    [RequireModulePermission("KPI", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<List<KpiSalaryDto>>>> CalculateSalary([FromBody] CalculateKpiSalaryRequest request)
    {
        var storeId = RequiredStoreId;

        try
        {
            // Æ¯u tiÃªn: Náº¿u cÃ³ KpiEmployeeTargets vá»›i ActualValue â†’ dÃ¹ng cÃ´ng thá»©c band-based
            var empTargets = await dbContext.KpiEmployeeTargets
                .Include(t => t.Employee)
                .Where(t => t.KpiPeriodId == request.PeriodId &&
                            t.ActualValue.HasValue &&
                            t.Deleted == null)
                .ToListAsync();

            if (empTargets.Count > 0)
            {
                var bandResults = new List<KpiSalaryDto>();

                // Pre-load all existing salaries for this period to avoid N+1
                var empIds = empTargets.Select(t => t.EmployeeId).Distinct().ToList();
                var existingSalariesMap = await dbContext.KpiSalaries
                    .AsTracking()
                    .Where(s => empIds.Contains(s.EmployeeId) && s.KpiPeriodId == request.PeriodId)
                    .ToDictionaryAsync(s => s.EmployeeId);

                foreach (var target in empTargets)
                {
                    var employee = target.Employee;

                    // TÃ­nh % hoÃ n thÃ nh
                    var pct = (target.ActualValue.HasValue && target.TargetValue != 0)
                        ? target.ActualValue.Value / target.TargetValue * 100m
                        : 0m;

                    decimal baseSalary, kpiBonusAmount, grossIncome;
                    if (pct < 100m)
                    {
                        // ChÆ°a Ä‘áº¡t 100%: lÆ°Æ¡ng tá»‰ lá»‡ + thÆ°á»Ÿng/pháº¡t theo PenaltyTiersJson
                        baseSalary = Math.Round(target.CompletionSalary * pct / 100m, 0);
                        kpiBonusAmount = CalcPenaltyBonus(target, pct);
                        grossIncome = baseSalary + kpiBonusAmount;
                        if (grossIncome < 0) grossIncome = 0;
                    }
                    else
                    {
                        // Äáº¡t/vÆ°á»£t 100%: lÆ°Æ¡ng cÆ¡ báº£n = CompletionSalary + thÆ°á»Ÿng vÆ°á»£t tá»« tiers
                        var bandBonus = CalcBandedBonus(target);
                        baseSalary = target.CompletionSalary;
                        kpiBonusAmount = bandBonus - target.CompletionSalary;
                        if (kpiBonusAmount < 0) kpiBonusAmount = 0;
                        grossIncome = baseSalary + kpiBonusAmount;
                    }

                    var allowances = 0m;
                    var deductions = 0m;
                    var netIncome = grossIncome - deductions;
                    var bonusRate = target.CompletionSalary > 0
                        ? Math.Round(kpiBonusAmount / target.CompletionSalary * 100m, 2)
                        : 0m;

                    existingSalariesMap.TryGetValue(target.EmployeeId, out var existing);
                    if (existing != null)
                    {
                        existing.BaseSalary = baseSalary;
                        existing.TotalKpiScore = target.CompletionRate;
                        existing.KpiBonusRate = bonusRate;
                        existing.KpiBonusAmount = kpiBonusAmount;
                        existing.Allowances = allowances;
                        existing.Deductions = deductions;
                        existing.GrossIncome = grossIncome;
                        existing.NetIncome = netIncome;
                        existing.UpdatedAt = DateTime.UtcNow;
                        dbContext.KpiSalaries.Update(existing);
                    }
                    else
                    {
                        existing = new KpiSalary
                        {
                            EmployeeId = target.EmployeeId,
                            KpiPeriodId = request.PeriodId,
                            BaseSalary = baseSalary,
                            TotalKpiScore = target.CompletionRate,
                            KpiBonusRate = bonusRate,
                            KpiBonusAmount = kpiBonusAmount,
                            Allowances = allowances,
                            Deductions = deductions,
                            GrossIncome = grossIncome,
                            NetIncome = netIncome,
                            StoreId = storeId,
                            IsActive = true
                        };
                        dbContext.KpiSalaries.Add(existing);
                    }

                    bandResults.Add(new KpiSalaryDto
                    {
                        Id = existing.Id,
                        EmployeeId = target.EmployeeId,
                        EmployeeCode = employee.EmployeeCode ?? "",
                        EmployeeName = (employee.LastName ?? "") + " " + (employee.FirstName ?? ""),
                        KpiPeriodId = request.PeriodId,
                        BaseSalary = baseSalary,
                        TotalKpiScore = target.CompletionRate,
                        KpiBonusRate = bonusRate,
                        KpiBonusAmount = kpiBonusAmount,
                        Allowances = allowances,
                        OtherBonus = existing.OtherBonus,
                        Deductions = deductions,
                        GrossIncome = grossIncome,
                        NetIncome = netIncome,
                        IsApproved = existing.IsApproved
                    });
                }

                await dbContext.SaveChangesAsync();

                var period2 = await dbContext.KpiPeriods.FindAsync(request.PeriodId);
                if (period2 != null && period2.Status == KpiPeriodStatus.Locked)
                {
                    period2.Status = KpiPeriodStatus.Calculated;
                    dbContext.KpiPeriods.Update(period2);
                    await dbContext.SaveChangesAsync();
                }

                // Notify employees about salary calculation
                try
                {
                    foreach (var result in bandResults)
                    {
                        var empUserId = await dbContext.Employees
                            .Where(e => e.Id == result.EmployeeId)
                            .Select(e => e.ApplicationUserId)
                            .FirstOrDefaultAsync();
                        if (empUserId.HasValue && empUserId.Value != CurrentUserId)
                        {
                            await notificationService.CreateAndSendAsync(
                                empUserId.Value, NotificationType.Info,
                                "LÆ°Æ¡ng KPI Ä‘Ã£ tÃ­nh",
                                $"LÆ°Æ¡ng KPI cá»§a báº¡n Ä‘Ã£ Ä‘Æ°á»£c tÃ­nh. Vui lÃ²ng kiá»ƒm tra.",
                                relatedEntityType: "KpiSalary",
                                fromUserId: CurrentUserId, categoryCode: "kpi", storeId: RequiredStoreId);
                        }
                    }
                }
                catch { /* Notification failure should not affect main operation */ }

                return Ok(AppResponse<List<KpiSalaryDto>>.Success(bandResults));
            }

            // 1. Láº¥y táº¥t cáº£ káº¿t quáº£ KPI trong ká»³ (fallback dÃ¹ng KpiResults)
            var kpiResults = await dbContext.KpiResults
                .Include(r => r.Employee)
                .Include(r => r.KpiConfig)
                .Where(r => r.KpiPeriodId == request.PeriodId && r.Deleted == null)
                .ToListAsync();

            // 2. Láº¥y bonus rules
            var bonusRules = await dbContext.KpiBonusRules
                .Where(r => r.StoreId == storeId && r.Deleted == null)
                .OrderBy(r => r.SortOrder)
                .ToListAsync();

            // 3. NhÃ³m theo nhÃ¢n viÃªn vÃ  tÃ­nh tá»•ng Ä‘iá»ƒm
            var employeeGroups = kpiResults.GroupBy(r => r.EmployeeId);
            var salaryResults = new List<KpiSalaryDto>();

            // Pre-load all employee benefits and existing salaries to avoid N+1
            var allEmployeeIds = employeeGroups.Select(g => g.Key).ToList();
            var employeeBenefitsMap = await dbContext.EmployeeBenefits
                .Include(eb => eb.Benefit)
                .Where(eb => allEmployeeIds.Contains(eb.EmployeeId) &&
                    (eb.EndDate == null || eb.EndDate > DateTime.UtcNow))
                .GroupBy(eb => eb.EmployeeId)
                .ToDictionaryAsync(g => g.Key, g => g.First());

            var existingSalariesMap2 = await dbContext.KpiSalaries
                .AsTracking()
                .Where(s => allEmployeeIds.Contains(s.EmployeeId) && s.KpiPeriodId == request.PeriodId)
                .ToDictionaryAsync(s => s.EmployeeId);

            foreach (var group in employeeGroups)
            {
                var employeeId = group.Key;
                var employee = group.First().Employee;
                var totalScore = group.Sum(r => r.WeightedScore);

                // TÃ¬m má»©c thÆ°á»Ÿng Ã¡p dá»¥ng
                var applicableRule = bonusRules.FirstOrDefault(r =>
                    totalScore >= r.MinScore && totalScore <= r.MaxScore);
                var bonusRate = applicableRule?.BonusRate ?? 0;

                // Láº¥y lÆ°Æ¡ng cÆ¡ báº£n tá»« SalaryProfile
                employeeBenefitsMap.TryGetValue(employeeId, out var employeeBenefit);

                var baseSalary = employeeBenefit?.Benefit?.Rate ?? 0;
                var allowances = (employeeBenefit?.Benefit?.MealAllowance ?? 0) +
                                 (employeeBenefit?.Benefit?.TransportAllowance ?? 0) +
                                 (employeeBenefit?.Benefit?.HousingAllowance ?? 0) +
                                 (employeeBenefit?.Benefit?.ResponsibilityAllowance ?? 0);

                var kpiBonusAmount = baseSalary * bonusRate / 100m;
                var grossIncome = baseSalary + kpiBonusAmount + allowances;
                var deductions = 0m;
                try
                {
                    var taxRes = await mediator.Send(
                        new CalculateTaxQuery(storeId, grossIncome, baseSalary, 0));
                    if (taxRes.IsSuccess && taxRes.Data != null)
                        deductions = taxRes.Data.TotalInsurance + taxRes.Data.TaxAmount;
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "KPI salary tax/insurance estimate failed for employee {EmployeeId}", employeeId);
                }
                var netIncome = grossIncome - deductions;

                // Upsert KpiSalary
                existingSalariesMap2.TryGetValue(employeeId, out var existing);

                if (existing != null)
                {
                    existing.BaseSalary = baseSalary;
                    existing.TotalKpiScore = totalScore;
                    existing.KpiBonusRate = bonusRate;
                    existing.KpiBonusAmount = kpiBonusAmount;
                    existing.Allowances = allowances;
                    existing.Deductions = deductions;
                    existing.GrossIncome = grossIncome;
                    existing.NetIncome = netIncome;
                    existing.UpdatedAt = DateTime.UtcNow;
                    dbContext.KpiSalaries.Update(existing);
                }
                else
                {
                    existing = new KpiSalary
                    {
                        EmployeeId = employeeId,
                        KpiPeriodId = request.PeriodId,
                        BaseSalary = baseSalary,
                        TotalKpiScore = totalScore,
                        KpiBonusRate = bonusRate,
                        KpiBonusAmount = kpiBonusAmount,
                        Allowances = allowances,
                        Deductions = deductions,
                        GrossIncome = grossIncome,
                        NetIncome = netIncome,
                        StoreId = storeId,
                        IsActive = true
                    };
                    dbContext.KpiSalaries.Add(existing);
                }

                salaryResults.Add(new KpiSalaryDto
                {
                    Id = existing.Id,
                    EmployeeId = employeeId,
                    EmployeeCode = employee.EmployeeCode ?? "",
                    EmployeeName = (employee.LastName ?? "") + " " + (employee.FirstName ?? ""),
                    KpiPeriodId = request.PeriodId,
                    BaseSalary = baseSalary,
                    TotalKpiScore = totalScore,
                    KpiBonusRate = bonusRate,
                    KpiBonusAmount = kpiBonusAmount,
                    Allowances = allowances,
                    OtherBonus = existing.OtherBonus,
                    Deductions = deductions,
                    GrossIncome = grossIncome,
                    NetIncome = netIncome,
                    IsApproved = existing.IsApproved
                });
            }

            await dbContext.SaveChangesAsync();

            // Cáº­p nháº­t tráº¡ng thÃ¡i ká»³
            var period = await dbContext.KpiPeriods.FindAsync(request.PeriodId);
            if (period != null && period.Status == KpiPeriodStatus.Locked)
            {
                period.Status = KpiPeriodStatus.Calculated;
                dbContext.KpiPeriods.Update(period);
                await dbContext.SaveChangesAsync();
            }

            // Notify employees about salary calculation (score-based path)
            try
            {
                foreach (var result in salaryResults)
                {
                    var empUserId = await dbContext.Employees
                        .Where(e => e.Id == result.EmployeeId)
                        .Select(e => e.ApplicationUserId)
                        .FirstOrDefaultAsync();
                    if (empUserId.HasValue && empUserId.Value != CurrentUserId)
                    {
                        await notificationService.CreateAndSendAsync(
                            empUserId.Value, NotificationType.Info,
                            "LÆ°Æ¡ng KPI Ä‘Ã£ tÃ­nh",
                            $"LÆ°Æ¡ng KPI cá»§a báº¡n Ä‘Ã£ Ä‘Æ°á»£c tÃ­nh. Vui lÃ²ng kiá»ƒm tra.",
                            relatedEntityType: "KpiSalary",
                            fromUserId: CurrentUserId, categoryCode: "kpi", storeId: RequiredStoreId);
                    }
                }
            }
            catch { /* Notification failure should not affect main operation */ }

            return Ok(AppResponse<List<KpiSalaryDto>>.Success(salaryResults));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to calculate KPI salary");
            return Ok(AppResponse<List<KpiSalaryDto>>.Fail($"Lá»—i tÃ­nh lÆ°Æ¡ng: {ex.Message}"));
        }
    }

    /// <summary>
    /// Láº¥y báº£ng lÆ°Æ¡ng KPI theo ká»³
    /// </summary>
    [HttpGet("salary")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<KpiSalaryDto>>>> GetSalaries([FromQuery] Guid periodId)
    {
        var salaries = await dbContext.KpiSalaries
            .Include(s => s.Employee)
            .Where(s => s.KpiPeriodId == periodId && s.Deleted == null)
            .OrderBy(s => s.Employee.EmployeeCode)
            .Select(s => new KpiSalaryDto
            {
                Id = s.Id,
                EmployeeId = s.EmployeeId,
                EmployeeCode = s.Employee.EmployeeCode ?? "",
                EmployeeName = (s.Employee.LastName ?? "") + " " + (s.Employee.FirstName ?? ""),
                KpiPeriodId = s.KpiPeriodId,
                BaseSalary = s.BaseSalary,
                TotalKpiScore = s.TotalKpiScore,
                KpiBonusRate = s.KpiBonusRate,
                KpiBonusAmount = s.KpiBonusAmount,
                Allowances = s.Allowances,
                OtherBonus = s.OtherBonus,
                Deductions = s.Deductions,
                GrossIncome = s.GrossIncome,
                NetIncome = s.NetIncome,
                IsApproved = s.IsApproved,
                Notes = s.Notes
            })
            .ToListAsync();

        return Ok(AppResponse<List<KpiSalaryDto>>.Success(salaries));
    }

    /// <summary>
    /// Duyá»‡t báº£ng lÆ°Æ¡ng KPI
    /// </summary>
    [HttpPost("salary/approve")]
    [RequireModulePermission("KPI", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<bool>>> ApproveSalaries([FromBody] ApproveSalaryRequest request)
    {
        var salaries = await dbContext.KpiSalaries
            .AsTracking()
            .Where(s => request.SalaryIds.Contains(s.Id))
            .ToListAsync();

        foreach (var salary in salaries)
        {
            salary.IsApproved = true;
            salary.ApprovedByUserId = CurrentUserId;
            salary.ApprovedDate = DateTime.UtcNow;
            salary.UpdatedAt = DateTime.UtcNow;
        }

        dbContext.KpiSalaries.UpdateRange(salaries);
        await dbContext.SaveChangesAsync();

        // Notify employees about salary approval
        try
        {
            var approvedSalaries = await dbContext.KpiSalaries
                .Include(s => s.Employee)
                .Where(s => request.SalaryIds.Contains(s.Id))
                .ToListAsync();
            foreach (var salary in approvedSalaries)
            {
                if (salary.Employee?.ApplicationUserId != null)
                {
                    await notificationService.CreateAndSendAsync(
                        salary.Employee.ApplicationUserId.Value, NotificationType.Success,
                        "LÆ°Æ¡ng KPI Ä‘Ã£ duyá»‡t",
                        $"LÆ°Æ¡ng KPI cá»§a báº¡n Ä‘Ã£ Ä‘Æ°á»£c duyá»‡t",
                        relatedEntityId: salary.Id, relatedEntityType: "KpiSalary",
                        fromUserId: CurrentUserId, categoryCode: "kpi", storeId: RequiredStoreId);
                }
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Xuáº¥t káº¿t quáº£ lÆ°Æ¡ng KPI lÃªn Google Sheet
    /// </summary>
    [HttpPost("salary/export-sheet")]
    [RequireModulePermission("KPI", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> ExportSalaryToSheet([FromBody] ExportSalaryToSheetRequest request)
    {
        try
        {
            var salaries = await dbContext.KpiSalaries
                .Include(s => s.Employee)
                .Where(s => s.KpiPeriodId == request.PeriodId && s.Deleted == null)
                .OrderBy(s => s.Employee.EmployeeCode)
                .ToListAsync();

            var rows = salaries.Select(s => new KpiSalarySheetRow
            {
                EmployeeCode = s.Employee.EmployeeCode ?? "",
                EmployeeName = (s.Employee.LastName ?? "") + " " + (s.Employee.FirstName ?? ""),
                TotalKpiScore = s.TotalKpiScore,
                KpiBonusRate = s.KpiBonusRate,
                BaseSalary = s.BaseSalary,
                KpiBonusAmount = s.KpiBonusAmount,
                GrossIncome = s.GrossIncome,
                NetIncome = s.NetIncome
            }).ToList();

            var ok = await kpiSheetService.WriteKpiSalaryResultsAsync(
                request.SpreadsheetId, request.SheetName, rows);

            return ok
                ? Ok(AppResponse<bool>.Success(true))
                : Ok(AppResponse<bool>.Fail("KhÃ´ng thá»ƒ ghi káº¿t quáº£ lÃªn Google Sheet"));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to export salary to sheet");
            return Ok(AppResponse<bool>.Fail($"Lá»—i xuáº¥t: {ex.Message}"));
        }
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // DASHBOARD / STATS
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Dashboard thá»‘ng kÃª KPI
    /// </summary>
    [HttpGet("dashboard")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<KpiDashboardDto>>> GetDashboard(
        [FromQuery] Guid? periodId,
        [FromQuery] Guid? branchId = null,
        [FromQuery] bool includeChildBranches = true)
    {
        var storeId = CurrentStoreId;
        var query = storeId.HasValue
            ? dbContext.KpiPeriods.Where(p => p.StoreId == storeId.Value)
            : dbContext.KpiPeriods.AsQueryable();

        KpiPeriod? period;
        if (periodId.HasValue)
        {
            period = await query.FirstOrDefaultAsync(p => p.Id == periodId.Value);
        }
        else
        {
            period = await query
                .Where(p => p.Deleted == null)
                .OrderByDescending(p => p.Year).ThenByDescending(p => p.Month)
                .FirstOrDefaultAsync();
        }

        if (period == null)
        {
            return Ok(AppResponse<KpiDashboardDto>.Success(new KpiDashboardDto()));
        }

        var branchScope = storeId.HasValue
            ? await BranchQueryHelper.ResolveEmployeeScopeAsync(
                dbContext, storeId.Value, branchId, includeChildBranches)
            : null;

        var kpiResultsQuery = dbContext.KpiResults
            .Where(r => r.KpiPeriodId == period.Id && r.Deleted == null);
        var kpiSalariesQuery = dbContext.KpiSalaries
            .Where(s => s.KpiPeriodId == period.Id && s.Deleted == null);
        if (branchScope != null)
        {
            if (branchScope.IsEmpty)
            {
                return Ok(AppResponse<KpiDashboardDto>.Success(new KpiDashboardDto
                {
                    CurrentPeriodId = period.Id,
                    CurrentPeriodName = period.Name,
                    PeriodStatus = period.Status,
                    LastSyncedAt = period.LastSyncedAt
                }));
            }
            kpiResultsQuery = kpiResultsQuery.Where(r => branchScope.EmployeeIds.Contains(r.EmployeeId));
            kpiSalariesQuery = kpiSalariesQuery.Where(s => branchScope.EmployeeIds.Contains(s.EmployeeId));
        }

        var kpiResults = await kpiResultsQuery.ToListAsync();
        var kpiSalaries = await kpiSalariesQuery.ToListAsync();

        var totalEmployees = kpiResults.Select(r => r.EmployeeId).Distinct().Count();
        var avgScore = kpiResults.Count > 0
            ? kpiResults.GroupBy(r => r.EmployeeId)
                .Select(g => g.Sum(r => r.WeightedScore))
                .Average()
            : 0;

        var dashboard = new KpiDashboardDto
        {
            CurrentPeriodId = period.Id,
            CurrentPeriodName = period.Name,
            PeriodStatus = period.Status,
            TotalEmployees = totalEmployees,
            TotalKpiConfigs = await dbContext.KpiConfigs.CountAsync(c =>
                (storeId == null || c.StoreId == storeId) && c.Deleted == null),
            AverageKpiScore = avgScore,
            TotalSalaryCalculated = kpiSalaries.Count,
            TotalApproved = kpiSalaries.Count(s => s.IsApproved),
            TotalBonusAmount = kpiSalaries.Sum(s => s.KpiBonusAmount),
            LastSyncedAt = period.LastSyncedAt
        };

        return Ok(AppResponse<KpiDashboardDto>.Success(dashboard));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // KPI EMPLOYEE TARGETS (Thiáº¿t láº­p KPI theo nhÃ¢n viÃªn trong ká»³)
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Láº¥y danh sÃ¡ch thiáº¿t láº­p KPI nhÃ¢n viÃªn cá»§a má»™t ká»³
    /// </summary>
    [HttpGet("employee-targets")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<KpiEmployeeTargetDto>>>> GetEmployeeTargets(
        [FromQuery] Guid periodId)
    {
        var rows = await dbContext.KpiEmployeeTargets
            .Include(t => t.Employee)
            .Where(t => t.KpiPeriodId == periodId && t.Deleted == null)
            .OrderBy(t => t.Employee.EmployeeCode)
            .Select(t => new KpiEmployeeTargetDto
            {
                Id = t.Id,
                EmployeeId = t.EmployeeId,
                EmployeeCode = t.Employee.EmployeeCode ?? "",
                EmployeeName = (t.Employee.LastName ?? "") + " " + (t.Employee.FirstName ?? ""),
                Department = t.Employee.Department,
                KpiPeriodId = t.KpiPeriodId,
                CriteriaType = t.CriteriaType,
                TargetValue = t.TargetValue,
                ActualValue = t.ActualValue,
                CompletionRate = t.CompletionRate,
                CompletionSalary = t.CompletionSalary,
                BonusTiersJson = t.BonusTiersJson,
                PenaltyTiersJson = t.PenaltyTiersJson,
                Notes = t.Notes,
                GoogleSheetUrl = t.GoogleSheetUrl,
                GoogleSheetName = t.GoogleSheetName,
                GoogleCellPosition = t.GoogleCellPosition,
                AutoSyncEnabled = t.AutoSyncEnabled,
                SyncIntervalMinutes = t.SyncIntervalMinutes,
            })
            .ToListAsync();

        return Ok(AppResponse<List<KpiEmployeeTargetDto>>.Success(rows));
    }

    /// <summary>
    /// LÆ°u hÃ ng loáº¡t (upsert) thiáº¿t láº­p KPI nhÃ¢n viÃªn cho má»™t ká»³
    /// </summary>
    [HttpPost("employee-targets/batch")]
    [RequireModulePermission("KPI", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<int>>> SaveEmployeeTargets(
        [FromBody] SaveKpiEmployeeTargetsRequest request)
    {
        var storeId = RequiredStoreId;
        int count = 0;

        // Pre-load all existing targets for this period to avoid N+1
        var employeeIds = request.Targets.Select(t => t.EmployeeId).Distinct().ToList();
        var existingTargets = await dbContext.KpiEmployeeTargets
            .AsTracking()
            .Where(t => t.KpiPeriodId == request.PeriodId &&
                        employeeIds.Contains(t.EmployeeId) &&
                        t.Deleted == null)
            .ToListAsync();
        var existingById = existingTargets.Where(t => true).ToDictionary(t => t.Id);
        var existingByEmployee = existingTargets.ToDictionary(t => t.EmployeeId);

        foreach (var item in request.Targets)
        {
            var completion = (item.TargetValue > 0 && item.ActualValue.HasValue)
                ? Math.Round(item.ActualValue.Value / item.TargetValue * 100m, 2)
                : 0m;

            KpiEmployeeTarget? existing = null;

            if (item.Id.HasValue)
                existingById.TryGetValue(item.Id.Value, out existing);

            if (existing == null)
                existingByEmployee.TryGetValue(item.EmployeeId, out existing);

            if (existing == null)
            {
                dbContext.KpiEmployeeTargets.Add(new KpiEmployeeTarget
                {
                    EmployeeId = item.EmployeeId,
                    KpiPeriodId = request.PeriodId,
                    CriteriaType = item.CriteriaType,
                    TargetValue = item.TargetValue,
                    ActualValue = item.ActualValue,
                    CompletionRate = completion,
                    CompletionSalary = item.CompletionSalary,
                    BonusTiersJson = item.BonusTiersJson,
                    PenaltyTiersJson = item.PenaltyTiersJson,
                    Notes = item.Notes,
                    StoreId = storeId,
                    IsActive = true
                });
            }
            else
            {
                existing.CriteriaType = item.CriteriaType;
                existing.TargetValue = item.TargetValue;
                existing.ActualValue = item.ActualValue;
                existing.CompletionRate = completion;
                existing.CompletionSalary = item.CompletionSalary;
                existing.BonusTiersJson = item.BonusTiersJson;
                existing.PenaltyTiersJson = item.PenaltyTiersJson;
                existing.Notes = item.Notes;
                existing.LastModified = DateTime.UtcNow;
                existing.LastModifiedBy = CurrentUserId.ToString();
            }
            count++;
        }

        await dbContext.SaveChangesAsync();

        // Notify employees about KPI target assignment
        try
        {
            var period = await dbContext.KpiPeriods.FindAsync(request.PeriodId);
            var periodName = period?.Name ?? "";
            var targetEmployees = await dbContext.Employees
                .Where(e => employeeIds.Contains(e.Id) && e.ApplicationUserId != null)
                .Select(e => new { e.Id, e.ApplicationUserId })
                .ToListAsync();
            foreach (var emp in targetEmployees)
            {
                if (emp.ApplicationUserId.HasValue && emp.ApplicationUserId.Value != CurrentUserId)
                {
                    await notificationService.CreateAndSendAsync(
                        emp.ApplicationUserId.Value, NotificationType.Info,
                        "Chá»‰ tiÃªu KPI má»›i",
                        $"Báº¡n Ä‘Æ°á»£c giao chá»‰ tiÃªu KPI cho ká»³: {periodName}",
                        relatedEntityType: "KpiEmployeeTarget",
                        fromUserId: CurrentUserId, categoryCode: "kpi", storeId: RequiredStoreId);
                }
            }
        }
        catch { /* Notification failure should not affect main operation */ }

        return Ok(AppResponse<int>.Success(count));
    }

    /// <summary>
    /// XÃ³a má»™t nhÃ¢n viÃªn khá»i thiáº¿t láº­p KPI cá»§a ká»³ (soft delete)
    /// </summary>
    [HttpDelete("employee-targets/{id}")]
    [RequireModulePermission("KPI", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteEmployeeTarget(Guid id)
    {
        var target = await dbContext.KpiEmployeeTargets.FindAsync(id);
        if (target == null) return NotFound(AppResponse<bool>.Fail("KhÃ´ng tÃ¬m tháº¥y thiáº¿t láº­p KPI"));

        target.Deleted = DateTime.UtcNow;
        target.DeletedBy = CurrentUserId.ToString();
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Äá»“ng bá»™ giÃ¡ trá»‹ thá»±c táº¿ tá»« Google Sheet vÃ o ActualValue cá»§a KpiEmployeeTargets
    /// </summary>
    [HttpPost("employee-targets/sync-actuals")]
    [RequireModulePermission("KPI", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SyncActualsFromSheet(
        [FromBody] SyncActualsFromSheetRequest request)
    {
        try
        {
            var sheetRows = await kpiSheetService.ReadKpiDataAsync(
                request.SpreadsheetId, request.SheetName, null);

            var targets = await dbContext.KpiEmployeeTargets
                .AsTracking()
                .Include(t => t.Employee)
                .Where(t => t.KpiPeriodId == request.PeriodId && t.Deleted == null)
                .ToListAsync();

            int updatedCount = 0;
            foreach (var target in targets)
            {
                var empCode = target.Employee?.EmployeeCode ?? "";
                var row = sheetRows.FirstOrDefault(r =>
                    r.EmployeeCode.Equals(empCode, StringComparison.OrdinalIgnoreCase));
                if (row == null) continue;

                // TÃ¬m cá»™t actual (exact hoáº·c case-insensitive)
                var key = row.KpiValues.Keys.FirstOrDefault(k =>
                    k.Equals(request.ActualColumnName, StringComparison.OrdinalIgnoreCase));
                if (key == null) continue;

                var actualVal = row.KpiValues[key];
                target.ActualValue = actualVal;
                target.CompletionRate = target.TargetValue > 0
                    ? Math.Round(actualVal / target.TargetValue * 100m, 2)
                    : 0m;
                target.LastModified = DateTime.UtcNow;
                target.LastModifiedBy = CurrentUserId.ToString();
                updatedCount++;
            }

            await dbContext.SaveChangesAsync();

            return Ok(AppResponse<object>.Success(new { updatedCount, totalRows = sheetRows.Count }));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to sync actuals from sheet");
            return Ok(AppResponse<object>.Fail($"Lá»—i Ä‘á»“ng bá»™: {ex.Message}"));
        }
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // GOOGLE SHEET CONFIG (PERIOD-LEVEL)
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// LÆ°u cáº¥u hÃ¬nh Google Sheet cho ká»³ (URL + sheet + employee cell mappings + auto-sync)
    /// </summary>
    [HttpPost("gsheet-config/{periodId}")]
    [RequireModulePermission("KPI", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<bool>>> SaveGSheetConfig(
        Guid periodId, [FromBody] SaveGSheetConfigRequest request)
    {
        var period = await dbContext.KpiPeriods.FindAsync(periodId);
        if (period == null)
            return NotFound(AppResponse<bool>.Fail("KhÃ´ng tÃ¬m tháº¥y ká»³"));

        // Save period-level config
        var spreadsheetId = ExtractSpreadsheetId(request.GoogleSheetUrl ?? "");
        period.GoogleSpreadsheetId = spreadsheetId;
        period.GoogleSheetName = request.GoogleSheetName?.Trim();
        period.AutoSyncEnabled = request.AutoSyncEnabled;
        period.AutoSyncTimeSlots = request.AutoSyncTimeSlots;
        period.LastModified = DateTime.UtcNow;
        period.LastModifiedBy = CurrentUserId.ToString();

        // Save employee cell mappings
        if (request.EmployeeMappings != null)
        {
            var targets = await dbContext.KpiEmployeeTargets
                .AsTracking()
                .Where(t => t.KpiPeriodId == periodId && t.Deleted == null)
                .ToListAsync();

            foreach (var mapping in request.EmployeeMappings)
            {
                if (!Guid.TryParse(mapping.EmployeeId, out var empId)) continue;
                var target = targets.FirstOrDefault(t => t.EmployeeId == empId);
                if (target == null) continue;

                target.GoogleSheetUrl = request.GoogleSheetUrl?.Trim();
                target.GoogleSheetName = request.GoogleSheetName?.Trim();
                target.GoogleCellPosition = mapping.CellPosition?.Trim();
                target.LastModified = DateTime.UtcNow;
                target.LastModifiedBy = CurrentUserId.ToString();
            }
        }

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Test káº¿t ná»‘i Google Sheet - kiá»ƒm tra truy cáº­p vÃ  láº¥y tÃªn cÃ¡c sheet
    /// </summary>
    [HttpPost("gsheet-config/test-connection")]
    [RequireModulePermission("KPI", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> TestGSheetConnection(
        [FromBody] TestGSheetConnectionRequest request)
    {
        try
        {
            var spreadsheetId = ExtractSpreadsheetId(request.GoogleSheetUrl ?? "");
            if (string.IsNullOrEmpty(spreadsheetId))
                return Ok(AppResponse<object>.Fail("Link Google Sheet khÃ´ng há»£p lá»‡"));

            var sheetNames = await kpiSheetService.GetSheetNamesAsync(spreadsheetId);
            return Ok(AppResponse<object>.Success(new
            {
                connected = true,
                sheetNames,
                spreadsheetId
            }));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "TestGSheetConnection failed. ExType={ExType}, Message={Msg}", ex.GetType().Name, ex.Message);

            var msg = ex.Message;
            var innerMsg = ex.InnerException?.Message ?? "";
            var fullMsg = $"{msg} {innerMsg}";

            var credsMissing = ex is FileNotFoundException;
            // Only flag notShared for actual 403/permission errors from Google API
            var notShared = !credsMissing &&
                (fullMsg.Contains("403") || fullMsg.Contains("forbidden", StringComparison.OrdinalIgnoreCase)
                || (fullMsg.Contains("permission", StringComparison.OrdinalIgnoreCase) && !fullMsg.Contains("credentials", StringComparison.OrdinalIgnoreCase)));

            // Read service account email to show in error
            string? saEmail = null;
            try
            {
                var credFile = Path.Combine(env.ContentRootPath, "credentials.json");
                if (System.IO.File.Exists(credFile))
                {
                    var json = System.IO.File.ReadAllText(credFile);
                    var doc = System.Text.Json.JsonDocument.Parse(json);
                    if (doc.RootElement.TryGetProperty("client_email", out var ep))
                        saEmail = ep.GetString();
                }
            }
            catch { /* ignore */ }

            return Ok(AppResponse<object>.Success(new
            {
                connected = false,
                notShared,
                credentialsMissing = credsMissing,
                serviceAccountEmail = saEmail,
                rawError = fullMsg,
                error = notShared
                    ? $"Google Sheet chÆ°a Ä‘Æ°á»£c chia sáº» cho service account. Vui lÃ²ng chia sáº» quyá»n Viewer cho: {saEmail ?? "(khÃ´ng rÃµ email)"}"
                    : credsMissing
                        ? "ChÆ°a cáº¥u hÃ¬nh file credentials.json trÃªn server. Vui lÃ²ng liÃªn há»‡ quáº£n trá»‹ viÃªn Ä‘á»ƒ thiáº¿t láº­p Google Service Account."
                        : $"KhÃ´ng thá»ƒ káº¿t ná»‘i: {msg}"
            }));
        }
    }

    /// <summary>
    /// Táº¡o sheet máº«u KPI vá»›i danh sÃ¡ch nhÃ¢n viÃªn trong ká»³
    /// </summary>
    [HttpPost("gsheet-config/{periodId}/create-template")]
    [RequireModulePermission("KPI", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> CreateGSheetTemplate(Guid periodId)
    {
        try
        {
            var period = await dbContext.KpiPeriods.FindAsync(periodId);
            if (period == null)
                return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y chu ká»³"));

            var spreadsheetId = period.GoogleSpreadsheetId;
            var sheetName = period.GoogleSheetName ?? "NhÃ¢n viÃªn";

            if (string.IsNullOrEmpty(spreadsheetId))
                return Ok(AppResponse<object>.Fail("ChÆ°a cáº¥u hÃ¬nh Google Sheet cho chu ká»³ nÃ y. Vui lÃ²ng thiáº¿t láº­p káº¿t ná»‘i trÆ°á»›c."));

            // Láº¥y nhÃ¢n viÃªn cÃ³ chá»‰ tiÃªu trong ká»³
            var targets = await dbContext.KpiEmployeeTargets
                .Include(t => t.Employee)
                .Where(t => t.KpiPeriodId == periodId && t.Deleted == null)
                .ToListAsync();

            List<KpiTemplateEmployee> employees;
            if (targets.Any())
            {
                employees = targets
                    .Where(t => t.Employee != null)
                    .Select(t => new KpiTemplateEmployee
                    {
                        EmployeeCode = t.Employee!.EmployeeCode,
                        EmployeeName = $"{t.Employee.LastName} {t.Employee.FirstName}".Trim()
                    })
                    .DistinctBy(e => e.EmployeeCode)
                    .OrderBy(e => e.EmployeeCode)
                    .ToList();
            }
            else
            {
                // Fallback: láº¥y táº¥t cáº£ nhÃ¢n viÃªn active
                var storeId = RequiredStoreId;
                var allEmployees = await dbContext.Set<Employee>()
                    .Where(e => e.StoreId == storeId && e.Deleted == null && e.IsActive)
                    .OrderBy(e => e.EmployeeCode)
                    .ToListAsync();

                employees = allEmployees.Select(e => new KpiTemplateEmployee
                {
                    EmployeeCode = e.EmployeeCode,
                    EmployeeName = $"{e.LastName} {e.FirstName}".Trim()
                }).ToList();
            }

            await kpiSheetService.CreateKpiTemplateAsync(spreadsheetId, sheetName, employees);

            return Ok(AppResponse<object>.Success(new
            {
                sheetName,
                employeeCount = employees.Count,
                message = $"ÄÃ£ táº¡o sheet máº«u '{sheetName}' vá»›i {employees.Count} nhÃ¢n viÃªn"
            }));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to create GSheet template for period {PeriodId}", periodId);
            return Ok(AppResponse<object>.Fail($"Lá»—i táº¡o template: {ex.Message}"));
        }
    }

    /// <summary>
    /// Kiá»ƒm tra tráº¡ng thÃ¡i credentials.json trÃªn server
    /// </summary>
    [HttpGet("gsheet-config/credentials-status")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public ActionResult<AppResponse<object>> GetCredentialsStatus()
    {
        var credPath = Path.Combine(env.ContentRootPath, "credentials.json");
        var exists = System.IO.File.Exists(credPath);
        string? serviceAccountEmail = null;
        if (exists)
        {
            try
            {
                var json = System.IO.File.ReadAllText(credPath);
                var doc = System.Text.Json.JsonDocument.Parse(json);
                if (doc.RootElement.TryGetProperty("client_email", out var emailProp))
                    serviceAccountEmail = emailProp.GetString();
            }
            catch { /* ignore parse errors */ }
        }
        return Ok(AppResponse<object>.Success(new
        {
            configured = exists,
            serviceAccountEmail,
        }));
    }

    /// <summary>
    /// Upload file credentials.json cho Google Service Account
    /// </summary>
    [HttpPost("gsheet-config/upload-credentials")]
    [RequireModulePermission("KPI", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> UploadCredentials()
    {
        var form = await Request.ReadFormAsync();
        var file = form.Files.GetFile("credentials");
        if (file == null || file.Length == 0)
            return Ok(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y file credentials"));

        // Validate JSON structure
        try
        {
            using var reader = new StreamReader(file.OpenReadStream());
            var content = await reader.ReadToEndAsync();
            var doc = System.Text.Json.JsonDocument.Parse(content);
            var root = doc.RootElement;

            // Must have required fields for a service account key
            if (!root.TryGetProperty("type", out var typeProp)
                || typeProp.GetString() != "service_account")
            {
                return Ok(AppResponse<object>.Fail("File khÃ´ng pháº£i Google Service Account JSON key. Vui lÃ²ng táº£i Ä‘Ãºng file tá»« Google Cloud Console."));
            }

            if (!root.TryGetProperty("client_email", out _)
                || !root.TryGetProperty("private_key", out _))
            {
                return Ok(AppResponse<object>.Fail("File credentials khÃ´ng há»£p lá»‡: thiáº¿u client_email hoáº·c private_key."));
            }

            // Save to credentials.json in ContentRootPath
            var savePath = Path.Combine(env.ContentRootPath, "credentials.json");
            await System.IO.File.WriteAllTextAsync(savePath, content);

            var email = root.TryGetProperty("client_email", out var emailProp2)
                ? emailProp2.GetString() : null;

            logger.LogInformation("Google credentials uploaded successfully. Service account: {Email}", email);

            return Ok(AppResponse<object>.Success(new
            {
                configured = true,
                serviceAccountEmail = email,
                message = "Upload credentials thÃ nh cÃ´ng!"
            }));
        }
        catch (System.Text.Json.JsonException)
        {
            return Ok(AppResponse<object>.Fail("File khÃ´ng pháº£i JSON há»£p lá»‡."));
        }
    }

    /// <summary>
    /// Copy cáº¥u hÃ¬nh GSheet tá»« ká»³ nguá»“n sang ká»³ Ä‘Ã­ch
    /// </summary>
    [HttpPost("gsheet-config/{periodId}/copy-from/{sourcePeriodId}")]
    [RequireModulePermission("KPI", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> CopyGSheetConfig(
        Guid periodId, Guid sourcePeriodId)
    {
        var sourcePeriod = await dbContext.KpiPeriods.FindAsync(sourcePeriodId);
        var destPeriod = await dbContext.KpiPeriods.FindAsync(periodId);
        if (sourcePeriod == null || destPeriod == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y ká»³"));

        // Copy period-level config
        destPeriod.GoogleSpreadsheetId = sourcePeriod.GoogleSpreadsheetId;
        destPeriod.GoogleSheetName = sourcePeriod.GoogleSheetName;
        destPeriod.AutoSyncEnabled = sourcePeriod.AutoSyncEnabled;
        destPeriod.AutoSyncTimeSlots = sourcePeriod.AutoSyncTimeSlots;
        destPeriod.LastModified = DateTime.UtcNow;
        destPeriod.LastModifiedBy = CurrentUserId.ToString();

        // Copy employee cell mappings
        var sourceTargets = await dbContext.KpiEmployeeTargets
            .Where(t => t.KpiPeriodId == sourcePeriodId && t.Deleted == null
                && t.GoogleCellPosition != null)
            .ToListAsync();

        var destTargets = await dbContext.KpiEmployeeTargets
            .AsTracking()
            .Where(t => t.KpiPeriodId == periodId && t.Deleted == null)
            .ToListAsync();

        int copiedCount = 0;
        foreach (var src in sourceTargets)
        {
            var dest = destTargets.FirstOrDefault(t => t.EmployeeId == src.EmployeeId);
            if (dest == null) continue;

            dest.GoogleSheetUrl = src.GoogleSheetUrl;
            dest.GoogleSheetName = src.GoogleSheetName;
            dest.GoogleCellPosition = src.GoogleCellPosition;
            dest.LastModified = DateTime.UtcNow;
            dest.LastModifiedBy = CurrentUserId.ToString();
            copiedCount++;
        }

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { copiedCount, totalSource = sourceTargets.Count }));
    }

    /// <summary>
    /// Äá»“ng bá»™ doanh sá»‘ tá»« Google Sheet. 
    /// Æ¯u tiÃªn Ä‘á»c theo MÃ£ NV + cá»™t "Tá»•ng KPI" tá»« sheet máº«u.
    /// Fallback: Ä‘á»c theo cell position náº¿u cÃ³ cáº¥u hÃ¬nh per-employee.
    /// </summary>
    [HttpPost("sync-actuals/{periodId}")]
    [RequireModulePermission("KPI", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SyncActualsPerEmployee(Guid periodId)
    {
        try
        {
            var period = await dbContext.KpiPeriods.FindAsync(periodId);
            if (period == null)
                return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y chu ká»³"));

            var allTargets = await dbContext.KpiEmployeeTargets
                .AsTracking()
                .Include(t => t.Employee)
                .Where(t => t.KpiPeriodId == periodId && t.Deleted == null)
                .ToListAsync();

            int updatedCount = 0;
            var errors = new List<string>();

            // â”€â”€ Mode 1: Äá»c theo MÃ£ NV (sheet máº«u) â”€â”€
            if (!string.IsNullOrEmpty(period.GoogleSpreadsheetId))
            {
                var sheetName = period.GoogleSheetName ?? "NhÃ¢n viÃªn";
                try
                {
                    var rows = await kpiSheetService.ReadKpiDataAsync(
                        period.GoogleSpreadsheetId, sheetName);

                    // XÃ¡c Ä‘á»‹nh cá»™t Tá»•ng KPI (máº·c Ä‘á»‹nh C náº¿u dÃ¹ng template)
                    string kpiColLetter = "C";
                    if (rows.Count > 0)
                    {
                        var firstRow = rows[0];
                        int colOffset = 0;
                        foreach (var key in firstRow.KpiValues.Keys)
                        {
                            if (key.Contains("Tá»•ng KPI", StringComparison.OrdinalIgnoreCase)
                                || key.Contains("KPI", StringComparison.OrdinalIgnoreCase))
                            {
                                // TÃ­nh cá»™t: skip MÃ£ NV(A) + TÃªn NV(B) + offset
                                kpiColLetter = GetColumnLetter(2 + colOffset); // 0=A,1=B,2=C
                                break;
                            }
                            colOffset++;
                        }
                    }

                    var sheetUrl = $"https://docs.google.com/spreadsheets/d/{period.GoogleSpreadsheetId}";

                    // Debug: log mÃ£ NV tá»« sheet vÃ  tá»« DB
                    var sheetCodes = rows.Select(r => r.EmployeeCode).ToList();
                    var dbCodes = allTargets.Where(t => t.Employee != null).Select(t => t.Employee!.EmployeeCode).ToList();
                    logger.LogWarning("[SYNC] Sheet codes: [{SheetCodes}]", string.Join(", ", sheetCodes));
                    logger.LogWarning("[SYNC] DB codes: [{DbCodes}]", string.Join(", ", dbCodes));

                    foreach (var row in rows)
                    {
                        // TÃ¬m target theo mÃ£ NV (normalize cáº£ 2 phÃ­a)
                        var sheetCode = row.EmployeeCode.Trim();
                        var target = allTargets.FirstOrDefault(t =>
                            t.Employee != null &&
                            NormalizeEmployeeCode(t.Employee.EmployeeCode ?? "").Equals(sheetCode, StringComparison.OrdinalIgnoreCase));

                        if (target == null) continue;

                        // Auto-map cell position: cá»™t KPI + dÃ²ng trong sheet
                        var cellPos = $"{kpiColLetter}{row.RowIndex}";
                        target.GoogleCellPosition = cellPos;
                        target.GoogleSheetUrl = sheetUrl;
                        target.GoogleSheetName = sheetName;

                        // Äá»c cá»™t "Tá»•ng KPI"
                        decimal? kpiValue = null;
                        foreach (var key in row.KpiValues.Keys)
                        {
                            if (key.Contains("Tá»•ng KPI", StringComparison.OrdinalIgnoreCase)
                                || key.Contains("TongKPI", StringComparison.OrdinalIgnoreCase)
                                || key.Contains("Total KPI", StringComparison.OrdinalIgnoreCase)
                                || key.Contains("KPI", StringComparison.OrdinalIgnoreCase))
                            {
                                kpiValue = row.KpiValues[key];
                                break;
                            }
                        }
                        // Fallback: láº¥y giÃ¡ trá»‹ Ä‘áº§u tiÃªn náº¿u chá»‰ cÃ³ 1 cá»™t sá»‘
                        kpiValue ??= row.KpiValues.Values.FirstOrDefault();

                        if (kpiValue.HasValue)
                        {
                            target.ActualValue = kpiValue.Value;
                            target.CompletionRate = target.TargetValue > 0
                                ? Math.Round(kpiValue.Value / target.TargetValue * 100m, 2)
                                : 0m;
                        }
                        target.LastModified = DateTime.UtcNow;
                        target.LastModifiedBy = CurrentUserId.ToString();
                        updatedCount++;
                    }

                    if (updatedCount > 0)
                    {
                        period.LastSyncedAt = DateTime.UtcNow;
                        await dbContext.SaveChangesAsync();
                        return Ok(AppResponse<object>.Success(new
                        {
                            updatedCount,
                            totalTargets = allTargets.Count,
                            mode = "code_lookup",
                            errors,
                            debug_sheetCodes = sheetCodes,
                            debug_dbCodes = dbCodes
                        }));
                    }
                    else
                    {
                        // KhÃ´ng match Ä‘Æ°á»£c â†’ tráº£ debug info
                        errors.Add($"Äá»c Ä‘Æ°á»£c {rows.Count} dÃ²ng tá»« sheet nhÆ°ng khÃ´ng match mÃ£ NV nÃ o.");
                        errors.Add($"Sheet codes: [{string.Join(", ", sheetCodes)}]");
                        errors.Add($"DB codes: [{string.Join(", ", dbCodes)}]");
                    }
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "Code-based sync failed, falling back to cell-based sync");
                    errors.Add($"Äá»c theo mÃ£ NV tháº¥t báº¡i: {ex.Message}");
                }
            }

            // â”€â”€ Mode 2: Fallback - Ä‘á»c theo cell position â”€â”€
            var cellTargets = allTargets
                .Where(t => t.GoogleSheetUrl != null && t.GoogleCellPosition != null)
                .ToList();

            foreach (var target in cellTargets)
            {
                try
                {
                    var spreadsheetId = ExtractSpreadsheetId(target.GoogleSheetUrl!);
                    if (string.IsNullOrEmpty(spreadsheetId)) continue;

                    var sheetName = target.GoogleSheetName ?? "Sheet1";
                    var cellPos = target.GoogleCellPosition!;
                    var range = $"{sheetName}!{cellPos}";

                    var val = await kpiSheetService.ReadCellValueAsync(spreadsheetId, range);
                    if (val.HasValue && val.Value > 0)
                    {
                        target.ActualValue = val.Value;
                        target.CompletionRate = target.TargetValue > 0
                            ? Math.Round(val.Value / target.TargetValue * 100m, 2)
                            : 0m;
                        target.LastModified = DateTime.UtcNow;
                        target.LastModifiedBy = CurrentUserId.ToString();
                        updatedCount++;
                    }
                }
                catch (Exception ex)
                {
                    var empName = (target.Employee?.LastName ?? "") + " " + (target.Employee?.FirstName ?? "");
                    errors.Add($"{empName}: {ex.Message}");
                }
            }

            period.LastSyncedAt = DateTime.UtcNow;
            await dbContext.SaveChangesAsync();
            return Ok(AppResponse<object>.Success(new { updatedCount, totalTargets = allTargets.Count, mode = "cell_position", errors }));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to sync actuals per employee");
            return Ok(AppResponse<object>.Fail($"Lá»—i Ä‘á»“ng bá»™: {ex.Message}"));
        }
    }

    /// <summary>
    /// Import doanh sá»‘ tá»« Excel - nháº­n JSON array [{employeeCode, actualValue}]
    /// </summary>
    [HttpPost("import-actuals/{periodId}")]
    [RequireModulePermission("KPI", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> ImportActualsFromExcel(
        Guid periodId, [FromBody] List<ImportActualDto> data)
    {
        if (data == null || data.Count == 0)
            return Ok(AppResponse<object>.Fail("KhÃ´ng cÃ³ dá»¯ liá»‡u import"));

        var targets = await dbContext.KpiEmployeeTargets
            .AsTracking()
            .Include(t => t.Employee)
            .Where(t => t.KpiPeriodId == periodId && t.Deleted == null)
            .ToListAsync();

        int updatedCount = 0;
        var errors = new List<string>();

        foreach (var item in data)
        {
            if (string.IsNullOrWhiteSpace(item.EmployeeCode)) continue;

            var normalizedCode = NormalizeEmployeeCode(item.EmployeeCode);
            var target = targets.FirstOrDefault(t =>
                t.Employee != null &&
                NormalizeEmployeeCode(t.Employee.EmployeeCode ?? "")
                    .Equals(normalizedCode, StringComparison.OrdinalIgnoreCase));

            if (target == null)
            {
                errors.Add($"KhÃ´ng tÃ¬m tháº¥y NV '{item.EmployeeCode}'");
                continue;
            }

            target.ActualValue = (decimal)item.ActualValue;
            target.CompletionRate = target.TargetValue > 0
                ? Math.Round((decimal)item.ActualValue / target.TargetValue * 100, 2) : 0;
            target.LastModifiedBy = "excel-import";
            updatedCount++;
        }

        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new
        {
            updatedCount,
            totalRows = data.Count,
            errors = errors.Take(10).ToList()
        }));
    }

    /// <summary>
    /// Táº£i file máº«u Excel cho ká»³
    /// </summary>
    [HttpGet("excel-template/{periodId}")]
    [RequireModulePermission("KPI", ModulePermissionAction.View)]
    public async Task<IActionResult> DownloadExcelTemplate(Guid periodId)
    {
        var targets = await dbContext.KpiEmployeeTargets
            .Include(t => t.Employee)
            .Where(t => t.KpiPeriodId == periodId && t.Deleted == null)
            .OrderBy(t => t.Employee.EmployeeCode)
            .ToListAsync();

        // Táº¡o CSV Ä‘Æ¡n giáº£n lÃ m template
        var sb = new System.Text.StringBuilder();
        sb.AppendLine("MÃ£ NV,TÃªn nhÃ¢n viÃªn,Doanh sá»‘ thá»±c táº¿");
        foreach (var t in targets)
        {
            var empCode = t.Employee?.EmployeeCode ?? "";
            var empName = (t.Employee?.LastName ?? "") + " " + (t.Employee?.FirstName ?? "");
            sb.AppendLine($"{empCode},{empName},");
        }

        var bytes = System.Text.Encoding.UTF8.GetPreamble()
            .Concat(System.Text.Encoding.UTF8.GetBytes(sb.ToString())).ToArray();
        return File(bytes, "text/csv", $"KPI_Template_{periodId:N}.csv");
    }

    private static string? ExtractSpreadsheetId(string url)
    {
        if (string.IsNullOrWhiteSpace(url)) return null;
        // If already just an ID
        if (!url.Contains('/')) return url;
        // Extract from URL like https://docs.google.com/spreadsheets/d/SPREADSHEET_ID/edit
        var match = System.Text.RegularExpressions.Regex.Match(url, @"/d/([a-zA-Z0-9_-]+)");
        return match.Success ? match.Groups[1].Value : null;
    }

    /// <summary>
    /// Ghi chá»‰ tiÃªu (targetValue) cá»§a tá»«ng nhÃ¢n viÃªn xuá»‘ng cá»™t D Google Sheet
    /// </summary>
    [HttpPost("gsheet-config/{periodId}/write-targets")]
    [RequireModulePermission("KPI", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> WriteTargetsToGSheet(Guid periodId)
    {
        try
        {
            var period = await dbContext.KpiPeriods.FindAsync(periodId);
            if (period == null)
                return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y chu ká»³"));

            var spreadsheetId = period.GoogleSpreadsheetId;
            var sheetName = period.GoogleSheetName ?? "NhÃ¢n viÃªn";

            if (string.IsNullOrEmpty(spreadsheetId))
                return Ok(AppResponse<object>.Fail("ChÆ°a cáº¥u hÃ¬nh Google Sheet cho chu ká»³ nÃ y."));

            // Äá»c dá»¯ liá»‡u sheet Ä‘á»ƒ match mÃ£ NV
            var rows = await kpiSheetService.ReadKpiDataAsync(spreadsheetId, sheetName);
            if (rows.Count == 0)
                return Ok(AppResponse<object>.Fail("Sheet trá»‘ng, hÃ£y táº¡o template trÆ°á»›c."));

            var targets = await dbContext.KpiEmployeeTargets
                .Include(t => t.Employee)
                .Where(t => t.KpiPeriodId == periodId && t.Deleted == null)
                .ToListAsync();

            // Ghi header cá»™t D
            var headerValues = new List<IList<object>> { new List<object> { "Chá»‰ tiÃªu" } };
            await kpiSheetService.WriteCellRangeAsync(spreadsheetId, $"{sheetName}!D1", headerValues);

            int writtenCount = 0;
            var errors = new List<string>();

            foreach (var row in rows)
            {
                var sheetCode = row.EmployeeCode.Trim();
                var target = targets.FirstOrDefault(t =>
                    t.Employee != null &&
                    NormalizeEmployeeCode(t.Employee.EmployeeCode ?? "")
                        .Equals(NormalizeEmployeeCode(sheetCode), StringComparison.OrdinalIgnoreCase));

                if (target == null)
                {
                    errors.Add($"KhÃ´ng tÃ¬m tháº¥y chá»‰ tiÃªu cho mÃ£ NV '{sheetCode}'");
                    continue;
                }

                var cellRange = $"{sheetName}!D{row.RowIndex}";
                var cellValues = new List<IList<object>> { new List<object> { (double)target.TargetValue } };
                await kpiSheetService.WriteCellRangeAsync(spreadsheetId, cellRange, cellValues);
                writtenCount++;
            }

            return Ok(AppResponse<object>.Success(new
            {
                writtenCount,
                totalRows = rows.Count,
                errors,
                message = $"ÄÃ£ ghi chá»‰ tiÃªu cho {writtenCount}/{rows.Count} nhÃ¢n viÃªn vÃ o cá»™t D"
            }));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to write targets to GSheet for period {PeriodId}", periodId);
            return Ok(AppResponse<object>.Fail($"Lá»—i ghi chá»‰ tiÃªu: {ex.Message}"));
        }
    }

    private static string GetColumnLetter(int colIndex)
    {
        var result = "";
        while (colIndex >= 0)
        {
            result = (char)('A' + colIndex % 26) + result;
            colIndex = colIndex / 26 - 1;
        }
        return result;
    }

    private static string NormalizeEmployeeCode(string code)
    {
        if (string.IsNullOrWhiteSpace(code)) return "";
        // Loáº¡i bá» .0, khoáº£ng tráº¯ng
        if (double.TryParse(code, System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out var num))
            return ((long)num).ToString();
        return code.Trim();
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // HELPER METHODS
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    private static KpiConfigDto MapConfigToDto(KpiConfig c) => new()
    {
        Id = c.Id,
        Code = c.Code,
        Name = c.Name,
        Description = c.Description,
        Type = c.Type,
        Unit = c.Unit,
        Weight = c.Weight,
        TargetValue = c.TargetValue,
        MinValue = c.MinValue,
        MaxValue = c.MaxValue,
        Frequency = c.Frequency,
        GoogleSheetColumnName = c.GoogleSheetColumnName,
        SortOrder = c.SortOrder,
        IsActive = c.IsActive
    };

    private static KpiPeriodDto MapPeriodToDto(KpiPeriod p) => new()
    {
        Id = p.Id,
        Name = p.Name,
        Year = p.Year,
        Month = p.Month,
        Quarter = p.Quarter,
        PeriodStart = p.PeriodStart,
        PeriodEnd = p.PeriodEnd,
        Frequency = p.Frequency,
        Status = p.Status,
        GoogleSpreadsheetId = p.GoogleSpreadsheetId,
        GoogleSheetName = p.GoogleSheetName,
        LastSyncedAt = p.LastSyncedAt,
        Notes = p.Notes
    };

    /// <summary>TÃ­nh thÆ°á»Ÿng vÆ°á»£t chá»‰ tiÃªu theo cáº¥u trÃºc band</summary>
    private static decimal CalcBandedBonus(KpiEmployeeTarget target)
    {
        if (!target.ActualValue.HasValue || target.TargetValue == 0) return 0;
        var act = target.ActualValue.Value;
        var tgt = target.TargetValue;
        var pct = act / tgt * 100m;
        if (pct < 100m) return 0;

        var bonus = target.CompletionSalary; // lÆ°Æ¡ng cá»‘ Ä‘á»‹nh khi Ä‘áº¡t 100%
        if (string.IsNullOrWhiteSpace(target.BonusTiersJson)) return bonus;

        try
        {
            var tiers = System.Text.Json.JsonSerializer.Deserialize<List<BandTier>>(
                target.BonusTiersJson,
                new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (tiers == null) return bonus;

            foreach (var band in tiers)
            {
                var fromVal = tgt * (decimal)band.FromPct / 100m;
                var toVal = band.ToPct < 0 ? act : tgt * (decimal)band.ToPct / 100m;
                if (act <= fromVal) continue;

                if (band.RateType == 2)
                {
                    // GiÃ¡ trá»‹ VNÄ cá»‘ Ä‘á»‹nh
                    bonus += band.Rate;
                }
                else if (band.RateType == 3)
                {
                    // % lÆ°Æ¡ng hoÃ n thÃ nh
                    bonus += Math.Round(target.CompletionSalary * band.Rate / 100m, 0);
                }
                else
                {
                    var inBand = Math.Min(act, toVal) - fromVal;
                    if (inBand <= 0) continue;
                    bonus += band.RateType == 1
                        ? inBand * band.Rate / 100m   // % giÃ¡ trá»‹ vÆ°á»£t
                        : inBand * band.Rate;          // Ä‘/Ä‘Æ¡n vá»‹ cá»‘ Ä‘á»‹nh
                }
            }
        }
        catch { /* Json parse failed, tráº£ vá» completionSalary */ }

        return bonus;
    }

    /// <summary>TÃ­nh thÆ°á»Ÿng/pháº¡t khi chÆ°a Ä‘áº¡t 100% theo PenaltyTiersJson</summary>
    private static decimal CalcPenaltyBonus(KpiEmployeeTarget target, decimal pct)
    {
        if (string.IsNullOrWhiteSpace(target.PenaltyTiersJson)) return 0;

        try
        {
            var tiers = System.Text.Json.JsonSerializer.Deserialize<List<BandTier>>(
                target.PenaltyTiersJson,
                new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (tiers == null) return 0;

            // TÃ¬m band chá»©a pct hiá»‡n táº¡i, Ã¡p dá»¥ng rate
            foreach (var band in tiers)
            {
                var fromPct = (decimal)band.FromPct;
                var toPct = band.ToPct < 0 ? 100m : (decimal)band.ToPct;
                if (pct >= fromPct && pct < toPct)
                {
                    // rate < 0 = pháº¡t, rate > 0 = thÆ°á»Ÿng
                    // rateType 1 = % cá»§a CompletionSalary, rateType 0 = sá»‘ tiá»n cá»‘ Ä‘á»‹nh
                    return band.RateType == 1
                        ? Math.Round(target.CompletionSalary * band.Rate / 100m, 0)
                        : band.Rate;
                }
            }
        }
        catch { /* ignore */ }

        return 0;
    }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// DTOs
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

public class KpiConfigDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public string? Description { get; set; }
    public KpiType Type { get; set; }
    public string? Unit { get; set; }
    public decimal Weight { get; set; }
    public decimal TargetValue { get; set; }
    public decimal? MinValue { get; set; }
    public decimal? MaxValue { get; set; }
    public KpiFrequency Frequency { get; set; }
    public string? GoogleSheetColumnName { get; set; }
    public int SortOrder { get; set; }
    public bool IsActive { get; set; }
}

public class KpiPeriodDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = "";
    public int Year { get; set; }
    public int? Month { get; set; }
    public int? Quarter { get; set; }
    public DateTime PeriodStart { get; set; }
    public DateTime PeriodEnd { get; set; }
    public KpiFrequency Frequency { get; set; }
    public KpiPeriodStatus Status { get; set; }
    public string? GoogleSpreadsheetId { get; set; }
    public string? GoogleSheetName { get; set; }
    public DateTime? LastSyncedAt { get; set; }
    public bool AutoSyncEnabled { get; set; }
    public string? AutoSyncTimeSlots { get; set; }
    public string? Notes { get; set; }
    public int ResultCount { get; set; }
    public int SalaryCount { get; set; }
}

public class KpiBonusRuleDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = "";
    public decimal MinScore { get; set; }
    public decimal MaxScore { get; set; }
    public decimal BonusRate { get; set; }
    public string? Description { get; set; }
    public int SortOrder { get; set; }
}

public class KpiResultDto
{
    public Guid Id { get; set; }
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = "";
    public string EmployeeName { get; set; } = "";
    public Guid KpiConfigId { get; set; }
    public string KpiConfigName { get; set; } = "";
    public Guid KpiPeriodId { get; set; }
    public decimal ActualValue { get; set; }
    public decimal TargetValue { get; set; }
    public decimal CompletionRate { get; set; }
    public decimal WeightedScore { get; set; }
    public string? Notes { get; set; }
    public string Source { get; set; } = "";
}

public class KpiSalaryDto
{
    public Guid Id { get; set; }
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = "";
    public string EmployeeName { get; set; } = "";
    public Guid KpiPeriodId { get; set; }
    public decimal BaseSalary { get; set; }
    public decimal TotalKpiScore { get; set; }
    public decimal KpiBonusRate { get; set; }
    public decimal KpiBonusAmount { get; set; }
    public decimal Allowances { get; set; }
    public decimal OtherBonus { get; set; }
    public decimal Deductions { get; set; }
    public decimal GrossIncome { get; set; }
    public decimal NetIncome { get; set; }
    public bool IsApproved { get; set; }
    public string? Notes { get; set; }
}

public class KpiDashboardDto
{
    public Guid? CurrentPeriodId { get; set; }
    public string? CurrentPeriodName { get; set; }
    public KpiPeriodStatus? PeriodStatus { get; set; }
    public int TotalEmployees { get; set; }
    public int TotalKpiConfigs { get; set; }
    public decimal AverageKpiScore { get; set; }
    public int TotalSalaryCalculated { get; set; }
    public int TotalApproved { get; set; }
    public decimal TotalBonusAmount { get; set; }
    public DateTime? LastSyncedAt { get; set; }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// REQUEST MODELS
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

public class CreateKpiConfigRequest
{
    public string Code { get; set; } = "";
    public string Name { get; set; } = "";
    public string? Description { get; set; }
    public KpiType Type { get; set; }
    public string? Unit { get; set; }
    public decimal Weight { get; set; }
    public decimal TargetValue { get; set; }
    public decimal? MinValue { get; set; }
    public decimal? MaxValue { get; set; }
    public KpiFrequency Frequency { get; set; }
    public string? GoogleSheetColumnName { get; set; }
    public int SortOrder { get; set; }
}

public class CreateKpiPeriodRequest
{
    public string Name { get; set; } = "";
    public int Year { get; set; }
    public int? Month { get; set; }
    public int? Quarter { get; set; }
    public DateTime PeriodStart { get; set; }
    public DateTime PeriodEnd { get; set; }
    public KpiFrequency Frequency { get; set; }
    public string? GoogleSpreadsheetId { get; set; }
    public string? GoogleSheetName { get; set; }
    public string? Notes { get; set; }
}

public class UpdateStatusRequest
{
    public KpiPeriodStatus Status { get; set; }
}

public class SaveKpiBonusRuleRequest
{
    public string Name { get; set; } = "";
    public decimal MinScore { get; set; }
    public decimal MaxScore { get; set; }
    public decimal BonusRate { get; set; }
    public string? Description { get; set; }
}

public class SaveKpiResultsRequest
{
    public Guid PeriodId { get; set; }
    public List<KpiResultItem> Results { get; set; } = new();
}

public class KpiResultItem
{
    public Guid EmployeeId { get; set; }
    public Guid KpiConfigId { get; set; }
    public decimal ActualValue { get; set; }
    public string? Notes { get; set; }
}

public class SyncKpiFromSheetRequest
{
    public string SpreadsheetId { get; set; } = "";
    public string SheetName { get; set; } = "";
    public Guid PeriodId { get; set; }
}

public class CalculateKpiSalaryRequest
{
    public Guid PeriodId { get; set; }
}

public class ApproveSalaryRequest
{
    public List<Guid> SalaryIds { get; set; } = new();
}

public class ExportSalaryToSheetRequest
{
    public string SpreadsheetId { get; set; } = "";
    public string SheetName { get; set; } = "";
    public Guid PeriodId { get; set; }
}

public class SyncKpiResult
{
    public bool Success { get; set; }
    public int TotalRows { get; set; }
    public int ProcessedEmployees { get; set; }
    public int CreatedCount { get; set; }
    public int UpdatedCount { get; set; }
    public List<string> SkippedRows { get; set; } = new();
}

public class KpiEmployeeTargetDto
{
    public Guid Id { get; set; }
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = "";
    public string EmployeeName { get; set; } = "";
    public string? Department { get; set; }
    public Guid KpiPeriodId { get; set; }
    public int CriteriaType { get; set; }
    public decimal TargetValue { get; set; }
    public decimal? ActualValue { get; set; }
    public decimal CompletionRate { get; set; }
    public decimal CompletionSalary { get; set; }
    public string? BonusTiersJson { get; set; }
    public string? PenaltyTiersJson { get; set; }
    public string? Notes { get; set; }
    // Google Sheet config
    public string? GoogleSheetUrl { get; set; }
    public string? GoogleSheetName { get; set; }
    public string? GoogleCellPosition { get; set; }
    public bool AutoSyncEnabled { get; set; }
    public int SyncIntervalMinutes { get; set; }
}

public class SaveKpiEmployeeTargetsRequest
{
    public Guid PeriodId { get; set; }
    public List<KpiEmployeeTargetItem> Targets { get; set; } = new();
}

public class SyncActualsFromSheetRequest
{
    public Guid PeriodId { get; set; }
    public string SpreadsheetId { get; set; } = "";
    public string SheetName { get; set; } = "";
    public string CodeColumnName { get; set; } = "MÃ£ NV";
    public string ActualColumnName { get; set; } = "";
}

public class BandTier
{
    public double FromPct { get; set; }
    public double ToPct { get; set; }  // -1 = khÃ´ng giá»›i háº¡n
    public decimal Rate { get; set; }
    public int RateType { get; set; }  // 0 = cá»‘ Ä‘á»‹nh Ä‘/Ä‘vt, 1 = % giÃ¡ trá»‹ vÆ°á»£t, 2 = VNÄ cá»‘ Ä‘á»‹nh, 3 = % lÆ°Æ¡ng hoÃ n thÃ nh
}

public class KpiEmployeeTargetItem
{
    public Guid? Id { get; set; }
    public Guid EmployeeId { get; set; }
    public int CriteriaType { get; set; }
    public decimal TargetValue { get; set; }
    public decimal? ActualValue { get; set; }
    public decimal CompletionSalary { get; set; }
    public string? BonusTiersJson { get; set; }
    public string? PenaltyTiersJson { get; set; }
    public string? Notes { get; set; }
}

public class SaveGSheetConfigRequest
{
    public string? GoogleSheetUrl { get; set; }
    public string? GoogleSheetName { get; set; }
    public bool AutoSyncEnabled { get; set; }
    public string? AutoSyncTimeSlots { get; set; }
    public List<EmployeeCellMapping>? EmployeeMappings { get; set; }
}

public class EmployeeCellMapping
{
    public string EmployeeId { get; set; } = "";
    public string? CellPosition { get; set; }
}

public class TestGSheetConnectionRequest
{
    public string? GoogleSheetUrl { get; set; }
}

public class ImportActualDto
{
    public string EmployeeCode { get; set; } = "";
    public double ActualValue { get; set; }
}
