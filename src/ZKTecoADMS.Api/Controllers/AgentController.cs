using Microsoft.Extensions.Configuration;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Agent Portal - Chức năng dành cho đại lý
/// </summary>
[Authorize(Roles = nameof(Roles.Agent))]
[Route("api/agent")]
public class AgentController : AuthenticatedControllerBase
{
    private readonly ZKTecoDbContext _dbContext;
    private readonly ILogger<AgentController> _logger;

    public AgentController(ZKTecoDbContext dbContext, ILogger<AgentController> logger)
    {
        _dbContext = dbContext;
        _logger = logger;
    }

    /// <summary>
    /// Lấy thông tin Agent hiện tại
    /// </summary>
    [HttpGet("profile")]
    public async Task<ActionResult<AppResponse<AgentProfileDto>>> GetMyProfile()
    {
        try
        {
            var agent = await _dbContext.Agents
                .Include(a => a.Stores)
                .Include(a => a.LicenseKeys)
                .FirstOrDefaultAsync(a => a.UserId == CurrentUserId);

            if (agent == null)
                return NotFound(AppResponse<AgentProfileDto>.Fail("Không tìm thấy thông tin đại lý"));

            var dto = new AgentProfileDto(
                agent.Id,
                agent.Name,
                agent.Code,
                agent.Email,
                agent.Phone,
                agent.Stores.Count,
                agent.MaxStores,
                agent.LicenseKeys.Count,
                agent.LicenseKeys.Count(l => l.IsUsed),
                agent.LicenseKeys.Count(l => !l.IsUsed && l.IsActive)
            );

            return Ok(AppResponse<AgentProfileDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agent profile");
            return StatusCode(500, AppResponse<AgentProfileDto>.Fail("Lỗi khi lấy thông tin đại lý"));
        }
    }

    /// <summary>
    /// Lấy danh sách License Keys được cấp cho Agent hiện tại
    /// </summary>
    [HttpGet("my-licenses")]
    public async Task<ActionResult<AppResponse<PagedList<LicenseKeyDto>>>> GetMyLicenseKeys(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] bool? isUsed = null,
        [FromQuery] string? licenseType = null,
        [FromQuery] string? search = null)
    {
        try
        {
            var agent = await _dbContext.Agents
                .FirstOrDefaultAsync(a => a.UserId == CurrentUserId);

            if (agent == null)
                return NotFound(AppResponse<PagedList<LicenseKeyDto>>.Fail("Không tìm thấy thông tin đại lý"));

            var query = _dbContext.LicenseKeys
                .Include(l => l.Store)
                .Include(l => l.ServicePackage)
                .Where(l => l.AgentId == agent.Id);

            if (isUsed.HasValue) query = query.Where(l => l.IsUsed == isUsed.Value);

            if (!string.IsNullOrEmpty(licenseType) && Enum.TryParse<LicenseType>(licenseType, true, out var lt))
                query = query.Where(l => l.LicenseType == lt);

            if (!string.IsNullOrEmpty(search))
                query = query.Where(l => l.Key.Contains(search) || 
                    (l.Store != null && l.Store.Name.Contains(search)) ||
                    (l.Notes != null && l.Notes.Contains(search)));

            var total = await query.CountAsync();
            var items = await query
                .OrderByDescending(l => l.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            var dtos = items.Select(l => new LicenseKeyDto(
                l.Id, l.Key, l.LicenseType.ToString(), l.DurationDays,
                l.MaxUsers, l.MaxDevices, l.IsUsed, l.ActivatedAt,
                l.StoreId, l.Store?.Name, l.AgentId, null,
                l.ServicePackageId, l.ServicePackage?.Name,
                l.Notes, l.IsActive, l.CreatedAt
            )).ToList();

            var result = new PagedList<LicenseKeyDto>(dtos, total, page, pageSize);
            return Ok(AppResponse<PagedList<LicenseKeyDto>>.Success(result));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agent license keys");
            return StatusCode(500, AppResponse<PagedList<LicenseKeyDto>>.Fail("Lỗi khi lấy danh sách license key"));
        }
    }

    /// <summary>
    /// Danh sách gian hàng thuộc đại lý hiện tại
    /// </summary>
    [HttpGet("stores")]
    public async Task<ActionResult<AppResponse<List<AgentStoreSummaryDto>>>> GetMyStores()
    {
        try
        {
            var agent = await _dbContext.Agents
                .AsNoTracking()
                .FirstOrDefaultAsync(a => a.UserId == CurrentUserId);

            if (agent == null)
                return NotFound(AppResponse<List<AgentStoreSummaryDto>>.Fail("Không tìm thấy thông tin đại lý"));

            var stores = await _dbContext.Stores
                .AsNoTracking()
                .Include(s => s.ServicePackage)
                .Where(s => s.AgentId == agent.Id)
                .OrderByDescending(s => s.CreatedAt)
                .Select(s => new AgentStoreSummaryDto(
                    s.Id,
                    s.Name,
                    s.Code,
                    s.IsActive,
                    s.IsLocked,
                    s.ExpiryDate,
                    s.ServicePackage != null ? s.ServicePackage.Name : null,
                    s.TrialStartDate,
                    s.TrialDays,
                    s.MaxUsers,
                    s.MaxDevices
                ))
                .ToListAsync();

            return Ok(AppResponse<List<AgentStoreSummaryDto>>.Success(stores));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agent stores");
            return StatusCode(500, AppResponse<List<AgentStoreSummaryDto>>.Fail("Lỗi khi lấy danh sách cửa hàng"));
        }
    }

    /// <summary>
    /// Link giới thiệu đăng ký cửa hàng cho đại lý
    /// </summary>
    [HttpGet("referral-link")]
    public async Task<ActionResult<AppResponse<AgentReferralLinkDto>>> GetReferralLink(
        [FromServices] IConfiguration configuration)
    {
        var agent = await _dbContext.Agents
            .AsNoTracking()
            .FirstOrDefaultAsync(a => a.UserId == CurrentUserId);

        if (agent == null)
            return NotFound(AppResponse<AgentReferralLinkDto>.Fail("Không tìm thấy thông tin đại lý"));

        var baseUrl = configuration["AppSettings:FlutterClientUrl"] ?? "http://localhost:3000";
        var link = $"{baseUrl}/#/register?agentCode={agent.Code}";
        return Ok(AppResponse<AgentReferralLinkDto>.Success(
            new AgentReferralLinkDto(agent.Code, link)));
    }
}

/// <summary>
/// Thông tin đại lý
/// </summary>
public record AgentProfileDto(
    Guid Id,
    string Name,
    string Code,
    string? Email,
    string? Phone,
    int StoreCount,
    int MaxStores,
    int TotalKeys,
    int UsedKeys,
    int AvailableKeys
);

public record AgentStoreSummaryDto(
    Guid Id,
    string Name,
    string Code,
    bool IsActive,
    bool IsLocked,
    DateTime? ExpiryDate,
    string? PackageName,
    DateTime? TrialStartDate,
    int TrialDays,
    int MaxUsers,
    int MaxDevices
);

public record AgentReferralLinkDto(string AgentCode, string ReferralLink);
