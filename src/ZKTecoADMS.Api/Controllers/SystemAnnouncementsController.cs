using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// SuperAdmin Announcements – broadcast / maintenance / renewal / marketing.
/// Phase 1: in-app + banner channels (Email/SMS/Push planned for Phase 3).
/// </summary>
[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin/announcements")]
public class SystemAnnouncementsController : AuthenticatedControllerBase
{
    private readonly IAnnouncementService _service;
    private readonly IAudienceResolver _audience;

    public SystemAnnouncementsController(IAnnouncementService service, IAudienceResolver audience)
    {
        _service = service;
        _audience = audience;
    }

    [HttpGet]
    public async Task<ActionResult<AppResponse<List<SystemAnnouncementDto>>>> List(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? keyword = null,
        [FromQuery] int? kind = null,
        [FromQuery] int? status = null,
        CancellationToken ct = default)
    {
        var data = await _service.ListAsync(page, pageSize, keyword, kind, status, ct);
        return Ok(AppResponse<List<SystemAnnouncementDto>>.Success(data));
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<AppResponse<SystemAnnouncementDto>>> Get(Guid id, CancellationToken ct)
    {
        var dto = await _service.GetAsync(id, ct);
        if (dto == null) return NotFound(AppResponse<SystemAnnouncementDto>.Fail("Không tìm thấy"));
        return Ok(AppResponse<SystemAnnouncementDto>.Success(dto));
    }

    [HttpPost]
    public async Task<ActionResult<AppResponse<SystemAnnouncementDto>>> Create(
        [FromBody] CreateSystemAnnouncementDto request, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(request.Title) || string.IsNullOrWhiteSpace(request.Content))
            return BadRequest(AppResponse<SystemAnnouncementDto>.Fail("Tiêu đề và nội dung không được rỗng"));

        var dto = await _service.CreateAsync(request, CurrentUserId, ct);
        return Ok(AppResponse<SystemAnnouncementDto>.Success(dto));
    }

    [HttpPost("{id:guid}/send")]
    public async Task<ActionResult<AppResponse<int>>> Send(Guid id, CancellationToken ct)
    {
        var n = await _service.SendAsync(id, ct);
        return Ok(AppResponse<int>.Success(n));
    }

    [HttpPost("{id:guid}/resend-failed")]
    public async Task<ActionResult<AppResponse<int>>> Resend(Guid id, CancellationToken ct)
    {
        var n = await _service.ResendFailedAsync(id, ct);
        return Ok(AppResponse<int>.Success(n));
    }

    [HttpPost("{id:guid}/cancel")]
    public async Task<ActionResult<AppResponse<bool>>> Cancel(Guid id, CancellationToken ct)
    {
        var ok = await _service.CancelAsync(id, ct);
        return Ok(AppResponse<bool>.Success(ok));
    }

    [HttpDelete("{id:guid}")]
    public async Task<ActionResult<AppResponse<bool>>> Delete(Guid id, CancellationToken ct)
    {
        var ok = await _service.DeleteAsync(id, ct);
        return Ok(AppResponse<bool>.Success(ok));
    }

    [HttpGet("{id:guid}/stats")]
    public async Task<ActionResult<AppResponse<AnnouncementStatsDto>>> Stats(Guid id, CancellationToken ct)
        => Ok(AppResponse<AnnouncementStatsDto>.Success(await _service.GetStatsAsync(id, ct)));

    [HttpPost("preview-audience")]
    public async Task<ActionResult<AppResponse<AudiencePreviewDto>>> PreviewAudience(
        [FromBody] AudienceSpec spec, CancellationToken ct)
        => Ok(AppResponse<AudiencePreviewDto>.Success(await _audience.PreviewAsync(spec ?? new AudienceSpec { AllUsers = true }, ct)));
}

/// <summary>
/// Public (auth) endpoint cho client (mọi role) lấy banner / popup đang active.
/// </summary>
[Authorize]
[Route("api/announcements")]
public class ActiveAnnouncementsController : AuthenticatedControllerBase
{
    private readonly IAnnouncementService _service;
    public ActiveAnnouncementsController(IAnnouncementService service) => _service = service;

    [HttpGet("active")]
    public async Task<ActionResult<AppResponse<List<ActiveAnnouncementDto>>>> Active(CancellationToken ct)
        => Ok(AppResponse<List<ActiveAnnouncementDto>>.Success(await _service.GetActiveForUserAsync(CurrentUserId, ct)));

    [HttpPost("{id:guid}/seen")]
    public async Task<ActionResult<AppResponse<bool>>> Seen(Guid id, CancellationToken ct)
    {
        await _service.MarkSeenAsync(id, CurrentUserId, ct);
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpPost("{id:guid}/clicked")]
    public async Task<ActionResult<AppResponse<bool>>> Clicked(Guid id, CancellationToken ct)
    {
        await _service.MarkClickedAsync(id, CurrentUserId, ct);
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpPost("{id:guid}/ack")]
    public async Task<ActionResult<AppResponse<bool>>> Ack(Guid id, CancellationToken ct)
    {
        await _service.MarkAckedAsync(id, CurrentUserId, ct);
        return Ok(AppResponse<bool>.Success(true));
    }

    [HttpPost("{id:guid}/dismiss")]
    public async Task<ActionResult<AppResponse<bool>>> Dismiss(Guid id, CancellationToken ct)
    {
        await _service.MarkDismissedAsync(id, CurrentUserId, ct);
        return Ok(AppResponse<bool>.Success(true));
    }
}
