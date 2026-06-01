using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Application.Commands.ShiftSwaps.CreateShiftSwap;
using ZKTecoADMS.Application.Commands.ShiftSwaps.RespondToSwap;
using ZKTecoADMS.Application.Commands.ShiftSwaps.ApproveSwap;
using ZKTecoADMS.Application.Commands.ShiftSwaps.CancelSwap;
using ZKTecoADMS.Application.Queries.ShiftSwaps.GetShiftSwaps;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.ShiftSwaps;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ShiftSwapsController(IMediator mediator, ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    /// <summary>
    /// Danh sách đồng nghiệp cùng phòng ban (để chọn khi tạo yêu cầu đổi ca).
    /// </summary>
    [HttpGet("colleagues")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("ShiftSwap", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<SwapColleagueDto>>>> GetColleagues()
    {
        var myEmployee = await dbContext.Employees.AsNoTracking()
            .FirstOrDefaultAsync(e => e.ApplicationUserId == CurrentUserId && e.StoreId == RequiredStoreId);
        if (myEmployee == null)
            return Ok(AppResponse<List<SwapColleagueDto>>.Success([]));

        var query = dbContext.Employees.AsNoTracking()
            .Where(e => e.StoreId == RequiredStoreId
                && e.ApplicationUserId != null
                && e.ApplicationUserId != CurrentUserId
                && e.WorkStatus == EmployeeWorkStatus.Active);

        if (!string.IsNullOrWhiteSpace(myEmployee.Department))
            query = query.Where(e => e.Department == myEmployee.Department);

        var colleagues = await query
            .OrderBy(e => e.LastName).ThenBy(e => e.FirstName)
            .Select(e => new SwapColleagueDto
            {
                UserId = e.ApplicationUserId!.Value,
                FullName = (e.LastName + " " + e.FirstName).Trim(),
                EmployeeCode = e.EmployeeCode ?? "",
                Department = e.Department
            })
            .Take(300)
            .ToListAsync();

        return Ok(AppResponse<List<SwapColleagueDto>>.Success(colleagues));
    }

    /// <summary>
    /// Lấy danh sách yêu cầu đổi ca
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("ShiftSwap", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PagedResult<ShiftSwapRequestDto>>>> GetShiftSwaps(
        [FromQuery] PaginationRequest request,
        [FromQuery] ShiftSwapStatus? status = null)
    {
        var query = new GetShiftSwapsQuery(RequiredStoreId, CurrentUserId, IsManager, request, status);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Lấy các yêu cầu đang chờ xác nhận từ đồng nghiệp (cho user hiện tại)
    /// </summary>
    [HttpGet("pending-for-me")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("ShiftSwap", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PagedResult<ShiftSwapRequestDto>>>> GetPendingForMe(
        [FromQuery] PaginationRequest request)
    {
        var query = new GetShiftSwapsQuery(
            RequiredStoreId, CurrentUserId, false, request, ShiftSwapStatus.Pending,
            TargetUserIdOnly: true);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Lấy các yêu cầu chờ quản lý duyệt
    /// </summary>
    [HttpGet("pending-approval")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("ShiftSwap", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PagedResult<ShiftSwapRequestDto>>>> GetPendingApproval(
        [FromQuery] PaginationRequest request)
    {
        var query = new GetShiftSwapsQuery(RequiredStoreId, CurrentUserId, true, request, ShiftSwapStatus.TargetAccepted);
        var result = await mediator.Send(query);
        return Ok(result);
    }

    /// <summary>
    /// Tạo yêu cầu đổi ca mới
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("ShiftSwap", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<ShiftSwapRequestDto>>> CreateShiftSwap(
        [FromBody] CreateShiftSwapRequestDto request)
    {
        var command = new CreateShiftSwapCommand(
            RequiredStoreId,
            CurrentUserId,
            request.TargetUserId,
            request.RequesterDate,
            request.RequesterShiftId,
            request.TargetDate,
            request.TargetShiftId,
            request.Reason);

        var result = await mediator.Send(command);
        return Ok(result);
    }

    /// <summary>
    /// Phản hồi yêu cầu đổi ca (từ người được yêu cầu)
    /// </summary>
    [HttpPost("{id}/respond")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("ShiftSwap", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> RespondToSwap(
        Guid id,
        [FromBody] RespondShiftSwapDto request)
    {
        var command = new RespondToSwapCommand(
            RequiredStoreId,
            id,
            CurrentUserId,
            request.Accept,
            request.RejectionReason);

        var result = await mediator.Send(command);
        return Ok(result);
    }

    /// <summary>
    /// Quản lý phê duyệt/từ chối yêu cầu đổi ca
    /// </summary>
    [HttpPost("{id}/approve")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("ShiftSwap", ModulePermissionAction.Approve)]
    public async Task<ActionResult<AppResponse<bool>>> ApproveSwap(
        Guid id,
        [FromBody] ManagerDecisionDto request)
    {
        var command = new ApproveSwapCommand(
            RequiredStoreId,
            id,
            CurrentUserId,
            request.Approve,
            request.RejectionReason,
            request.Note);

        var result = await mediator.Send(command);
        return Ok(result);
    }

    /// <summary>
    /// Hủy yêu cầu đổi ca (chỉ người tạo mới được hủy)
    /// </summary>
    [HttpDelete("{id}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("ShiftSwap", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> CancelSwap(Guid id)
    {
        var command = new CancelSwapCommand(RequiredStoreId, id, CurrentUserId);
        var result = await mediator.Send(command);
        return Ok(result);
    }
}
