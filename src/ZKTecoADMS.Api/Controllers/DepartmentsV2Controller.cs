using ZKTecoADMS.Application.Helpers;
using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Phòng ban v2: cây phòng ban kèm số nhân viên (theo chi nhánh đang xem), danh sách nhân viên của phòng,
/// chuyển nhân viên hàng loạt, sắp xếp / đổi phòng cha, xóa phòng kèm chuyển nhân viên, tìm người quản lý.
/// Tạo / sửa phòng ban vẫn dùng api/departments (đã đồng bộ tên phòng ban trên hồ sơ nhân viên).
/// </summary>
[ApiController]
[Route("api/departments/v2")]
[Authorize]
public class DepartmentsV2Controller(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    sealed record EmpRow(Guid Id, Guid? DepartmentId, string? DepartmentText, Guid? BranchId);

    async Task<Func<Guid?, bool>> InViewAsync(Guid storeId)
    {
        var view = await BranchViewHelper.ViewBranchIdsAsync(HttpContext, db, storeId);
        var hq = HttpContext.BranchContext()?.HeadquarterBranchId;
        return b => BranchViewHelper.InView(view, b, hq);
    }

    /// <summary>Phòng ban của nhân viên: theo mã phòng, nhân viên cũ chỉ có tên chữ thì khớp theo tên.</summary>
    static Guid? DeptOf(EmpRow e, IReadOnlyDictionary<string, Guid> byName) =>
        e.DepartmentId ?? (e.DepartmentText != null && byName.TryGetValue(e.DepartmentText.Trim(), out var id) ? id : null);

    static List<string> Positions(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            return JsonSerializer.Deserialize<List<string>>(json) ?? [];
        }
        catch
        {
            return [];
        }
    }

    // ─── Tổng quan cây ───────────────────────────────────────────

    [HttpGet("overview")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Department", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Overview()
    {
        var storeId = RequiredStoreId;
        var depts = await db.Departments.AsNoTracking().Where(d => d.StoreId == storeId)
            .OrderBy(d => d.SortOrder).ThenBy(d => d.Name)
            .Select(d => new { d.Id, d.Code, d.Name, d.Description, d.ParentDepartmentId, d.ManagerId, d.SortOrder, d.IsActive, d.Positions, d.Level })
            .ToListAsync();
        var byName = depts.GroupBy(d => d.Name.Trim(), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.First().Id, StringComparer.OrdinalIgnoreCase);
        var inView = await InViewAsync(storeId);
        var emps = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.WorkStatus != EmployeeWorkStatus.Resigned)
            .Select(e => new EmpRow(e.Id, e.DepartmentId, e.Department, e.BranchId))
            .ToListAsync();
        var visible = emps.Where(e => inView(e.BranchId)).ToList();
        var direct = visible.GroupBy(e => DeptOf(e, byName)).ToDictionary(g => g.Key ?? Guid.Empty, g => g.Count());
        var managers = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && depts.Select(d => d.ManagerId).Contains(e.Id))
            .Select(e => new { e.Id, Name = (e.LastName + " " + e.FirstName).Trim(), e.PhotoUrl, e.Position })
            .ToDictionaryAsync(e => e.Id);

        var pairs = depts.Select(d => (d.Id, d.ParentDepartmentId)).ToList();
        int Total(Guid id) => DepartmentOrgHelper.WithDescendants(pairs, id).Sum(x => direct.GetValueOrDefault(x));

        var items = depts.Select(d =>
        {
            var m = d.ManagerId is Guid mid ? managers.GetValueOrDefault(mid) : null;
            return new
            {
                id = d.Id,
                code = d.Code,
                name = d.Name,
                description = d.Description,
                parentId = d.ParentDepartmentId,
                sortOrder = d.SortOrder,
                isActive = d.IsActive,
                level = d.Level,
                positions = Positions(d.Positions),
                managerId = d.ManagerId,
                managerName = m?.Name,
                managerPhoto = m?.PhotoUrl,
                managerPosition = m?.Position,
                directCount = direct.GetValueOrDefault(d.Id),
                totalCount = Total(d.Id),
                childCount = depts.Count(x => x.ParentDepartmentId == d.Id),
            };
        }).ToList();
        return Ok(AppResponse<object>.Success(new
        {
            items,
            totalEmployees = visible.Count,
            unassigned = direct.GetValueOrDefault(Guid.Empty),
        }));
    }

    // ─── Nhân viên của phòng ─────────────────────────────────────

    /// <summary>Nhân viên của phòng ban ("none" = chưa có phòng ban). includeChildren = gồm phòng con.</summary>
    [HttpGet("{id}/members")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Department", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Members(string id, [FromQuery] bool includeChildren = false)
    {
        var storeId = RequiredStoreId;
        var depts = await db.Departments.AsNoTracking().Where(d => d.StoreId == storeId)
            .Select(d => new { d.Id, d.Name, d.ParentDepartmentId }).ToListAsync();
        var byName = depts.GroupBy(d => d.Name.Trim(), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => g.First().Id, StringComparer.OrdinalIgnoreCase);
        var deptName = depts.ToDictionary(d => d.Id, d => d.Name);
        HashSet<Guid>? target = null;
        if (id != "none")
        {
            if (!Guid.TryParse(id, out var gid) || !deptName.ContainsKey(gid))
                return Ok(AppResponse<object>.Error("Không tìm thấy phòng ban"));
            target = includeChildren
                ? DepartmentOrgHelper.WithDescendants(depts.Select(d => (d.Id, d.ParentDepartmentId)), gid)
                : [gid];
        }
        var inView = await InViewAsync(storeId);
        var branchNames = await db.Branches.AsNoTracking().Where(b => b.StoreId == storeId)
            .ToDictionaryAsync(b => b.Id, b => b.Name);
        var rows = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.WorkStatus != EmployeeWorkStatus.Resigned)
            .Select(e => new
            {
                e.Id, e.EmployeeCode, Name = (e.LastName + " " + e.FirstName).Trim(), e.Position, e.PhotoUrl,
                e.BranchId, e.DepartmentId, e.Department, e.WorkStatus, e.PhoneNumber,
            })
            .ToListAsync();
        var list = rows
            .Where(e => inView(e.BranchId))
            .Select(e => new { e, dept = DeptOf(new EmpRow(e.Id, e.DepartmentId, e.Department, e.BranchId), byName) })
            .Where(x => target == null ? x.dept == null : x.dept is Guid g && target.Contains(g))
            .OrderBy(x => x.e.Name)
            .Select(x => new
            {
                id = x.e.Id,
                employeeCode = x.e.EmployeeCode,
                name = x.e.Name,
                position = x.e.Position,
                photoUrl = x.e.PhotoUrl,
                phone = x.e.PhoneNumber,
                branchName = x.e.BranchId is Guid b ? branchNames.GetValueOrDefault(b) : null,
                departmentId = x.dept,
                departmentName = x.dept is Guid d ? deptName.GetValueOrDefault(d) : null,
                onLeave = x.e.WorkStatus == EmployeeWorkStatus.OnLeave,
                probation = x.e.WorkStatus == EmployeeWorkStatus.Probation,
            }).ToList();
        return Ok(AppResponse<object>.Success(list));
    }

    /// <summary>Tìm nhân viên (chọn người quản lý) — tối đa 30 người.</summary>
    [HttpGet("employee-search")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Department", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> EmployeeSearch([FromQuery] string? q)
    {
        var storeId = RequiredStoreId;
        var term = VnSearch.FoldText(q);
        var rows = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.WorkStatus != EmployeeWorkStatus.Resigned)
            .Where(e => term == "" || VnSearch.Fold(e.LastName + " " + e.FirstName).Contains(term) || VnSearch.Fold(e.EmployeeCode).Contains(term))
            .OrderBy(e => e.FirstName)
            .Take(30)
            .Select(e => new
            {
                id = e.Id, name = (e.LastName + " " + e.FirstName).Trim(), employeeCode = e.EmployeeCode,
                position = e.Position, department = e.Department, photoUrl = e.PhotoUrl,
            })
            .ToListAsync();
        return Ok(AppResponse<object>.Success(rows));
    }

    // ─── Chuyển nhân viên ────────────────────────────────────────

    public sealed class MoveEmployeesRequest
    {
        public List<Guid> EmployeeIds { get; set; } = [];
        /// <summary>null = bỏ khỏi phòng ban.</summary>
        public Guid? TargetDepartmentId { get; set; }
    }

    [HttpPost("move-employees")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "Department", "Employee")]
    public async Task<ActionResult<AppResponse<object>>> MoveEmployees([FromBody] MoveEmployeesRequest req)
    {
        if (req.EmployeeIds.Count == 0) return Ok(AppResponse<object>.Error("Chưa chọn nhân viên"));
        var n = await DepartmentOrgHelper.MoveEmployeesAsync(db, RequiredStoreId, req.EmployeeIds, req.TargetDepartmentId);
        return n < 0
            ? Ok(AppResponse<object>.Error("Không tìm thấy phòng ban nhận"))
            : Ok(AppResponse<object>.Success(new { moved = n }));
    }

    // ─── Sắp xếp / đổi phòng cha ─────────────────────────────────

    public sealed class ReorderItem
    {
        public Guid Id { get; set; }
        public Guid? ParentId { get; set; }
        public int SortOrder { get; set; }
    }

    public sealed class ReorderRequest
    {
        public List<ReorderItem> Items { get; set; } = [];
    }

    [HttpPost("reorder")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Department", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Reorder([FromBody] ReorderRequest req)
    {
        var storeId = RequiredStoreId;
        var all = await db.Departments.AsTracking().Where(d => d.StoreId == storeId).ToListAsync();
        var byId = all.ToDictionary(d => d.Id);
        var parentOf = all.ToDictionary(d => d.Id, d => d.ParentDepartmentId);
        foreach (var it in req.Items)
        {
            if (!byId.ContainsKey(it.Id)) return Ok(AppResponse<object>.Error("Phòng ban không tồn tại"));
            if (it.ParentId is Guid p && !byId.ContainsKey(p)) return Ok(AppResponse<object>.Error("Phòng ban cha không tồn tại"));
            parentOf[it.Id] = it.ParentId;
        }
        foreach (var it in req.Items)
        {
            parentOf[it.Id] = null;
            if (DepartmentOrgHelper.CreatesCycle(parentOf, it.Id, it.ParentId))
                return Ok(AppResponse<object>.Error($"Không thể đặt \"{byId[it.Id].Name}\" vào trong chính phòng con của nó"));
            parentOf[it.Id] = it.ParentId;
        }
        foreach (var it in req.Items)
        {
            var d = byId[it.Id];
            d.ParentDepartmentId = it.ParentId;
            d.SortOrder = it.SortOrder;
            d.UpdatedAt = DateTime.UtcNow;
        }
        DepartmentOrgHelper.RecomputeHierarchy(all);
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { updated = req.Items.Count }));
    }

    // ─── Xóa kèm chuyển nhân viên ────────────────────────────────

    public sealed class DeleteDepartmentRequest
    {
        /// <summary>Phòng nhận nhân viên (bắt buộc nếu phòng còn nhân viên).</summary>
        public Guid? TargetDepartmentId { get; set; }
    }

    [HttpPost("{id:guid}/delete")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Department", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id, [FromBody] DeleteDepartmentRequest req)
    {
        var storeId = RequiredStoreId;
        var dept = await db.Departments.AsTracking().FirstOrDefaultAsync(d => d.Id == id && d.StoreId == storeId);
        if (dept == null) return Ok(AppResponse<object>.Error("Phòng ban không tồn tại"));
        if (await db.Departments.AnyAsync(d => d.StoreId == storeId && d.ParentDepartmentId == id))
            return Ok(AppResponse<object>.Error("Phòng ban còn phòng con. Chuyển hoặc xóa phòng con trước."));
        if (req.TargetDepartmentId == id) return Ok(AppResponse<object>.Error("Phòng nhận phải khác phòng đang xóa"));

        var name = dept.Name.Trim();
        var empIds = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && (e.DepartmentId == id || (e.DepartmentId == null && e.Department == name)))
            .Select(e => e.Id).ToListAsync();
        if (empIds.Count > 0)
        {
            if (req.TargetDepartmentId == null)
                return Ok(AppResponse<object>.Error($"Phòng ban còn {empIds.Count} nhân viên. Chọn phòng ban nhận nhân viên trước khi xóa."));
            var moved = await DepartmentOrgHelper.MoveEmployeesAsync(db, storeId, empIds, req.TargetDepartmentId);
            if (moved < 0) return Ok(AppResponse<object>.Error("Không tìm thấy phòng ban nhận"));
        }
        // Người quản lý trực tiếp / phân quyền theo phòng ban bị xóa: giữ nguyên bản ghi, phòng ban xóa mềm.
        db.Departments.Remove(dept);
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { moved = empIds.Count }));
    }
}
