using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
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
public partial class AgentController : AuthenticatedControllerBase
{
    private readonly ZKTecoDbContext _dbContext;
    private readonly UserManager<ApplicationUser> _userManager;
    private readonly ILogger<AgentController> _logger;
    private readonly ISystemNotificationService _notificationService;

    public AgentController(
        ZKTecoDbContext dbContext,
        UserManager<ApplicationUser> userManager,
        ILogger<AgentController> logger,
        ISystemNotificationService notificationService)
    {
        _dbContext = dbContext;
        _userManager = userManager;
        _logger = logger;
        _notificationService = notificationService;
    }

    private Task<(Agent Agent, ActionResult? Error)> RequireCurrentAgentAsync() =>
        AgentScopeHelper.RequireAgentAsync(
            _dbContext, _userManager, CurrentUserId, _logger);

    /// <summary>
    /// Lấy thông tin Agent hiện tại
    /// </summary>
    [HttpGet("profile")]
    public async Task<ActionResult<AppResponse<AgentProfileDto>>> GetMyProfile(
        [FromServices] IConfiguration configuration)
    {
        try
        {
            var (agent, err) = await RequireCurrentAgentAsync();
            if (err != null) return err;

            var dto = await BuildAgentProfileDtoAsync(agent.Id, configuration);
            return Ok(AppResponse<AgentProfileDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agent profile");
            return StatusCode(500, AppResponse<AgentProfileDto>.Fail("Lỗi khi lấy thông tin đại lý"));
        }
    }

    /// <summary>
    /// Đại lý tự cập nhật thông tin liên hệ / giới thiệu (không đổi mã, tên doanh nghiệp).
    /// </summary>
    [HttpPut("profile")]
    public async Task<ActionResult<AppResponse<AgentProfileDto>>> UpdateMyProfile(
        [FromBody] UpdateAgentProfileRequest request,
        [FromServices] IConfiguration configuration)
    {
        try
        {
            var (agent, err) = await RequireCurrentAgentAsync();
            if (err != null) return err;

            var tracked = await _dbContext.Agents.FirstOrDefaultAsync(a => a.Id == agent.Id);
            if (tracked == null)
                return NotFound(AppResponse<AgentProfileDto>.Fail("Không tìm thấy đại lý"));

            if (request.Description != null)
                tracked.Description = string.IsNullOrWhiteSpace(request.Description)
                    ? null
                    : request.Description.Trim();
            if (request.Address != null)
                tracked.Address = string.IsNullOrWhiteSpace(request.Address)
                    ? null
                    : request.Address.Trim();
            if (request.Phone != null)
                tracked.Phone = string.IsNullOrWhiteSpace(request.Phone)
                    ? null
                    : request.Phone.Trim();

            tracked.UpdatedAt = DateTime.UtcNow;
            tracked.UpdatedBy = CurrentUserId.ToString();
            await _dbContext.SaveChangesAsync();

            var dto = await BuildAgentProfileDtoAsync(tracked.Id, configuration);
            return Ok(AppResponse<AgentProfileDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating agent profile");
            return StatusCode(500, AppResponse<AgentProfileDto>.Fail("Lỗi khi cập nhật thông tin đại lý"));
        }
    }

    private async Task<AgentProfileDto> BuildAgentProfileDtoAsync(
        Guid agentId,
        IConfiguration configuration)
    {
        var agentFull = await _dbContext.Agents
            .Include(a => a.Stores)
            .Include(a => a.LicenseKeys)
            .Include(a => a.User)
            .FirstAsync(a => a.Id == agentId);

        var baseUrl = configuration["AppSettings:FlutterClientUrl"] ?? "https://sbox.sana.vn";
        var referralLink = $"{baseUrl}/#/register?agentCode={agentFull.Code}";

        return new AgentProfileDto(
            agentFull.Id,
            agentFull.Name,
            agentFull.Code,
            agentFull.Email ?? agentFull.User?.Email,
            agentFull.Phone,
            agentFull.Description,
            agentFull.Address,
            agentFull.Stores.Count,
            AgentStoreStatsHelper.CountActivated(agentFull.Stores),
            AgentStoreStatsHelper.CountTrial(agentFull.Stores),
            agentFull.MaxStores,
            agentFull.LicenseKeys.Count,
            agentFull.LicenseKeys.Count(l => l.IsUsed),
            agentFull.LicenseKeys.Count(l => !l.IsUsed && l.IsActive),
            agentFull.RenewalDayBalance,
            referralLink);
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
            var (agent, err) = await RequireCurrentAgentAsync();
            if (err != null) return err;

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
    /// Tổng quan cổng đại lý — thống kê cửa hàng, thiết bị, license trong phạm vi đại lý.
    /// </summary>
    [HttpGet("dashboard")]
    public async Task<ActionResult<AppResponse<AgentDashboardDto>>> GetDashboard(
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        try
        {
            var (agent, err) = await RequireCurrentAgentAsync();
            if (err != null) return err;

            var utcNow = DateTime.UtcNow;
            DateTime vnNow;
            try
            {
                var vnTz = TimeZoneInfo.FindSystemTimeZoneById("Asia/Ho_Chi_Minh");
                vnNow = TimeZoneInfo.ConvertTimeFromUtc(utcNow, vnTz);
            }
            catch
            {
                try
                {
                    var vnTz = TimeZoneInfo.FindSystemTimeZoneById("SE Asia Standard Time");
                    vnNow = TimeZoneInfo.ConvertTimeFromUtc(utcNow, vnTz);
                }
                catch
                {
                    vnNow = utcNow.AddHours(7);
                }
            }

            var today = vnNow.Date;
            var tomorrow = today.AddDays(1);
            var periodFrom = fromDate?.Date ?? today;
            var periodTo = (toDate?.Date ?? today).AddDays(1);

            var storeIds = await _dbContext.Stores.AsNoTracking()
                .Where(s => s.AgentId == agent.Id)
                .Select(s => s.Id)
                .ToListAsync();

            var stores = await _dbContext.Stores.AsNoTracking()
                .Where(s => s.AgentId == agent.Id)
                .Select(s => new { s.IsActive, s.IsLocked, s.ExpiryDate, s.TrialStartDate, s.TrialDays })
                .ToListAsync();

            var now = utcNow;
            var expiringThreshold = now.AddDays(30);
            var onlineThreshold = utcNow.AddSeconds(-90);

            var totalDevices = 0;
            var onlineDevices = 0;
            if (storeIds.Count > 0)
            {
                var deviceQuery = _dbContext.Devices.AsNoTracking()
                    .Where(d => d.StoreId != null && storeIds.Contains(d.StoreId.Value));
                totalDevices = await deviceQuery.CountAsync();
                onlineDevices = await deviceQuery.CountAsync(d =>
                    d.LastOnline != null && d.LastOnline > onlineThreshold);
            }

            var keys = await _dbContext.LicenseKeys.AsNoTracking()
                .Where(l => l.AgentId == agent.Id)
                .Select(l => new { l.IsUsed, l.IsActive })
                .ToListAsync();

            var totalUsers = await _userManager.Users
                .CountAsync(u => u.Store != null && u.Store.AgentId == agent.Id);

            var todayAttendances = 0;
            var storeAttendances = new List<StoreAttendanceDto>();
            if (storeIds.Count > 0)
            {
                todayAttendances = await _dbContext.AttendanceLogs
                    .CountAsync(a => a.AttendanceTime >= today && a.AttendanceTime < tomorrow
                                     && a.Device.StoreId != null
                                     && storeIds.Contains(a.Device.StoreId.Value));

                var storeAttendanceData = await _dbContext.AttendanceLogs
                    .Where(a => a.AttendanceTime >= today && a.AttendanceTime < tomorrow
                                && a.Device.StoreId != null
                                && storeIds.Contains(a.Device.StoreId.Value))
                    .Select(a => new { StoreName = a.Device.Store!.Name })
                    .ToListAsync();
                storeAttendances = storeAttendanceData
                    .GroupBy(a => a.StoreName)
                    .Select(g => new StoreAttendanceDto(g.Key, g.Count()))
                    .OrderByDescending(x => x.Count)
                    .ToList();
            }

            var storesCreatedInPeriod = await _dbContext.Stores
                .CountAsync(s => s.AgentId == agent.Id
                                 && s.CreatedAt >= periodFrom && s.CreatedAt < periodTo);

            var keysActivatedInPeriod = await _dbContext.LicenseKeys
                .CountAsync(l => l.AgentId == agent.Id
                                 && l.ActivatedAt != null
                                 && l.ActivatedAt >= periodFrom && l.ActivatedAt < periodTo);

            var keysCreatedInPeriod = await _dbContext.LicenseKeys
                .CountAsync(l => l.AgentId == agent.Id
                                 && l.CreatedAt >= periodFrom && l.CreatedAt < periodTo);

            var usersCreatedInPeriod = await _userManager.Users
                .CountAsync(u => u.Store != null && u.Store.AgentId == agent.Id
                                 && u.CreatedAt >= periodFrom && u.CreatedAt < periodTo);

            var recentActivities = new List<RecentActivityDto>();

            var recentStoresCreated = await _dbContext.Stores
                .Where(s => s.AgentId == agent.Id
                            && s.CreatedAt >= periodFrom && s.CreatedAt < periodTo)
                .OrderByDescending(s => s.CreatedAt)
                .Take(20)
                .Select(s => new RecentActivityDto(
                    s.Id,
                    "StoreCreated",
                    $"Cửa hàng \"{s.Name}\" ({s.Code}) đã được tạo",
                    s.Name,
                    null,
                    s.CreatedAt))
                .ToListAsync();
            recentActivities.AddRange(recentStoresCreated);

            var recentKeysActivated = await _dbContext.LicenseKeys
                .Include(l => l.Store)
                .Where(l => l.AgentId == agent.Id
                            && l.ActivatedAt != null
                            && l.ActivatedAt >= periodFrom && l.ActivatedAt < periodTo)
                .OrderByDescending(l => l.ActivatedAt)
                .Take(20)
                .Select(l => new RecentActivityDto(
                    l.Id,
                    "KeyActivated",
                    $"Key \"{l.Key}\" đã kích hoạt cho \"{(l.Store != null ? l.Store.Name : "N/A")}\"",
                    l.Store != null ? l.Store.Name : null,
                    null,
                    l.ActivatedAt!.Value))
                .ToListAsync();
            recentActivities.AddRange(recentKeysActivated);

            recentActivities = recentActivities
                .OrderByDescending(a => a.CreatedAt)
                .Take(30)
                .ToList();

            var dto = new AgentDashboardDto(
                agent.Name,
                agent.Code,
                stores.Count,
                agent.MaxStores,
                stores.Count(s => s.IsActive && !s.IsLocked),
                stores.Count(s => s.IsLocked),
                stores.Count(s => !s.IsActive && !s.IsLocked),
                totalDevices,
                onlineDevices,
                totalDevices - onlineDevices,
                keys.Count,
                keys.Count(k => k.IsUsed),
                keys.Count(k => !k.IsUsed && k.IsActive),
                stores.Count(s => s.ExpiryDate.HasValue
                                  && s.ExpiryDate.Value >= now
                                  && s.ExpiryDate.Value <= expiringThreshold),
                stores.Count(s => s.TrialStartDate.HasValue
                                  && s.TrialStartDate.Value.AddDays(s.TrialDays) >= now),
                totalUsers,
                todayAttendances,
                storesCreatedInPeriod,
                keysActivatedInPeriod,
                keysCreatedInPeriod,
                usersCreatedInPeriod,
                storeAttendances,
                recentActivities
            );

            return Ok(AppResponse<AgentDashboardDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agent dashboard");
            return StatusCode(500, AppResponse<AgentDashboardDto>.Fail("Lỗi khi lấy tổng quan đại lý"));
        }
    }

    /// <summary>
    /// Thiết bị thuộc các cửa hàng của đại lý hiện tại (chỉ xem).
    /// </summary>
    [HttpGet("devices")]
    public async Task<ActionResult<AppResponse<object>>> GetMyDevices(
        [FromQuery] Guid? storeId = null,
        [FromQuery] bool? isOnline = null,
        [FromQuery] string? search = null,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        try
        {
            var (agent, err) = await RequireCurrentAgentAsync();
            if (err != null) return err;

            if (pageSize > 200) pageSize = 200;
            if (page < 1) page = 1;

            var storeIds = await _dbContext.Stores.AsNoTracking()
                .Where(s => s.AgentId == agent.Id)
                .Select(s => s.Id)
                .ToListAsync();

            if (storeIds.Count == 0)
            {
                return Ok(AppResponse<object>.Success(new
                {
                    items = Array.Empty<AgentDeviceDto>(),
                    totalCount = 0,
                    page,
                    pageSize,
                }));
            }

            if (storeId.HasValue && !storeIds.Contains(storeId.Value))
                return BadRequest(AppResponse<object>.Fail("Cửa hàng không thuộc đại lý này"));

            var query = _dbContext.Devices.AsNoTracking()
                .Include(d => d.Store)
                .Where(d => d.StoreId != null && storeIds.Contains(d.StoreId.Value));

            if (storeId.HasValue)
                query = query.Where(d => d.StoreId == storeId.Value);

            if (!string.IsNullOrWhiteSpace(search))
            {
                var pattern = $"%{search.Trim()}%";
                query = query.Where(d =>
                    EF.Functions.ILike(d.SerialNumber, pattern) ||
                    EF.Functions.ILike(d.DeviceName, pattern) ||
                    (d.Store != null && EF.Functions.ILike(d.Store.Name, pattern)));
            }

            if (isOnline.HasValue)
            {
                var status = isOnline.Value ? "Online" : "Offline";
                query = query.Where(d => d.DeviceStatus == status);
            }

            var totalCount = await query.CountAsync();
            var items = await query
                .OrderByDescending(d => d.LastOnline)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(d => new AgentDeviceDto(
                    d.Id,
                    d.SerialNumber,
                    d.DeviceName,
                    d.IpAddress,
                    d.DeviceStatus == "Online",
                    d.StoreId,
                    d.Store != null ? d.Store.Name : null,
                    d.Store != null ? d.Store.Code : null,
                    d.LastOnline,
                    d.IsActive
                ))
                .ToListAsync();

            return Ok(AppResponse<object>.Success(new
            {
                items,
                totalCount,
                page,
                pageSize,
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agent devices");
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi lấy danh sách thiết bị"));
        }
    }

    /// <summary>
    /// Danh sách cửa hàng thuộc đại lý (định dạng giống SystemAdmin stores).
    /// </summary>
    [HttpGet("stores")]
    public async Task<ActionResult<AppResponse<object>>> GetMyStores(
        [FromQuery] string? search = null,
        [FromQuery] bool? isActive = null,
        [FromQuery] bool? isLocked = null,
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 1000)
    {
        try
        {
            var (agent, err) = await RequireCurrentAgentAsync();
            if (err != null) return err;

            if (pageSize > 2000) pageSize = 2000;
            if (pageNumber < 1) pageNumber = 1;

            var query = _dbContext.Stores
                .AsNoTracking()
                .Include(s => s.Owner)
                .Include(s => s.Agent)
                .Include(s => s.Users)
                .Include(s => s.Devices)
                .Include(s => s.ServicePackage)
                .Where(s => s.AgentId == agent.Id);

            if (!string.IsNullOrEmpty(search))
            {
                var searchPattern = $"%{search}%";
                query = query.Where(s =>
                    EF.Functions.ILike(s.Name, searchPattern) ||
                    EF.Functions.ILike(s.Code, searchPattern) ||
                    (s.Address != null && EF.Functions.ILike(s.Address, searchPattern)));
            }

            if (isActive.HasValue)
                query = query.Where(s => s.IsActive == isActive.Value);

            if (isLocked.HasValue)
                query = query.Where(s => s.IsLocked == isLocked.Value);

            var totalCount = await query.CountAsync();
            var stores = await query
                .OrderByDescending(s => s.CreatedAt)
                .Skip((pageNumber - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            var items = stores.Select(AgentStoreMapper.ToStoreDetailDto).ToList();
            return Ok(AppResponse<object>.Success(new { items, totalCount, pageNumber, pageSize }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agent stores");
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi lấy danh sách cửa hàng"));
        }
    }

    /// <summary>
    /// Link giới thiệu đăng ký cửa hàng cho đại lý
    /// </summary>
    [HttpGet("referral-link")]
    public async Task<ActionResult<AppResponse<AgentReferralLinkDto>>> GetReferralLink(
        [FromServices] IConfiguration configuration)
    {
        var (agent, err) = await RequireCurrentAgentAsync();
        if (err != null) return err;

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
    string? Description,
    string? Address,
    int StoreCount,
    int ActivatedStoresCount,
    int TrialStoresCount,
    int MaxStores,
    int TotalKeys,
    int UsedKeys,
    int AvailableKeys,
    int RenewalDayBalance,
    string? ReferralLink
);

public record UpdateAgentProfileRequest(
    string? Description,
    string? Address,
    string? Phone
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

public record AgentDashboardDto(
    string AgentName,
    string AgentCode,
    int StoreCount,
    int MaxStores,
    int ActiveStores,
    int LockedStores,
    int InactiveStores,
    int TotalDevices,
    int OnlineDevices,
    int OfflineDevices,
    int TotalKeys,
    int UsedKeys,
    int AvailableKeys,
    int StoresExpiringSoon,
    int StoresInTrial,
    int TotalUsers,
    int TodayAttendances,
    int StoresCreatedInPeriod,
    int KeysActivatedInPeriod,
    int KeysCreatedInPeriod,
    int UsersCreatedInPeriod,
    List<StoreAttendanceDto> StoreAttendances,
    List<RecentActivityDto> RecentActivities
);

public record AgentDeviceDto(
    Guid Id,
    string SerialNumber,
    string Name,
    string? IPAddress,
    bool IsOnline,
    Guid? StoreId,
    string? StoreName,
    string? StoreCode,
    DateTime? LastSyncAt,
    bool IsActive
);
