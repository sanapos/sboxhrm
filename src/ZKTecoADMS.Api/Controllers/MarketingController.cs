using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>SuperAdmin marketing — templates + campaigns (Phase 3).</summary>
[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin/marketing")]
public class MarketingController : AuthenticatedControllerBase
{
    private readonly IMarketingService _svc;
    public MarketingController(IMarketingService svc) { _svc = svc; }

    // ---- Templates ----

    [HttpGet("templates")]
    public async Task<ActionResult<AppResponse<List<NotificationTemplateDto>>>> ListTemplates([FromQuery] bool? activeOnly, CancellationToken ct)
        => Ok(AppResponse<List<NotificationTemplateDto>>.Success(await _svc.ListTemplatesAsync(activeOnly, ct)));

    [HttpPost("templates")]
    public async Task<ActionResult<AppResponse<NotificationTemplateDto>>> CreateTemplate([FromBody] CreateNotificationTemplateDto dto, CancellationToken ct)
        => Ok(AppResponse<NotificationTemplateDto>.Success(await _svc.CreateTemplateAsync(dto, ct)));

    [HttpPut("templates/{id:guid}")]
    public async Task<ActionResult<AppResponse<bool>>> UpdateTemplate(Guid id, [FromBody] CreateNotificationTemplateDto dto, CancellationToken ct)
        => Ok(AppResponse<bool>.Success(await _svc.UpdateTemplateAsync(id, dto, ct)));

    [HttpDelete("templates/{id:guid}")]
    public async Task<ActionResult<AppResponse<bool>>> DeleteTemplate(Guid id, CancellationToken ct)
        => Ok(AppResponse<bool>.Success(await _svc.DeleteTemplateAsync(id, ct)));

    // ---- Campaigns ----

    [HttpGet("campaigns")]
    public async Task<ActionResult<AppResponse<List<MarketingCampaignDto>>>> ListCampaigns([FromQuery] int page = 1, [FromQuery] int pageSize = 50, CancellationToken ct = default)
        => Ok(AppResponse<List<MarketingCampaignDto>>.Success(await _svc.ListCampaignsAsync(page, pageSize, ct)));

    [HttpGet("campaigns/{id:guid}")]
    public async Task<ActionResult<AppResponse<MarketingCampaignDto?>>> GetCampaign(Guid id, CancellationToken ct)
        => Ok(AppResponse<MarketingCampaignDto?>.Success(await _svc.GetCampaignAsync(id, ct)));

    [HttpPost("campaigns")]
    public async Task<ActionResult<AppResponse<MarketingCampaignDto>>> CreateCampaign([FromBody] CreateMarketingCampaignDto dto, CancellationToken ct)
        => Ok(AppResponse<MarketingCampaignDto>.Success(await _svc.CreateCampaignAsync(dto, CurrentUserId, ct)));

    [HttpPost("campaigns/{id:guid}/launch")]
    public async Task<ActionResult<AppResponse<bool>>> LaunchCampaign(Guid id, CancellationToken ct)
        => Ok(AppResponse<bool>.Success(await _svc.LaunchCampaignAsync(id, ct)));

    [HttpPost("campaigns/{id:guid}/cancel")]
    public async Task<ActionResult<AppResponse<bool>>> CancelCampaign(Guid id, CancellationToken ct)
        => Ok(AppResponse<bool>.Success(await _svc.CancelCampaignAsync(id, ct)));

    [HttpDelete("campaigns/{id:guid}")]
    public async Task<ActionResult<AppResponse<bool>>> DeleteCampaign(Guid id, CancellationToken ct)
        => Ok(AppResponse<bool>.Success(await _svc.DeleteCampaignAsync(id, ct)));
}
