using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// API Controller quản lý chi nhánh
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
    // ═══════════════════════════════════════════════════════════════
    // LẤY DANH SÁCH
    // ═══════════════════════════════════════════════════════════════

    /// <summary>
    /// Lấy danh sách chi nhánh (flat list)
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<AppResponse<List<BranchDto>>>> GetBranches(
        [FromQuery] string? search,
        [FromQuery] bool? isActive)
    {
        var storeId = CurrentStoreId;

        // Phân quyền: Admin thấy tất cả; Manager/Manager chi nhánh chỉ thấy CN quản lý
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
    /// Lấy cây chi nhánh (hierarchical)
    /// </summary>
    [HttpGet("tree")]
    public async Task<ActionResult<AppResponse<List<BranchTreeNodeDto>>>> GetBranchTree()
    {
        var storeId = CurrentStoreId;

        // Phân quyền: Admin thấy tất cả, Manager chỉ thấy sub-tree của CN mình
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
        var children = allBranches
            .Where(b => b.ParentBranchId == branch.Id)
            .Select(b => BuildTreeNode(b, allBranches, employeeCounts))
            .ToList();

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
            EmployeeCount = employeeCounts.GetValueOrDefault(branch.Id, 0),
            Children = children,
        };
    }

    /// <summary>
    /// Lấy thống kê chi nhánh
    /// </summary>
    [HttpGet("stats")]
    public async Task<ActionResult<AppResponse<BranchStatsDto>>> GetStats()
    {
        var storeId = CurrentStoreId;
        var query = dbContext.Branches.Where(b => b.Deleted == null);
        if (storeId.HasValue)
            query = query.Where(b => b.StoreId == storeId.Value);

        var totalBranches = await query.CountAsync();
        var activeBranches = await query.CountAsync(b => b.IsActive);
        var headquarterCount = await query.CountAsync(b => b.IsHeadquarter);

        var totalEmployees = await dbContext.Set<Employee>()
            .Where(e => e.Deleted == null && (!storeId.HasValue || e.StoreId == storeId.Value))
            .CountAsync();

        return Ok(AppResponse<BranchStatsDto>.Success(new BranchStatsDto
        {
            TotalBranches = totalBranches,
            ActiveBranches = activeBranches,
            InactiveBranches = totalBranches - activeBranches,
            HeadquarterCount = headquarterCount,
            TotalEmployees = totalEmployees,
        }));
    }

    /// <summary>
    /// Lấy chi tiết 1 chi nhánh
    /// </summary>
    [HttpGet("{id}")]
    public async Task<ActionResult<AppResponse<BranchDto>>> GetBranch(Guid id)
    {
        var branch = await dbContext.Branches
            .Include(b => b.Manager)
            .Include(b => b.ParentBranch)
            .FirstOrDefaultAsync(b => b.Id == id && b.Deleted == null);

        if (branch == null)
            return NotFound(AppResponse<BranchDto>.Fail("Không tìm thấy chi nhánh"));

        var dto = MapToDto(branch);
        return Ok(AppResponse<BranchDto>.Success(dto));
    }

    // ═══════════════════════════════════════════════════════════════
    // TẠO MỚI
    // ═══════════════════════════════════════════════════════════════

    /// <summary>
    /// Tạo chi nhánh mới
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<BranchDto>>> CreateBranch([FromBody] CreateBranchRequest request)
    {
        var storeId = CurrentStoreId;

        // Check duplicate code
        var existingCode = await dbContext.Branches
            .AnyAsync(b => b.Code == request.Code
                && b.Deleted == null
                && (!storeId.HasValue || b.StoreId == storeId.Value));
        if (existingCode)
            return BadRequest(AppResponse<BranchDto>.Fail($"Mã chi nhánh '{request.Code}' đã tồn tại"));

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

    // ═══════════════════════════════════════════════════════════════
    // CẬP NHẬT
    // ═══════════════════════════════════════════════════════════════

    /// <summary>
    /// Cập nhật chi nhánh
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<BranchDto>>> UpdateBranch(Guid id, [FromBody] UpdateBranchRequest request)
    {
        var storeId = CurrentStoreId;
        var branch = await dbContext.Branches
            .AsTracking()
            .FirstOrDefaultAsync(b => b.Id == id && b.Deleted == null);

        if (branch == null)
            return NotFound(AppResponse<BranchDto>.Fail("Không tìm thấy chi nhánh"));

        // Check duplicate code (exclude self)
        var existingCode = await dbContext.Branches
            .AnyAsync(b => b.Code == request.Code && b.Id != id
                && b.Deleted == null
                && (!storeId.HasValue || b.StoreId == storeId.Value));
        if (existingCode)
            return BadRequest(AppResponse<BranchDto>.Fail($"Mã chi nhánh '{request.Code}' đã tồn tại"));

        // Prevent circular parent
        if (request.ParentBranchId.HasValue && request.ParentBranchId.Value == id)
            return BadRequest(AppResponse<BranchDto>.Fail("Chi nhánh không thể là cha của chính nó"));

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

    // ═══════════════════════════════════════════════════════════════
    // XÓA
    // ═══════════════════════════════════════════════════════════════

    /// <summary>
    /// Xóa chi nhánh (soft delete)
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteBranch(Guid id)
    {
        var branch = await dbContext.Branches
            .AsTracking()
            .FirstOrDefaultAsync(b => b.Id == id && b.Deleted == null);

        if (branch == null)
            return NotFound(AppResponse<bool>.Fail("Không tìm thấy chi nhánh"));

        // Check children
        var hasChildren = await dbContext.Branches
            .AnyAsync(b => b.ParentBranchId == id && b.Deleted == null);
        if (hasChildren)
            return BadRequest(AppResponse<bool>.Fail("Không thể xóa chi nhánh có chi nhánh con. Hãy xóa chi nhánh con trước."));

        branch.Deleted = DateTime.UtcNow;
        branch.DeletedBy = CurrentUserId.ToString();
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Chuyển đổi trạng thái hoạt động
    /// </summary>
    [HttpPatch("{id}/toggle-active")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<BranchDto>>> ToggleActive(Guid id)
    {
        var branch = await dbContext.Branches
            .AsTracking()
            .Include(b => b.Manager)
            .Include(b => b.ParentBranch)
            .FirstOrDefaultAsync(b => b.Id == id && b.Deleted == null);

        if (branch == null)
            return NotFound(AppResponse<BranchDto>.Fail("Không tìm thấy chi nhánh"));

        branch.IsActive = !branch.IsActive;
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<BranchDto>.Success(MapToDto(branch)));
    }

    /// <summary>
    /// Lấy danh sách chi nhánh cho dropdown select
    /// </summary>
    [HttpGet("select")]
    public async Task<ActionResult<AppResponse<List<BranchSelectDto>>>> GetBranchesForSelect()
    {
        var storeId = CurrentStoreId;

        List<Guid>? allowedBranchIds = null;
        if (!IsAdmin && storeId.HasValue)
            allowedBranchIds = await dataScopeService.GetManagedBranchIdsAsync(CurrentUserId, storeId.Value);

        var branches = await dbContext.Branches
            .Where(b => b.Deleted == null && b.IsActive)
            .Where(b => !storeId.HasValue || b.StoreId == storeId.Value)
            .Where(b => allowedBranchIds == null || allowedBranchIds.Contains(b.Id))
            .OrderBy(b => b.SortOrder).ThenBy(b => b.Name)
            .Select(b => new BranchSelectDto
            {
                Id = b.Id,
                Code = b.Code,
                Name = b.Name,
                IsHeadquarter = b.IsHeadquarter,
            })
            .ToListAsync();

        return Ok(AppResponse<List<BranchSelectDto>>.Success(branches));
    }

    // ═══════════════════════════════════════════════════════════════
    // PHÂN QUYỀN CHI NHÁNH (BranchPermission)
    // ═══════════════════════════════════════════════════════════════

    /// <summary>
    /// Lấy danh sách phân quyền của 1 chi nhánh
    /// </summary>
    [HttpGet("{branchId}/permissions")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
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
    /// Thêm phân quyền cho user ở chi nhánh
    /// </summary>
    [HttpPost("{branchId}/permissions")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<BranchPermissionDto>>> CreateBranchPermission(
        Guid branchId, [FromBody] CreateBranchPermissionRequest request)
    {
        var storeId = CurrentStoreId;

        var branch = await dbContext.Branches
            .FirstOrDefaultAsync(b => b.Id == branchId && b.Deleted == null);
        if (branch == null)
            return NotFound(AppResponse<BranchPermissionDto>.Fail("Không tìm thấy chi nhánh"));

        var targetUser = await dbContext.Users
            .FirstOrDefaultAsync(u => u.Id == request.UserId);
        if (targetUser == null)
            return NotFound(AppResponse<BranchPermissionDto>.Fail("Không tìm thấy user"));

        // Upsert: nếu đã có thì update, không thì tạo mới
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
    /// Cập nhật phân quyền chi nhánh
    /// </summary>
    [HttpPut("permissions/{permId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> UpdateBranchPermission(
        Guid permId, [FromBody] UpdateBranchPermissionRequest request)
    {
        var perm = await dbContext.BranchPermissions
            .AsTracking()
            .FirstOrDefaultAsync(p => p.Id == permId);
        if (perm == null)
            return NotFound(AppResponse<bool>.Fail("Không tìm thấy phân quyền"));

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
    /// Xóa phân quyền chi nhánh
    /// </summary>
    [HttpDelete("permissions/{permId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteBranchPermission(Guid permId)
    {
        var perm = await dbContext.BranchPermissions
            .AsTracking()
            .FirstOrDefaultAsync(p => p.Id == permId);
        if (perm == null)
            return NotFound(AppResponse<bool>.Fail("Không tìm thấy phân quyền"));

        dbContext.BranchPermissions.Remove(perm);
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Lấy danh sách chi nhánh mà user hiện tại quản lý (dùng cho UI)
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
            })
            .ToListAsync();

        return Ok(AppResponse<List<BranchSelectDto>>.Success(branches));
    }

    // ═══════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════
// DTOs
// ═══════════════════════════════════════════════════════════════

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
    public int EmployeeCount { get; set; }
    public List<BranchTreeNodeDto> Children { get; set; } = [];
}

public class BranchStatsDto
{
    public int TotalBranches { get; set; }
    public int ActiveBranches { get; set; }
    public int InactiveBranches { get; set; }
    public int HeadquarterCount { get; set; }
    public int TotalEmployees { get; set; }
}

public class BranchSelectDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public bool IsHeadquarter { get; set; }
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
