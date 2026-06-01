using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// API Controller quáº£n lÃ½ sÆ¡ Ä‘á»“ tá»• chá»©c & luá»“ng duyá»‡t
/// </summary>
[ApiController]
[Route("api/orgchart")]
[Authorize]
#pragma warning disable CS9113 // Parameter is unread
public class OrgChartController(
    ZKTecoDbContext dbContext,
    ILogger<OrgChartController> logger)
    : AuthenticatedControllerBase
#pragma warning restore CS9113
{
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // CHá»¨C Vá»¤ (OrgPosition) CRUD
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Láº¥y danh sÃ¡ch chá»©c vá»¥
    /// </summary>
    [HttpGet("positions")]
    [RequireModulePermission("OrgChart", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<OrgPositionDto>>>> GetPositions()
    {
        var storeId = CurrentStoreId;
        var query = storeId.HasValue
            ? dbContext.OrgPositions.Where(p => p.StoreId == storeId.Value)
            : dbContext.OrgPositions.AsQueryable();

        var positions = await query
            .Where(p => p.Deleted == null)
            .OrderBy(p => p.Level).ThenBy(p => p.SortOrder)
            .Select(p => new OrgPositionDto
            {
                Id = p.Id,
                Code = p.Code,
                Name = p.Name,
                Description = p.Description,
                Level = p.Level,
                SortOrder = p.SortOrder,
                Color = p.Color,
                IconName = p.IconName,
                CanApprove = p.CanApprove,
                MaxApprovalAmount = p.MaxApprovalAmount,
                IsActive = p.IsActive,
                AssignmentCount = p.OrgAssignments.Count(a => a.Deleted == null && a.IsActive)
            })
            .ToListAsync();

        return Ok(AppResponse<List<OrgPositionDto>>.Success(positions));
    }

    /// <summary>
    /// Táº¡o chá»©c vá»¥ má»›i
    /// </summary>
    [HttpPost("positions")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("OrgChart", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<OrgPositionDto>>> CreatePosition([FromBody] CreateOrgPositionRequest request)
    {
        var storeId = RequiredStoreId;

        // Check duplicate code
        var exists = await dbContext.OrgPositions
            .AnyAsync(p => p.StoreId == storeId && p.Code == request.Code && p.Deleted == null);
        if (exists)
            return Ok(AppResponse<OrgPositionDto>.Error($"MÃ£ chá»©c vá»¥ '{request.Code}' Ä‘Ã£ tá»“n táº¡i"));

        var position = new OrgPosition
        {
            Code = request.Code,
            Name = request.Name,
            Description = request.Description,
            Level = request.Level,
            SortOrder = request.SortOrder,
            Color = request.Color,
            IconName = request.IconName,
            CanApprove = request.CanApprove,
            MaxApprovalAmount = request.MaxApprovalAmount,
            StoreId = storeId,
            IsActive = true,
            CreatedBy = CurrentUserId.ToString()
        };

        dbContext.OrgPositions.Add(position);
        await dbContext.SaveChangesAsync();

        var dto = new OrgPositionDto
        {
            Id = position.Id,
            Code = position.Code,
            Name = position.Name,
            Description = position.Description,
            Level = position.Level,
            SortOrder = position.SortOrder,
            Color = position.Color,
            IconName = position.IconName,
            CanApprove = position.CanApprove,
            MaxApprovalAmount = position.MaxApprovalAmount,
            IsActive = position.IsActive,
            AssignmentCount = 0
        };

        return Ok(AppResponse<OrgPositionDto>.Success(dto));
    }

    /// <summary>
    /// Cáº­p nháº­t chá»©c vá»¥
    /// </summary>
    [HttpPut("positions/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("OrgChart", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<OrgPositionDto>>> UpdatePosition(Guid id, [FromBody] UpdateOrgPositionRequest request)
    {
        var storeId = RequiredStoreId;
        var position = await dbContext.OrgPositions
            .AsTracking()
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);

        if (position == null)
            return Ok(AppResponse<OrgPositionDto>.Error("KhÃ´ng tÃ¬m tháº¥y chá»©c vá»¥"));

        // Check duplicate code
        var exists = await dbContext.OrgPositions
            .AnyAsync(p => p.StoreId == storeId && p.Code == request.Code && p.Id != id && p.Deleted == null);
        if (exists)
            return Ok(AppResponse<OrgPositionDto>.Error($"MÃ£ chá»©c vá»¥ '{request.Code}' Ä‘Ã£ tá»“n táº¡i"));

        position.Code = request.Code;
        position.Name = request.Name;
        position.Description = request.Description;
        position.Level = request.Level;
        position.SortOrder = request.SortOrder;
        position.Color = request.Color;
        position.IconName = request.IconName;
        position.CanApprove = request.CanApprove;
        position.MaxApprovalAmount = request.MaxApprovalAmount;
        position.IsActive = request.IsActive;
        position.UpdatedAt = DateTime.Now;
        position.UpdatedBy = CurrentUserId.ToString();

        await dbContext.SaveChangesAsync();

        var dto = new OrgPositionDto
        {
            Id = position.Id,
            Code = position.Code,
            Name = position.Name,
            Description = position.Description,
            Level = position.Level,
            SortOrder = position.SortOrder,
            Color = position.Color,
            IconName = position.IconName,
            CanApprove = position.CanApprove,
            MaxApprovalAmount = position.MaxApprovalAmount,
            IsActive = position.IsActive,
            AssignmentCount = await dbContext.OrgAssignments.CountAsync(a => a.PositionId == id && a.Deleted == null && a.IsActive)
        };

        return Ok(AppResponse<OrgPositionDto>.Success(dto));
    }

    /// <summary>
    /// XÃ³a chá»©c vá»¥
    /// </summary>
    [HttpDelete("positions/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("OrgChart", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeletePosition(Guid id)
    {
        var storeId = RequiredStoreId;
        var position = await dbContext.OrgPositions
            .AsTracking()
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);

        if (position == null)
            return Ok(AppResponse<bool>.Error("KhÃ´ng tÃ¬m tháº¥y chá»©c vá»¥"));

        // Check if position is used in assignments
        var hasAssignments = await dbContext.OrgAssignments
            .AnyAsync(a => a.PositionId == id && a.Deleted == null);
        if (hasAssignments)
            return Ok(AppResponse<bool>.Error("KhÃ´ng thá»ƒ xÃ³a chá»©c vá»¥ Ä‘ang Ä‘Æ°á»£c gÃ¡n cho nhÃ¢n viÃªn"));

        position.Deleted = DateTime.Now;
        position.DeletedBy = CurrentUserId.ToString();
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // GÃN CHá»¨C Vá»¤ (OrgAssignment) CRUD
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Láº¥y danh sÃ¡ch gÃ¡n chá»©c vá»¥ (cÃ³ filter theo phÃ²ng ban)
    /// </summary>
    [HttpGet("assignments")]
    [RequireModulePermission("OrgChart", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<OrgAssignmentDto>>>> GetAssignments(
        [FromQuery] Guid? departmentId = null,
        [FromQuery] Guid? positionId = null,
        [FromQuery] Guid? employeeId = null)
    {
        var storeId = CurrentStoreId;
        var query = dbContext.OrgAssignments
            .Include(a => a.Employee)
            .Include(a => a.Department)
            .Include(a => a.Position)
            .Include(a => a.ReportToAssignment)
                .ThenInclude(r => r!.Employee)
            .Where(a => a.Deleted == null);

        if (storeId.HasValue)
            query = query.Where(a => a.StoreId == storeId.Value);
        if (departmentId.HasValue)
            query = query.Where(a => a.DepartmentId == departmentId.Value);
        if (positionId.HasValue)
            query = query.Where(a => a.PositionId == positionId.Value);
        if (employeeId.HasValue)
            query = query.Where(a => a.EmployeeId == employeeId.Value);

        var assignments = await query
            .OrderByDescending(a => a.StartDate)
            .ThenBy(a => a.Department!.Name)
            .ThenBy(a => a.Position!.Level)
            .ThenBy(a => a.Employee!.FirstName)
            .Select(a => new OrgAssignmentDto
            {
                Id = a.Id,
                EmployeeId = a.EmployeeId,
                EmployeeName = a.Employee != null ? a.Employee.LastName + " " + a.Employee.FirstName : "",
                EmployeeCode = a.Employee != null ? a.Employee.EmployeeCode : "",
                EmployeePhoto = a.Employee != null ? a.Employee.PhotoUrl : null,
                DepartmentId = a.DepartmentId,
                DepartmentName = a.Department != null ? a.Department.Name : "",
                PositionId = a.PositionId,
                PositionName = a.Position != null ? a.Position.Name : "",
                PositionLevel = a.Position != null ? a.Position.Level : 0,
                PositionColor = a.Position != null ? a.Position.Color : null,
                IsPrimary = a.IsPrimary,
                StartDate = a.StartDate,
                EndDate = a.EndDate,
                ReportToAssignmentId = a.ReportToAssignmentId,
                ReportToEmployeeName = a.ReportToAssignment != null && a.ReportToAssignment.Employee != null
                    ? a.ReportToAssignment.Employee.LastName + " " + a.ReportToAssignment.Employee.FirstName
                    : null,
                IsActive = a.Deleted == null && (!a.EndDate.HasValue || a.EndDate.Value.Date >= DateTime.UtcNow.Date),
                DirectReportsCount = a.DirectReports.Count(d => d.Deleted == null && d.IsActive)
            })
            .ToListAsync();

        return Ok(AppResponse<List<OrgAssignmentDto>>.Success(assignments));
    }

    /// <summary>
    /// Táº¡o gÃ¡n chá»©c vá»¥ má»›i
    /// </summary>
    [HttpPost("assignments")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("OrgChart", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<OrgAssignmentDto>>> CreateAssignment([FromBody] CreateOrgAssignmentRequest request)
    {
        var storeId = RequiredStoreId;

        // Validate employee exists
        var employee = await dbContext.Employees
            .FirstOrDefaultAsync(e => e.Id == request.EmployeeId && e.StoreId == storeId && e.Deleted == null);
        if (employee == null)
            return Ok(AppResponse<OrgAssignmentDto>.Error("KhÃ´ng tÃ¬m tháº¥y nhÃ¢n viÃªn"));

        // Validate department exists
        var department = await dbContext.Departments
            .FirstOrDefaultAsync(d => d.Id == request.DepartmentId && d.StoreId == storeId && d.Deleted == null);
        if (department == null)
            return Ok(AppResponse<OrgAssignmentDto>.Error("KhÃ´ng tÃ¬m tháº¥y phÃ²ng ban"));

        // Validate position exists
        var position = await dbContext.OrgPositions
            .FirstOrDefaultAsync(p => p.Id == request.PositionId && p.StoreId == storeId && p.Deleted == null);
        if (position == null)
            return Ok(AppResponse<OrgAssignmentDto>.Error("KhÃ´ng tÃ¬m tháº¥y chá»©c vá»¥"));

        // Chỉ chặn trùng khi còn một gán đang hiệu lực (chưa có ngày kết thúc)
        var existsActive = await dbContext.OrgAssignments
            .AnyAsync(a => a.EmployeeId == request.EmployeeId
                && a.DepartmentId == request.DepartmentId
                && a.PositionId == request.PositionId
                && a.Deleted == null
                && a.EndDate == null);
        if (existsActive)
            return Ok(AppResponse<OrgAssignmentDto>.Error("Nhân viên đang giữ chức vụ này tại phòng ban (chưa kết thúc). Hãy kết thúc bản ghi cũ trước khi thêm mới."));

        var today = DateTime.UtcNow.Date;
        var isCurrentlyHeld = !request.EndDate.HasValue || request.EndDate.Value.Date >= today;

        // Kết thúc các chức vụ chính cũ khi gán chính mới
        if (request.IsPrimary && isCurrentlyHeld)
        {
            var endOn = request.StartDate?.Date ?? today;
            var otherPrimaries = await dbContext.OrgAssignments
                .AsTracking()
                .Where(a => a.EmployeeId == request.EmployeeId && a.IsPrimary && a.Deleted == null && a.EndDate == null)
                .ToListAsync();
            foreach (var op in otherPrimaries)
            {
                op.IsPrimary = false;
                op.EndDate = endOn;
                op.IsActive = false;
                op.UpdatedAt = DateTime.UtcNow;
                op.UpdatedBy = CurrentUserId.ToString();
            }
        }
        else if (request.IsPrimary)
        {
            var otherPrimaries = await dbContext.OrgAssignments
                .AsTracking()
                .Where(a => a.EmployeeId == request.EmployeeId && a.IsPrimary && a.Deleted == null)
                .ToListAsync();
            foreach (var op in otherPrimaries)
                op.IsPrimary = false;
        }

        var assignment = new OrgAssignment
        {
            EmployeeId = request.EmployeeId,
            DepartmentId = request.DepartmentId,
            PositionId = request.PositionId,
            IsPrimary = request.IsPrimary,
            StartDate = request.StartDate,
            EndDate = request.EndDate,
            ReportToAssignmentId = request.ReportToAssignmentId,
            StoreId = storeId,
            IsActive = isCurrentlyHeld,
            CreatedBy = CurrentUserId.ToString()
        };

        dbContext.OrgAssignments.Add(assignment);

        if (request.IsPrimary && isCurrentlyHeld)
            employee.DepartmentId = request.DepartmentId;

        await dbContext.SaveChangesAsync();

        var dto = new OrgAssignmentDto
        {
            Id = assignment.Id,
            EmployeeId = assignment.EmployeeId,
            EmployeeName = employee.LastName + " " + employee.FirstName,
            EmployeeCode = employee.EmployeeCode,
            EmployeePhoto = employee.PhotoUrl,
            DepartmentId = assignment.DepartmentId,
            DepartmentName = department.Name,
            PositionId = assignment.PositionId,
            PositionName = position.Name,
            PositionLevel = position.Level,
            PositionColor = position.Color,
            IsPrimary = assignment.IsPrimary,
            StartDate = assignment.StartDate,
            EndDate = assignment.EndDate,
            ReportToAssignmentId = assignment.ReportToAssignmentId,
            IsActive = assignment.Deleted == null && (!assignment.EndDate.HasValue || assignment.EndDate.Value.Date >= DateTime.UtcNow.Date),
            DirectReportsCount = 0
        };

        return Ok(AppResponse<OrgAssignmentDto>.Success(dto));
    }

    /// <summary>
    /// Cáº­p nháº­t gÃ¡n chá»©c vá»¥
    /// </summary>
    [HttpPut("assignments/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("OrgChart", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<OrgAssignmentDto>>> UpdateAssignment(Guid id, [FromBody] UpdateOrgAssignmentRequest request)
    {
        var storeId = RequiredStoreId;
        var assignment = await dbContext.OrgAssignments
            .AsTracking()
            .Include(a => a.Employee)
            .Include(a => a.Department)
            .Include(a => a.Position)
            .FirstOrDefaultAsync(a => a.Id == id && a.StoreId == storeId && a.Deleted == null);

        if (assignment == null)
            return Ok(AppResponse<OrgAssignmentDto>.Error("KhÃ´ng tÃ¬m tháº¥y báº£n ghi gÃ¡n chá»©c vá»¥"));

        // If setting as primary, unset others
        if (request.IsPrimary && !assignment.IsPrimary)
        {
            var otherPrimaries = await dbContext.OrgAssignments
                .AsTracking()
                .Where(a => a.EmployeeId == assignment.EmployeeId && a.IsPrimary && a.Id != id && a.Deleted == null)
                .ToListAsync();
            foreach (var op in otherPrimaries)
                op.IsPrimary = false;
        }

        assignment.IsPrimary = request.IsPrimary;
        assignment.ReportToAssignmentId = request.ReportToAssignmentId;
        assignment.StartDate = request.StartDate;
        assignment.EndDate = request.EndDate;
        var today = DateTime.UtcNow.Date;
        assignment.IsActive = request.IsActive
            && (!assignment.EndDate.HasValue || assignment.EndDate.Value.Date >= today);
        assignment.UpdatedAt = DateTime.UtcNow;
        assignment.UpdatedBy = CurrentUserId.ToString();

        if (assignment.IsPrimary && assignment.IsActive && assignment.Employee != null)
            assignment.Employee.DepartmentId = assignment.DepartmentId;

        await dbContext.SaveChangesAsync();

        var dto = new OrgAssignmentDto
        {
            Id = assignment.Id,
            EmployeeId = assignment.EmployeeId,
            EmployeeName = assignment.Employee != null ? assignment.Employee.LastName + " " + assignment.Employee.FirstName : "",
            EmployeeCode = assignment.Employee?.EmployeeCode ?? "",
            EmployeePhoto = assignment.Employee?.PhotoUrl,
            DepartmentId = assignment.DepartmentId,
            DepartmentName = assignment.Department?.Name ?? "",
            PositionId = assignment.PositionId,
            PositionName = assignment.Position?.Name ?? "",
            PositionLevel = assignment.Position?.Level ?? 0,
            PositionColor = assignment.Position?.Color,
            IsPrimary = assignment.IsPrimary,
            StartDate = assignment.StartDate,
            EndDate = assignment.EndDate,
            ReportToAssignmentId = assignment.ReportToAssignmentId,
            IsActive = assignment.Deleted == null && (!assignment.EndDate.HasValue || assignment.EndDate.Value.Date >= today),
            DirectReportsCount = await dbContext.OrgAssignments.CountAsync(d => d.ReportToAssignmentId == id && d.Deleted == null && d.IsActive)
        };

        return Ok(AppResponse<OrgAssignmentDto>.Success(dto));
    }

    /// <summary>
    /// XÃ³a gÃ¡n chá»©c vá»¥
    /// </summary>
    [HttpDelete("assignments/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("OrgChart", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteAssignment(Guid id)
    {
        var storeId = RequiredStoreId;
        var assignment = await dbContext.OrgAssignments
            .AsTracking()
            .FirstOrDefaultAsync(a => a.Id == id && a.StoreId == storeId && a.Deleted == null);

        if (assignment == null)
            return Ok(AppResponse<bool>.Error("KhÃ´ng tÃ¬m tháº¥y báº£n ghi gÃ¡n chá»©c vá»¥"));

        // Check if anyone reports to this assignment
        var hasReports = await dbContext.OrgAssignments
            .AnyAsync(a => a.ReportToAssignmentId == id && a.Deleted == null);
        if (hasReports)
            return Ok(AppResponse<bool>.Error("KhÃ´ng thá»ƒ xÃ³a - cÃ³ nhÃ¢n viÃªn Ä‘ang bÃ¡o cÃ¡o cho chá»©c vá»¥ nÃ y"));

        assignment.Deleted = DateTime.Now;
        assignment.DeletedBy = CurrentUserId.ToString();
        await dbContext.SaveChangesAsync();

        return Ok(AppResponse<bool>.Success(true));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // SÆ  Äá»’ Tá»” CHá»¨C (OrgChart Tree)
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Láº¥y sÆ¡ Ä‘á»“ tá»• chá»©c dáº¡ng cÃ¢y (theo phÃ²ng ban + chá»©c vá»¥ + nhÃ¢n viÃªn)
    /// </summary>
    [HttpGet("tree")]
    [RequireModulePermission("OrgChart", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<OrgChartNodeDto>>>> GetOrgChartTree()
    {
        var storeId = CurrentStoreId;

        // Get all departments
        var departments = await dbContext.Departments
            .Where(d => d.Deleted == null && d.IsActive && (storeId == null || d.StoreId == storeId))
            .OrderBy(d => d.Level).ThenBy(d => d.SortOrder)
            .ToListAsync();

        // Get all active assignments with employee + position
        var assignments = await dbContext.OrgAssignments
            .Include(a => a.Employee)
            .Include(a => a.Position)
            .Where(a => a.Deleted == null && a.IsActive && (storeId == null || a.StoreId == storeId))
            .OrderBy(a => a.Position!.Level).ThenBy(a => a.Employee!.LastName)
            .ToListAsync();

        // Build tree: root departments first
        var rootDepts = departments.Where(d => d.ParentDepartmentId == null).ToList();
        var tree = new List<OrgChartNodeDto>();

        foreach (var dept in rootDepts)
        {
            tree.Add(BuildDeptNode(dept, departments, assignments));
        }

        return Ok(AppResponse<List<OrgChartNodeDto>>.Success(tree));
    }

    private OrgChartNodeDto BuildDeptNode(Department dept, List<Department> allDepts, List<OrgAssignment> allAssignments)
    {
        var deptAssignments = allAssignments.Where(a => a.DepartmentId == dept.Id).ToList();

        var node = new OrgChartNodeDto
        {
            Id = dept.Id.ToString(),
            NodeType = "department",
            Name = dept.Name,
            Code = dept.Code,
            Description = dept.Description,
            Level = dept.Level,
            Members = deptAssignments.Select(a => new OrgChartMemberDto
            {
                AssignmentId = a.Id,
                EmployeeId = a.EmployeeId,
                EmployeeName = a.Employee != null ? a.Employee.LastName + " " + a.Employee.FirstName : "",
                EmployeeCode = a.Employee?.EmployeeCode ?? "",
                EmployeePhoto = a.Employee?.PhotoUrl,
                PositionId = a.PositionId,
                PositionName = a.Position?.Name ?? "",
                PositionLevel = a.Position?.Level ?? 0,
                PositionColor = a.Position?.Color,
                IsPrimary = a.IsPrimary,
                ReportToAssignmentId = a.ReportToAssignmentId,
                IsHead = a.Position?.Level == deptAssignments.Min(x => x.Position?.Level ?? 999)
            }).OrderBy(m => m.PositionLevel).ToList(),
            Children = new List<OrgChartNodeDto>()
        };

        // Add child departments
        var childDepts = allDepts.Where(d => d.ParentDepartmentId == dept.Id).OrderBy(d => d.SortOrder).ToList();
        foreach (var child in childDepts)
        {
            node.Children.Add(BuildDeptNode(child, allDepts, allAssignments));
        }

        return node;
    }

    /// <summary>
    /// Láº¥y thá»‘ng kÃª sÆ¡ Ä‘á»“ tá»• chá»©c
    /// </summary>
    [HttpGet("stats")]
    [RequireModulePermission("OrgChart", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<OrgChartStatsDto>>> GetOrgChartStats()
    {
        var storeId = CurrentStoreId;

        var totalDepartments = await dbContext.Departments
            .CountAsync(d => d.Deleted == null && d.IsActive && (storeId == null || d.StoreId == storeId));

        var totalPositions = await dbContext.OrgPositions
            .CountAsync(p => p.Deleted == null && p.IsActive && (storeId == null || p.StoreId == storeId));

        var totalAssignments = await dbContext.OrgAssignments
            .CountAsync(a => a.Deleted == null && a.IsActive && (storeId == null || a.StoreId == storeId));

        var totalEmployees = await dbContext.Employees
            .CountAsync(e => e.Deleted == null && e.IsActive && (storeId == null || e.StoreId == storeId));

        var unassignedEmployees = totalEmployees - await dbContext.OrgAssignments
            .Where(a => a.Deleted == null && a.IsActive && (storeId == null || a.StoreId == storeId))
            .Select(a => a.EmployeeId)
            .Distinct()
            .CountAsync();

        var totalApprovalFlows = await dbContext.ApprovalFlows
            .CountAsync(f => f.Deleted == null && f.IsActive && (storeId == null || f.StoreId == storeId));

        return Ok(AppResponse<OrgChartStatsDto>.Success(new OrgChartStatsDto
        {
            TotalDepartments = totalDepartments,
            TotalPositions = totalPositions,
            TotalAssignments = totalAssignments,
            TotalEmployees = totalEmployees,
            UnassignedEmployees = unassignedEmployees < 0 ? 0 : unassignedEmployees,
            TotalApprovalFlows = totalApprovalFlows
        }));
    }

    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
    // LUá»’NG DUYá»†T (ApprovalFlow) CRUD
    // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

    /// <summary>
    /// Láº¥y danh sÃ¡ch luá»“ng duyá»‡t
    /// </summary>
    [HttpGet("approval-flows")]
    [RequireModulePermission("OrgChart", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ApprovalFlowDto>>>> GetApprovalFlows()
    {
        var storeId = CurrentStoreId;
        var query = dbContext.ApprovalFlows
            .Include(f => f.Steps.Where(s => s.Deleted == null).OrderBy(s => s.StepOrder))
                .ThenInclude(s => s.ApproverPosition)
            .Include(f => f.Steps.Where(s => s.Deleted == null).OrderBy(s => s.StepOrder))
                .ThenInclude(s => s.ApproverEmployee)
            .Include(f => f.Department)
            .Where(f => f.Deleted == null);

        if (storeId.HasValue)
            query = query.Where(f => f.StoreId == storeId.Value);

        var flows = await query
            .OrderBy(f => f.RequestType).ThenBy(f => f.Priority)
            .Select(f => new ApprovalFlowDto
            {
                Id = f.Id,
                Code = f.Code,
                Name = f.Name,
                Description = f.Description,
                RequestType = f.RequestType,
                RequestTypeName = f.RequestType.ToString(),
                DepartmentId = f.DepartmentId,
                DepartmentName = f.Department != null ? f.Department.Name : null,
                Priority = f.Priority,
                IsActive = f.IsActive,
                Steps = f.Steps.Select(s => new ApprovalStepDto
                {
                    Id = s.Id,
                    StepOrder = s.StepOrder,
                    Name = s.Name,
                    ApproverType = s.ApproverType,
                    ApproverTypeName = s.ApproverType.ToString(),
                    ApproverPositionId = s.ApproverPositionId,
                    ApproverPositionName = s.ApproverPosition != null ? s.ApproverPosition.Name : null,
                    ApproverEmployeeId = s.ApproverEmployeeId,
                    ApproverEmployeeName = s.ApproverEmployee != null
                        ? s.ApproverEmployee.LastName + " " + s.ApproverEmployee.FirstName : null,
                    IsRequired = s.IsRequired,
                    MaxWaitHours = s.MaxWaitHours,
                    TimeoutAction = s.TimeoutAction,
                    TimeoutActionName = s.TimeoutAction.ToString(),
                    IsActive = s.IsActive
                }).OrderBy(s => s.StepOrder).ToList()
            })
            .ToListAsync();

        return Ok(AppResponse<List<ApprovalFlowDto>>.Success(flows));
    }

    /// <summary>
    /// Táº¡o luá»“ng duyá»‡t má»›i (kÃ¨m cÃ¡c bÆ°á»›c)
    /// </summary>
    [HttpPost("approval-flows")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("OrgChart", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<ApprovalFlowDto>>> CreateApprovalFlow([FromBody] CreateApprovalFlowRequest request)
    {
        var storeId = RequiredStoreId;

        // Check duplicate code
        var exists = await dbContext.ApprovalFlows
            .AnyAsync(f => f.StoreId == storeId && f.Code == request.Code && f.Deleted == null);
        if (exists)
            return Ok(AppResponse<ApprovalFlowDto>.Error($"MÃ£ luá»“ng duyá»‡t '{request.Code}' Ä‘Ã£ tá»“n táº¡i"));

        var flow = new ApprovalFlow
        {
            Code = request.Code,
            Name = request.Name,
            Description = request.Description,
            RequestType = request.RequestType,
            DepartmentId = request.DepartmentId,
            Priority = request.Priority,
            StoreId = storeId,
            IsActive = true,
            CreatedBy = CurrentUserId.ToString()
        };

        // Add steps
        if (request.Steps != null)
        {
            int order = 1;
            foreach (var stepReq in request.Steps)
            {
                flow.Steps.Add(new ApprovalStep
                {
                    StepOrder = order++,
                    Name = stepReq.Name,
                    ApproverType = stepReq.ApproverType,
                    ApproverPositionId = stepReq.ApproverPositionId,
                    ApproverEmployeeId = stepReq.ApproverEmployeeId,
                    IsRequired = stepReq.IsRequired,
                    MaxWaitHours = stepReq.MaxWaitHours,
                    TimeoutAction = stepReq.TimeoutAction,
                    IsActive = true,
                    CreatedBy = CurrentUserId.ToString()
                });
            }
        }

        dbContext.ApprovalFlows.Add(flow);
        await dbContext.SaveChangesAsync();

        // Return DTO
        var dto = new ApprovalFlowDto
        {
            Id = flow.Id,
            Code = flow.Code,
            Name = flow.Name,
            Description = flow.Description,
            RequestType = flow.RequestType,
            RequestTypeName = flow.RequestType.ToString(),
            DepartmentId = flow.DepartmentId,
            Priority = flow.Priority,
            IsActive = flow.IsActive,
            Steps = flow.Steps.Select(s => new ApprovalStepDto
            {
                Id = s.Id,
                StepOrder = s.StepOrder,
                Name = s.Name,
                ApproverType = s.ApproverType,
                ApproverTypeName = s.ApproverType.ToString(),
                ApproverPositionId = s.ApproverPositionId,
                ApproverEmployeeId = s.ApproverEmployeeId,
                IsRequired = s.IsRequired,
                MaxWaitHours = s.MaxWaitHours,
                TimeoutAction = s.TimeoutAction,
                TimeoutActionName = s.TimeoutAction.ToString(),
                IsActive = s.IsActive
            }).ToList()
        };

        return Ok(AppResponse<ApprovalFlowDto>.Success(dto));
    }

    /// <summary>
    /// Cáº­p nháº­t luá»“ng duyá»‡t (kÃ¨m cáº­p nháº­t cÃ¡c bÆ°á»›c)
    /// </summary>
    [HttpPut("approval-flows/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("OrgChart", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<ApprovalFlowDto>>> UpdateApprovalFlow(Guid id, [FromBody] UpdateApprovalFlowRequest request)
    {
        var storeId = RequiredStoreId;
        var flow = await dbContext.ApprovalFlows
            .AsTracking()
            .Include(f => f.Steps)
            .FirstOrDefaultAsync(f => f.Id == id && f.StoreId == storeId && f.Deleted == null);

        if (flow == null)
            return Ok(AppResponse<ApprovalFlowDto>.Error("KhÃ´ng tÃ¬m tháº¥y luá»“ng duyá»‡t"));

        flow.Code = request.Code;
        flow.Name = request.Name;
        flow.Description = request.Description;
        flow.RequestType = request.RequestType;
        flow.DepartmentId = request.DepartmentId;
        flow.Priority = request.Priority;
        flow.IsActive = request.IsActive;
        flow.UpdatedAt = DateTime.Now;
        flow.UpdatedBy = CurrentUserId.ToString();

        // Replace steps
        if (request.Steps != null)
        {
            // Soft delete old steps
            foreach (var oldStep in flow.Steps.Where(s => s.Deleted == null))
            {
                oldStep.Deleted = DateTime.Now;
                oldStep.DeletedBy = CurrentUserId.ToString();
            }

            int order = 1;
            foreach (var stepReq in request.Steps)
            {
                flow.Steps.Add(new ApprovalStep
                {
                    StepOrder = order++,
                    Name = stepReq.Name,
                    ApproverType = stepReq.ApproverType,
                    ApproverPositionId = stepReq.ApproverPositionId,
                    ApproverEmployeeId = stepReq.ApproverEmployeeId,
                    IsRequired = stepReq.IsRequired,
                    MaxWaitHours = stepReq.MaxWaitHours,
                    TimeoutAction = stepReq.TimeoutAction,
                    IsActive = true,
                    CreatedBy = CurrentUserId.ToString()
                });
            }
        }

        await dbContext.SaveChangesAsync();

        var dto = new ApprovalFlowDto
        {
            Id = flow.Id,
            Code = flow.Code,
            Name = flow.Name,
            Description = flow.Description,
            RequestType = flow.RequestType,
            RequestTypeName = flow.RequestType.ToString(),
            DepartmentId = flow.DepartmentId,
            Priority = flow.Priority,
            IsActive = flow.IsActive,
            Steps = flow.Steps.Where(s => s.Deleted == null).OrderBy(s => s.StepOrder).Select(s => new ApprovalStepDto
            {
                Id = s.Id,
                StepOrder = s.StepOrder,
                Name = s.Name,
                ApproverType = s.ApproverType,
                ApproverTypeName = s.ApproverType.ToString(),
                ApproverPositionId = s.ApproverPositionId,
                ApproverEmployeeId = s.ApproverEmployeeId,
                IsRequired = s.IsRequired,
                MaxWaitHours = s.MaxWaitHours,
                TimeoutAction = s.TimeoutAction,
                TimeoutActionName = s.TimeoutAction.ToString(),
                IsActive = s.IsActive
            }).ToList()
        };

        return Ok(AppResponse<ApprovalFlowDto>.Success(dto));
    }

    /// <summary>
    /// XÃ³a luá»“ng duyá»‡t
    /// </summary>
    [HttpDelete("approval-flows/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("OrgChart", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteApprovalFlow(Guid id)
    {
        var storeId = RequiredStoreId;
        var flow = await dbContext.ApprovalFlows
            .AsTracking()
            .Include(f => f.Steps)
            .FirstOrDefaultAsync(f => f.Id == id && f.StoreId == storeId && f.Deleted == null);

        if (flow == null)
            return Ok(AppResponse<bool>.Error("KhÃ´ng tÃ¬m tháº¥y luá»“ng duyá»‡t"));

        flow.Deleted = DateTime.Now;
        flow.DeletedBy = CurrentUserId.ToString();

        foreach (var step in flow.Steps.Where(s => s.Deleted == null))
        {
            step.Deleted = DateTime.Now;
            step.DeletedBy = CurrentUserId.ToString();
        }

        await dbContext.SaveChangesAsync();
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>
    /// Láº¥y danh sÃ¡ch nhÃ¢n viÃªn chÆ°a Ä‘Æ°á»£c gÃ¡n chá»©c vá»¥
    /// </summary>
    [HttpGet("unassigned-employees")]
    [RequireModulePermission("OrgChart", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<UnassignedEmployeeDto>>>> GetUnassignedEmployees()
    {
        var storeId = CurrentStoreId;

        var assignedEmployeeIds = await dbContext.OrgAssignments
            .Where(a => a.Deleted == null && a.IsActive && (storeId == null || a.StoreId == storeId))
            .Select(a => a.EmployeeId)
            .Distinct()
            .ToListAsync();

        var unassigned = await dbContext.Employees
            .Where(e => e.Deleted == null && e.IsActive && (storeId == null || e.StoreId == storeId)
                && !assignedEmployeeIds.Contains(e.Id))
            .OrderBy(e => e.LastName).ThenBy(e => e.FirstName)
            .Select(e => new UnassignedEmployeeDto
            {
                Id = e.Id,
                EmployeeCode = e.EmployeeCode,
                FullName = e.LastName + " " + e.FirstName,
                PhotoUrl = e.PhotoUrl,
                DepartmentName = e.Department,
                Position = e.Position,
                CompanyEmail = e.CompanyEmail
            })
            .ToListAsync();

        return Ok(AppResponse<List<UnassignedEmployeeDto>>.Success(unassigned));
    }
}

// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
// DTOs
// â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

public class OrgPositionDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public int Level { get; set; }
    public int SortOrder { get; set; }
    public string? Color { get; set; }
    public string? IconName { get; set; }
    public bool CanApprove { get; set; }
    public decimal? MaxApprovalAmount { get; set; }
    public bool IsActive { get; set; }
    public int AssignmentCount { get; set; }
}

public class CreateOrgPositionRequest
{
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public int Level { get; set; }
    public int SortOrder { get; set; }
    public string? Color { get; set; }
    public string? IconName { get; set; }
    public bool CanApprove { get; set; }
    public decimal? MaxApprovalAmount { get; set; }
}

public class UpdateOrgPositionRequest
{
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public int Level { get; set; }
    public int SortOrder { get; set; }
    public string? Color { get; set; }
    public string? IconName { get; set; }
    public bool CanApprove { get; set; }
    public decimal? MaxApprovalAmount { get; set; }
    public bool IsActive { get; set; }
}

public class OrgAssignmentDto
{
    public Guid Id { get; set; }
    public Guid EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string EmployeeCode { get; set; } = string.Empty;
    public string? EmployeePhoto { get; set; }
    public Guid DepartmentId { get; set; }
    public string DepartmentName { get; set; } = string.Empty;
    public Guid PositionId { get; set; }
    public string PositionName { get; set; } = string.Empty;
    public int PositionLevel { get; set; }
    public string? PositionColor { get; set; }
    public bool IsPrimary { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public Guid? ReportToAssignmentId { get; set; }
    public string? ReportToEmployeeName { get; set; }
    public bool IsActive { get; set; }
    public int DirectReportsCount { get; set; }
}

public class CreateOrgAssignmentRequest
{
    public Guid EmployeeId { get; set; }
    public Guid DepartmentId { get; set; }
    public Guid PositionId { get; set; }
    public bool IsPrimary { get; set; } = true;
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public Guid? ReportToAssignmentId { get; set; }
}

public class UpdateOrgAssignmentRequest
{
    public bool IsPrimary { get; set; }
    public Guid? ReportToAssignmentId { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
    public bool IsActive { get; set; }
}

public class OrgChartNodeDto
{
    public string Id { get; set; } = string.Empty;
    public string NodeType { get; set; } = string.Empty; // "department"
    public string Name { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty;
    public string? Description { get; set; }
    public int Level { get; set; }
    public List<OrgChartMemberDto> Members { get; set; } = new();
    public List<OrgChartNodeDto> Children { get; set; } = new();
}

public class OrgChartMemberDto
{
    public Guid AssignmentId { get; set; }
    public Guid EmployeeId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string EmployeeCode { get; set; } = string.Empty;
    public string? EmployeePhoto { get; set; }
    public Guid PositionId { get; set; }
    public string PositionName { get; set; } = string.Empty;
    public int PositionLevel { get; set; }
    public string? PositionColor { get; set; }
    public bool IsPrimary { get; set; }
    public Guid? ReportToAssignmentId { get; set; }
    public bool IsHead { get; set; }
}

public class OrgChartStatsDto
{
    public int TotalDepartments { get; set; }
    public int TotalPositions { get; set; }
    public int TotalAssignments { get; set; }
    public int TotalEmployees { get; set; }
    public int UnassignedEmployees { get; set; }
    public int TotalApprovalFlows { get; set; }
}

public class ApprovalFlowDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public ApprovalRequestType RequestType { get; set; }
    public string RequestTypeName { get; set; } = string.Empty;
    public Guid? DepartmentId { get; set; }
    public string? DepartmentName { get; set; }
    public int Priority { get; set; }
    public bool IsActive { get; set; }
    public List<ApprovalStepDto> Steps { get; set; } = new();
}

public class ApprovalStepDto
{
    public Guid Id { get; set; }
    public int StepOrder { get; set; }
    public string Name { get; set; } = string.Empty;
    public ApproverType ApproverType { get; set; }
    public string ApproverTypeName { get; set; } = string.Empty;
    public Guid? ApproverPositionId { get; set; }
    public string? ApproverPositionName { get; set; }
    public Guid? ApproverEmployeeId { get; set; }
    public string? ApproverEmployeeName { get; set; }
    public bool IsRequired { get; set; }
    public int? MaxWaitHours { get; set; }
    public TimeoutAction TimeoutAction { get; set; }
    public string TimeoutActionName { get; set; } = string.Empty;
    public bool IsActive { get; set; }
}

public class CreateApprovalFlowRequest
{
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public ApprovalRequestType RequestType { get; set; }
    public Guid? DepartmentId { get; set; }
    public int Priority { get; set; }
    public List<CreateApprovalStepRequest>? Steps { get; set; }
}

public class UpdateApprovalFlowRequest
{
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public ApprovalRequestType RequestType { get; set; }
    public Guid? DepartmentId { get; set; }
    public int Priority { get; set; }
    public bool IsActive { get; set; }
    public List<CreateApprovalStepRequest>? Steps { get; set; }
}

public class CreateApprovalStepRequest
{
    public string Name { get; set; } = string.Empty;
    public ApproverType ApproverType { get; set; }
    public Guid? ApproverPositionId { get; set; }
    public Guid? ApproverEmployeeId { get; set; }
    public bool IsRequired { get; set; } = true;
    public int? MaxWaitHours { get; set; }
    public TimeoutAction TimeoutAction { get; set; } = TimeoutAction.Escalate;
}

public class UnassignedEmployeeDto
{
    public Guid Id { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public string? PhotoUrl { get; set; }
    public string? DepartmentName { get; set; }
    public string? Position { get; set; }
    public string CompanyEmail { get; set; } = string.Empty;
}

