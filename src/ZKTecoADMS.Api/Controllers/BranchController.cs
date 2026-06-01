using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// API Controller quáº£n lÃ½ chi nhÃ¡nh
/// </summary>
[ApiController]
[Route("api/branches")]
[Authorize]
public class BranchController(
    ZKTecoDbContext dbContext,
    IDataScopeService dataScopeService,
    ILogger<BranchController> logger)
    : AuthenticatedControllerBase
{
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // Láº¤Y DANH SÃCH
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Láº¥y danh sÃ¡ch chi nhÃ¡nh (flat list)
    /// </summary>
    [HttpGet]
    [RequireModulePermission("Branch", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<BranchDto>>>> GetBranches(
        [FromQuery] string? search,
        [FromQuery] bool? isActive)
    {
        var storeId = CurrentStoreId;

        // PhÃ¢n quyá»n: Admin tháº¥y táº¥t cáº£; Manager/Manager chi nhÃ¡nh chá»‰ tháº¥y CN quáº£n lÃ½
        List<Guid>? allowedBranchIds = null;
        if (!IsAdmin && storeId.HasValue)
            allowedBranchIds = await dataScopeService.GetManagedBranchIdsAsync(CurrentUserId, storeId.Value);

        var query = dbContext.Branches
            .Include(b => b.Manager)
            .Include(b => b.ParentBranch)
            .Where(b => b.Deleted == null);

        if (storeId.HasValue)
            query = query.Where(b => b.StoreId == storeId.Value);

        if (allowedBranchIds != null)
            query = query.Where(b => allowedBranchIds.Contains(b.Id));

        if (!string.IsNullOrWhiteSpace(search))
            query = query.Where(b =>
                b.Name.Contains(search) ||
                b.Code.Contains(search) ||
                (b.Address != null && b.Address.Contains(search)) ||
                (b.City != null && b.City.Contains(search)));

        if (isActive.HasValue)
            query = query.Where(b => b.IsActive == isActive.Value);

        var branches = await query
            .OrderBy(b => b.SortOrder).ThenBy(b => b.Name)
            .Select(b => new BranchDto
            {
                Id = b.Id,
                Code = b.Code,
                Name = b.Name,
                Description = b.Description,
                Phone = b.Phone,
                Email = b.Email,
                Address = b.Address,
                City = b.City,
                District = b.District,
                Ward = b.Ward,
                Latitude = b.Latitude,
                Longitude = b.Longitude,
                ParentBranchId = b.ParentBranchId,
                ParentBranchName = b.ParentBranch != null ? b.ParentBranch.Name : null,
                ManagerId = b.ManagerId,
                ManagerName = b.Manager != null ? b.Manager.LastName + " " + b.Manager.FirstName : null,
                ManagerPhoto = b.Manager != null ? b.Manager.PhotoUrl : null,
                IsHeadquarter = b.IsHeadquarter,
                SortOrder = b.SortOrder,
                TaxCode = b.TaxCode,
                OpenTime = b.OpenTime,
                CloseTime = b.CloseTime,
                MaxEmployees = b.MaxEmployees,
                IsActive = b.IsActive,
                EmployeeCount = dbContext.Set<Employee>()
                    .Count(e => e.BranchId == b.Id && e.Deleted == null),
                CreatedAt = b.CreatedAt,
            })
            .ToListAsync();

        return Ok(AppResponse<List<BranchDto>>.Success(branches));
    }

    /// <summary>
    /// Láº¥y cÃ¢y chi nhÃ¡nh (hierarchical)
    /// </summary>
    [HttpGet("tree")]
    [RequireModulePermission("Branch", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<BranchTreeNodeDto>>>> GetBranchTree()
    {
        var storeId = CurrentStoreId;

        // PhÃ¢n quyá»n: Admin tháº¥y táº¥t cáº£, Manager chá»‰ tháº¥y sub-tree cá»§a CN mÃ¬nh
        List<Guid>? allowedBranchIds = null;
        if (!IsAdmin && storeId.HasValue)
            allowedBranchIds = await dataScopeService.GetManagedBranchIdsAsync(CurrentUserId, storeId.Value);

        var branches = await dbContext.Branches
            .Include(b => b.Manager)
            .Where(b => b.Deleted == null)
            .Where(b => !storeId.HasValue || b.StoreId == storeId.Value)
            .Where(b => allowedBranchIds == null || allowedBranchIds.Contains(b.Id))
            .OrderBy(b => b.SortOrder).ThenBy(b => b.Name)
            .ToListAsync();

        // Count employees per branch via BranchId
        var employeeCounts = await dbContext.Set<Employee>()
            .Where(e => e.Deleted == null && e.BranchId.HasValue && (!storeId.HasValue || e.StoreId == storeId.Value))
            .GroupBy(e => e.BranchId!.Value)
            .Select(g => new { BranchId = g.Key, Count = g.Count() })
            .ToDictionaryAsync(g => g.BranchId, g => g.Count);

        var rootBranches = branches.Where(b => b.ParentBranchId == null).ToList();
        var tree = rootBranches.Select(b => BuildTreeNode(b, branches, employeeCounts)).ToList();

        return Ok(AppResponse<List<BranchTreeNodeDto>>.Success(tree));
    }

    private static BranchTreeNodeDto BuildTreeNode(
        Branch branch,
        List<Branch> allBranches,
        Dictionary<Guid, int> employeeCounts)
    {
        var childNodes = allBranches
            .Where(b => b.ParentBranchId == branch.Id)
            .Select(b => BuildTreeNode(b, allBranches, employeeCounts))
            .ToList();

        var directCount = employeeCounts.GetValueOrDefault(branch.Id, 0);
        var rolledCount = directCount + childNodes.Sum(c => c.EmployeeCount);

        return new BranchTreeNodeDto
        {
            Id = branch.Id,
            Code = branch.Code,
            Name = branch.Name,
            Address = branch.Address,
            City = branch.City,
            Phone = branch.Phone,
            ManagerName = branch.Manager != null
                ? branch.Manager.LastName + " " + branch.Manager.FirstName
                : null,
            ManagerPhoto = branch.Manager?.PhotoUrl,
            IsHeadquarter = branch.IsHeadquarter,
            IsActive = branch.IsActive,
            EmployeeCount = rolledCount,
            DirectEmployeeCount = directCount,
            Children = childNodes,
        };
    }

    /// <summary>
    /// Láº¥y thá»‘ng kÃª chi nhÃ¡nh
    /// </summary>
    [HttpGet("stats")]
    [RequireModulePermission("Branch", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<BranchStatsDto>>> GetStats()
    {
        var storeId = CurrentStoreId;
        var query = dbContext.Branches.Where(b => b.Deleted == null);
        if (storeId.HasValue)
            query = query.Where(b => b.StoreId == storeId.Value);

        var totalBranches = await query.CountAsync();
        var activeBranches = await query.CountAsync(b => b.IsActive);
        var headquarterCount = await query.CountAsync(b => b.IsHeadquarter);

        var employeeBase = dbContext.Set<Employee>()
            .Where(e => e.Deleted == null && (!storeId.HasValue || e.StoreId == storeId.Value));

        var totalEmployees = await employeeBase.CountAsync();
        var assignedEmployees = await employeeBase.CountAsync(e => e.BranchId != null);
        var unassignedEmployees = totalEmployees - assignedEmployees;

        return Ok(AppResponse<BranchStatsDto>.Success(new BranchStatsDto
        {
            TotalBranches = totalBranches,
            ActiveBranches = activeBranches,
            InactiveBranches = totalBranches - activeBranches,
            HeadquarterCount = headquarterCount,
            TotalEmployees = totalEmployees,
            AssignedEmployees = assignedEmployees,
            UnassignedEmployees = unassignedEmployees,
        }));
    }

    /// <summary>
    /// Láº¥y chi tiáº¿t 1 chi nhÃ¡nh
    /// </summary>
    [HttpGet("{id}")]
    [RequireModulePermission("Branch", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<BranchDto>>> GetBranch(Guid id)
    {
        var branch = await dbContext.Branches
            .Include(b => b.Manager)
            .Include(b => b.ParentBranch)
            .FirstOrDefaultAsync(b => b.Id == id && b.Deleted == null);

        if (branch == null)
            return NotFound(AppResponse<BranchDto>.Fail("KhÃ´ng tÃ¬m tháº¥y chi nhÃ¡nh"));

        var dto = MapToDto(branch);
        dto.EmployeeCount = await dbContext.Set<Employee>()
            .CountAsync(e => e.BranchId == id && e.Deleted == null);
        return Ok(AppResponse<BranchDto>.Success(dto));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // Táº O Má»šI
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Táº¡o chi nhÃ¡nh má»›i
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Branch", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<BranchDto>>> CreateBranch([FromBody] CreateBranchRequest request)
    {
        var storeId = CurrentStoreId;

        // Check duplicate code
        var existingCode = await dbContext.Branches
            .AnyAsync(b => b.Code == request.Code
                && b.Deleted == null
                && (!storeId.HasValue || b.StoreId == storeId.Value));
        if (existingCode)
            return BadRequest(AppResponse<BranchDto>.Fail($"MÃ£ chi nhÃ¡nh '{request.Code}' Ä‘Ã£ tá»“n táº¡i"));

        // If set as headquarter, unset others
        if (request.IsHeadquarter)
        {
            var hqs = await dbContext.Branches                .AsTracking()                .Where(b => b.IsHeadquarter && b.Deleted == null
                    && (!storeId.HasValue || b.StoreId == storeId.Value))
                .ToListAsync();
            foreach (var hq in hqs) hq.IsHeadquarter = false;
        }

        var branch = new Branch
        {
            Id = Guid.NewGuid(),
            Code = request.Code.Trim(),
            Name = request.Name.Trim(),
            Description = request.Description?.Trim(),
            Phone = request.Phone?.Trim(),
            Email = request.Email?.Trim(),
            Address = request.Address?.Trim(),
            City = request.City?.Trim(),
            District = request.District?.Trim(),
            Ward = request.Ward?.Trim(),
            Latitude = request.Latitude,
            Longitude = request.Longitude,
            ParentBranchId = request.ParentBranchId,
            ManagerId = request.ManagerId,
            IsHeadquarter = request.IsHeadquarter,
            SortOrder = request.SortOrder,
            TaxCode = request.TaxCode?.Trim(),
            OpenTime = request.OpenTime,
            CloseTime = request.CloseTime,
            MaxEmployees = request.MaxEmployees,
            StoreId = storeId,
            IsActive = true,
        };

        dbContext.Branches.Add(branch);
        await dbContext.SaveChangesAsync();

        // Reload with navigation
        var saved = await dbContext.Branches
            .Include(b => b.Manager)
            .Include(b => b.ParentBranch)
            .FirstAsync(b => b.Id == branch.Id);

        return Ok(AppResponse<BranchDto>.Success(MapToDto(saved)));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // Cáº¬P NHáº¬T
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Cáº­p nháº­t chi nhÃ¡nh
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Branch", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<BranchDto>>> UpdateBranch(Guid id, [FromBody] UpdateBranchRequest request)
    {
        var storeId = CurrentStoreId;
        var branch = await dbContext.Branches
            .AsTracking()
            .FirstOrDefaultAsync(b => b.Id == id && b.Deleted == null);

        if (branch == null)
            return NotFound(AppResponse<BranchDto>.Fail("KhÃ´ng tÃ¬m tháº¥y chi nhÃ¡nh"));

        // Check duplicate code (exclude self)
        var existingCode = await dbContext.Branches
            .AnyAsync(b => b.Code == request.Code && b.Id != id
                && b.Deleted == null
                && (!storeId.HasValue || b.StoreId == storeId.Value));
        if (existingCode)
            return BadRequest(AppResponse<BranchDto>.Fail($"MÃ£ chi nhÃ¡nh '{request.Code}' Ä‘Ã£ tá»“n táº¡i"));

        // Prevent circular parent
        if (request.ParentBranchId.HasValue && request.ParentBranchId.Value == id)
            return BadRequest(AppResponse<BranchDto>.Fail("Chi nhÃ¡nh khÃ´ng thá»ƒ lÃ  cha cá»§a chÃ­nh nÃ³"));

        // If set as headquarter, unset others
        if (request.IsHeadquarter && !branch.IsHeadquarter)
        {
            var hqs = await dbContext.Branches
                .AsTracking()
                .Where(b => b.IsHeadquarter && b.Id != id && b.Deleted == null
                    && (!storeId.HasValue || b.StoreId == storeId.Value))
                .ToListAsync();
            foreach (var hq in hqs) hq.IsHeadquarter = false;
        }

        branch.Code = request.Code.Trim();
        branch.Name = request.Name.Trim();
        branch.Description = request.Description?.Trim();
        branch.Phone = request.Phone?.Trim();
        branch.Email = request.Email?.Trim();
        branch.Address = request.Address?.Trim();
        branch.City = request.City?.Trim();
        branch.District = request.District?.Trim();
        branch.Ward = request.Ward?.Trim();
        branch.Latitude = request.Latitude;
        branch.Longitude = request.Longitude;
        branch.ParentBranchId = request.ParentBranchId;
        branch.ManagerId = request.ManagerId;
        branch.IsHeadquarter = request.IsHeadquarter;
        branch.SortOrder = request.SortOrder;
        branch.TaxCode = request.TaxCode?.Trim();
        branch.OpenTime = request.OpenTime;
        branch.CloseTime = request.CloseTime;
        branch.MaxEmployees = request.MaxEmployees;
        branch.IsActive = request.IsActive;

        await dbContext.SaveChangesAsync();

        var updated = await dbContext.Branches
            .Include(b => b.Manager)
            .Include(b => b.ParentBranch)
            .FirstAsync(b => b.Id == id);

        return Ok(AppResponse<BranchDto>.Success(MapToDto(updated)));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // XÃ“A
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// XÃ³a chi nhÃ¡nh (soft delete)
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Branch", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteBranch(Guid id)
    {
        var branch = await dbContext.Branches
            .AsTracking()
            .FirstOrDefaultAsync(b => b.Id == id && b.Deleted == null);

        if (branch == null)
            return NotFound(AppResponse<bool>.Fail("KhÃ´ng tÃ¬m tháº¥y chi nhÃ¡nh"));

        // Check children
        var hasChildren = await dbContext.Branches
            .AnyAsync(b => b.ParentBranchId == id && b.Deleted == null);
        if (hasChildren)
            return BadRequest(AppResponse<bool>.Fail("KhÃ´ng thá»ƒ xÃ³a chi nhÃ¡nh cÃ³ chi nhÃ¡nh con. HÃ£y xÃ³a chi nhÃ¡nh con trÆ°á»›c."));

        var linkedEmployees = await dbContext.Set<Employee>()
            .AsTracking()
            .Where(e => e.BranchId == id && e.Deleted == null)
            .ToListAsync();
        foreach (var emp in linkedEmployees)
            emp.BranchId = null;

        branch.Deleted = DateTime.UtcNow;
        branch.DeletedBy = CurrentUserId.ToString();
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Chuyá»ƒn Ä‘á»•i tráº¡ng thÃ¡i hoáº¡t Ä‘á»™ng
    /// </summary>
    [HttpPatch("{id}/toggle-active")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Branch", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<BranchDto>>> ToggleActive(Guid id)
    {
        var branch = await dbContext.Branches
            .AsTracking()
            .Include(b => b.Manager)
            .Include(b => b.ParentBranch)
            .FirstOrDefaultAsync(b => b.Id == id && b.Deleted == null);

        if (branch == null)
            return NotFound(AppResponse<BranchDto>.Fail("KhÃ´ng tÃ¬m tháº¥y chi nhÃ¡nh"));

        branch.IsActive = !branch.IsActive;
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<BranchDto>.Success(MapToDto(branch)));
    }

    /// <summary>
    /// Láº¥y danh sÃ¡ch chi nhÃ¡nh cho dropdown select
    /// </summary>
    [HttpGet("select")]
    public async Task<ActionResult<AppResponse<List<BranchSelectDto>>>> GetBranchesForSelect()
    {
        var storeId = CurrentStoreId;

        List<Guid>? allowedBranchIds = null;
        if (!IsAdmin && storeId.HasValue)
        {
            var scoped = await dataScopeService.GetManagedBranchIdsAsync(CurrentUserId, storeId.Value);
            // Không gán CN cụ thể → dropdown HR dùng tất cả CN trong cửa hàng
            allowedBranchIds = scoped.Count > 0 ? scoped : null;
        }

        var branches = await dbContext.Branches
            .Where(b => b.Deleted == null)
            .Where(b => !storeId.HasValue || b.StoreId == storeId.Value)
            .Where(b => allowedBranchIds == null || allowedBranchIds.Contains(b.Id))
            .OrderBy(b => b.SortOrder).ThenBy(b => b.Name)
            .Select(b => new BranchSelectDto
            {
                Id = b.Id,
                Code = b.Code,
                Name = b.Name,
                IsHeadquarter = b.IsHeadquarter,
                ParentBranchId = b.ParentBranchId,
            })
            .ToListAsync();

        return Ok(AppResponse<List<BranchSelectDto>>.Success(branches));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // PHÃ‚N QUYá»€N CHI NHÃNH (BranchPermission)
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Láº¥y danh sÃ¡ch phÃ¢n quyá»n cá»§a 1 chi nhÃ¡nh
    /// </summary>
    [HttpGet("{branchId}/permissions")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Branch", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<BranchPermissionDto>>>> GetBranchPermissions(Guid branchId)
    {
        var perms = await dbContext.BranchPermissions
            .Include(p => p.User)
            .Where(p => p.BranchId == branchId && p.IsActive)
            .Select(p => new BranchPermissionDto
            {
                Id = p.Id,
                UserId = p.UserId,
                UserName = p.User != null ? p.User.FullName ?? p.User.UserName ?? "" : "",
                UserEmail = p.User != null ? p.User.Email ?? "" : "",
                BranchId = p.BranchId,
                IncludeChildren = p.IncludeChildren,
                CanView = p.CanView,
                CanCreate = p.CanCreate,
                CanEdit = p.CanEdit,
                CanDelete = p.CanDelete,
                IsActive = p.IsActive,
                GrantedBy = p.GrantedBy,
                Note = p.Note,
                CreatedAt = p.CreatedAt,
            })
            .ToListAsync();

        return Ok(AppResponse<List<BranchPermissionDto>>.Success(perms));
    }

    /// <summary>
    /// ThÃªm phÃ¢n quyá»n cho user á»Ÿ chi nhÃ¡nh
    /// </summary>
    [HttpPost("{branchId}/permissions")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Branch", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<BranchPermissionDto>>> CreateBranchPermission(
        Guid branchId, [FromBody] CreateBranchPermissionRequest request)
    {
        var storeId = CurrentStoreId;

        var branch = await dbContext.Branches
            .FirstOrDefaultAsync(b => b.Id == branchId && b.Deleted == null);
        if (branch == null)
            return NotFound(AppResponse<BranchPermissionDto>.Fail("KhÃ´ng tÃ¬m tháº¥y chi nhÃ¡nh"));

        var targetUser = await dbContext.Users
            .FirstOrDefaultAsync(u => u.Id == request.UserId);
        if (targetUser == null)
            return NotFound(AppResponse<BranchPermissionDto>.Fail("KhÃ´ng tÃ¬m tháº¥y user"));

        // Upsert: náº¿u Ä‘Ã£ cÃ³ thÃ¬ update, khÃ´ng thÃ¬ táº¡o má»›i
        var existing = await dbContext.BranchPermissions
            .AsTracking()
            .FirstOrDefaultAsync(p => p.UserId == request.UserId && p.BranchId == branchId);

        if (existing != null)
        {
            existing.IncludeChildren = request.IncludeChildren;
            existing.CanView = request.CanView;
            existing.CanCreate = request.CanCreate;
            existing.CanEdit = request.CanEdit;
            existing.CanDelete = request.CanDelete;
            existing.IsActive = true;
            existing.Note = request.Note;
            existing.GrantedBy = CurrentUserId.ToString();
        }
        else
        {
            existing = new BranchPermission
            {
                Id = Guid.NewGuid(),
                UserId = request.UserId,
                BranchId = branchId,
                StoreId = storeId,
                IncludeChildren = request.IncludeChildren,
                CanView = request.CanView,
                CanCreate = request.CanCreate,
                CanEdit = request.CanEdit,
                CanDelete = request.CanDelete,
                IsActive = true,
                Note = request.Note,
                GrantedBy = CurrentUserId.ToString(),
            };
            dbContext.BranchPermissions.Add(existing);
        }

        await dbContext.SaveChangesAsync();

        var result = new BranchPermissionDto
        {
            Id = existing.Id,
            UserId = existing.UserId,
            UserName = targetUser.FullName ?? targetUser.UserName ?? "",
            UserEmail = targetUser.Email ?? "",
            BranchId = existing.BranchId,
            IncludeChildren = existing.IncludeChildren,
            CanView = existing.CanView,
            CanCreate = existing.CanCreate,
            CanEdit = existing.CanEdit,
            CanDelete = existing.CanDelete,
            IsActive = existing.IsActive,
            GrantedBy = existing.GrantedBy,
            Note = existing.Note,
            CreatedAt = existing.CreatedAt,
        };
        return Ok(AppResponse<BranchPermissionDto>.Success(result));
    }

    /// <summary>
    /// Cáº­p nháº­t phÃ¢n quyá»n chi nhÃ¡nh
    /// </summary>
    [HttpPut("permissions/{permId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Branch", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> UpdateBranchPermission(
        Guid permId, [FromBody] UpdateBranchPermissionRequest request)
    {
        var perm = await dbContext.BranchPermissions
            .AsTracking()
            .FirstOrDefaultAsync(p => p.Id == permId);
        if (perm == null)
            return NotFound(AppResponse<bool>.Fail("KhÃ´ng tÃ¬m tháº¥y phÃ¢n quyá»n"));

        perm.IncludeChildren = request.IncludeChildren;
        perm.CanView = request.CanView;
        perm.CanCreate = request.CanCreate;
        perm.CanEdit = request.CanEdit;
        perm.CanDelete = request.CanDelete;
        perm.IsActive = request.IsActive;
        perm.Note = request.Note;
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// XÃ³a phÃ¢n quyá»n chi nhÃ¡nh
    /// </summary>
    [HttpDelete("permissions/{permId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Branch", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteBranchPermission(Guid permId)
    {
        var perm = await dbContext.BranchPermissions
            .AsTracking()
            .FirstOrDefaultAsync(p => p.Id == permId);
        if (perm == null)
            return NotFound(AppResponse<bool>.Fail("KhÃ´ng tÃ¬m tháº¥y phÃ¢n quyá»n"));

        dbContext.BranchPermissions.Remove(perm);
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Láº¥y danh sÃ¡ch chi nhÃ¡nh mÃ  user hiá»‡n táº¡i quáº£n lÃ½ (dÃ¹ng cho UI)
    /// </summary>
    [HttpGet("my-branches")]
    public async Task<ActionResult<AppResponse<List<BranchSelectDto>>>> GetMyBranches()
    {
        var storeId = CurrentStoreId;
        if (!storeId.HasValue)
            return Ok(AppResponse<List<BranchSelectDto>>.Success([]));

        List<Guid> managedIds;
        if (IsAdmin)
        {
            managedIds = await dbContext.Branches
                .Where(b => b.StoreId == storeId.Value && b.Deleted == null && b.IsActive)
                .Select(b => b.Id)
                .ToListAsync();
        }
        else
        {
            managedIds = await dataScopeService.GetManagedBranchIdsAsync(CurrentUserId, storeId.Value);
        }

        if (managedIds.Count == 0)
            return Ok(AppResponse<List<BranchSelectDto>>.Success([]));

        var branches = await dbContext.Branches
            .Where(b => managedIds.Contains(b.Id) && b.Deleted == null)
            .OrderBy(b => b.SortOrder).ThenBy(b => b.Name)
            .Select(b => new BranchSelectDto
            {
                Id = b.Id,
                Code = b.Code,
                Name = b.Name,
                IsHeadquarter = b.IsHeadquarter,
                ParentBranchId = b.ParentBranchId,
            })
            .ToListAsync();

        return Ok(AppResponse<List<BranchSelectDto>>.Success(branches));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // HELPERS
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    private static BranchDto MapToDto(Branch b)
    {
        return new BranchDto
        {
            Id = b.Id,
            Code = b.Code,
            Name = b.Name,
            Description = b.Description,
            Phone = b.Phone,
            Email = b.Email,
            Address = b.Address,
            City = b.City,
            District = b.District,
            Ward = b.Ward,
            Latitude = b.Latitude,
            Longitude = b.Longitude,
            ParentBranchId = b.ParentBranchId,
            ParentBranchName = b.ParentBranch?.Name,
            ManagerId = b.ManagerId,
            ManagerName = b.Manager != null ? b.Manager.LastName + " " + b.Manager.FirstName : null,
            ManagerPhoto = b.Manager?.PhotoUrl,
            IsHeadquarter = b.IsHeadquarter,
            SortOrder = b.SortOrder,
            TaxCode = b.TaxCode,
            OpenTime = b.OpenTime,
            CloseTime = b.CloseTime,
            MaxEmployees = b.MaxEmployees,
            IsActive = b.IsActive,
            CreatedAt = b.CreatedAt,
        };
    }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// DTOs
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

public class BranchDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public string? Address { get; set; }
    public string? City { get; set; }
    public string? District { get; set; }
    public string? Ward { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public Guid? ParentBranchId { get; set; }
    public string? ParentBranchName { get; set; }
    public Guid? ManagerId { get; set; }
    public string? ManagerName { get; set; }
    public string? ManagerPhoto { get; set; }
    public bool IsHeadquarter { get; set; }
    public int SortOrder { get; set; }
    public string? TaxCode { get; set; }
    public TimeSpan? OpenTime { get; set; }
    public TimeSpan? CloseTime { get; set; }
    public int? MaxEmployees { get; set; }
    public bool IsActive { get; set; }
    public int EmployeeCount { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class CreateBranchRequest
{
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public string? Address { get; set; }
    public string? City { get; set; }
    public string? District { get; set; }
    public string? Ward { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public Guid? ParentBranchId { get; set; }
    public Guid? ManagerId { get; set; }
    public bool IsHeadquarter { get; set; }
    public int SortOrder { get; set; }
    public string? TaxCode { get; set; }
    public TimeSpan? OpenTime { get; set; }
    public TimeSpan? CloseTime { get; set; }
    public int? MaxEmployees { get; set; }
}

public class UpdateBranchRequest
{
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? Phone { get; set; }
    public string? Email { get; set; }
    public string? Address { get; set; }
    public string? City { get; set; }
    public string? District { get; set; }
    public string? Ward { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public Guid? ParentBranchId { get; set; }
    public Guid? ManagerId { get; set; }
    public bool IsHeadquarter { get; set; }
    public int SortOrder { get; set; }
    public string? TaxCode { get; set; }
    public TimeSpan? OpenTime { get; set; }
    public TimeSpan? CloseTime { get; set; }
    public int? MaxEmployees { get; set; }
    public bool IsActive { get; set; } = true;
}

public class BranchTreeNodeDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Address { get; set; }
    public string? City { get; set; }
    public string? Phone { get; set; }
    public string? ManagerName { get; set; }
    public string? ManagerPhoto { get; set; }
    public bool IsHeadquarter { get; set; }
    public bool IsActive { get; set; }
    /// <summary>Direct + all descendant employees.</summary>
    public int EmployeeCount { get; set; }
    /// <summary>Employees assigned only to this branch.</summary>
    public int DirectEmployeeCount { get; set; }
    public List<BranchTreeNodeDto> Children { get; set; } = [];
}

public class BranchStatsDto
{
    public int TotalBranches { get; set; }
    public int ActiveBranches { get; set; }
    public int InactiveBranches { get; set; }
    public int HeadquarterCount { get; set; }
    public int TotalEmployees { get; set; }
    public int AssignedEmployees { get; set; }
    public int UnassignedEmployees { get; set; }
}

public class BranchSelectDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public bool IsHeadquarter { get; set; }
    public Guid? ParentBranchId { get; set; }
}

public class BranchPermissionDto
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public string UserName { get; set; } = string.Empty;
    public string UserEmail { get; set; } = string.Empty;
    public Guid? BranchId { get; set; }
    public bool IncludeChildren { get; set; }
    public bool CanView { get; set; }
    public bool CanCreate { get; set; }
    public bool CanEdit { get; set; }
    public bool CanDelete { get; set; }
    public bool IsActive { get; set; }
    public string? GrantedBy { get; set; }
    public string? Note { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class CreateBranchPermissionRequest
{
    public Guid UserId { get; set; }
    public bool IncludeChildren { get; set; } = true;
    public bool CanView { get; set; } = true;
    public bool CanCreate { get; set; }
    public bool CanEdit { get; set; }
    public bool CanDelete { get; set; }
    public string? Note { get; set; }
}

public class UpdateBranchPermissionRequest
{
    public bool IncludeChildren { get; set; } = true;
    public bool CanView { get; set; } = true;
    public bool CanCreate { get; set; }
    public bool CanEdit { get; set; }
    public bool CanDelete { get; set; }
    public bool IsActive { get; set; } = true;
    public string? Note { get; set; }
}

