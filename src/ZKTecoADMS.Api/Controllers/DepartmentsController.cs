using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.Departments.CreateDepartment;
using ZKTecoADMS.Application.Commands.Departments.UpdateDepartment;
using ZKTecoADMS.Application.Commands.Departments.DeleteDepartment;
using ZKTecoADMS.Application.Queries.Departments.GetAllDepartments;
using ZKTecoADMS.Application.Queries.Departments.GetDepartmentById;
using ZKTecoADMS.Application.Queries.Departments.GetDepartmentTree;
using ZKTecoADMS.Application.Queries.Departments.GetDepartmentsForSelect;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Departments;
using ZKTecoADMS.Application.Models;

using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class DepartmentsController(IMediator mediator, ICacheService cacheService) : AuthenticatedControllerBase
{
    /// <summary>
    /// Lấy danh sách phòng ban có phân trang
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<PagedResult<DepartmentDto>>>> GetAllDepartments(
        [FromQuery] PaginationRequest request,
        [FromQuery] string? searchTerm = null,
        [FromQuery] bool? isActive = null)
    {
        var query = new GetAllDepartmentsQuery(RequiredStoreId, request, searchTerm, isActive);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Lấy cây phòng ban (tree view)
    /// </summary>
    [HttpGet("tree")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<DepartmentTreeNodeDto>>>> GetDepartmentTree(
        [FromQuery] bool includeInactive = false)
    {
        var query = new GetDepartmentTreeQuery(RequiredStoreId, includeInactive);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Lấy danh sách phòng ban cho dropdown
    /// </summary>
    [HttpGet("select")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<DepartmentSelectDto>>>> GetDepartmentsForSelect()
    {
        var storeId = RequiredStoreId;
        var result = await cacheService.GetOrCreateAsync(
            $"departments_select_{storeId}",
            async () =>
            {
                var query = new GetDepartmentsForSelectQuery(storeId);
                return await mediator.Send(query);
            },
            TimeSpan.FromMinutes(10));
        return Ok(result);
    }

    /// <summary>
    /// Lấy thông tin chi tiết phòng ban
    /// </summary>
    [HttpGet("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<DepartmentDto>>> GetDepartmentById(Guid id)
    {
        var query = new GetDepartmentByIdQuery(RequiredStoreId, id);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Tạo phòng ban mới
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<DepartmentDto>>> CreateDepartment([FromBody] CreateDepartmentDto request)
    {
        var command = new CreateDepartmentCommand(
            RequiredStoreId,
            request.Code,
            request.Name,
            request.Description,
            request.ParentDepartmentId,
            request.ManagerId,
            request.SortOrder,
            request.Positions);

        var result = await mediator.Send(command);
        cacheService.RemoveByPrefix("departments_select_");
        return Ok(result);
    }

    /// <summary>
    /// Cập nhật phòng ban
    /// </summary>
    [HttpPut("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<DepartmentDto>>> UpdateDepartment(Guid id, [FromBody] UpdateDepartmentDto request)
    {
        var command = new UpdateDepartmentCommand(
            RequiredStoreId,
            id,
            request.Code,
            request.Name,
            request.Description,
            request.ParentDepartmentId,
            request.ManagerId,
            request.SortOrder,
            request.IsActive,
            request.Positions);

        var result = await mediator.Send(command);
        cacheService.RemoveByPrefix("departments_select_");
        return Ok(result);
    }

    /// <summary>
    /// Xóa phòng ban
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteDepartment(Guid id)
    {
        var command = new DeleteDepartmentCommand(RequiredStoreId, id);
        var result = await mediator.Send(command);
        cacheService.RemoveByPrefix("departments_select_");
        return Ok(result);
    }
}
