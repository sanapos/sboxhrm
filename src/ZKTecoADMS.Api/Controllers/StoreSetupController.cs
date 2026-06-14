using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Tạo / xóa mẫu thiết lập (phòng ban, ca, phạt, phụ cấp, ngày lễ) — không bao gồm demo 10 NV.
/// </summary>
[ApiController]
[Route("api/store-setup")]
[Authorize]
public class StoreSetupController(
    ZKTecoDbContext dbContext,
    IRepository<Department> departmentRepository,
    IRepository<ShiftTemplate> shiftTemplateRepository,
    IRepository<Holiday> holidayRepository,
    IRepository<PenaltySetting> penaltySettingRepository,
    IRepository<Allowance> allowanceRepository,
    IRepository<Permission> permissionRepository,
    IRepository<RolePermission> rolePermissionRepository,
    ILogger<StoreSetupController> logger) : AuthenticatedControllerBase
{
    static readonly string[] SetupMarkers = StoreDefaultSetupSeeder.SetupCreatedByMarkers;

    /// <summary>
    /// Tạo mẫu thiết lập còn thiếu (không ghi đè nếu đã có dữ liệu).
    /// </summary>
    [HttpPost("seed-defaults")]
    [RequireModulePermission("SystemSettings", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<StoreSetupSeedResult>>> SeedDefaults(CancellationToken ct)
    {
        try
        {
            var storeId = RequiredStoreId;
            var store = await dbContext.Stores
                .AsNoTracking()
                .FirstOrDefaultAsync(s => s.Id == storeId, ct);
            if (store?.OwnerId == null)
            {
                return Ok(AppResponse<StoreSetupSeedResult>.Error(
                    "Chưa có tài khoản quản trị cửa hàng. Không thể tạo mẫu ca làm việc."));
            }

            var result = await StoreDefaultSetupSeeder.SeedAllIfEmptyAsync(
                storeId,
                store.OwnerId.Value,
                departmentRepository,
                shiftTemplateRepository,
                holidayRepository,
                penaltySettingRepository,
                allowanceRepository,
                permissionRepository,
                rolePermissionRepository,
                "StoreSetup",
                ct);

            return Ok(AppResponse<StoreSetupSeedResult>.Success(result));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Seed store setup defaults failed");
            return StatusCode(500, AppResponse<StoreSetupSeedResult>.Fail(ex.Message));
        }
    }

    /// <summary>
    /// Xóa mẫu thiết lập (CreatedBy Register / StoreSetup). Không xóa dữ liệu demo SampleData.
    /// </summary>
    [HttpDelete("delete-defaults")]
    [RequireModulePermission("SystemSettings", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<StoreSetupDeleteResult>>> DeleteDefaults(CancellationToken ct)
    {
        try
        {
            var storeId = RequiredStoreId;

            var departments = await dbContext.Departments
                .Where(d => d.StoreId == storeId
                    && d.CreatedBy != null
                    && SetupMarkers.Contains(d.CreatedBy))
                .ToListAsync(ct);

            var deptIds = departments.Select(d => d.Id).ToHashSet();
            var usedDeptIds = await dbContext.Employees
                .Where(e => e.StoreId == storeId
                    && e.Deleted == null
                    && e.DepartmentId.HasValue
                    && deptIds.Contains(e.DepartmentId.Value))
                .Select(e => e.DepartmentId!.Value)
                .Distinct()
                .ToListAsync(ct);
            departments = departments.Where(d => !usedDeptIds.Contains(d.Id)).ToList();

            var shiftTemplates = await dbContext.ShiftTemplates
                .Where(s => s.StoreId == storeId
                    && s.CreatedBy != null
                    && SetupMarkers.Contains(s.CreatedBy))
                .ToListAsync(ct);

            var holidays = await dbContext.Holidays
                .Where(h => h.StoreId == storeId
                    && h.CreatedBy != null
                    && SetupMarkers.Contains(h.CreatedBy))
                .ToListAsync(ct);

            var allowances = await dbContext.Allowances
                .Where(a => a.StoreId == storeId
                    && a.CreatedBy != null
                    && SetupMarkers.Contains(a.CreatedBy))
                .ToListAsync(ct);

            var penalties = await dbContext.PenaltySettings
                .Where(p => p.StoreId == storeId
                    && p.CreatedBy != null
                    && SetupMarkers.Contains(p.CreatedBy))
                .ToListAsync(ct);

            if (departments.Count == 0 && shiftTemplates.Count == 0 && holidays.Count == 0
                && allowances.Count == 0 && penalties.Count == 0)
            {
                return Ok(AppResponse<StoreSetupDeleteResult>.Error(
                    "Không tìm thấy mẫu thiết lập để xóa (hoặc phòng ban đang có nhân viên)."));
            }

            dbContext.Departments.RemoveRange(departments);
            dbContext.ShiftTemplates.RemoveRange(shiftTemplates);
            dbContext.Holidays.RemoveRange(holidays);
            dbContext.Allowances.RemoveRange(allowances);
            dbContext.PenaltySettings.RemoveRange(penalties);
            await dbContext.SaveChangesAsync(ct);

            var result = new StoreSetupDeleteResult(
                $"Đã xóa mẫu thiết lập: {departments.Count} phòng ban, {shiftTemplates.Count} ca, " +
                $"{allowances.Count} phụ cấp, {penalties.Count} thiết lập phạt, {holidays.Count} ngày lễ.",
                departments.Count,
                shiftTemplates.Count,
                holidays.Count,
                allowances.Count,
                penalties.Count);

            return Ok(AppResponse<StoreSetupDeleteResult>.Success(result));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Delete store setup defaults failed");
            return StatusCode(500, AppResponse<StoreSetupDeleteResult>.Fail(ex.Message));
        }
    }
}
