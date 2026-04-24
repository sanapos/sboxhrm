using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// SuperAdmin: quản lý cửa sổ bảo trì.
/// </summary>
[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin/maintenance")]
public class MaintenanceWindowsController : AuthenticatedControllerBase
{
    private readonly IMaintenanceService _svc;
    public MaintenanceWindowsController(IMaintenanceService svc) { _svc = svc; }

    [HttpGet]
    public async Task<ActionResult<AppResponse<List<MaintenanceWindowDto>>>> List([FromQuery] bool? activeOnly, CancellationToken ct)
    {
        var data = await _svc.ListAsync(activeOnly, ct);
        return Ok(AppResponse<List<MaintenanceWindowDto>>.Success(data));
    }

    [HttpPost]
    public async Task<ActionResult<AppResponse<MaintenanceWindowDto>>> Create([FromBody] CreateMaintenanceWindowDto dto, CancellationToken ct)
    {
        var data = await _svc.CreateAsync(dto, CurrentUserId, ct);
        return Ok(AppResponse<MaintenanceWindowDto>.Success(data));
    }

    [HttpPost("{id:guid}/activate")]
    public async Task<ActionResult<AppResponse<bool>>> Activate(Guid id, CancellationToken ct)
        => Ok(AppResponse<bool>.Success(await _svc.SetActiveAsync(id, true, ct)));

    [HttpPost("{id:guid}/deactivate")]
    public async Task<ActionResult<AppResponse<bool>>> Deactivate(Guid id, CancellationToken ct)
        => Ok(AppResponse<bool>.Success(await _svc.SetActiveAsync(id, false, ct)));

    [HttpDelete("{id:guid}")]
    public async Task<ActionResult<AppResponse<bool>>> Delete(Guid id, CancellationToken ct)
        => Ok(AppResponse<bool>.Success(await _svc.DeleteAsync(id, ct)));
}

/// <summary>
/// Public-ish endpoint cho client poll trạng thái bảo trì (anonymous OK – chỉ trả thông tin
/// ở mức "Có/Không" + message). Dùng cho banner client hiển thị trước khi đăng nhập.
/// </summary>
[AllowAnonymous]
[ApiController]
[Route("api/maintenance")]
public class PublicMaintenanceController : ControllerBase
{
    private readonly IMaintenanceService _svc;
    public PublicMaintenanceController(IMaintenanceService svc) { _svc = svc; }

    [HttpGet("active")]
    public async Task<ActionResult<AppResponse<ActiveMaintenanceDto>>> Active(CancellationToken ct)
    {
        var data = await _svc.GetActiveAsync(ct);
        return Ok(AppResponse<ActiveMaintenanceDto>.Success(data));
    }
}
