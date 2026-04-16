using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// System Administration - Quản trị toàn bộ hệ thống (SuperAdmin only)
/// </summary>
[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin")]
public class SystemAdminController : AuthenticatedControllerBase
{
    private readonly ZKTecoDbContext _dbContext;
    private readonly UserManager<ApplicationUser> _userManager;
    private readonly ILogger<SystemAdminController> _logger;
    private readonly IConfiguration _configuration;
    private readonly ICacheService _cache;
    private readonly ISystemNotificationService _notificationService;

    public SystemAdminController(
        ZKTecoDbContext dbContext, 
        UserManager<ApplicationUser> userManager,
        ILogger<SystemAdminController> logger,
        IConfiguration configuration,
        ICacheService cache,
        ISystemNotificationService notificationService)
    {
        _dbContext = dbContext;
        _userManager = userManager;
        _logger = logger;
        _configuration = configuration;
        _cache = cache;
        _notificationService = notificationService;
    }
    
    private string GetRegistrationLink(string token) 
    {
        var baseUrl = _configuration["AppSettings:FlutterClientUrl"] ?? "http://localhost:3000";
        return $"{baseUrl}/#/agent-register/{token}";
    }
    
    private static string GenerateRegistrationToken()
    {
        return $"AGT-{Guid.NewGuid():N}"[..24].ToUpper();
    }

    /// <summary>
    /// Lấy thống kê tổng quan hệ thống
    /// </summary>
    [HttpGet("dashboard")]
    public async Task<ActionResult<AppResponse<SystemDashboardDto>>> GetDashboard(
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        try
        {
            var today = DateTime.UtcNow.Date;
            var tomorrow = today.AddDays(1);
            var periodFrom = fromDate?.Date ?? today;
            var periodTo = (toDate?.Date ?? today).AddDays(1); // inclusive end

            // Thống kê stores
            var totalStores = await _dbContext.Stores.CountAsync();
            var activeStores = await _dbContext.Stores.CountAsync(s => s.IsActive);
            var inactiveStores = totalStores - activeStores;
            var lockedStores = await _dbContext.Stores.CountAsync(s => s.IsLocked);

            // Thống kê users
            var totalUsers = await _userManager.Users.CountAsync();

            // Thống kê devices
            var totalDevices = await _dbContext.Devices.CountAsync();
            var onlineDevices = await _dbContext.Devices.CountAsync(d => d.DeviceStatus == "Online");
            var offlineDevices = totalDevices - onlineDevices;

            // Chấm công hôm nay (use range instead of .Date)
            var totalAttendanceToday = await _dbContext.AttendanceLogs
                .CountAsync(a => a.AttendanceTime >= today && a.AttendanceTime < tomorrow);

            // License stats
            var totalLicenseKeys = await _dbContext.LicenseKeys.CountAsync();
            var usedLicenseKeys = await _dbContext.LicenseKeys.CountAsync(l => l.IsUsed);
            var availableLicenseKeys = await _dbContext.LicenseKeys.CountAsync(l => !l.IsUsed && l.IsActive);

            // Agents
            var totalAgents = await _dbContext.Agents.CountAsync();

            // ═══ Time-filtered stats ═══
            var storesCreatedInPeriod = await _dbContext.Stores
                .CountAsync(s => s.CreatedAt >= periodFrom && s.CreatedAt < periodTo);

            var keysActivatedInPeriod = await _dbContext.LicenseKeys
                .CountAsync(l => l.ActivatedAt != null && l.ActivatedAt >= periodFrom && l.ActivatedAt < periodTo);

            var keysCreatedInPeriod = await _dbContext.LicenseKeys
                .CountAsync(l => l.CreatedAt >= periodFrom && l.CreatedAt < periodTo);

            var usersCreatedInPeriod = await _userManager.Users
                .CountAsync(u => u.CreatedAt >= periodFrom && u.CreatedAt < periodTo);

            // Top stores by users
            var topStores = await _dbContext.Stores
                .OrderByDescending(s => s.Users.Count)
                .Take(5)
                .Select(s => new StoreStatDto(
                    s.Id,
                    s.Name,
                    s.Code,
                    s.Users.Count,
                    s.Devices.Count,
                    s.IsActive
                ))
                .ToListAsync();

            // Store attendance breakdown for today
            var storeAttendanceData = await _dbContext.AttendanceLogs
                .Where(a => a.AttendanceTime >= today && a.AttendanceTime < tomorrow && a.Device.StoreId != null)
                .Select(a => new { StoreName = a.Device.Store!.Name })
                .ToListAsync();
            var storeAttendances = storeAttendanceData
                .GroupBy(a => a.StoreName)
                .Select(g => new StoreAttendanceDto(g.Key, g.Count()))
                .OrderByDescending(x => x.Count)
                .ToList();

            var recentActivities = new List<RecentActivityDto>();

            // Cửa hàng được tạo gần đây
            var recentStoresCreated = await _dbContext.Stores
                .Where(s => s.CreatedAt >= periodFrom && s.CreatedAt < periodTo)
                .OrderByDescending(s => s.CreatedAt)
                .Take(20)
                .Select(s => new RecentActivityDto(
                    s.Id,
                    "StoreCreated",
                    $"Cửa hàng \"{s.Name}\" ({s.Code}) đã được tạo",
                    s.Name,
                    null,
                    s.CreatedAt
                ))
                .ToListAsync();
            recentActivities.AddRange(recentStoresCreated);

            // Key được kích hoạt gần đây
            var recentKeysActivated = await _dbContext.LicenseKeys
                .Include(l => l.Store)
                .Where(l => l.ActivatedAt != null && l.ActivatedAt >= periodFrom && l.ActivatedAt < periodTo)
                .OrderByDescending(l => l.ActivatedAt)
                .Take(20)
                .Select(l => new RecentActivityDto(
                    l.Id,
                    "KeyActivated",
                    $"Key \"{l.Key}\" đã kích hoạt cho \"{(l.Store != null ? l.Store.Name : "N/A")}\"",
                    l.Store != null ? l.Store.Name : null,
                    null,
                    l.ActivatedAt!.Value
                ))
                .ToListAsync();
            recentActivities.AddRange(recentKeysActivated);

            // Sắp xếp theo thời gian mới nhất
            recentActivities = recentActivities
                .OrderByDescending(a => a.CreatedAt)
                .Take(30)
                .ToList();

            var dashboard = new SystemDashboardDto(
                totalStores,
                activeStores,
                inactiveStores,
                totalUsers,
                totalDevices,
                onlineDevices,
                offlineDevices,
                totalAttendanceToday,
                topStores,
                recentActivities,
                totalLicenseKeys,
                usedLicenseKeys,
                availableLicenseKeys,
                totalAgents,
                storesCreatedInPeriod,
                keysActivatedInPeriod,
                keysCreatedInPeriod,
                usersCreatedInPeriod,
                lockedStores,
                storeAttendances
            );

            return Ok(AppResponse<SystemDashboardDto>.Success(dashboard));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting system dashboard");
            return StatusCode(500, AppResponse<SystemDashboardDto>.Fail("Error getting dashboard"));
        }
    }

    /// <summary>
    /// Lấy danh sách tất cả stores với bộ lọc mở rộng
    /// </summary>
    [HttpGet("stores")]
    public async Task<ActionResult<AppResponse<object>>> GetAllStores(
        [FromQuery] string? search = null,
        [FromQuery] string? phone = null,
        [FromQuery] bool? isActive = null,
        [FromQuery] bool? isLocked = null,
        [FromQuery] Guid? agentId = null,
        [FromQuery] string? licenseType = null,
        [FromQuery] string? expiryStatus = null,
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 1000) // expired, expiring_soon, active
    {
        try
        {
            if (pageSize > 2000) pageSize = 2000;
            if (pageNumber < 1) pageNumber = 1;

            var query = _dbContext.Stores
                .Include(s => s.Owner)
                .Include(s => s.Agent)
                .Include(s => s.Users)
                .Include(s => s.Devices)
                .Include(s => s.ServicePackage)
                .AsQueryable();

            // Search by name, code, address, email
            if (!string.IsNullOrEmpty(search))
            {
                var searchPattern = $"%{search}%";
                query = query.Where(s => 
                    EF.Functions.ILike(s.Name, searchPattern) || 
                    EF.Functions.ILike(s.Code, searchPattern) ||
                    (s.Address != null && EF.Functions.ILike(s.Address, searchPattern)) ||
                    (s.Owner != null && s.Owner.Email != null && EF.Functions.ILike(s.Owner.Email, searchPattern)));
            }

            // Search by phone
            if (!string.IsNullOrEmpty(phone))
            {
                query = query.Where(s => s.Phone != null && s.Phone.Contains(phone));
            }

            // Filter by active status
            if (isActive.HasValue)
            {
                query = query.Where(s => s.IsActive == isActive.Value);
            }

            // Filter by locked status
            if (isLocked.HasValue)
            {
                query = query.Where(s => s.IsLocked == isLocked.Value);
            }

            // Filter by agent
            if (agentId.HasValue)
            {
                query = query.Where(s => s.AgentId == agentId.Value);
            }

            // Filter by license type
            if (!string.IsNullOrEmpty(licenseType) && Enum.TryParse<LicenseType>(licenseType, true, out var lt))
            {
                query = query.Where(s => s.LicenseType == lt);
            }

            // Filter by expiry status
            if (!string.IsNullOrEmpty(expiryStatus))
            {
                var now = DateTime.UtcNow;
                var soonThreshold = now.AddDays(30);
                
                query = expiryStatus.ToLower() switch
                {
                    "expired" => query.Where(s => s.ExpiryDate.HasValue && s.ExpiryDate.Value < now),
                    "expiring_soon" => query.Where(s => s.ExpiryDate.HasValue && s.ExpiryDate.Value >= now && s.ExpiryDate.Value <= soonThreshold),
                    "active" => query.Where(s => !s.ExpiryDate.HasValue || s.ExpiryDate.Value > now),
                    _ => query
                };
            }

            var totalCount = await query.CountAsync();

            var stores = await query
                .OrderByDescending(s => s.CreatedAt)
                .Skip((pageNumber - 1) * pageSize)
                .Take(pageSize)
                .Select(s => new StoreDetailDto(
                    s.Id,
                    s.Name,
                    s.Code,
                    s.Description,
                    s.Address,
                    s.Phone,
                    s.IsActive,
                    s.IsLocked,
                    s.LockReason,
                    s.LicenseType.ToString(),
                    s.LicenseKey,
                    s.ExpiryDate,
                    s.MaxUsers,
                    s.MaxDevices,
                    s.RenewalCount,
                    s.ServicePackageId,
                    s.ServicePackage != null ? s.ServicePackage.Name : null,
                    s.TrialStartDate,
                    s.TrialDays,
                    s.OwnerId,
                    s.Owner != null ? s.Owner.FullName : null,
                    s.Owner != null ? s.Owner.Email : null,
                    s.AgentId,
                    s.Agent != null ? s.Agent.Name : null,
                    s.Agent != null ? s.Agent.Email : null,
                    s.Users.Count,
                    s.Devices.Count,
                    s.Users.Count(u => u.Role == nameof(Roles.Employee)),
                    s.CreatedAt,
                    s.UpdatedAt,
                    s.Devices.SelectMany(d => d.AttendanceLogs)
                        .OrderByDescending(a => a.AttendanceTime)
                        .Select(a => (DateTime?)a.AttendanceTime)
                        .FirstOrDefault()
                ))
                .ToListAsync();

            return Ok(AppResponse<object>.Success(new { items = stores, totalCount, pageNumber, pageSize }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting stores");
            return StatusCode(500, AppResponse<object>.Fail("Error getting stores"));
        }
    }

    /// <summary>
    /// Lấy chi tiết một store
    /// </summary>
    [HttpGet("stores/{id:guid}")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> GetStoreById(Guid id)
    {
        try
        {
            var store = await _dbContext.Stores
                .Include(s => s.Owner)
                .Include(s => s.Agent)
                .Include(s => s.Users)
                .Include(s => s.Devices)
                .FirstOrDefaultAsync(s => s.Id == id);

            if (store == null)
            {
                return NotFound(AppResponse<StoreDetailDto>.Fail("Store not found"));
            }

            var dto = MapToStoreDetailDto(store);

            return Ok(AppResponse<StoreDetailDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting store {StoreId}", id);
            return StatusCode(500, AppResponse<StoreDetailDto>.Fail("Error getting store"));
        }
    }

    /// <summary>
    /// Kích hoạt/Vô hiệu hóa store
    /// </summary>
    [HttpPost("stores/{id:guid}/toggle-status")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> ToggleStoreStatus(Guid id)
    {
        try
        {
            var store = await _dbContext.Stores
                .AsTracking()
                .Include(s => s.Owner)
                .Include(s => s.Agent)
                .Include(s => s.Users)
                .Include(s => s.Devices)
                .FirstOrDefaultAsync(s => s.Id == id);

            if (store == null)
            {
                return NotFound(AppResponse<StoreDetailDto>.Fail("Store not found"));
            }

            store.IsActive = !store.IsActive;
            store.UpdatedAt = DateTime.UtcNow;
            store.UpdatedBy = CurrentUserId.ToString();

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} toggled store {StoreId} status to {IsActive}", 
                CurrentUserId, id, store.IsActive);

            var dto = MapToStoreDetailDto(store);

            return Ok(AppResponse<StoreDetailDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error toggling store status {StoreId}", id);
            return StatusCode(500, AppResponse<StoreDetailDto>.Fail("Error updating store"));
        }
    }

    /// <summary>
    /// Cập nhật thông tin store
    /// </summary>
    [HttpPut("stores/{id:guid}")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> UpdateStore(Guid id, [FromBody] UpdateStoreRequest request)
    {
        try
        {
            var store = await _dbContext.Stores
                .AsTracking()
                .Include(s => s.Owner)
                .Include(s => s.Agent)
                .Include(s => s.Users)
                .Include(s => s.Devices)
                .FirstOrDefaultAsync(s => s.Id == id);

            if (store == null)
            {
                return NotFound(AppResponse<StoreDetailDto>.Fail("Store not found"));
            }

            store.Name = request.Name;
            store.Description = request.Description;
            store.Address = request.Address;
            store.Phone = request.Phone;
            store.UpdatedAt = DateTime.UtcNow;
            store.UpdatedBy = CurrentUserId.ToString();

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} updated store {StoreId}", CurrentUserId, id);

            var dto = MapToStoreDetailDto(store);

            return Ok(AppResponse<StoreDetailDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating store {StoreId}", id);
            return StatusCode(500, AppResponse<StoreDetailDto>.Fail("Error updating store"));
        }
    }

    /// <summary>
    /// Lấy danh sách tất cả users trong hệ thống
    /// </summary>
    [HttpGet("users")]
    public async Task<ActionResult<AppResponse<object>>> GetAllUsers(
        [FromQuery] string? search = null,
        [FromQuery] Guid? storeId = null,
        [FromQuery] string? role = null,
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 500)
    {
        try
        {
            if (pageSize > 1000) pageSize = 1000;
            if (pageNumber < 1) pageNumber = 1;

            var query = _userManager.Users
                .Include(u => u.Store)
                .AsQueryable();

            if (!string.IsNullOrEmpty(search))
            {
                var searchPattern = $"%{search}%";
                query = query.Where(u => 
                    EF.Functions.ILike(u.Email!, searchPattern) || 
                    EF.Functions.ILike(u.FullName, searchPattern));
            }

            if (storeId.HasValue)
            {
                query = query.Where(u => u.StoreId == storeId.Value);
            }

            if (!string.IsNullOrEmpty(role))
            {
                query = query.Where(u => u.Role == role);
            }

            var totalCount = await query.CountAsync();

            var users = await query
                .OrderByDescending(u => u.CreatedAt)
                .Skip((pageNumber - 1) * pageSize)
                .Take(pageSize)
                .Select(u => new SystemUserDto(
                    u.Id,
                    u.Email ?? "",
                    u.FullName,
                    u.Role ?? "",
                    u.StoreId,
                    u.Store != null ? u.Store.Name : null,
                    u.Store != null ? u.Store.Code : null,
                    u.IsActive,
                    u.CreatedAt,
                    u.LastLoginAt
                ))
                .ToListAsync();

            return Ok(AppResponse<object>.Success(new { items = users, totalCount, pageNumber, pageSize }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting users");
            return StatusCode(500, AppResponse<List<SystemUserDto>>.Fail("Error getting users"));
        }
    }

    /// <summary>
    /// Lấy danh sách tất cả devices trong hệ thống
    /// </summary>
    [HttpGet("devices")]
    public async Task<ActionResult<AppResponse<object>>> GetAllDevices(
        [FromQuery] string? search = null,
        [FromQuery] Guid? storeId = null,
        [FromQuery] bool? isOnline = null,
        [FromQuery] bool? isClaimed = null,
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 500)
    {
        try
        {
            if (pageSize > 1000) pageSize = 1000;
            if (pageNumber < 1) pageNumber = 1;

            var query = _dbContext.Devices
                .Include(d => d.Store)
                .AsQueryable();

            if (!string.IsNullOrEmpty(search))
            {
                var searchPattern = $"%{search}%";
                query = query.Where(d => 
                    EF.Functions.ILike(d.SerialNumber, searchPattern) || 
                    EF.Functions.ILike(d.DeviceName, searchPattern));
            }

            if (storeId.HasValue)
            {
                query = query.Where(d => d.StoreId == storeId.Value);
            }

            // Filter by claimed status (connected to store or not)
            if (isClaimed.HasValue)
            {
                if (isClaimed.Value)
                {
                    query = query.Where(d => d.StoreId != null);
                }
                else
                {
                    query = query.Where(d => d.StoreId == null);
                }
            }

            if (isOnline.HasValue)
            {
                var status = isOnline.Value ? "Online" : "Offline";
                query = query.Where(d => d.DeviceStatus == status);
            }

            var totalCount = await query.CountAsync();

            var devices = await query
                .OrderByDescending(d => d.LastOnline)
                .Skip((pageNumber - 1) * pageSize)
                .Take(pageSize)
                .Select(d => new SystemDeviceDto(
                    d.Id,
                    d.SerialNumber,
                    d.DeviceName,
                    d.IpAddress,
                    d.DeviceStatus == "Online",
                    d.StoreId,
                    d.Store != null ? d.Store.Name : null,
                    d.Store != null ? d.Store.Code : null,
                    d.LastOnline,
                    d.CreatedAt
                ))
                .ToListAsync();

            return Ok(AppResponse<object>.Success(new { items = devices, totalCount, pageNumber, pageSize }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting devices");
            return StatusCode(500, AppResponse<List<SystemDeviceDto>>.Fail("Error getting devices"));
        }
    }

    /// <summary>
    /// Gỡ thiết bị khỏi cửa hàng (không xóa dữ liệu chấm công)
    /// </summary>
    [HttpPut("devices/{id:guid}/unassign-store")]
    public async Task<ActionResult<AppResponse<SystemDeviceDto>>> UnassignDeviceStore(Guid id)
    {
        try
        {
            var device = await _dbContext.Devices
                .AsTracking()
                .Include(d => d.Store)
                .FirstOrDefaultAsync(d => d.Id == id);

            if (device == null)
            {
                return Ok(AppResponse<SystemDeviceDto>.Fail("Không tìm thấy thiết bị"));
            }

            device.StoreId = null;
            device.OwnerId = null;
            device.IsClaimed = false;
            device.ClaimedAt = null;
            device.IsActive = false;
            device.UpdatedAt = DateTime.UtcNow;

            await _dbContext.SaveChangesAsync();

            var dto = new SystemDeviceDto(
                device.Id,
                device.SerialNumber,
                device.DeviceName,
                device.IpAddress,
                device.DeviceStatus == "Online",
                device.StoreId,
                null,
                null,
                device.LastOnline,
                device.CreatedAt
            );

            _logger.LogInformation("SuperAdmin {UserId} unassigned device {DeviceId} from store", CurrentUserId, id);
            return Ok(AppResponse<SystemDeviceDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error unassigning device from store");
            return StatusCode(500, AppResponse<SystemDeviceDto>.Fail("Không thể gỡ thiết bị khỏi cửa hàng"));
        }
    }

    /// <summary>
    /// Gán thiết bị vào cửa hàng (chuyển cửa hàng)
    /// </summary>
    [HttpPut("devices/{id:guid}/assign-store/{storeId:guid}")]
    public async Task<ActionResult<AppResponse<SystemDeviceDto>>> AssignDeviceToStore(Guid id, Guid storeId)
    {
        try
        {
            var device = await _dbContext.Devices
                .AsTracking()
                .FirstOrDefaultAsync(d => d.Id == id);

            if (device == null)
            {
                return Ok(AppResponse<SystemDeviceDto>.Fail("Không tìm thấy thiết bị"));
            }

            var store = await _dbContext.Stores
                .Include(s => s.Owner)
                .FirstOrDefaultAsync(s => s.Id == storeId);

            if (store == null)
            {
                return Ok(AppResponse<SystemDeviceDto>.Fail("Không tìm thấy cửa hàng"));
            }

            device.StoreId = storeId;
            device.OwnerId = store.OwnerId;
            device.IsClaimed = true;
            device.ClaimedAt = DateTime.UtcNow;
            device.IsActive = true;
            device.UpdatedAt = DateTime.UtcNow;

            await _dbContext.SaveChangesAsync();

            var dto = new SystemDeviceDto(
                device.Id,
                device.SerialNumber,
                device.DeviceName,
                device.IpAddress,
                device.DeviceStatus == "Online",
                device.StoreId,
                store.Name,
                store.Code,
                device.LastOnline,
                device.CreatedAt
            );

            _logger.LogInformation("SuperAdmin {UserId} assigned device {DeviceId} to store {StoreId}", CurrentUserId, id, storeId);
            return Ok(AppResponse<SystemDeviceDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error assigning device to store");
            return StatusCode(500, AppResponse<SystemDeviceDto>.Fail("Không thể gán thiết bị vào cửa hàng"));
        }
    }

    /// <summary>
    /// Lấy thống kê attendance theo ngày
    /// </summary>
    [HttpGet("attendance-stats")]
    public async Task<ActionResult<AppResponse<object>>> GetAttendanceStats(
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null)
    {
        try
        {
            var from = fromDate?.Date ?? DateTime.UtcNow.Date.AddDays(-7);
            var to = toDate?.Date ?? DateTime.UtcNow.Date;

            var stats = await _dbContext.AttendanceLogs
                .Where(a => a.AttendanceTime.Date >= from && a.AttendanceTime.Date <= to)
                .GroupBy(a => a.AttendanceTime.Date)
                .Select(g => new {
                    Date = g.Key,
                    Count = g.Count()
                })
                .OrderBy(x => x.Date)
                .ToListAsync();

            var totalByStore = await _dbContext.AttendanceLogs
                .Include(a => a.Device)
                .Where(a => a.AttendanceTime.Date >= from && a.AttendanceTime.Date <= to)
                .GroupBy(a => a.Device.StoreId)
                .Select(g => new {
                    StoreId = g.Key,
                    StoreName = _dbContext.Stores
                        .Where(s => s.Id == g.Key)
                        .Select(s => s.Name)
                        .FirstOrDefault() ?? "Unknown",
                    Count = g.Count()
                })
                .OrderByDescending(x => x.Count)
                .Take(10)
                .ToListAsync();

            return Ok(AppResponse<object>.Success(new {
                ByDate = stats,
                ByStore = totalByStore,
                FromDate = from,
                ToDate = to,
                TotalCount = stats.Sum(s => s.Count)
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting attendance stats");
            return StatusCode(500, AppResponse<object>.Fail("Error getting attendance stats"));
        }
    }

    /// <summary>
    /// Tạo SuperAdmin mới (chỉ SuperAdmin hiện tại mới có thể tạo)
    /// </summary>
    [HttpPost("create-superadmin")]
    public async Task<ActionResult<AppResponse<SystemUserDto>>> CreateSuperAdmin([FromBody] CreateSuperAdminRequest request)
    {
        try
        {
            // Check if email already exists
            var existingUser = await _userManager.FindByEmailAsync(request.Email);

            if (existingUser != null)
            {
                return BadRequest(AppResponse<SystemUserDto>.Fail("Email already exists"));
            }

            var newUser = new ApplicationUser
            {
                Id = Guid.NewGuid(),
                Email = request.Email,
                UserName = request.Email,
                FirstName = request.FullName.Split(' ').FirstOrDefault() ?? request.FullName,
                LastName = request.FullName.Split(' ').Skip(1).FirstOrDefault() ?? "",
                Role = nameof(Roles.SuperAdmin),
                IsActive = true,
                StoreId = null, // SuperAdmin không thuộc store nào
                CreatedAt = DateTime.UtcNow,
                CreatedBy = CurrentUserId.ToString(),
                EmailConfirmed = true
            };

            var result = await _userManager.CreateAsync(newUser, request.Password);
            if (!result.Succeeded)
            {
                return BadRequest(AppResponse<SystemUserDto>.Fail(string.Join(", ", result.Errors.Select(e => e.Description))));
            }

            // Add to SuperAdmin role
            await _userManager.AddToRoleAsync(newUser, nameof(Roles.SuperAdmin));

            _logger.LogInformation("SuperAdmin {CurrentUserId} created new SuperAdmin {NewUserId}", 
                CurrentUserId, newUser.Id);

            var dto = new SystemUserDto(
                newUser.Id,
                newUser.Email ?? "",
                newUser.FullName,
                newUser.Role ?? "",
                null,
                null,
                null,
                newUser.IsActive,
                newUser.CreatedAt,
                null
            );

            return Ok(AppResponse<SystemUserDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating SuperAdmin");
            return StatusCode(500, AppResponse<SystemUserDto>.Fail("Error creating SuperAdmin"));
        }
    }
    
    #region Agent (Đại lý) Management
    
    /// <summary>
    /// Lấy danh sách Agents
    /// </summary>
    [HttpGet("agents")]
    public async Task<ActionResult<AppResponse<PagedList<AgentDto>>>> GetAgents(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? search = null,
        [FromQuery] bool? isActive = null,
        [FromQuery] string? phone = null,
        [FromQuery] bool? hasStores = null,
        [FromQuery] bool? hasLicenseKeys = null,
        [FromQuery] string? licenseStatus = null) // expired, expiring, active
    {
        try
        {
            var query = _dbContext.Agents
                .Include(a => a.User)
                .Include(a => a.Stores)
                .Include(a => a.LicenseKeys)
                .AsQueryable();

            if (!string.IsNullOrEmpty(search))
            {
                query = query.Where(a => 
                    a.Name.Contains(search) || 
                    a.Code.Contains(search) || 
                    (a.Email != null && a.Email.Contains(search)) ||
                    (a.Phone != null && a.Phone.Contains(search)));
            }
            
            if (isActive.HasValue)
            {
                query = query.Where(a => a.IsActive == isActive.Value);
            }
            
            if (!string.IsNullOrEmpty(phone))
            {
                query = query.Where(a => a.Phone != null && a.Phone.Contains(phone));
            }
            
            if (hasStores.HasValue)
            {
                if (hasStores.Value)
                    query = query.Where(a => a.Stores.Any());
                else
                    query = query.Where(a => !a.Stores.Any());
            }
            
            if (hasLicenseKeys.HasValue)
            {
                if (hasLicenseKeys.Value)
                    query = query.Where(a => a.LicenseKeys.Any());
                else
                    query = query.Where(a => !a.LicenseKeys.Any());
            }
            
            if (!string.IsNullOrEmpty(licenseStatus))
            {
                var now = DateTime.UtcNow;
                query = licenseStatus.ToLower() switch
                {
                    "expired" => query.Where(a => a.LicenseExpiryDate.HasValue && a.LicenseExpiryDate.Value < now),
                    "expiring" => query.Where(a => a.LicenseExpiryDate.HasValue && a.LicenseExpiryDate.Value >= now && a.LicenseExpiryDate.Value < now.AddDays(30)),
                    "active" => query.Where(a => !a.LicenseExpiryDate.HasValue || a.LicenseExpiryDate.Value >= now),
                    _ => query
                };
            }

            var total = await query.CountAsync();
            var agents = await query
                .OrderByDescending(a => a.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();
                
            var items = agents.Select(a => MapToAgentDto(a)).ToList();

            var result = new PagedList<AgentDto>(items, total, page, pageSize);
            return Ok(AppResponse<PagedList<AgentDto>>.Success(result));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agents");
            return StatusCode(500, AppResponse<PagedList<AgentDto>>.Fail("Error getting agents"));
        }
    }
    
    private AgentDto MapToAgentDto(Agent a)
    {
        return new AgentDto(
            a.Id,
            a.Name,
            a.Code,
            a.Description,
            a.Address,
            a.Phone,
            a.Email,
            a.IsActive,
            a.LicenseKey,
            a.LicenseExpiryDate,
            a.MaxStores,
            a.Stores?.Count ?? 0,
            a.UserId,
            a.User?.Email,
            a.CreatedAt,
            // License Key Stats
            a.LicenseKeys?.Count ?? 0,
            a.LicenseKeys?.Count(lk => lk.IsUsed) ?? 0,
            a.LicenseKeys?.Count(lk => !lk.IsUsed && lk.IsActive) ?? 0,
            // Store Stats
            a.Stores?.Count(s => s.IsActive && !s.IsLocked) ?? 0,
            a.Stores?.Count(s => s.IsLocked) ?? 0,
            // Registration Info
            a.RegistrationToken,
            a.RegistrationTokenExpiry,
            a.IsRegistrationCompleted,
            !string.IsNullOrEmpty(a.RegistrationToken) && !a.IsRegistrationCompleted ? GetRegistrationLink(a.RegistrationToken) : null
        );
    }

    /// <summary>
    /// Lấy chi tiết Agent
    /// </summary>
    [HttpGet("agents/{id}")]
    public async Task<ActionResult<AppResponse<AgentDto>>> GetAgent(Guid id)
    {
        try
        {
            var agent = await _dbContext.Agents
                .Include(a => a.User)
                .Include(a => a.Stores)
                .Include(a => a.LicenseKeys)
                .FirstOrDefaultAsync(a => a.Id == id);

            if (agent == null)
            {
                return NotFound(AppResponse<AgentDto>.Fail("Agent không tồn tại"));
            }

            return Ok(AppResponse<AgentDto>.Success(MapToAgentDto(agent)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agent {AgentId}", id);
            return StatusCode(500, AppResponse<AgentDto>.Fail("Error getting agent"));
        }
    }

    /// <summary>
    /// Tạo Agent mới (tạo token để đại lý tự đăng ký)
    /// </summary>
    [HttpPost("agents")]
    public async Task<ActionResult<AppResponse<AgentDto>>> CreateAgent([FromBody] CreateAgentRequest request)
    {
        try
        {
            // Check code unique
            if (await _dbContext.Agents.AnyAsync(a => a.Code.ToLower() == request.Code.ToLower()))
            {
                return BadRequest(AppResponse<AgentDto>.Fail("Mã đại lý đã tồn tại"));
            }

            // Generate registration token
            var registrationToken = GenerateRegistrationToken();
            var tokenExpiry = DateTime.UtcNow.AddDays(request.TokenValidDays > 0 ? request.TokenValidDays : 30);

            // Create agent (without user account - agent will self-register)
            var agent = new Agent
            {
                Id = Guid.NewGuid(),
                Name = request.Name,
                Code = request.Code.ToUpper(),
                Description = request.Description,
                Address = request.Address,
                Phone = request.Phone,
                Email = request.Email,
                IsActive = true,
                MaxStores = request.MaxStores,
                RegistrationToken = registrationToken,
                RegistrationTokenExpiry = tokenExpiry,
                IsRegistrationCompleted = false,
                UserId = null,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = CurrentUserId.ToString()
            };

            _dbContext.Agents.Add(agent);
            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} created Agent {AgentId} with registration token", CurrentUserId, agent.Id);

            return Ok(AppResponse<AgentDto>.Success(MapToAgentDto(agent)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating agent");
            return StatusCode(500, AppResponse<AgentDto>.Fail("Error creating agent"));
        }
    }
    
    /// <summary>
    /// Tạo lại token đăng ký cho đại lý
    /// </summary>
    [HttpPost("agents/{id}/regenerate-token")]
    public async Task<ActionResult<AppResponse<AgentDto>>> RegenerateAgentToken(Guid id, [FromQuery] int validDays = 30)
    {
        try
        {
            var agent = await _dbContext.Agents
                .AsTracking()
                .Include(a => a.User)
                .Include(a => a.Stores)
                .Include(a => a.LicenseKeys)
                .FirstOrDefaultAsync(a => a.Id == id);

            if (agent == null)
            {
                return NotFound(AppResponse<AgentDto>.Fail("Agent không tồn tại"));
            }

            if (agent.IsRegistrationCompleted)
            {
                return BadRequest(AppResponse<AgentDto>.Fail("Đại lý đã hoàn tất đăng ký, không thể tạo token mới"));
            }

            agent.RegistrationToken = GenerateRegistrationToken();
            agent.RegistrationTokenExpiry = DateTime.UtcNow.AddDays(validDays);
            agent.LastModified = DateTime.UtcNow;
            agent.LastModifiedBy = CurrentUserId.ToString();

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} regenerated token for Agent {AgentId}", CurrentUserId, id);

            return Ok(AppResponse<AgentDto>.Success(MapToAgentDto(agent)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error regenerating token for agent {AgentId}", id);
            return StatusCode(500, AppResponse<AgentDto>.Fail("Error regenerating token"));
        }
    }

    /// <summary>
    /// Cập nhật Agent
    /// </summary>
    [HttpPut("agents/{id}")]
    public async Task<ActionResult<AppResponse<AgentDto>>> UpdateAgent(Guid id, [FromBody] UpdateAgentRequest request)
    {
        try
        {
            var agent = await _dbContext.Agents
                .AsTracking()
                .Include(a => a.User)
                .Include(a => a.Stores)
                .Include(a => a.LicenseKeys)
                .FirstOrDefaultAsync(a => a.Id == id);

            if (agent == null)
            {
                return NotFound(AppResponse<AgentDto>.Fail("Agent không tồn tại"));
            }

            // Update fields
            if (request.Name != null) agent.Name = request.Name;
            if (request.Description != null) agent.Description = request.Description;
            if (request.Address != null) agent.Address = request.Address;
            if (request.Phone != null) agent.Phone = request.Phone;
            if (request.Email != null) agent.Email = request.Email;
            if (request.MaxStores != null) agent.MaxStores = request.MaxStores.Value;
            if (request.IsActive != null) agent.IsActive = request.IsActive.Value;
            if (request.LicenseKey != null) agent.LicenseKey = request.LicenseKey;
            if (request.LicenseExpiryDate != null) agent.LicenseExpiryDate = request.LicenseExpiryDate;

            agent.LastModified = DateTime.UtcNow;
            agent.LastModifiedBy = CurrentUserId.ToString();

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} updated Agent {AgentId}", CurrentUserId, agent.Id);

            return Ok(AppResponse<AgentDto>.Success(MapToAgentDto(agent)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating agent {AgentId}", id);
            return StatusCode(500, AppResponse<AgentDto>.Fail("Error updating agent"));
        }
    }

    /// <summary>
    /// Xóa Agent
    /// </summary>
    [HttpDelete("agents/{id}")]
    public async Task<ActionResult<AppResponse<bool>>> DeleteAgent(Guid id)
    {
        try
        {
            var agent = await _dbContext.Agents
                .Include(a => a.Stores)
                .FirstOrDefaultAsync(a => a.Id == id);

            if (agent == null)
            {
                return NotFound(AppResponse<bool>.Fail("Agent không tồn tại"));
            }

            if (agent.Stores.Any())
            {
                return BadRequest(AppResponse<bool>.Fail($"Không thể xóa. Agent đang quản lý {agent.Stores.Count} cửa hàng"));
            }

            // Delete user account if exists
            if (agent.UserId != null)
            {
                var user = await _userManager.FindByIdAsync(agent.UserId.ToString()!);
                if (user != null)
                {
                    await _userManager.DeleteAsync(user);
                }
            }

            _dbContext.Agents.Remove(agent);
            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} deleted Agent {AgentId}", CurrentUserId, id);

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting agent {AgentId}", id);
            return StatusCode(500, AppResponse<bool>.Fail("Error deleting agent"));
        }
    }

    /// <summary>
    /// Gán Store cho Agent
    /// </summary>
    [HttpPost("agents/{agentId}/stores/{storeId}")]
    public async Task<ActionResult<AppResponse<bool>>> AssignStoreToAgent(Guid agentId, Guid storeId)
    {
        try
        {
            var agent = await _dbContext.Agents
                .Include(a => a.Stores)
                .FirstOrDefaultAsync(a => a.Id == agentId);

            if (agent == null)
            {
                return NotFound(AppResponse<bool>.Fail("Agent không tồn tại"));
            }

            var store = await _dbContext.Stores.FindAsync(storeId);
            if (store == null)
            {
                return NotFound(AppResponse<bool>.Fail("Store không tồn tại"));
            }

            if (store.AgentId != null && store.AgentId != agentId)
            {
                return BadRequest(AppResponse<bool>.Fail("Store đã được gán cho Agent khác"));
            }

            if (agent.Stores.Count >= agent.MaxStores)
            {
                return BadRequest(AppResponse<bool>.Fail($"Agent đã đạt giới hạn {agent.MaxStores} cửa hàng"));
            }

            store.AgentId = agentId;
            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} assigned Store {StoreId} to Agent {AgentId}", 
                CurrentUserId, storeId, agentId);

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error assigning store to agent");
            return StatusCode(500, AppResponse<bool>.Fail("Error assigning store to agent"));
        }
    }

    /// <summary>
    /// Xóa Store khỏi Agent
    /// </summary>
    [HttpDelete("agents/{agentId}/stores/{storeId}")]
    public async Task<ActionResult<AppResponse<bool>>> RemoveStoreFromAgent(Guid agentId, Guid storeId)
    {
        try
        {
            var store = await _dbContext.Stores.FindAsync(storeId);
            if (store == null)
            {
                return NotFound(AppResponse<bool>.Fail("Store không tồn tại"));
            }

            if (store.AgentId != agentId)
            {
                return BadRequest(AppResponse<bool>.Fail("Store không thuộc Agent này"));
            }

            store.AgentId = null;
            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} removed Store {StoreId} from Agent {AgentId}", 
                CurrentUserId, storeId, agentId);

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error removing store from agent");
            return StatusCode(500, AppResponse<bool>.Fail("Error removing store from agent"));
        }
    }
    
    #endregion

    #region License Key Management

    /// <summary>
    /// Tạo License Key mới
    /// </summary>
    [HttpPost("licenses")]
    public async Task<ActionResult<AppResponse<LicenseKeyDto>>> CreateLicenseKey([FromBody] CreateLicenseKeyRequest request)
    {
        try
        {
            // Generate unique key
            var key = GenerateLicenseKey(request.LicenseType);

            var license = new LicenseKey
            {
                Id = Guid.NewGuid(),
                Key = key,
                LicenseType = request.LicenseType,
                DurationDays = request.DurationDays,
                MaxUsers = request.MaxUsers,
                MaxDevices = request.MaxDevices,
                Notes = request.Notes,
                ServicePackageId = request.ServicePackageId,
                IsUsed = false,
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = CurrentUserId.ToString()
            };

            _dbContext.LicenseKeys.Add(license);
            await _dbContext.SaveChangesAsync();

            // Reload with includes for DTO mapping
            var created = await _dbContext.LicenseKeys
                .Include(l => l.Store)
                .Include(l => l.Agent)
                .Include(l => l.ServicePackage)
                .FirstAsync(l => l.Id == license.Id);

            _logger.LogInformation("SuperAdmin {UserId} created License Key {Key}", CurrentUserId, key);

            return Ok(AppResponse<LicenseKeyDto>.Success(MapToLicenseKeyDto(created)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating license key");
            return StatusCode(500, AppResponse<LicenseKeyDto>.Fail("Error creating license key"));
        }
    }

    /// <summary>
    /// Tạo nhiều License Key cùng lúc
    /// </summary>
    [HttpPost("licenses/batch")]
    public async Task<ActionResult<AppResponse<List<LicenseKeyDto>>>> CreateBatchLicenseKeys([FromBody] CreateBatchLicenseKeyRequest request)
    {
        try
        {
            var licenses = new List<LicenseKey>();

            for (int i = 0; i < request.Count; i++)
            {
                var key = GenerateLicenseKey(request.LicenseType);
                var license = new LicenseKey
                {
                    Id = Guid.NewGuid(),
                    Key = key,
                    LicenseType = request.LicenseType,
                    DurationDays = request.DurationDays,
                    MaxUsers = request.MaxUsers,
                    MaxDevices = request.MaxDevices,
                    Notes = request.Notes,
                    ServicePackageId = request.ServicePackageId,
                    IsUsed = false,
                    IsActive = true,
                    CreatedAt = DateTime.UtcNow,
                    CreatedBy = CurrentUserId.ToString()
                };
                licenses.Add(license);
            }

            _dbContext.LicenseKeys.AddRange(licenses);
            await _dbContext.SaveChangesAsync();

            // Reload with includes
            var ids = licenses.Select(l => l.Id).ToList();
            var created = await _dbContext.LicenseKeys
                .Include(l => l.Store)
                .Include(l => l.Agent)
                .Include(l => l.ServicePackage)
                .Where(l => ids.Contains(l.Id))
                .ToListAsync();

            _logger.LogInformation("SuperAdmin {UserId} created {Count} License Keys", CurrentUserId, request.Count);

            return Ok(AppResponse<List<LicenseKeyDto>>.Success(created.Select(MapToLicenseKeyDto).ToList()));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating batch license keys");
            return StatusCode(500, AppResponse<List<LicenseKeyDto>>.Fail("Error creating license keys"));
        }
    }

    /// <summary>
    /// Lấy danh sách License Keys
    /// </summary>
    [HttpGet("licenses")]
    public async Task<ActionResult<AppResponse<PagedList<LicenseKeyDto>>>> GetLicenseKeys(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] bool? isUsed = null,
        [FromQuery] LicenseType? licenseType = null,
        [FromQuery] Guid? agentId = null,
        [FromQuery] bool? isActive = null,
        [FromQuery] string? search = null,
        [FromQuery] Guid? servicePackageId = null)
    {
        try
        {
            var query = _dbContext.LicenseKeys
                .Include(l => l.Store)
                .Include(l => l.Agent)
                .Include(l => l.ServicePackage)
                .AsQueryable();

            if (isUsed.HasValue)
                query = query.Where(l => l.IsUsed == isUsed.Value);

            if (licenseType.HasValue)
                query = query.Where(l => l.LicenseType == licenseType.Value);
                
            if (agentId.HasValue)
                query = query.Where(l => l.AgentId == agentId.Value);
                
            if (isActive.HasValue)
                query = query.Where(l => l.IsActive == isActive.Value);
                
            if (!string.IsNullOrWhiteSpace(search))
                query = query.Where(l => l.Key.Contains(search) || (l.Notes != null && l.Notes.Contains(search)));
                
            if (servicePackageId.HasValue)
                query = query.Where(l => l.ServicePackageId == servicePackageId.Value);

            var total = await query.CountAsync();
            var items = await query
                .OrderByDescending(l => l.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();

            var dtos = items.Select(MapToLicenseKeyDto).ToList();
            var result = new PagedList<LicenseKeyDto>(dtos, total, page, pageSize);

            return Ok(AppResponse<PagedList<LicenseKeyDto>>.Success(result));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting license keys");
            return StatusCode(500, AppResponse<PagedList<LicenseKeyDto>>.Fail("Error getting license keys"));
        }
    }

    /// <summary>
    /// Revoke License Key
    /// </summary>
    [HttpDelete("licenses/{id}")]
    public async Task<ActionResult<AppResponse<bool>>> RevokeLicenseKey(Guid id)
    {
        try
        {
            var license = await _dbContext.LicenseKeys.FindAsync(id);
            if (license == null)
            {
                return NotFound(AppResponse<bool>.Fail("License key not found"));
            }

            license.IsActive = false;
            license.UpdatedAt = DateTime.UtcNow;
            license.UpdatedBy = CurrentUserId.ToString();

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} revoked License Key {Key}", CurrentUserId, license.Key);

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error revoking license key");
            return StatusCode(500, AppResponse<bool>.Fail("Error revoking license key"));
        }
    }

    /// <summary>
    /// Xóa vĩnh viễn License Key (chỉ cho phép key chưa kích hoạt và chưa gán cho đại lý)
    /// </summary>
    [HttpDelete("licenses/{id}/permanent")]
    public async Task<ActionResult<AppResponse<bool>>> DeleteLicenseKeyPermanent(Guid id)
    {
        try
        {
            var license = await _dbContext.LicenseKeys.FindAsync(id);
            if (license == null)
                return NotFound(AppResponse<bool>.Fail("License key not found"));

            if (license.IsUsed)
                return BadRequest(AppResponse<bool>.Fail("Không thể xóa key đã kích hoạt"));

            if (license.AgentId != null)
                return BadRequest(AppResponse<bool>.Fail("Không thể xóa key đã gán cho đại lý"));

            _dbContext.LicenseKeys.Remove(license);
            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} permanently deleted License Key {Key}", CurrentUserId, license.Key);
            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting license key");
            return StatusCode(500, AppResponse<bool>.Fail("Error deleting license key"));
        }
    }

    /// <summary>
    /// Gán License Key cho Agent/Đại lý
    /// </summary>
    [HttpPost("licenses/{id}/assign-agent")]
    public async Task<ActionResult<AppResponse<LicenseKeyDto>>> AssignLicenseToAgent(Guid id, [FromBody] AssignLicenseToAgentRequest request)
    {
        try
        {
            var license = await _dbContext.LicenseKeys
                .AsTracking()
                .Include(l => l.Store)
                .Include(l => l.Agent)
                .Include(l => l.ServicePackage)
                .FirstOrDefaultAsync(l => l.Id == id);
                
            if (license == null)
                return NotFound(AppResponse<LicenseKeyDto>.Fail("License key not found"));
                
            if (license.IsUsed)
                return BadRequest(AppResponse<LicenseKeyDto>.Fail("License key đã được sử dụng"));
                
            var agent = await _dbContext.Agents.FindAsync(request.AgentId);
            if (agent == null)
                return NotFound(AppResponse<LicenseKeyDto>.Fail("Agent not found"));
                
            license.AgentId = request.AgentId;
            license.UpdatedAt = DateTime.UtcNow;
            license.UpdatedBy = CurrentUserId.ToString();
            
            await _dbContext.SaveChangesAsync();
            _logger.LogInformation("SuperAdmin {UserId} assigned License {Key} to Agent {AgentId}", CurrentUserId, license.Key, request.AgentId);
            
            return Ok(AppResponse<LicenseKeyDto>.Success(MapToLicenseKeyDto(license)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error assigning license to agent");
            return StatusCode(500, AppResponse<LicenseKeyDto>.Fail("Error assigning license to agent"));
        }
    }
    
    /// <summary>
    /// Gán nhiều License Keys cho Agent/Đại lý
    /// </summary>
    [HttpPost("licenses/batch-assign-agent")]
    public async Task<ActionResult<AppResponse<BatchAssignResult>>> BatchAssignLicensesToAgent([FromBody] BatchAssignLicenseRequest request)
    {
        try
        {
            var agent = await _dbContext.Agents.FindAsync(request.AgentId);
            if (agent == null)
                return NotFound(AppResponse<BatchAssignResult>.Fail("Agent not found"));
                
            var licenses = await _dbContext.LicenseKeys
                .AsTracking()
                .Where(l => request.LicenseKeyIds.Contains(l.Id) && !l.IsUsed && l.IsActive)
                .ToListAsync();
                
            var assignedCount = 0;
            var failedIds = new List<Guid>();
            
            foreach (var license in licenses)
            {
                if (license.AgentId == null || license.AgentId == request.AgentId)
                {
                    license.AgentId = request.AgentId;
                    license.UpdatedAt = DateTime.UtcNow;
                    license.UpdatedBy = CurrentUserId.ToString();
                    assignedCount++;
                }
                else
                {
                    failedIds.Add(license.Id);
                }
            }
            
            await _dbContext.SaveChangesAsync();
            _logger.LogInformation("SuperAdmin {UserId} batch-assigned {Count} Licenses to Agent {AgentId}", CurrentUserId, assignedCount, request.AgentId);
            
            return Ok(AppResponse<BatchAssignResult>.Success(new BatchAssignResult(assignedCount, failedIds)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error batch assigning licenses");
            return StatusCode(500, AppResponse<BatchAssignResult>.Fail("Error batch assigning licenses"));
        }
    }
    
    /// <summary>
    /// Cấp key hàng loạt cho đại lý theo số lượng (tự động chọn key available)
    /// </summary>
    [HttpPost("licenses/batch-assign-agent-by-count")]
    public async Task<ActionResult<AppResponse<BatchAssignResult>>> BatchAssignLicensesToAgentByCount([FromBody] BatchAssignByCountRequest request)
    {
        try
        {
            if (request.Count <= 0)
                return BadRequest(AppResponse<BatchAssignResult>.Fail("Số lượng phải lớn hơn 0"));
                
            var agent = await _dbContext.Agents.FindAsync(request.AgentId);
            if (agent == null)
                return NotFound(AppResponse<BatchAssignResult>.Fail("Agent not found"));

            var query = _dbContext.LicenseKeys
                .AsTracking()
                .Where(l => !l.IsUsed && l.IsActive && l.AgentId == null);

            if (request.ServicePackageId.HasValue)
                query = query.Where(l => l.ServicePackageId == request.ServicePackageId.Value);

            if (request.LicenseType.HasValue)
                query = query.Where(l => l.LicenseType == request.LicenseType.Value);

            var licenses = await query
                .OrderBy(l => l.CreatedAt)
                .Take(request.Count)
                .ToListAsync();

            if (!licenses.Any())
                return BadRequest(AppResponse<BatchAssignResult>.Fail("Không có key khả dụng phù hợp"));

            foreach (var license in licenses)
            {
                license.AgentId = request.AgentId;
                license.UpdatedAt = DateTime.UtcNow;
                license.UpdatedBy = CurrentUserId.ToString();
            }

            await _dbContext.SaveChangesAsync();
            _logger.LogInformation("SuperAdmin {UserId} assigned {Count} available licenses to Agent {AgentId}", CurrentUserId, licenses.Count, request.AgentId);

            return Ok(AppResponse<BatchAssignResult>.Success(new BatchAssignResult(licenses.Count, new List<Guid>())));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error batch assigning licenses by count");
            return StatusCode(500, AppResponse<BatchAssignResult>.Fail("Error batch assigning licenses by count"));
        }
    }
    
    /// <summary>
    /// Gán nhiều License Keys cho Store
    /// </summary>
    [HttpPost("licenses/batch-assign-store")]
    public async Task<ActionResult<AppResponse<BatchAssignResult>>> BatchAssignLicensesToStore([FromBody] BatchAssignLicenseToStoreRequest request)
    {
        try
        {
            var store = await _dbContext.Stores.FindAsync(request.StoreId);
            if (store == null)
                return NotFound(AppResponse<BatchAssignResult>.Fail("Store not found"));
                
            // Only get one available license for the store (takes the first matching one)
            var license = await _dbContext.LicenseKeys
                .AsTracking()
                .Where(l => request.LicenseKeyIds.Contains(l.Id) && !l.IsUsed && l.IsActive)
                .FirstOrDefaultAsync();
                
            if (license == null)
                return BadRequest(AppResponse<BatchAssignResult>.Fail("Không có key hợp lệ"));
                
            // Activate license for store
            license.IsUsed = true;
            license.StoreId = request.StoreId;
            license.ActivatedAt = DateTime.UtcNow;
            license.UpdatedAt = DateTime.UtcNow;
            license.UpdatedBy = CurrentUserId.ToString();
            
            // Update store subscription
            store.LicenseKey = license.Key;
            store.LicenseType = license.LicenseType;
            store.MaxUsers = license.MaxUsers;
            store.MaxDevices = license.MaxDevices;
            store.ExpiryDate = DateTime.UtcNow.AddDays(license.DurationDays);
            store.IsActive = true;
            store.IsLocked = false;
            store.UpdatedAt = DateTime.UtcNow;
            
            await _dbContext.SaveChangesAsync();
            _logger.LogInformation("SuperAdmin {UserId} activated License {Key} for Store {StoreId}", CurrentUserId, license.Key, request.StoreId);
            
            return Ok(AppResponse<BatchAssignResult>.Success(new BatchAssignResult(1, new List<Guid>())));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error batch assigning licenses to store");
            return StatusCode(500, AppResponse<BatchAssignResult>.Fail("Error batch assigning licenses to store"));
        }
    }
    
    /// <summary>
    /// Thu hồi nhiều License Keys
    /// </summary>
    [HttpPost("licenses/batch-revoke")]
    public async Task<ActionResult<AppResponse<BatchAssignResult>>> BatchRevokeLicenses([FromBody] BatchRevokeRequest request)
    {
        try
        {
            var licenses = await _dbContext.LicenseKeys
                .AsTracking()
                .Where(l => request.LicenseKeyIds.Contains(l.Id))
                .ToListAsync();
                
            var revokedCount = 0;
            foreach (var license in licenses)
            {
                license.IsActive = false;
                license.UpdatedAt = DateTime.UtcNow;
                license.UpdatedBy = CurrentUserId.ToString();
                revokedCount++;
            }
            
            await _dbContext.SaveChangesAsync();
            _logger.LogInformation("SuperAdmin {UserId} batch-revoked {Count} Licenses", CurrentUserId, revokedCount);
            
            return Ok(AppResponse<BatchAssignResult>.Success(new BatchAssignResult(revokedCount, new List<Guid>())));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error batch revoking licenses");
            return StatusCode(500, AppResponse<BatchAssignResult>.Fail("Error batch revoking licenses"));
        }
    }
    
    /// <summary>
    /// Xuất danh sách License Keys (CSV/JSON)
    /// </summary>
    [HttpGet("licenses/export")]
    public async Task<IActionResult> ExportLicenseKeys(
        [FromQuery] string format = "csv",
        [FromQuery] bool? isUsed = null,
        [FromQuery] LicenseType? licenseType = null,
        [FromQuery] Guid? agentId = null,
        [FromQuery] bool? isActive = null)
    {
        try
        {
            var query = _dbContext.LicenseKeys
                .Include(l => l.Store)
                .Include(l => l.Agent)
                .Include(l => l.ServicePackage)
                .AsQueryable();
                
            if (isUsed.HasValue) query = query.Where(l => l.IsUsed == isUsed.Value);
            if (licenseType.HasValue) query = query.Where(l => l.LicenseType == licenseType.Value);
            if (agentId.HasValue) query = query.Where(l => l.AgentId == agentId.Value);
            if (isActive.HasValue) query = query.Where(l => l.IsActive == isActive.Value);
            
            var licenses = await query.OrderByDescending(l => l.CreatedAt).ToListAsync();
            
            if (format.ToLower() == "json")
            {
                var jsonData = licenses.Select(l => new
                {
                    l.Key,
                    LicenseType = l.LicenseType.ToString(),
                    l.DurationDays,
                    l.MaxUsers,
                    l.MaxDevices,
                    l.IsUsed,
                    l.IsActive,
                    l.ActivatedAt,
                    StoreName = l.Store?.Name,
                    AgentName = l.Agent?.Name,
                    l.Notes,
                    l.CreatedAt
                });
                return Ok(jsonData);
            }
            else
            {
                var csv = new StringBuilder();
                csv.AppendLine("Key,LicenseType,DurationDays,MaxUsers,MaxDevices,IsUsed,IsActive,ActivatedAt,StoreName,AgentName,Notes,CreatedAt");
                foreach (var l in licenses)
                {
                    csv.AppendLine($"\"{l.Key}\",\"{l.LicenseType}\",{l.DurationDays},{l.MaxUsers},{l.MaxDevices},{l.IsUsed},{l.IsActive},\"{l.ActivatedAt:yyyy-MM-dd HH:mm}\",\"{l.Store?.Name}\",\"{l.Agent?.Name}\",\"{l.Notes?.Replace("\"", "\"\"")}\",\"{l.CreatedAt:yyyy-MM-dd HH:mm}\"");
                }
                
                var bytes = Encoding.UTF8.GetBytes(csv.ToString());
                return File(bytes, "text/csv", $"license_keys_{DateTime.Now:yyyyMMdd_HHmmss}.csv");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error exporting license keys");
            return StatusCode(500, "Error exporting license keys");
        }
    }
    
    /// <summary>
    /// Lấy License Keys theo Agent
    /// </summary>
    [HttpGet("agents/{agentId}/licenses")]
    public async Task<ActionResult<AppResponse<PagedList<LicenseKeyDto>>>> GetAgentLicenseKeys(
        Guid agentId,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] bool? isUsed = null)
    {
        try
        {
            var query = _dbContext.LicenseKeys
                .Include(l => l.Store)
                .Where(l => l.AgentId == agentId);
                
            if (isUsed.HasValue) query = query.Where(l => l.IsUsed == isUsed.Value);
            
            var total = await query.CountAsync();
            var items = await query
                .OrderByDescending(l => l.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync();
                
            var dtos = items.Select(MapToLicenseKeyDto).ToList();
            var result = new PagedList<LicenseKeyDto>(dtos, total, page, pageSize);
            
            return Ok(AppResponse<PagedList<LicenseKeyDto>>.Success(result));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agent license keys");
            return StatusCode(500, AppResponse<PagedList<LicenseKeyDto>>.Fail("Error getting agent license keys"));
        }
    }

    /// <summary>
    /// Kích hoạt License Key cho Store — cộng thêm ngày sử dụng, gán gói dịch vụ từ key
    /// Mỗi cửa hàng tối đa 3 lần gia hạn (lần đầu kích hoạt không tính)
    /// </summary>
    [HttpPost("stores/{storeId}/activate-license")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> ActivateLicenseForStore(Guid storeId, [FromBody] ActivateLicenseRequest request)
    {
        try
        {
            var store = await _dbContext.Stores
                .AsTracking()
                .Include(s => s.Owner)
                .Include(s => s.Agent)
                .Include(s => s.Users)
                .Include(s => s.Devices)
                .Include(s => s.ServicePackage)
                .FirstOrDefaultAsync(s => s.Id == storeId);

            if (store == null)
            {
                return NotFound(AppResponse<StoreDetailDto>.Fail("Store not found"));
            }

            var license = await _dbContext.LicenseKeys
                .AsTracking()
                .Include(l => l.ServicePackage)
                .FirstOrDefaultAsync(l => l.Key == request.LicenseKey && l.IsActive && !l.IsUsed);

            if (license == null)
            {
                return BadRequest(AppResponse<StoreDetailDto>.Fail("License key không hợp lệ hoặc đã được sử dụng"));
            }

            // Kiểm tra giới hạn gia hạn: lần đầu kích hoạt (chưa có LicenseKey) không tính
            var isFirstActivation = string.IsNullOrEmpty(store.LicenseKey);
            if (!isFirstActivation && store.RenewalCount >= 3)
            {
                return BadRequest(AppResponse<StoreDetailDto>.Fail(
                    "Cửa hàng đã gia hạn tối đa 3 lần. Không thể kích hoạt thêm key."));
            }

            // Activate license
            license.IsUsed = true;
            license.StoreId = storeId;
            license.ActivatedAt = DateTime.UtcNow;

            // Cộng thêm ngày sử dụng (không reset)
            var baseDate = store.ExpiryDate ?? DateTime.UtcNow;
            if (baseDate < DateTime.UtcNow) baseDate = DateTime.UtcNow;
            store.ExpiryDate = baseDate.AddDays(license.DurationDays);

            // Cập nhật thông tin license & gói dịch vụ từ key
            store.LicenseKey = license.Key;
            store.LicenseType = license.LicenseType;
            store.MaxUsers = license.MaxUsers;
            store.MaxDevices = license.MaxDevices;

            // Gán gói dịch vụ từ key (nếu key có gói)
            if (license.ServicePackageId != null)
            {
                store.ServicePackageId = license.ServicePackageId;
            }

            // Tăng số lần gia hạn (lần đầu không tính)
            if (!isFirstActivation)
            {
                store.RenewalCount++;
            }

            store.IsActive = true;
            store.IsLocked = false;
            store.LockReason = null;
            store.UpdatedAt = DateTime.UtcNow;

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} activated License {Key} for Store {StoreId} (renewal #{Count})", 
                CurrentUserId, license.Key, storeId, store.RenewalCount);

            // Thông báo cho chủ cửa hàng về việc kích hoạt key
            try
            {
                if (store.OwnerId.HasValue)
                {
                    var packageName = license.ServicePackage?.Name ?? license.LicenseType.ToString();
                    await _notificationService.CreateAndSendAsync(
                        targetUserId: store.OwnerId.Value,
                        type: NotificationType.Success,
                        title: "Kích hoạt License thành công",
                        message: $"Cửa hàng '{store.Name}' đã được kích hoạt gói {packageName}, hạn sử dụng đến {store.ExpiryDate:dd/MM/yyyy}",
                        relatedEntityId: storeId,
                        relatedEntityType: "Store",
                        categoryCode: "license",
                        storeId: storeId);
                }
            }
            catch { }

            return Ok(AppResponse<StoreDetailDto>.Success(MapToStoreDetailDto(store)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error activating license for store {StoreId}", storeId);
            return StatusCode(500, AppResponse<StoreDetailDto>.Fail("Error activating license"));
        }
    }

    #endregion

    #region Store Advanced Management

    /// <summary>
    /// Khóa cửa hàng (không cho truy cập)
    /// </summary>
    [HttpPost("stores/{id}/lock")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> LockStore(Guid id, [FromBody] LockStoreRequest request)
    {
        try
        {
            var store = await _dbContext.Stores
                .AsTracking()
                .Include(s => s.Owner)
                .Include(s => s.Users)
                .Include(s => s.Devices)
                .FirstOrDefaultAsync(s => s.Id == id);

            if (store == null)
            {
                return NotFound(AppResponse<StoreDetailDto>.Fail("Store not found"));
            }

            store.IsLocked = true;
            store.LockReason = request.Reason;
            store.LockedAt = DateTime.UtcNow;
            store.UpdatedAt = DateTime.UtcNow;
            store.UpdatedBy = CurrentUserId.ToString();

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} locked Store {StoreId}. Reason: {Reason}", 
                CurrentUserId, id, request.Reason);

            return Ok(AppResponse<StoreDetailDto>.Success(MapToStoreDetailDto(store)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error locking store {StoreId}", id);
            return StatusCode(500, AppResponse<StoreDetailDto>.Fail("Error locking store"));
        }
    }

    /// <summary>
    /// Mở khóa cửa hàng
    /// </summary>
    [HttpPost("stores/{id}/unlock")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> UnlockStore(Guid id)
    {
        try
        {
            var store = await _dbContext.Stores
                .AsTracking()
                .Include(s => s.Owner)
                .Include(s => s.Users)
                .Include(s => s.Devices)
                .FirstOrDefaultAsync(s => s.Id == id);

            if (store == null)
            {
                return NotFound(AppResponse<StoreDetailDto>.Fail("Store not found"));
            }

            store.IsLocked = false;
            store.LockReason = null;
            store.LockedAt = null;
            store.UpdatedAt = DateTime.UtcNow;
            store.UpdatedBy = CurrentUserId.ToString();

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} unlocked Store {StoreId}", CurrentUserId, id);

            return Ok(AppResponse<StoreDetailDto>.Success(MapToStoreDetailDto(store)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error unlocking store {StoreId}", id);
            return StatusCode(500, AppResponse<StoreDetailDto>.Fail("Error unlocking store"));
        }
    }

    /// <summary>
    /// Gia hạn subscription cho Store
    /// </summary>
    [HttpPost("stores/{id}/extend")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> ExtendStoreSubscription(Guid id, [FromBody] ExtendSubscriptionRequest request)
    {
        try
        {
            var store = await _dbContext.Stores
                .AsTracking()
                .Include(s => s.Owner)
                .Include(s => s.Users)
                .Include(s => s.Devices)
                .FirstOrDefaultAsync(s => s.Id == id);

            if (store == null)
            {
                return NotFound(AppResponse<StoreDetailDto>.Fail("Store not found"));
            }

            // Calculate new expiry date
            var baseDate = store.ExpiryDate ?? DateTime.UtcNow;
            if (baseDate < DateTime.UtcNow)
            {
                baseDate = DateTime.UtcNow;
            }

            store.ExpiryDate = baseDate.AddDays(request.DaysToAdd);
            
            if (request.MaxUsers.HasValue)
            {
                store.MaxUsers = request.MaxUsers.Value;
            }
            
            if (request.MaxDevices.HasValue)
            {
                store.MaxDevices = request.MaxDevices.Value;
            }
            
            if (request.LicenseType.HasValue)
            {
                store.LicenseType = request.LicenseType.Value;
            }

            store.UpdatedAt = DateTime.UtcNow;
            store.UpdatedBy = CurrentUserId.ToString();

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} extended Store {StoreId} subscription by {Days} days", 
                CurrentUserId, id, request.DaysToAdd);

            return Ok(AppResponse<StoreDetailDto>.Success(MapToStoreDetailDto(store)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error extending store subscription {StoreId}", id);
            return StatusCode(500, AppResponse<StoreDetailDto>.Fail("Error extending subscription"));
        }
    }

    /// <summary>
    /// Cập nhật giới hạn users/devices cho Store
    /// </summary>
    [HttpPut("stores/{id}/limits")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> UpdateStoreLimits(Guid id, [FromBody] UpdateStoreLimitsRequest request)
    {
        try
        {
            var store = await _dbContext.Stores
                .AsTracking()
                .Include(s => s.Owner)
                .Include(s => s.Users)
                .Include(s => s.Devices)
                .FirstOrDefaultAsync(s => s.Id == id);

            if (store == null)
            {
                return NotFound(AppResponse<StoreDetailDto>.Fail("Store not found"));
            }

            store.MaxUsers = request.MaxUsers;
            store.MaxDevices = request.MaxDevices;
            store.UpdatedAt = DateTime.UtcNow;
            store.UpdatedBy = CurrentUserId.ToString();

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} updated Store {StoreId} limits: MaxUsers={MaxUsers}, MaxDevices={MaxDevices}", 
                CurrentUserId, id, request.MaxUsers, request.MaxDevices);

            return Ok(AppResponse<StoreDetailDto>.Success(MapToStoreDetailDto(store)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating store limits {StoreId}", id);
            return StatusCode(500, AppResponse<StoreDetailDto>.Fail("Error updating store limits"));
        }
    }

    /// <summary>
    /// Xóa toàn bộ dữ liệu cửa hàng
    /// </summary>
    [HttpDelete("stores/{id}/data")]
    public async Task<ActionResult<AppResponse<bool>>> DeleteAllStoreData(Guid id, [FromQuery] bool confirmDelete = false)
    {
        try
        {
            if (!confirmDelete)
            {
                return BadRequest(AppResponse<bool>.Fail("Vui lòng xác nhận xóa dữ liệu (confirmDelete=true)"));
            }

            var store = await _dbContext.Stores
                .Include(s => s.Devices)
                .Include(s => s.Users)
                .FirstOrDefaultAsync(s => s.Id == id);

            if (store == null)
            {
                return NotFound(AppResponse<bool>.Fail("Store not found"));
            }

            // Delete attendance records using ExecuteDeleteAsync (no memory load)
            await _dbContext.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == id)
                .ExecuteDeleteAsync();

            // Delete device commands
            var deviceIds = store.Devices.Select(d => d.Id).ToList();
            await _dbContext.DeviceCommands
                .Where(c => deviceIds.Contains(c.DeviceId))
                .ExecuteDeleteAsync();

            // Delete device users and their fingerprints
            await _dbContext.DeviceUsers
                .Where(du => deviceIds.Contains(du.DeviceId))
                .ExecuteDeleteAsync();

            // Delete device settings
            await _dbContext.DeviceSettings
                .Where(s => deviceIds.Contains(s.DeviceId))
                .ExecuteDeleteAsync();

            // Delete devices
            _dbContext.Devices.RemoveRange(store.Devices);

            // Delete employees
            await _dbContext.Employees
                .Where(e => e.StoreId == id)
                .ExecuteDeleteAsync();

            // Reset store
            store.Devices.Clear();

            await _dbContext.SaveChangesAsync();

            _logger.LogWarning("SuperAdmin {UserId} deleted ALL DATA for Store {StoreId}", CurrentUserId, id);

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting store data {StoreId}", id);
            return StatusCode(500, AppResponse<bool>.Fail("Error deleting store data"));
        }
    }

    /// <summary>
    /// Xóa hoàn toàn cửa hàng và tất cả dữ liệu liên quan
    /// </summary>
    [HttpDelete("stores/{id}")]
    public async Task<ActionResult<AppResponse<bool>>> DeleteStore(Guid id, [FromQuery] bool confirmDelete = false)
    {
        try
        {
            if (!confirmDelete)
            {
                return BadRequest(AppResponse<bool>.Fail("Vui lòng xác nhận xóa cửa hàng (confirmDelete=true)"));
            }

            var store = await _dbContext.Stores.FirstOrDefaultAsync(s => s.Id == id);
            if (store == null)
            {
                return NotFound(AppResponse<bool>.Fail("Store not found"));
            }

            var storeName = store.Name;

            using var transaction = await _dbContext.Database.BeginTransactionAsync();

            // Use raw SQL to delete all related data in correct order (child tables first)
            // This handles all 50+ tables referencing StoreId

            // Helper to execute delete with a fresh parameter each time
            async Task DeleteFrom(string table, string column = "\"StoreId\"")
            {
                try
                {
#pragma warning disable EF1002 // Table/column names are hardcoded, not user input
                    await _dbContext.Database.ExecuteSqlRawAsync(
                        $"DELETE FROM \"{table}\" WHERE {column} = @storeId",
                        new Npgsql.NpgsqlParameter("@storeId", id));
#pragma warning restore EF1002
                }
                catch (Npgsql.PostgresException ex) when (ex.SqlState == "42P01" || ex.SqlState == "42703" || ex.SqlState == "42P10")
                {
                    _logger.LogDebug("Table {Table} or column not found, skipping: {Message}", table, ex.Message);
                }
            }

            async Task ExecuteRawSafe(string sql)
            {
                try
                {
                    await _dbContext.Database.ExecuteSqlRawAsync(sql,
                        new Npgsql.NpgsqlParameter("@storeId", id));
                }
                catch (Npgsql.PostgresException ex) when (ex.SqlState == "42P01" || ex.SqlState == "42703" || ex.SqlState == "42P10")
                {
                    _logger.LogDebug("Table or column in query does not exist, skipping: {Sql}", sql);
                }
            }

            // 1. Delete deep child tables (depend on Devices/Employees)
            // Attendance logs via Device
            await ExecuteRawSafe(
                "DELETE FROM \"AttendanceLogs\" WHERE \"DeviceId\" IN (SELECT \"Id\" FROM \"Devices\" WHERE \"StoreId\" = @storeId)");

            // Device commands, users, settings, info via Device
            await ExecuteRawSafe(
                "DELETE FROM \"DeviceCommands\" WHERE \"DeviceId\" IN (SELECT \"Id\" FROM \"Devices\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"FingerprintTemplates\" WHERE \"EmployeeId\" IN (SELECT \"Id\" FROM \"DeviceUsers\" WHERE \"DeviceId\" IN (SELECT \"Id\" FROM \"Devices\" WHERE \"StoreId\" = @storeId))");
            await ExecuteRawSafe(
                "DELETE FROM \"FaceTemplates\" WHERE \"EmployeeId\" IN (SELECT \"Id\" FROM \"DeviceUsers\" WHERE \"DeviceId\" IN (SELECT \"Id\" FROM \"Devices\" WHERE \"StoreId\" = @storeId))");
            await ExecuteRawSafe(
                "DELETE FROM \"DeviceUsers\" WHERE \"DeviceId\" IN (SELECT \"Id\" FROM \"Devices\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"DeviceSettings\" WHERE \"DeviceId\" IN (SELECT \"Id\" FROM \"Devices\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"DeviceInfos\" WHERE \"DeviceId\" IN (SELECT \"Id\" FROM \"Devices\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"SyncLogs\" WHERE \"DeviceId\" IN (SELECT \"Id\" FROM \"Devices\" WHERE \"StoreId\" = @storeId)");

            // Task child tables via WorkTasks
            await ExecuteRawSafe(
                "DELETE FROM \"TaskComments\" WHERE \"TaskId\" IN (SELECT \"Id\" FROM \"WorkTasks\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"TaskHistories\" WHERE \"TaskId\" IN (SELECT \"Id\" FROM \"WorkTasks\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"TaskAttachments\" WHERE \"TaskId\" IN (SELECT \"Id\" FROM \"WorkTasks\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"TaskAssignees\" WHERE \"TaskId\" IN (SELECT \"Id\" FROM \"WorkTasks\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"TaskReminders\" WHERE \"TaskId\" IN (SELECT \"Id\" FROM \"WorkTasks\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"TaskEvaluations\" WHERE \"TaskId\" IN (SELECT \"Id\" FROM \"WorkTasks\" WHERE \"StoreId\" = @storeId)");

            // Asset child tables
            await ExecuteRawSafe(
                "DELETE FROM \"AssetImages\" WHERE \"AssetId\" IN (SELECT \"Id\" FROM \"Assets\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"AssetTransfers\" WHERE \"AssetId\" IN (SELECT \"Id\" FROM \"Assets\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"AssetInventoryItems\" WHERE \"InventoryId\" IN (SELECT \"Id\" FROM \"AssetInventories\" WHERE \"StoreId\" = @storeId)");

            // Communication child tables
            await ExecuteRawSafe(
                "DELETE FROM \"CommunicationComments\" WHERE \"CommunicationId\" IN (SELECT \"Id\" FROM \"InternalCommunications\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"CommunicationReactions\" WHERE \"CommunicationId\" IN (SELECT \"Id\" FROM \"InternalCommunications\" WHERE \"StoreId\" = @storeId)");

            // Employee child tables
            await ExecuteRawSafe(
                "DELETE FROM \"EmployeeBenefits\" WHERE \"EmployeeId\" IN (SELECT \"Id\" FROM \"Employees\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"EmployeeWorkingInfos\" WHERE \"EmployeeId\" IN (SELECT \"Id\" FROM \"Employees\" WHERE \"StoreId\" = @storeId)");

            // Approval child tables
            await ExecuteRawSafe(
                "DELETE FROM \"ApprovalSteps\" WHERE \"ApprovalFlowId\" IN (SELECT \"Id\" FROM \"ApprovalFlows\" WHERE \"StoreId\" = @storeId)");

            // 2. Delete all tables with direct StoreId reference
            await DeleteFrom("Devices");
            await DeleteFrom("Employees");
            await DeleteFrom("WorkTasks");
            await DeleteFrom("Assets");
            await DeleteFrom("AssetCategories");
            await DeleteFrom("AssetInventories");
            await DeleteFrom("InternalCommunications");
            await DeleteFrom("ContentCategories");
            await DeleteFrom("ScheduleRegistrations");
            await DeleteFrom("ShiftSwapRequests");
            await DeleteFrom("Geofences");

            // Nullable StoreId tables
            await DeleteFrom("AttendanceCorrectionRequests");
            await DeleteFrom("Leaves");
            await DeleteFrom("Overtimes");
            await DeleteFrom("Payslips");
            await DeleteFrom("AdvanceRequests");
            await DeleteFrom("Allowances");
            await DeleteFrom("Benefits");
            await DeleteFrom("Shifts");
            await DeleteFrom("ShiftTemplates");
            await DeleteFrom("ShiftSalaryLevels");
            await DeleteFrom("WorkSchedules");
            await DeleteFrom("Holidays");
            await DeleteFrom("PenaltySettings");
            await DeleteFrom("PenaltyTickets");
            await DeleteFrom("InsuranceSettings");
            await DeleteFrom("TaxSettings");
            await DeleteFrom("EmployeeTaxDeductions");
            await DeleteFrom("KpiSalaries");
            await DeleteFrom("KpiResults");
            await DeleteFrom("KpiPeriods");
            await DeleteFrom("KpiEmployeeTargets");
            await DeleteFrom("KpiConfigs");
            await DeleteFrom("KpiBonusRules");
            await DeleteFrom("BankAccounts");
            await DeleteFrom("TransactionCategories");
            await DeleteFrom("CashTransactions");
            await DeleteFrom("HrDocuments");
            await DeleteFrom("Notifications");
            await DeleteFrom("NotificationCategories");
            await DeleteFrom("NotificationPreferences");
            await DeleteFrom("RolePermissions");
            await DeleteFrom("DepartmentPermissions");
            await DeleteFrom("ApprovalFlows");
            await DeleteFrom("OrgPositions");
            await DeleteFrom("OrgAssignments");
            await DeleteFrom("Branches");
            await DeleteFrom("Departments");
            await DeleteFrom("SystemConfigurations");
            await DeleteFrom("AppSettings");
            await DeleteFrom("AuditLogs");
            await DeleteFrom("LicenseKeys");

            // 3. Delete users of this store & their refresh tokens
            // First, clear OwnerId on the store to avoid FK violation when deleting users
            await ExecuteRawSafe(
                "UPDATE \"Stores\" SET \"OwnerId\" = NULL WHERE \"Id\" = @storeId");
            await ExecuteRawSafe(
                "DELETE FROM \"UserRefreshTokens\" WHERE \"UserId\" IN (SELECT \"Id\" FROM \"AspNetUsers\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"AspNetUserRoles\" WHERE \"UserId\" IN (SELECT \"Id\" FROM \"AspNetUsers\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"AspNetUserClaims\" WHERE \"UserId\" IN (SELECT \"Id\" FROM \"AspNetUsers\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"AspNetUserLogins\" WHERE \"UserId\" IN (SELECT \"Id\" FROM \"AspNetUsers\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"AspNetUserTokens\" WHERE \"UserId\" IN (SELECT \"Id\" FROM \"AspNetUsers\" WHERE \"StoreId\" = @storeId)");
            await ExecuteRawSafe(
                "DELETE FROM \"AspNetUsers\" WHERE \"StoreId\" = @storeId");

            // 3.5. Dynamic safety net: discover any remaining tables with StoreId column
            // This catches new tables added after the hardcoded list above
            try
            {
                var remainingTables = await _dbContext.Database
                    .SqlQueryRaw<string>(
                        @"SELECT c.table_name FROM information_schema.columns c
                          JOIN information_schema.tables t ON c.table_name = t.table_name AND t.table_schema = 'public' AND t.table_type = 'BASE TABLE'
                          WHERE c.column_name = 'StoreId' AND c.table_schema = 'public'
                          AND c.table_name NOT IN ('Stores')")
                    .ToListAsync();

                foreach (var table in remainingTables)
                {
                    await DeleteFrom(table);
                }
            }
            catch (Exception ex)
            {
                _logger.LogDebug("Dynamic table discovery skipped: {Message}", ex.Message);
            }

            // 4. Delete the store itself
            _dbContext.Stores.Remove(store);
            await _dbContext.SaveChangesAsync();

            await transaction.CommitAsync();

            _logger.LogWarning("SuperAdmin {UserId} PERMANENTLY DELETED Store {StoreId} ({StoreName}) and ALL related data",
                CurrentUserId, id, storeName);

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error permanently deleting store {StoreId}", id);
            return StatusCode(500, AppResponse<bool>.Fail($"Lỗi khi xóa cửa hàng: {ex.Message}"));
        }
    }

    /// <summary>
    /// Cập nhật thông tin đăng nhập user
    /// </summary>
    [HttpPut("users/{id}/credentials")]
    public async Task<ActionResult<AppResponse<SystemUserDto>>> UpdateUserCredentials(Guid id, [FromBody] UpdateUserCredentialsRequest request)
    {
        try
        {
            var user = await _userManager.FindByIdAsync(id.ToString());
            if (user == null)
            {
                return NotFound(AppResponse<SystemUserDto>.Fail("User not found"));
            }

            // Update email if provided
            if (!string.IsNullOrEmpty(request.NewEmail) && request.NewEmail != user.Email)
            {
                var existingUser = await _userManager.FindByEmailAsync(request.NewEmail);
                if (existingUser != null)
                {
                    return BadRequest(AppResponse<SystemUserDto>.Fail("Email đã được sử dụng"));
                }

                user.Email = request.NewEmail;
                user.UserName = request.NewEmail;
                user.NormalizedEmail = request.NewEmail.ToUpper();
                user.NormalizedUserName = request.NewEmail.ToUpper();
            }

            // Update password if provided
            if (!string.IsNullOrEmpty(request.NewPassword))
            {
                var token = await _userManager.GeneratePasswordResetTokenAsync(user);
                var result = await _userManager.ResetPasswordAsync(user, token, request.NewPassword);
                if (!result.Succeeded)
                {
                    return BadRequest(AppResponse<SystemUserDto>.Fail(string.Join(", ", result.Errors.Select(e => e.Description))));
                }
            }

            // Update name if provided
            if (!string.IsNullOrEmpty(request.FullName))
            {
                var names = request.FullName.Split(' ');
                user.FirstName = names.FirstOrDefault() ?? user.FirstName;
                user.LastName = names.Length > 1 ? string.Join(" ", names.Skip(1)) : user.LastName;
            }

            await _userManager.UpdateAsync(user);

            _logger.LogInformation("SuperAdmin {UserId} updated credentials for User {TargetUserId}", 
                CurrentUserId, id);

            var store = user.StoreId.HasValue 
                ? await _dbContext.Stores.FindAsync(user.StoreId.Value) 
                : null;

            return Ok(AppResponse<SystemUserDto>.Success(new SystemUserDto(
                user.Id,
                user.Email ?? "",
                user.FullName,
                user.Role ?? "",
                user.StoreId,
                store?.Name,
                store?.Code,
                user.IsActive,
                user.CreatedAt,
                user.LastLoginAt
            )));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating user credentials {UserId}", id);
            return StatusCode(500, AppResponse<SystemUserDto>.Fail("Error updating user credentials"));
        }
    }

    /// <summary>
    /// Cập nhật vai trò (role) của user
    /// </summary>
    [HttpPut("users/{id:guid}/role")]
    public async Task<ActionResult<AppResponse<SystemUserDto>>> UpdateUserRole(Guid id, [FromBody] UpdateUserRoleRequest request)
    {
        try
        {
            var validRoles = Enum.GetNames(typeof(Roles));
            if (!validRoles.Contains(request.Role))
                return BadRequest(AppResponse<SystemUserDto>.Fail($"Invalid role. Valid roles: {string.Join(", ", validRoles)}"));

            var user = await _userManager.FindByIdAsync(id.ToString());
            if (user == null)
                return NotFound(AppResponse<SystemUserDto>.Fail("User not found"));

            // Remove old roles
            var currentRoles = await _userManager.GetRolesAsync(user);
            if (currentRoles.Any())
                await _userManager.RemoveFromRolesAsync(user, currentRoles);

            // Set new role
            user.Role = request.Role;
            await _userManager.UpdateAsync(user);
            await _userManager.AddToRoleAsync(user, request.Role);

            _logger.LogInformation("SuperAdmin {UserId} changed role of User {TargetUserId} to {Role}",
                CurrentUserId, id, request.Role);

            var store = user.StoreId.HasValue
                ? await _dbContext.Stores.FindAsync(user.StoreId.Value)
                : null;

            return Ok(AppResponse<SystemUserDto>.Success(new SystemUserDto(
                user.Id,
                user.Email ?? "",
                user.FullName,
                user.Role ?? "",
                user.StoreId,
                store?.Name,
                store?.Code,
                user.IsActive,
                user.CreatedAt,
                user.LastLoginAt
            )));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating user role {UserId}", id);
            return StatusCode(500, AppResponse<SystemUserDto>.Fail("Error updating user role"));
        }
    }

    /// <summary>
    /// Xóa user khỏi hệ thống (SuperAdmin only)
    /// </summary>
    [HttpDelete("users/{id:guid}")]
    public async Task<ActionResult<AppResponse<bool>>> DeleteUser(Guid id)
    {
        try
        {
            if (id == CurrentUserId)
            {
                return BadRequest(AppResponse<bool>.Fail("Không thể xóa tài khoản của chính mình"));
            }

            var user = await _userManager.FindByIdAsync(id.ToString());
            if (user == null)
            {
                return NotFound(AppResponse<bool>.Fail("User not found"));
            }

            var isOwner = await _dbContext.Stores.AnyAsync(s => s.OwnerId == id);
            if (isOwner)
            {
                return BadRequest(AppResponse<bool>.Fail("Không thể xóa tài khoản owner của cửa hàng"));
            }

            var result = await _userManager.DeleteAsync(user);
            if (!result.Succeeded)
            {
                return BadRequest(AppResponse<bool>.Fail(string.Join(", ", result.Errors.Select(e => e.Description))));
            }

            _logger.LogWarning("SuperAdmin {CurrentUserId} deleted user {UserId} ({Email})", 
                CurrentUserId, id, user.Email);

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting user {UserId}", id);
            return StatusCode(500, AppResponse<bool>.Fail("Error deleting user"));
        }
    }

    /// <summary>
    /// Lấy thông tin chi tiết Store bao gồm license info
    /// </summary>
    [HttpGet("stores/{id}/full")]
    public async Task<ActionResult<AppResponse<StoreFullDetailDto>>> GetStoreFullDetail(Guid id)
    {
        try
        {
            var store = await _dbContext.Stores
                .Include(s => s.Owner)
                .Include(s => s.Users)
                .Include(s => s.Devices)
                .Include(s => s.LicenseKeys)
                .FirstOrDefaultAsync(s => s.Id == id);

            if (store == null)
            {
                return NotFound(AppResponse<StoreFullDetailDto>.Fail("Store not found"));
            }

            var dto = new StoreFullDetailDto(
                store.Id,
                store.Name,
                store.Code,
                store.Description,
                store.Address,
                store.Phone,
                store.IsActive,
                store.IsLocked,
                store.LockReason,
                store.LockedAt,
                store.LicenseType.ToString(),
                store.LicenseKey,
                store.ExpiryDate,
                store.MaxUsers,
                store.MaxDevices,
                store.Users.Count,
                store.Devices.Count,
                store.OwnerId,
                store.Owner?.FullName,
                store.Owner?.Email,
                store.CreatedAt,
                store.UpdatedAt
            );

            return Ok(AppResponse<StoreFullDetailDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting store full detail {StoreId}", id);
            return StatusCode(500, AppResponse<StoreFullDetailDto>.Fail("Error getting store detail"));
        }
    }

    #endregion

    #region Helper Methods

    private static string GenerateLicenseKey(LicenseType type)
    {
        var prefix = type switch
        {
            LicenseType.Basic => "BAS",
            LicenseType.Advanced => "ADV",
            LicenseType.Professional => "PRO",
            _ => "KEY"
        };

        var guid = Guid.NewGuid().ToString("N").ToUpper()[..12];
        return $"{prefix}-{guid[..4]}-{guid[4..8]}-{guid[8..12]}";
    }

    private static LicenseKeyDto MapToLicenseKeyDto(LicenseKey license)
    {
        return new LicenseKeyDto(
            license.Id,
            license.Key,
            license.LicenseType.ToString(),
            license.DurationDays,
            license.MaxUsers,
            license.MaxDevices,
            license.IsUsed,
            license.ActivatedAt,
            license.StoreId,
            license.Store?.Name,
            license.AgentId,
            license.Agent?.Name,
            license.ServicePackageId,
            license.ServicePackage?.Name,
            license.Notes,
            license.IsActive,
            license.CreatedAt
        );
    }

    private static StoreDetailDto MapToStoreDetailDto(Store store)
    {
        return new StoreDetailDto(
            store.Id,
            store.Name,
            store.Code,
            store.Description,
            store.Address,
            store.Phone,
            store.IsActive,
            store.IsLocked,
            store.LockReason,
            store.LicenseType.ToString(),
            store.LicenseKey,
            store.ExpiryDate,
            store.MaxUsers,
            store.MaxDevices,
            store.RenewalCount,
            store.ServicePackageId,
            store.ServicePackage?.Name,
            store.TrialStartDate,
            store.TrialDays,
            store.OwnerId,
            store.Owner?.FullName,
            store.Owner?.Email,
            store.AgentId,
            store.Agent?.Name,
            store.Agent?.Email,
            store.Users.Count,
            store.Devices.Count,
            store.Users.Count(u => u.Role == nameof(Roles.Employee)),
            store.CreatedAt,
            store.UpdatedAt
        );
    }

    #endregion
    
    #region App Settings (Thiết lập thông tin phần mềm)
    
    /// <summary>
    /// Lấy tất cả App Settings
    /// </summary>
    [HttpGet("settings")]
    public async Task<ActionResult<AppResponse<List<AppSettingsDto>>>> GetAllSettings()
    {
        try
        {
            var settings = await _dbContext.AppSettings
                .OrderBy(s => s.Group)
                .ThenBy(s => s.DisplayOrder)
                .Select(s => new AppSettingsDto(
                    s.Id,
                    s.Key,
                    s.Value,
                    s.Description,
                    s.Group,
                    s.DataType,
                    s.DisplayOrder,
                    s.IsPublic,
                    s.LastModified
                ))
                .ToListAsync();

            return Ok(AppResponse<List<AppSettingsDto>>.Success(settings));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting app settings");
            return StatusCode(500, AppResponse<List<AppSettingsDto>>.Fail("Error getting app settings"));
        }
    }
    
    /// <summary>
    /// Lấy setting theo key
    /// </summary>
    [HttpGet("settings/{key}")]
    public async Task<ActionResult<AppResponse<AppSettingsDto>>> GetSetting(string key)
    {
        try
        {
            var setting = await _dbContext.AppSettings
                .FirstOrDefaultAsync(s => s.Key == key);

            if (setting == null)
            {
                return NotFound(AppResponse<AppSettingsDto>.Fail("Setting không tồn tại"));
            }

            var dto = new AppSettingsDto(
                setting.Id,
                setting.Key,
                setting.Value,
                setting.Description,
                setting.Group,
                setting.DataType,
                setting.DisplayOrder,
                setting.IsPublic,
                setting.LastModified
            );

            return Ok(AppResponse<AppSettingsDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting app setting {Key}", key);
            return StatusCode(500, AppResponse<AppSettingsDto>.Fail("Error getting app setting"));
        }
    }
    
    /// <summary>
    /// Tạo hoặc cập nhật setting
    /// </summary>
    [HttpPost("settings")]
    public async Task<ActionResult<AppResponse<AppSettingsDto>>> UpsertSetting([FromBody] UpsertAppSettingRequest request)
    {
        try
        {
            var setting = await _dbContext.AppSettings
                .AsTracking()
                .FirstOrDefaultAsync(s => s.Key == request.Key);

            if (setting == null)
            {
                // Create new
                setting = new AppSettings
                {
                    Id = Guid.NewGuid(),
                    Key = request.Key,
                    Value = request.Value,
                    Description = request.Description,
                    Group = request.Group,
                    DataType = request.DataType,
                    DisplayOrder = request.DisplayOrder,
                    IsPublic = request.IsPublic,
                    CreatedAt = DateTime.UtcNow,
                    CreatedBy = CurrentUserId.ToString()
                };
                _dbContext.AppSettings.Add(setting);
            }
            else
            {
                // Update existing
                setting.Value = request.Value;
                setting.Description = request.Description;
                setting.Group = request.Group;
                setting.DataType = request.DataType;
                setting.DisplayOrder = request.DisplayOrder;
                setting.IsPublic = request.IsPublic;
                setting.LastModified = DateTime.UtcNow;
                setting.LastModifiedBy = CurrentUserId.ToString();
            }

            await _dbContext.SaveChangesAsync();
            _cache.RemoveByPrefix("public_setting");

            _logger.LogInformation("SuperAdmin {UserId} upserted setting {Key}", CurrentUserId, request.Key);

            var dto = new AppSettingsDto(
                setting.Id,
                setting.Key,
                setting.Value,
                setting.Description,
                setting.Group,
                setting.DataType,
                setting.DisplayOrder,
                setting.IsPublic,
                setting.LastModified
            );

            return Ok(AppResponse<AppSettingsDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error upserting app setting {Key}", request.Key);
            return StatusCode(500, AppResponse<AppSettingsDto>.Fail("Error upserting app setting"));
        }
    }
    
    /// <summary>
    /// Cập nhật nhiều settings cùng lúc
    /// </summary>
    [HttpPut("settings/batch")]
    public async Task<ActionResult<AppResponse<bool>>> UpdateSettingsBatch([FromBody] UpdateAppSettingsRequest request)
    {
        try
        {
            // Pre-load all settings by keys to avoid N+1
            var keys = request.Settings.Select(s => s.Key).ToList();
            var existingSettings = await _dbContext.AppSettings
                .AsTracking()
                .Where(s => keys.Contains(s.Key))
                .ToDictionaryAsync(s => s.Key);

            foreach (var item in request.Settings)
            {
                if (existingSettings.TryGetValue(item.Key, out var setting))
                {
                    setting.Value = item.Value;
                    setting.LastModified = DateTime.UtcNow;
                    setting.LastModifiedBy = CurrentUserId.ToString();
                }
                else
                {
                    // Create new with default values
                    var newSetting = new AppSettings
                    {
                        Id = Guid.NewGuid(),
                        Key = item.Key,
                        Value = item.Value,
                        Group = GetGroupFromKey(item.Key),
                        DataType = GetDataTypeFromKey(item.Key),
                        DisplayOrder = 0,
                        IsPublic = true,
                        CreatedAt = DateTime.UtcNow,
                        CreatedBy = CurrentUserId.ToString()
                    };
                    _dbContext.AppSettings.Add(newSetting);
                }
            }

            await _dbContext.SaveChangesAsync();
            _cache.RemoveByPrefix("public_setting");

            _logger.LogInformation("SuperAdmin {UserId} batch updated {Count} settings", CurrentUserId, request.Settings.Count);

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error batch updating app settings");
            return StatusCode(500, AppResponse<bool>.Fail("Error batch updating app settings"));
        }
    }
    
    /// <summary>
    /// Khởi tạo settings mặc định
    /// </summary>
    [HttpPost("settings/initialize")]
    public async Task<ActionResult<AppResponse<bool>>> InitializeDefaultSettings()
    {
        try
        {
            var defaultSettings = new List<(string Key, string Description, string Group, string DataType, int Order)>
            {
                // General
                (AppSettingKeys.CompanyLogo, "Logo công ty", "General", "image", 1),
                (AppSettingKeys.CompanyName, "Tên công ty", "General", "text", 2),
                (AppSettingKeys.CompanyAddress, "Địa chỉ công ty", "General", "text", 3),
                (AppSettingKeys.CompanyDescription, "Mô tả công ty", "General", "textarea", 4),
                
                // Contact
                (AppSettingKeys.FeedbackEmail, "Email góp ý", "Contact", "email", 1),
                (AppSettingKeys.TechnicalSupportPhone, "SĐT Hỗ trợ kỹ thuật", "Contact", "phone", 2),
                (AppSettingKeys.TechnicalSupportEmail, "Email Hỗ trợ kỹ thuật", "Contact", "email", 3),
                (AppSettingKeys.SalesPhone, "SĐT Bộ phận bán hàng", "Contact", "phone", 4),
                (AppSettingKeys.SalesEmail, "Email Bộ phận bán hàng", "Contact", "email", 5),
                
                // Social
                (AppSettingKeys.FacebookUrl, "Link Facebook/Fanpage", "Social", "url", 1),
                (AppSettingKeys.YoutubeUrl, "Link YouTube", "Social", "url", 2),
                (AppSettingKeys.ZaloUrl, "Link Zalo", "Social", "url", 3),
                (AppSettingKeys.WebsiteUrl, "Website", "Social", "url", 4),
                
                // Legal
                (AppSettingKeys.TermsOfService, "Điều khoản sử dụng", "Legal", "textarea", 1),
                (AppSettingKeys.PrivacyPolicy, "Chính sách bảo mật", "Legal", "textarea", 2),
            };

            // Pre-load all existing setting keys to avoid N+1
            var allKeys = defaultSettings.Select(d => d.Key).ToList();
            var existingKeys = (await _dbContext.AppSettings
                .Where(s => allKeys.Contains(s.Key))
                .Select(s => s.Key)
                .ToListAsync()).ToHashSet();

            foreach (var (key, desc, group, dataType, order) in defaultSettings)
            {
                if (!existingKeys.Contains(key))
                {
                    var setting = new AppSettings
                    {
                        Id = Guid.NewGuid(),
                        Key = key,
                        Description = desc,
                        Group = group,
                        DataType = dataType,
                        DisplayOrder = order,
                        IsPublic = true,
                        CreatedAt = DateTime.UtcNow,
                        CreatedBy = CurrentUserId.ToString()
                    };
                    _dbContext.AppSettings.Add(setting);
                }
            }

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} initialized default app settings", CurrentUserId);

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error initializing default app settings");
            return StatusCode(500, AppResponse<bool>.Fail("Error initializing default app settings"));
        }
    }
    
    private static string GetGroupFromKey(string key)
    {
        if (key.Contains("company") || key.Contains("logo")) return "General";
        if (key.Contains("email") || key.Contains("phone") || key.Contains("support") || key.Contains("sales")) return "Contact";
        if (key.Contains("url") || key.Contains("facebook") || key.Contains("youtube") || key.Contains("zalo")) return "Social";
        if (key.Contains("terms") || key.Contains("policy") || key.Contains("privacy")) return "Legal";
        return "General";
    }
    
    private static string GetDataTypeFromKey(string key)
    {
        if (key.Contains("logo")) return "image";
        if (key.Contains("email")) return "email";
        if (key.Contains("phone")) return "phone";
        if (key.Contains("url")) return "url";
        if (key.Contains("terms") || key.Contains("policy") || key.Contains("description")) return "textarea";
        return "text";
    }
    
    #endregion
    
    #region Audit Logs
    
    /// <summary>
    /// Lấy danh sách audit logs với phân trang và filter
    /// </summary>
    [HttpGet("audit-logs")]
    public async Task<ActionResult<AppResponse<object>>> GetAuditLogs(
        [FromQuery] string? action = null,
        [FromQuery] string? entityType = null,
        [FromQuery] Guid? userId = null,
        [FromQuery] Guid? storeId = null,
        [FromQuery] string? status = null,
        [FromQuery] DateTime? fromDate = null,
        [FromQuery] DateTime? toDate = null,
        [FromQuery] string? search = null,
        [FromQuery] int pageNumber = 1,
        [FromQuery] int pageSize = 50)
    {
        try
        {
            var query = _dbContext.AuditLogs.AsQueryable();
            
            // Filters
            if (!string.IsNullOrEmpty(action))
                query = query.Where(a => a.Action == action);
                
            if (!string.IsNullOrEmpty(entityType))
                query = query.Where(a => a.EntityType == entityType);
                
            if (userId.HasValue)
                query = query.Where(a => a.UserId == userId);
                
            if (storeId.HasValue)
                query = query.Where(a => a.StoreId == storeId);
                
            if (!string.IsNullOrEmpty(status))
                query = query.Where(a => a.Status == status);
                
            if (fromDate.HasValue)
                query = query.Where(a => a.Timestamp >= fromDate.Value);
                
            if (toDate.HasValue)
                query = query.Where(a => a.Timestamp <= toDate.Value.AddDays(1));
                
            if (!string.IsNullOrEmpty(search))
                query = query.Where(a => 
                    (a.UserEmail != null && a.UserEmail.Contains(search)) ||
                    (a.UserName != null && a.UserName.Contains(search)) ||
                    (a.EntityName != null && a.EntityName.Contains(search)) ||
                    (a.Details != null && a.Details.Contains(search)));
            
            var total = await query.CountAsync();
            
            var items = await query
                .OrderByDescending(a => a.Timestamp)
                .Skip((pageNumber - 1) * pageSize)
                .Take(pageSize)
                .Select(a => new
                {
                    a.Id,
                    a.Action,
                    a.EntityType,
                    a.EntityId,
                    a.EntityName,
                    a.Details,
                    a.UserId,
                    a.UserEmail,
                    a.UserName,
                    a.UserRole,
                    a.StoreId,
                    a.StoreName,
                    a.IpAddress,
                    a.Timestamp,
                    a.Status,
                    a.ErrorMessage
                })
                .ToListAsync();
            
            return Ok(AppResponse<object>.Success(new
            {
                items,
                total,
                pageNumber,
                pageSize,
                totalPages = (int)Math.Ceiling(total / (double)pageSize)
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting audit logs");
            return StatusCode(500, AppResponse<object>.Fail("Error getting audit logs"));
        }
    }
    
    /// <summary>
    /// Ghi một audit log
    /// </summary>
    private async Task LogAuditAsync(
        string action,
        string entityType,
        string? entityId = null,
        string? entityName = null,
        string? details = null,
        Guid? storeId = null,
        string? storeName = null,
        string status = "Success",
        string? errorMessage = null)
    {
        try
        {
            var ipAddress = HttpContext?.Connection?.RemoteIpAddress?.ToString();
            var userAgent = HttpContext?.Request?.Headers["User-Agent"].ToString();
            
            var auditLog = new AuditLog
            {
                Id = Guid.NewGuid(),
                Action = action,
                EntityType = entityType,
                EntityId = entityId,
                EntityName = entityName,
                Details = details,
                UserId = CurrentUserId,
                UserEmail = User.FindFirst(System.Security.Claims.ClaimTypes.Email)?.Value,
                UserName = User.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value,
                UserRole = User.FindFirst(System.Security.Claims.ClaimTypes.Role)?.Value,
                StoreId = storeId,
                StoreName = storeName,
                IpAddress = ipAddress,
                UserAgent = userAgent,
                Timestamp = DateTime.UtcNow,
                Status = status,
                ErrorMessage = errorMessage
            };
            
            _dbContext.AuditLogs.Add(auditLog);
            await _dbContext.SaveChangesAsync();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error logging audit");
        }
    }
    
    /// <summary>
    /// Lấy thống kê audit logs
    /// </summary>
    [HttpGet("audit-logs/stats")]
    public async Task<ActionResult<AppResponse<object>>> GetAuditStats()
    {
        try
        {
            var today = DateTime.UtcNow.Date;
            var last7Days = today.AddDays(-7);
            var last30Days = today.AddDays(-30);
            
            var totalLogs = await _dbContext.AuditLogs.CountAsync();
            var todayLogs = await _dbContext.AuditLogs.CountAsync(a => a.Timestamp >= today);
            var last7DaysLogs = await _dbContext.AuditLogs.CountAsync(a => a.Timestamp >= last7Days);
            var last30DaysLogs = await _dbContext.AuditLogs.CountAsync(a => a.Timestamp >= last30Days);
            
            var failedLogs = await _dbContext.AuditLogs.CountAsync(a => a.Status == "Failed");
            var loginLogs = await _dbContext.AuditLogs.CountAsync(a => a.Action == AuditActions.Login);
            
            // Action breakdown (top 10)
            var actionBreakdown = await _dbContext.AuditLogs
                .GroupBy(a => a.Action)
                .Select(g => new { Action = g.Key, Count = g.Count() })
                .OrderByDescending(x => x.Count)
                .Take(10)
                .ToListAsync();
                
            // Entity type breakdown
            var entityBreakdown = await _dbContext.AuditLogs
                .GroupBy(a => a.EntityType)
                .Select(g => new { EntityType = g.Key, Count = g.Count() })
                .OrderByDescending(x => x.Count)
                .Take(10)
                .ToListAsync();
            
            return Ok(AppResponse<object>.Success(new
            {
                totalLogs,
                todayLogs,
                last7DaysLogs,
                last30DaysLogs,
                failedLogs,
                loginLogs,
                actionBreakdown,
                entityBreakdown
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting audit stats");
            return StatusCode(500, AppResponse<object>.Fail("Error getting audit stats"));
        }
    }
    
    #endregion
    
    #region Database Management
    
    /// <summary>
    /// Lấy thông tin database (size, bảng, record counts)
    /// </summary>
    [HttpGet("database/info")]
    public async Task<ActionResult<AppResponse<object>>> GetDatabaseInfo()
    {
        try
        {
            var connString = _configuration.GetConnectionString("DefaultConnection");
            var builder = new Npgsql.NpgsqlConnectionStringBuilder(connString);
            
            // Get database size
            var dbSize = await _dbContext.Database.SqlQueryRaw<string>(
                "SELECT pg_size_pretty(pg_database_size(current_database())) AS \"Value\""
            ).FirstOrDefaultAsync() ?? "N/A";
            
            // Get table counts
            var attendanceCount = await _dbContext.AttendanceLogs.CountAsync();
            var employeeCount = await _dbContext.Employees.CountAsync();
            var deviceCount = await _dbContext.Devices.CountAsync();
            var deviceCommandCount = await _dbContext.DeviceCommands.CountAsync();
            var deviceUserCount = await _dbContext.DeviceUsers.CountAsync();
            var storeCount = await _dbContext.Stores.CountAsync();
            var userCount = await _userManager.Users.CountAsync();
            var auditLogCount = await _dbContext.AuditLogs.CountAsync();
            
            // Get backup directory info
            var backupDir = Path.Combine(Directory.GetCurrentDirectory(), "backups");
            var backupCount = 0;
            long backupTotalSizeBytes = 0;
            if (Directory.Exists(backupDir))
            {
                var files = Directory.GetFiles(backupDir);
                backupCount = files.Length;
                backupTotalSizeBytes = files.Sum(f => new FileInfo(f).Length);
            }
            
            return Ok(AppResponse<object>.Success(new
            {
                databaseName = builder.Database,
                host = builder.Host,
                size = dbSize,
                tables = new
                {
                    stores = storeCount,
                    users = userCount,
                    employees = employeeCount,
                    devices = deviceCount,
                    deviceUsers = deviceUserCount,
                    deviceCommands = deviceCommandCount,
                    attendanceLogs = attendanceCount,
                    auditLogs = auditLogCount
                },
                backups = new
                {
                    count = backupCount,
                    totalSizeMB = Math.Round(backupTotalSizeBytes / 1024.0 / 1024.0, 2)
                }
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting database info");
            return StatusCode(500, AppResponse<object>.Fail("Error getting database info"));
        }
    }
    
    /// <summary>
    /// Backup toàn bộ database
    /// </summary>
    [HttpPost("database/backup")]
    public async Task<ActionResult<AppResponse<object>>> BackupDatabase()
    {
        try
        {
            var connString = _configuration.GetConnectionString("DefaultConnection");
            var builder = new Npgsql.NpgsqlConnectionStringBuilder(connString);
            
            var backupDir = Path.Combine(Directory.GetCurrentDirectory(), "backups");
            Directory.CreateDirectory(backupDir);
            
            var fileName = $"backup_{builder.Database}_{DateTime.UtcNow:yyyyMMdd_HHmmss}.backup";
            var filePath = Path.Combine(backupDir, fileName);
            
            var pgDumpPath = _configuration["DatabaseTools:PgDumpPath"] ?? "pg_dump";
            
            var startInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = pgDumpPath,
                Arguments = $"-h {builder.Host} -p {builder.Port} -U {builder.Username} -d {builder.Database} -F c -f \"{filePath}\"",
                RedirectStandardError = true,
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            startInfo.Environment["PGPASSWORD"] = builder.Password;
            
            using var process = System.Diagnostics.Process.Start(startInfo);
            if (process == null)
                return StatusCode(500, AppResponse<object>.Fail("Không thể khởi động pg_dump"));
            
            await process.WaitForExitAsync();
            
            if (process.ExitCode != 0)
            {
                var error = await process.StandardError.ReadToEndAsync();
                _logger.LogError("pg_dump failed: {Error}", error);
                return StatusCode(500, AppResponse<object>.Fail($"Backup thất bại: {error}"));
            }
            
            var fileInfo = new FileInfo(filePath);
            _logger.LogInformation("SuperAdmin {UserId} created backup: {FileName} ({Size}MB)",
                CurrentUserId, fileName, fileInfo.Length / 1024 / 1024);
            
            return Ok(AppResponse<object>.Success(new
            {
                fileName,
                sizeMB = Math.Round(fileInfo.Length / 1024.0 / 1024.0, 2),
                createdAt = DateTime.UtcNow
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating database backup");
            return StatusCode(500, AppResponse<object>.Fail("Backup thất bại: " + ex.Message));
        }
    }
    
    /// <summary>
    /// Backup dữ liệu theo store (export JSON)
    /// </summary>
    [HttpPost("database/backup/store/{storeId:guid}")]
    public async Task<ActionResult<AppResponse<object>>> BackupStoreData(Guid storeId)
    {
        try
        {
            var store = await _dbContext.Stores
                .Include(s => s.Devices)
                .FirstOrDefaultAsync(s => s.Id == storeId);
            
            if (store == null)
                return NotFound(AppResponse<object>.Fail("Không tìm thấy cửa hàng"));
            
            var deviceIds = store.Devices.Select(d => d.Id).ToList();
            
            // Collect store data
            var employees = await _dbContext.Employees
                .Where(e => e.StoreId == storeId)
                .ToListAsync();
            
            var attendanceLogs = await _dbContext.AttendanceLogs
                .Where(a => a.Device != null && a.Device.StoreId == storeId)
                .ToListAsync();
            
            var deviceUsers = await _dbContext.DeviceUsers
                .Where(du => deviceIds.Contains(du.DeviceId))
                .ToListAsync();
            
            var backupDir = Path.Combine(Directory.GetCurrentDirectory(), "backups");
            Directory.CreateDirectory(backupDir);
            
            var fileName = $"store_{store.Code}_{DateTime.UtcNow:yyyyMMdd_HHmmss}.json";
            var filePath = Path.Combine(backupDir, fileName);
            
            var backupData = new
            {
                storeId = store.Id,
                storeName = store.Name,
                storeCode = store.Code,
                exportedAt = DateTime.UtcNow,
                data = new
                {
                    employeeCount = employees.Count,
                    attendanceCount = attendanceLogs.Count,
                    deviceUserCount = deviceUsers.Count,
                    deviceCount = store.Devices.Count
                }
            };
            
            var json = System.Text.Json.JsonSerializer.Serialize(backupData, new System.Text.Json.JsonSerializerOptions { WriteIndented = true });
            await System.IO.File.WriteAllTextAsync(filePath, json);
            
            var fileInfo = new FileInfo(filePath);
            _logger.LogInformation("SuperAdmin {UserId} created store backup: {FileName}", CurrentUserId, fileName);
            
            return Ok(AppResponse<object>.Success(new
            {
                fileName,
                sizeMB = Math.Round(fileInfo.Length / 1024.0 / 1024.0, 2),
                createdAt = DateTime.UtcNow,
                storeName = store.Name
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating store backup");
            return StatusCode(500, AppResponse<object>.Fail("Backup cửa hàng thất bại"));
        }
    }
    
    /// <summary>
    /// Lấy danh sách file backup
    /// </summary>
    [HttpGet("database/backups")]
    public ActionResult<AppResponse<List<object>>> GetBackupFiles()
    {
        try
        {
            var backupDir = Path.Combine(Directory.GetCurrentDirectory(), "backups");
            if (!Directory.Exists(backupDir))
                return Ok(AppResponse<List<object>>.Success(new List<object>()));
            
            var files = Directory.GetFiles(backupDir)
                .Select(f => new FileInfo(f))
                .OrderByDescending(f => f.CreationTimeUtc)
                .Select(f => (object)new
                {
                    fileName = f.Name,
                    sizeMB = Math.Round(f.Length / 1024.0 / 1024.0, 2),
                    createdAt = f.CreationTimeUtc,
                    type = f.Extension == ".backup" ? "full" : "store"
                })
                .ToList();
            
            return Ok(AppResponse<List<object>>.Success(files));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error listing backup files");
            return StatusCode(500, AppResponse<List<object>>.Fail("Error listing backups"));
        }
    }
    
    /// <summary>
    /// Download file backup
    /// </summary>
    [HttpGet("database/backups/{fileName}/download")]
    public IActionResult DownloadBackup(string fileName)
    {
        // Sanitize to prevent path traversal
        fileName = Path.GetFileName(fileName);
        if (string.IsNullOrEmpty(fileName))
            return BadRequest("Invalid file name");
        
        var filePath = Path.Combine(Directory.GetCurrentDirectory(), "backups", fileName);
        if (!System.IO.File.Exists(filePath))
            return NotFound("File not found");
        
        _logger.LogInformation("SuperAdmin {UserId} downloaded backup: {FileName}", CurrentUserId, fileName);
        return PhysicalFile(filePath, "application/octet-stream", fileName);
    }
    
    /// <summary>
    /// Xóa file backup
    /// </summary>
    [HttpDelete("database/backups/{fileName}")]
    public ActionResult<AppResponse<bool>> DeleteBackupFile(string fileName)
    {
        try
        {
            fileName = Path.GetFileName(fileName);
            if (string.IsNullOrEmpty(fileName))
                return BadRequest(AppResponse<bool>.Fail("Invalid file name"));
            
            var filePath = Path.Combine(Directory.GetCurrentDirectory(), "backups", fileName);
            if (!System.IO.File.Exists(filePath))
                return NotFound(AppResponse<bool>.Fail("File not found"));
            
            System.IO.File.Delete(filePath);
            _logger.LogWarning("SuperAdmin {UserId} deleted backup: {FileName}", CurrentUserId, fileName);
            
            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting backup file");
            return StatusCode(500, AppResponse<bool>.Fail("Error deleting backup"));
        }
    }
    
    /// <summary>
    /// Restore database từ file backup
    /// </summary>
    [HttpPost("database/restore")]
    public async Task<ActionResult<AppResponse<object>>> RestoreDatabase([FromBody] RestoreDatabaseRequest request)
    {
        try
        {
            if (string.IsNullOrEmpty(request.FileName))
                return BadRequest(AppResponse<object>.Fail("Vui lòng chọn file backup"));
            
            if (!request.ConfirmRestore)
                return BadRequest(AppResponse<object>.Fail("Vui lòng xác nhận restore (confirmRestore=true)"));
            
            var sanitizedName = Path.GetFileName(request.FileName);
            var filePath = Path.Combine(Directory.GetCurrentDirectory(), "backups", sanitizedName);
            if (!System.IO.File.Exists(filePath))
                return NotFound(AppResponse<object>.Fail("File backup không tồn tại"));
            
            var connString = _configuration.GetConnectionString("DefaultConnection");
            var builder = new Npgsql.NpgsqlConnectionStringBuilder(connString);
            
            var pgRestorePath = _configuration["DatabaseTools:PgRestorePath"] ?? "pg_restore";
            
            var startInfo = new System.Diagnostics.ProcessStartInfo
            {
                FileName = pgRestorePath,
                Arguments = $"-h {builder.Host} -p {builder.Port} -U {builder.Username} -d {builder.Database} --clean --if-exists \"{filePath}\"",
                RedirectStandardError = true,
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            startInfo.Environment["PGPASSWORD"] = builder.Password;
            
            using var process = System.Diagnostics.Process.Start(startInfo);
            if (process == null)
                return StatusCode(500, AppResponse<object>.Fail("Không thể khởi động pg_restore"));
            
            await process.WaitForExitAsync();
            
            var stderr = await process.StandardError.ReadToEndAsync();
            
            _logger.LogWarning("SuperAdmin {UserId} restored database from: {FileName}, ExitCode: {ExitCode}",
                CurrentUserId, sanitizedName, process.ExitCode);
            
            return Ok(AppResponse<object>.Success(new
            {
                fileName = sanitizedName,
                exitCode = process.ExitCode,
                warnings = stderr,
                restoredAt = DateTime.UtcNow
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error restoring database");
            return StatusCode(500, AppResponse<object>.Fail("Restore thất bại: " + ex.Message));
        }
    }
    
    /// <summary>
    /// Xóa dữ liệu vận hành (chấm công, thiết bị, nhân viên) — KHÔNG xóa stores, users, licenses
    /// </summary>
    [HttpDelete("database/purge-all")]
    public async Task<ActionResult<AppResponse<object>>> PurgeAllData([FromQuery] string confirmCode)
    {
        try
        {
            if (confirmCode != "CONFIRM_DELETE_ALL")
                return BadRequest(AppResponse<object>.Fail("Mã xác nhận không đúng. Nhập 'CONFIRM_DELETE_ALL' để xác nhận."));
            
            // Delete in order (respect FK constraints)
            // Chỉ xóa dữ liệu vận hành, giữ nguyên stores/users/licenses/settings
            var deletedAttendance = await _dbContext.AttendanceLogs.ExecuteDeleteAsync();
            var deletedCommands = await _dbContext.DeviceCommands.ExecuteDeleteAsync();
            var deletedDeviceUsers = await _dbContext.DeviceUsers.ExecuteDeleteAsync();
            var deletedDeviceSettings = await _dbContext.DeviceSettings.ExecuteDeleteAsync();
            var deletedFingerprintTemplates = await _dbContext.FingerprintTemplates.ExecuteDeleteAsync();
            var deletedFaceTemplates = await _dbContext.FaceTemplates.ExecuteDeleteAsync();
            var deletedDevices = await _dbContext.Devices.ExecuteDeleteAsync();
            var deletedEmployees = await _dbContext.Employees.ExecuteDeleteAsync();
            
            _logger.LogWarning("SuperAdmin {UserId} PURGED OPERATIONAL DATA: Attendance={A}, Commands={C}, DeviceUsers={DU}, Devices={D}, Employees={E}",
                CurrentUserId, deletedAttendance, deletedCommands, deletedDeviceUsers, deletedDevices, deletedEmployees);
            
            return Ok(AppResponse<object>.Success(new
            {
                deletedAttendance,
                deletedCommands,
                deletedDeviceUsers,
                deletedDeviceSettings,
                deletedFingerprintTemplates,
                deletedFaceTemplates,
                deletedDevices,
                deletedEmployees,
                purgedAt = DateTime.UtcNow
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error purging all data");
            return StatusCode(500, AppResponse<object>.Fail("Xóa dữ liệu thất bại: " + ex.Message));
        }
    }
    
    #endregion
    
    #region System Health
    
    /// <summary>
    /// Lấy thông tin sức khỏe hệ thống
    /// </summary>
    [HttpGet("system-health")]
    public async Task<ActionResult<AppResponse<object>>> GetSystemHealth()
    {
        try
        {
            var startTime = DateTime.UtcNow;
            
            // Database check
            bool databaseHealthy = false;
            string? databaseError = null;
            try
            {
                await _dbContext.Database.CanConnectAsync();
                databaseHealthy = true;
            }
            catch (Exception ex)
            {
                databaseError = ex.Message;
            }
            
            // Get counts
            var totalStores = await _dbContext.Stores.CountAsync();
            var activeStores = await _dbContext.Stores.CountAsync(s => s.IsActive);
            var lockedStores = await _dbContext.Stores.CountAsync(s => s.IsLocked);
            
            var totalUsers = await _userManager.Users.CountAsync();
            var superAdminCount = (await _userManager.GetUsersInRoleAsync(nameof(Roles.SuperAdmin))).Count;
            
            var totalDevices = await _dbContext.Devices.CountAsync();
            var onlineDevices = await _dbContext.Devices.CountAsync(d => d.DeviceStatus == "Online");
            var connectedDevices = await _dbContext.Devices.CountAsync(d => d.StoreId != null);
            
            var totalLicenseKeys = await _dbContext.LicenseKeys.CountAsync();
            var usedLicenseKeys = await _dbContext.LicenseKeys.CountAsync(l => l.IsUsed);
            var activeLicenseKeys = await _dbContext.LicenseKeys.CountAsync(l => l.IsActive && !l.IsUsed);
            
            var totalAgents = await _dbContext.Agents.CountAsync();
            var activeAgents = await _dbContext.Agents.CountAsync(a => a.IsActive);
            
            // Today stats
            var today = DateTime.UtcNow.Date;
            var attendanceToday = await _dbContext.AttendanceLogs.CountAsync(a => a.AttendanceTime >= today);
            var newStoresThisMonth = await _dbContext.Stores.CountAsync(s => s.CreatedAt >= today.AddDays(-30));
            
            // Recent audit logs count
            var recentAuditLogs = await _dbContext.AuditLogs.CountAsync(a => a.Timestamp >= today);
            var failedAuditLogs = await _dbContext.AuditLogs.CountAsync(a => a.Status == "Failed" && a.Timestamp >= today.AddDays(-7));
            
            // Expiring stores (next 30 days)
            var expiringDate = today.AddDays(30);
            var expiringStores = await _dbContext.Stores.CountAsync(s => s.ExpiryDate != null && s.ExpiryDate <= expiringDate && s.ExpiryDate > today);
            var expiredStores = await _dbContext.Stores.CountAsync(s => s.ExpiryDate != null && s.ExpiryDate < today);
            
            // Memory info (process level)
            var process = System.Diagnostics.Process.GetCurrentProcess();
            var memoryUsedMB = process.WorkingSet64 / 1024 / 1024;
            
            var endTime = DateTime.UtcNow;
            var responseTimeMs = (endTime - startTime).TotalMilliseconds;
            
            return Ok(AppResponse<object>.Success(new
            {
                status = databaseHealthy ? "Healthy" : "Unhealthy",
                timestamp = DateTime.UtcNow,
                responseTimeMs,
                
                database = new
                {
                    healthy = databaseHealthy,
                    error = databaseError
                },
                
                stores = new
                {
                    total = totalStores,
                    active = activeStores,
                    locked = lockedStores,
                    expiring = expiringStores,
                    expired = expiredStores,
                    newThisMonth = newStoresThisMonth
                },
                
                users = new
                {
                    total = totalUsers,
                    superAdmins = superAdminCount
                },
                
                devices = new
                {
                    total = totalDevices,
                    online = onlineDevices,
                    offline = totalDevices - onlineDevices,
                    connected = connectedDevices,
                    notConnected = totalDevices - connectedDevices
                },
                
                licenses = new
                {
                    total = totalLicenseKeys,
                    used = usedLicenseKeys,
                    available = activeLicenseKeys,
                    inactive = totalLicenseKeys - usedLicenseKeys - activeLicenseKeys
                },
                
                agents = new
                {
                    total = totalAgents,
                    active = activeAgents
                },
                
                today = new
                {
                    attendance = attendanceToday,
                    auditLogs = recentAuditLogs
                },
                
                alerts = new
                {
                    failedAuditLogs7Days = failedAuditLogs,
                    expiringStores30Days = expiringStores,
                    expiredStores
                },
                
                system = new
                {
                    memoryUsedMB,
                    serverTime = DateTime.UtcNow,
                    environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") ?? "Production"
                }
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting system health");
            return StatusCode(500, AppResponse<object>.Fail("Error getting system health: " + ex.Message));
        }
    }
    
    #endregion

    #region Service Packages (Gói dịch vụ)

    /// <summary>
    /// Lấy danh sách tất cả module/chức năng có thể chọn cho gói dịch vụ
    /// </summary>
    [HttpGet("service-packages/available-modules")]
    public ActionResult<AppResponse<List<FeatureModuleDto>>> GetAvailableModules()
    {
        var modules = new List<FeatureModuleDto>
        {
            // ══════════ TỔNG QUAN ══════════
            new("Home", "Trang chủ", "Màn hình tổng quan menu", "Tổng quan"),
            new("Notification", "Thông báo", "Hệ thống thông báo", "Tổng quan"),

            // ══════════ HỒ SƠ NHÂN SỰ ══════════
            new("Dashboard", "Bảng điều khiển", "Bảng điều khiển tổng quan", "Hồ sơ nhân sự"),
            new("Employee", "Hồ sơ nhân sự", "Thông tin nhân viên, chức vụ", "Hồ sơ nhân sự"),
            new("DeviceUser", "Nhân sự chấm công", "Nhân sự trên máy chấm công", "Hồ sơ nhân sự"),
            new("Department", "Phòng ban", "Quản lý phòng ban", "Hồ sơ nhân sự"),
            new("Leave", "Nghỉ phép", "Quản lý nghỉ phép", "Hồ sơ nhân sự"),
            new("SalarySettings", "Thiết lập lương", "Cấu hình bảng lương", "Hồ sơ nhân sự"),

            // ══════════ CHẤM CÔNG ══════════
            new("Attendance", "Chấm công", "Dữ liệu chấm công", "Chấm công"),
            new("WorkSchedule", "Lịch làm việc", "Phân lịch làm việc", "Chấm công"),
            new("AttendanceSummary", "Tổng hợp chấm công", "Bảng tổng hợp chấm công", "Chấm công"),
            new("AttendanceByShift", "Tổng hợp theo ca", "Chấm công theo ca làm việc", "Chấm công"),
            new("AttendanceApproval", "Duyệt chấm công", "Duyệt điều chỉnh chấm công", "Chấm công"),
            new("ScheduleApproval", "Duyệt lịch làm việc", "Duyệt lịch làm việc đăng ký", "Chấm công"),
            new("Payroll", "Tổng hợp lương", "Bảng lương nhân viên", "Chấm công"),

            // ══════════ TÀI CHÍNH ══════════
            new("BonusPenalty", "Thưởng / Phạt", "Quản lý thưởng phạt", "Tài chính"),
            new("PenaltyTickets", "Phiếu phạt", "Phiếu phạt tự động từ chấm công", "Tài chính"),
            new("AdvanceRequests", "Ứng lương", "Quản lý ứng lương", "Tài chính"),
            new("CashTransaction", "Thu chi", "Quản lý thu chi", "Tài chính"),

            // ══════════ QUẢN LÝ VẬN HÀNH ══════════
            new("Asset", "Tài sản", "Quản lý tài sản", "Quản lý Vận hành"),
            new("Task", "Công việc", "Quản lý công việc", "Quản lý Vận hành"),
            new("Communication", "Truyền thông", "Truyền thông nội bộ", "Quản lý Vận hành"),
            new("KPI", "KPI", "Đánh giá KPI", "Quản lý Vận hành"),

            // ══════════ BÁO CÁO ══════════
            new("HrReport", "Báo cáo nhân sự", "Thống kê nhân sự, phòng ban", "Báo cáo"),
            new("AttendanceReport", "Báo cáo chấm công", "Ngày, tháng, đi muộn, phòng ban", "Báo cáo"),
            new("PayrollReport", "Báo cáo lương", "Chi phí lương, phân bổ", "Báo cáo"),

            // ══════════ CÀI ĐẶT ══════════
            new("SettingsHub", "Thiết lập HRM", "Trung tâm cài đặt HRM", "Cài đặt"),
            new("ShiftSetup", "Thiết lập ca", "Ca làm việc, vào sớm, đi trễ, về sớm, tăng ca", "Cài đặt"),
            new("MobileAttendance", "Chấm công mobile", "Face ID, GPS, vùng chấm công", "Cài đặt"),
            new("Holiday", "Ngày lễ", "Ngày nghỉ lễ, hệ số công", "Cài đặt"),
            new("Device", "Máy chấm công", "Kết nối, quản lý, điều khiển máy chấm công", "Cài đặt"),
            new("Allowance", "Phụ cấp", "Phụ cấp cố định, phụ cấp ngày công", "Cài đặt"),
            new("PenaltySetup", "Phạt", "Đi trễ, về sớm, tái phạm, kỷ luật", "Cài đặt"),
            new("Insurance", "Bảo hiểm", "BHXH, BHYT, BHTN, lương cơ sở", "Cài đặt"),
            new("Tax", "Thuế TNCN", "Bậc thuế, giảm trừ gia cảnh", "Cài đặt"),
            new("UserManagement", "Tài khoản", "Người dùng, kích hoạt, vai trò", "Cài đặt"),
            new("Role", "Phân quyền", "Ma trận quyền, vai trò, module", "Cài đặt"),
            new("DepartmentPermission", "PQ Phòng ban", "Phân quyền theo sơ đồ cây phòng ban", "Cài đặt"),
            new("SystemSettings", "Hệ thống", "Giờ kết thúc ngày, tham số vận hành", "Cài đặt"),
            new("NotificationSettings", "Thiết lập thông báo", "Nhóm thông báo, bật/tắt nhận thông báo", "Cài đặt"),
            new("GoogleDrive", "Google Drive", "Lưu trữ ảnh, service account", "Cài đặt"),
            new("AIGemini", "AI Gemini", "API key, model, tham số AI", "Cài đặt"),
            new("Settings", "Cài đặt chung", "Cài đặt hệ thống", "Cài đặt"),
        };

        return Ok(AppResponse<List<FeatureModuleDto>>.Success(modules));
    }

    /// <summary>
    /// Lấy danh sách gói dịch vụ
    /// </summary>
    [HttpGet("service-packages")]
    public async Task<ActionResult<AppResponse<List<ServicePackageDto>>>> GetServicePackages()
    {
        try
        {
            var packages = await _dbContext.ServicePackages
                .Include(p => p.Stores)
                .OrderByDescending(p => p.CreatedAt)
                .Select(p => new ServicePackageDto(
                    p.Id,
                    p.Name,
                    p.Description,
                    p.IsActive,
                    p.DefaultDurationDays,
                    p.MaxUsers,
                    p.MaxDevices,
                    System.Text.Json.JsonSerializer.Deserialize<List<string>>(p.AllowedModules, (System.Text.Json.JsonSerializerOptions?)null) ?? new List<string>(),
                    p.Stores.Count,
                    p.CreatedAt,
                    p.UpdatedAt
                ))
                .ToListAsync();

            return Ok(AppResponse<List<ServicePackageDto>>.Success(packages));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting service packages");
            return StatusCode(500, AppResponse<List<ServicePackageDto>>.Fail("Error getting service packages"));
        }
    }

    /// <summary>
    /// Tạo gói dịch vụ mới
    /// </summary>
    [HttpPost("service-packages")]
    public async Task<ActionResult<AppResponse<ServicePackageDto>>> CreateServicePackage([FromBody] CreateServicePackageRequest request)
    {
        try
        {
            var package = new ServicePackage
            {
                Id = Guid.NewGuid(),
                Name = request.Name,
                Description = request.Description,
                DefaultDurationDays = request.DefaultDurationDays,
                MaxUsers = request.MaxUsers,
                MaxDevices = request.MaxDevices,
                AllowedModules = System.Text.Json.JsonSerializer.Serialize(request.AllowedModules),
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = CurrentUserId.ToString(),
            };

            _dbContext.ServicePackages.Add(package);
            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} created service package {PackageName}", CurrentUserId, request.Name);

            var dto = new ServicePackageDto(
                package.Id, package.Name, package.Description, package.IsActive,
                package.DefaultDurationDays, package.MaxUsers, package.MaxDevices,
                request.AllowedModules, 0, package.CreatedAt, package.UpdatedAt);

            return Ok(AppResponse<ServicePackageDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating service package");
            return StatusCode(500, AppResponse<ServicePackageDto>.Fail("Error creating service package"));
        }
    }

    /// <summary>
    /// Cập nhật gói dịch vụ
    /// </summary>
    [HttpPut("service-packages/{id:guid}")]
    public async Task<ActionResult<AppResponse<ServicePackageDto>>> UpdateServicePackage(Guid id, [FromBody] UpdateServicePackageRequest request)
    {
        try
        {
            var package = await _dbContext.ServicePackages
                .AsTracking()
                .Include(p => p.Stores)
                .FirstOrDefaultAsync(p => p.Id == id);

            if (package == null)
                return NotFound(AppResponse<ServicePackageDto>.Fail("Service package not found"));

            package.Name = request.Name;
            package.Description = request.Description;
            package.DefaultDurationDays = request.DefaultDurationDays;
            package.MaxUsers = request.MaxUsers;
            package.MaxDevices = request.MaxDevices;
            package.AllowedModules = System.Text.Json.JsonSerializer.Serialize(request.AllowedModules);
            package.IsActive = request.IsActive;
            package.UpdatedAt = DateTime.UtcNow;
            package.UpdatedBy = CurrentUserId.ToString();

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} updated service package {PackageId}", CurrentUserId, id);

            var dto = new ServicePackageDto(
                package.Id, package.Name, package.Description, package.IsActive,
                package.DefaultDurationDays, package.MaxUsers, package.MaxDevices,
                request.AllowedModules, package.Stores.Count, package.CreatedAt, package.UpdatedAt);

            return Ok(AppResponse<ServicePackageDto>.Success(dto));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating service package {PackageId}", id);
            return StatusCode(500, AppResponse<ServicePackageDto>.Fail("Error updating service package"));
        }
    }

    /// <summary>
    /// Xóa gói dịch vụ
    /// </summary>
    [HttpDelete("service-packages/{id:guid}")]
    public async Task<ActionResult<AppResponse<bool>>> DeleteServicePackage(Guid id)
    {
        try
        {
            var package = await _dbContext.ServicePackages
                .AsTracking()
                .Include(p => p.Stores)
                .FirstOrDefaultAsync(p => p.Id == id);

            if (package == null)
                return NotFound(AppResponse<bool>.Fail("Service package not found"));

            if (package.Stores.Any())
                return BadRequest(AppResponse<bool>.Fail($"Không thể xóa: có {package.Stores.Count} cửa hàng đang sử dụng gói này"));

            _dbContext.ServicePackages.Remove(package);
            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} deleted service package {PackageId}", CurrentUserId, id);

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting service package {PackageId}", id);
            return StatusCode(500, AppResponse<bool>.Fail("Error deleting service package"));
        }
    }

    /// <summary>
    /// Gán gói dịch vụ cho store
    /// </summary>
    [HttpPost("stores/{storeId:guid}/assign-package/{packageId:guid}")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> AssignPackageToStore(Guid storeId, Guid packageId)
    {
        try
        {
            var store = await _dbContext.Stores
                .AsTracking()
                .Include(s => s.Owner)
                .Include(s => s.Agent)
                .Include(s => s.Users)
                .Include(s => s.Devices)
                .Include(s => s.ServicePackage)
                .FirstOrDefaultAsync(s => s.Id == storeId);

            if (store == null)
                return NotFound(AppResponse<StoreDetailDto>.Fail("Store not found"));

            var package = await _dbContext.ServicePackages.FindAsync(packageId);
            if (package == null)
                return NotFound(AppResponse<StoreDetailDto>.Fail("Service package not found"));

            store.ServicePackageId = packageId;
            store.MaxUsers = package.MaxUsers;
            store.MaxDevices = package.MaxDevices;
            store.UpdatedAt = DateTime.UtcNow;
            store.UpdatedBy = CurrentUserId.ToString();

            // If store was expired or trial, extend based on package duration
            if (store.ExpiryDate == null || store.ExpiryDate < DateTime.UtcNow)
            {
                store.ExpiryDate = DateTime.UtcNow.AddDays(package.DefaultDurationDays);
            }

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} assigned package {PackageId} to store {StoreId}",
                CurrentUserId, packageId, storeId);

            return Ok(AppResponse<StoreDetailDto>.Success(MapToStoreDetailDto(store)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error assigning package to store");
            return StatusCode(500, AppResponse<StoreDetailDto>.Fail("Error assigning package"));
        }
    }

    /// <summary>
    /// Gia hạn thêm ngày cho store (tối đa 3 lần)
    /// </summary>
    [HttpPost("stores/{id:guid}/extend-days")]
    public async Task<ActionResult<AppResponse<StoreDetailDto>>> ExtendStoreDays(Guid id, [FromBody] ExtendDaysRequest request)
    {
        try
        {
            var store = await _dbContext.Stores
                .AsTracking()
                .Include(s => s.Owner)
                .Include(s => s.Agent)
                .Include(s => s.Users)
                .Include(s => s.Devices)
                .Include(s => s.ServicePackage)
                .FirstOrDefaultAsync(s => s.Id == id);

            if (store == null)
                return NotFound(AppResponse<StoreDetailDto>.Fail("Store not found"));

            if (store.RenewalCount >= 3)
            {
                return BadRequest(AppResponse<StoreDetailDto>.Fail(
                    "Cửa hàng đã gia hạn tối đa 3 lần. Vui lòng kích hoạt key mới."));
            }

            var baseDate = store.ExpiryDate ?? DateTime.UtcNow;
            if (baseDate < DateTime.UtcNow) baseDate = DateTime.UtcNow;

            store.ExpiryDate = baseDate.AddDays(request.Days);
            store.RenewalCount++;
            store.IsLocked = false;
            store.LockReason = null;
            store.IsActive = true;
            store.UpdatedAt = DateTime.UtcNow;
            store.UpdatedBy = CurrentUserId.ToString();

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} extended store {StoreId} by {Days} days (renewal #{Count})",
                CurrentUserId, id, request.Days, store.RenewalCount);

            return Ok(AppResponse<StoreDetailDto>.Success(MapToStoreDetailDto(store)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error extending store days");
            return StatusCode(500, AppResponse<StoreDetailDto>.Fail("Error extending store"));
        }
    }

    #endregion

    #region Key Activation Promotions

    /// <summary>
    /// Lấy danh sách chương trình khuyến mãi kích key
    /// </summary>
    [HttpGet("key-promotions")]
    public async Task<ActionResult<AppResponse<List<KeyActivationPromotionDto>>>> GetKeyPromotions()
    {
        try
        {
            var promos = await _dbContext.KeyActivationPromotions
                .Include(p => p.ServicePackage)
                .OrderByDescending(p => p.CreatedAt)
                .Select(p => new KeyActivationPromotionDto(
                    p.Id, p.Name, p.ServicePackageId,
                    p.ServicePackage != null ? p.ServicePackage.Name : "",
                    p.StartDate, p.EndDate,
                    p.Bonus1Key, p.Bonus2Keys, p.Bonus3Keys, p.Bonus4Keys,
                    p.IsActive, p.CreatedAt))
                .ToListAsync();

            return Ok(AppResponse<List<KeyActivationPromotionDto>>.Success(promos));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting key promotions");
            return StatusCode(500, AppResponse<List<KeyActivationPromotionDto>>.Fail("Error getting key promotions"));
        }
    }

    /// <summary>
    /// Tạo chương trình khuyến mãi kích key
    /// </summary>
    [HttpPost("key-promotions")]
    public async Task<ActionResult<AppResponse<KeyActivationPromotionDto>>> CreateKeyPromotion([FromBody] CreateKeyPromotionRequest request)
    {
        try
        {
            var pkg = await _dbContext.ServicePackages.FindAsync(request.ServicePackageId);
            if (pkg == null)
                return BadRequest(AppResponse<KeyActivationPromotionDto>.Fail("Gói dịch vụ không tồn tại"));

            var promo = new KeyActivationPromotion
            {
                Id = Guid.NewGuid(),
                Name = request.Name,
                ServicePackageId = request.ServicePackageId,
                StartDate = request.StartDate,
                EndDate = request.EndDate,
                Bonus1Key = request.Bonus1Key,
                Bonus2Keys = request.Bonus2Keys,
                Bonus3Keys = request.Bonus3Keys,
                Bonus4Keys = request.Bonus4Keys,
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = CurrentUserId.ToString()
            };

            _dbContext.KeyActivationPromotions.Add(promo);
            await _dbContext.SaveChangesAsync();

            return Ok(AppResponse<KeyActivationPromotionDto>.Success(new KeyActivationPromotionDto(
                promo.Id, promo.Name, promo.ServicePackageId, pkg.Name,
                promo.StartDate, promo.EndDate,
                promo.Bonus1Key, promo.Bonus2Keys, promo.Bonus3Keys, promo.Bonus4Keys,
                promo.IsActive, promo.CreatedAt)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating key promotion");
            return StatusCode(500, AppResponse<KeyActivationPromotionDto>.Fail("Error creating key promotion"));
        }
    }

    /// <summary>
    /// Cập nhật chương trình khuyến mãi kích key
    /// </summary>
    [HttpPut("key-promotions/{id:guid}")]
    public async Task<ActionResult<AppResponse<KeyActivationPromotionDto>>> UpdateKeyPromotion(Guid id, [FromBody] CreateKeyPromotionRequest request)
    {
        try
        {
            var promo = await _dbContext.KeyActivationPromotions
                .AsTracking()
                .Include(p => p.ServicePackage)
                .FirstOrDefaultAsync(p => p.Id == id);

            if (promo == null)
                return NotFound(AppResponse<KeyActivationPromotionDto>.Fail("Promotion not found"));

            var pkg = await _dbContext.ServicePackages.FindAsync(request.ServicePackageId);
            if (pkg == null)
                return BadRequest(AppResponse<KeyActivationPromotionDto>.Fail("Gói dịch vụ không tồn tại"));

            promo.Name = request.Name;
            promo.ServicePackageId = request.ServicePackageId;
            promo.StartDate = request.StartDate;
            promo.EndDate = request.EndDate;
            promo.Bonus1Key = request.Bonus1Key;
            promo.Bonus2Keys = request.Bonus2Keys;
            promo.Bonus3Keys = request.Bonus3Keys;
            promo.Bonus4Keys = request.Bonus4Keys;
            promo.UpdatedAt = DateTime.UtcNow;
            promo.UpdatedBy = CurrentUserId.ToString();

            await _dbContext.SaveChangesAsync();

            return Ok(AppResponse<KeyActivationPromotionDto>.Success(new KeyActivationPromotionDto(
                promo.Id, promo.Name, promo.ServicePackageId, pkg.Name,
                promo.StartDate, promo.EndDate,
                promo.Bonus1Key, promo.Bonus2Keys, promo.Bonus3Keys, promo.Bonus4Keys,
                promo.IsActive, promo.CreatedAt)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating key promotion");
            return StatusCode(500, AppResponse<KeyActivationPromotionDto>.Fail("Error updating key promotion"));
        }
    }

    /// <summary>
    /// Xóa chương trình khuyến mãi kích key
    /// </summary>
    [HttpDelete("key-promotions/{id:guid}")]
    public async Task<ActionResult<AppResponse<bool>>> DeleteKeyPromotion(Guid id)
    {
        try
        {
            var promo = await _dbContext.KeyActivationPromotions.FindAsync(id);
            if (promo == null)
                return NotFound(AppResponse<bool>.Fail("Promotion not found"));

            _dbContext.KeyActivationPromotions.Remove(promo);
            await _dbContext.SaveChangesAsync();

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error deleting key promotion");
            return StatusCode(500, AppResponse<bool>.Fail("Error deleting key promotion"));
        }
    }

    /// <summary>
    /// Kích hoạt nhiều key cùng lúc cho cửa hàng — chỉ cho phép key cùng gói
    /// Tự động áp dụng chương trình khuyến mãi nếu có
    /// </summary>
    [HttpPost("stores/{storeId:guid}/activate-bulk")]
    public async Task<ActionResult<AppResponse<BulkActivationResultDto>>> BulkActivateLicenses(
        Guid storeId, [FromBody] BulkActivateLicenseRequest request)
    {
        try
        {
            var store = await _dbContext.Stores
                .AsTracking()
                .Include(s => s.Owner)
                .Include(s => s.Agent)
                .Include(s => s.Users)
                .Include(s => s.Devices)
                .Include(s => s.ServicePackage)
                .FirstOrDefaultAsync(s => s.Id == storeId);

            if (store == null)
                return NotFound(AppResponse<BulkActivationResultDto>.Fail("Store not found"));

            if (request.LicenseKeys == null || request.LicenseKeys.Count == 0)
                return BadRequest(AppResponse<BulkActivationResultDto>.Fail("Chưa nhập license key nào"));

            // Tìm tất cả key hợp lệ
            var licenses = await _dbContext.LicenseKeys
                .AsTracking()
                .Include(l => l.ServicePackage)
                .Where(l => request.LicenseKeys.Contains(l.Key) && l.IsActive && !l.IsUsed)
                .ToListAsync();

            if (licenses.Count == 0)
                return BadRequest(AppResponse<BulkActivationResultDto>.Fail("Không có key hợp lệ hoặc đã được sử dụng"));

            // Kiểm tra tất cả key cùng 1 gói
            var packageIds = licenses.Select(l => l.ServicePackageId).Where(id => id != null).Distinct().ToList();
            if (packageIds.Count > 1)
                return BadRequest(AppResponse<BulkActivationResultDto>.Fail(
                    "Tất cả key phải cùng một gói dịch vụ. Không thể kích key thuộc nhiều gói khác nhau."));

            // Ưu tiên packageId từ key, nếu không có thì lấy từ store
            var packageId = packageIds.FirstOrDefault() ?? store.ServicePackageId;

            // Tính tổng ngày từ tất cả key
            var totalDays = licenses.Sum(l => l.DurationDays);
            var keyCount = licenses.Count;

            // Tìm chương trình khuyến mãi đang áp dụng
            var now = DateTime.UtcNow;
            var promo = packageId != null
                ? await _dbContext.KeyActivationPromotions
                    .Where(p => p.ServicePackageId == packageId.Value
                        && p.IsActive
                        && p.StartDate <= now
                        && p.EndDate >= now)
                    .FirstOrDefaultAsync()
                : null;

            // Tính bonus theo số lượng key
            int bonusDays = 0;
            if (promo != null)
            {
                bonusDays = keyCount switch
                {
                    1 => promo.Bonus1Key,
                    2 => promo.Bonus2Keys,
                    3 => promo.Bonus3Keys,
                    _ => promo.Bonus4Keys  // >= 4 keys
                };
            }

            // Kiểm tra lần đầu kích hoạt TRƯỚC khi cập nhật LicenseKey
            var isFirstActivation = string.IsNullOrEmpty(store.LicenseKey);

            // Kích hoạt tất cả key
            foreach (var license in licenses)
            {
                license.IsUsed = true;
                license.StoreId = storeId;
                license.ActivatedAt = DateTime.UtcNow;
                license.UpdatedAt = DateTime.UtcNow;
                license.UpdatedBy = CurrentUserId.ToString();
            }

            // Cộng ngày: tổng ngày key + bonus khuyến mãi
            var baseDate = store.ExpiryDate ?? DateTime.UtcNow;
            if (baseDate < DateTime.UtcNow) baseDate = DateTime.UtcNow;
            store.ExpiryDate = baseDate.AddDays(totalDays + bonusDays);

            // Cập nhật store từ key cuối cùng
            var lastLicense = licenses.Last();
            store.LicenseKey = string.Join(", ", licenses.Select(l => l.Key));
            store.LicenseType = lastLicense.LicenseType;
            store.MaxUsers = licenses.Max(l => l.MaxUsers);
            store.MaxDevices = licenses.Max(l => l.MaxDevices);

            if (packageId != null)
                store.ServicePackageId = packageId;

            if (!isFirstActivation)
                store.RenewalCount++;

            store.IsActive = true;
            store.IsLocked = false;
            store.LockReason = null;
            store.UpdatedAt = DateTime.UtcNow;
            store.UpdatedBy = CurrentUserId.ToString();

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("SuperAdmin {UserId} bulk activated {Count} keys for Store {StoreId}. Total days: {TotalDays} + bonus: {BonusDays}",
                CurrentUserId, keyCount, storeId, totalDays, bonusDays);

            // Thông báo cho chủ cửa hàng về việc kích hoạt key
            try
            {
                if (store.OwnerId.HasValue)
                {
                    var packageName = lastLicense.ServicePackage?.Name ?? lastLicense.LicenseType.ToString();
                    var bonusText = bonusDays > 0 ? $" (+ {bonusDays} ngày KM)" : "";
                    await _notificationService.CreateAndSendAsync(
                        targetUserId: store.OwnerId.Value,
                        type: NotificationType.Success,
                        title: "Kích hoạt License thành công",
                        message: $"Cửa hàng '{store.Name}' đã kích hoạt {keyCount} key gói {packageName}, thêm {totalDays} ngày{bonusText}. Hạn đến {store.ExpiryDate:dd/MM/yyyy}",
                        relatedEntityId: storeId,
                        relatedEntityType: "Store",
                        categoryCode: "license",
                        storeId: storeId);
                }
            }
            catch { }

            return Ok(AppResponse<BulkActivationResultDto>.Success(new BulkActivationResultDto(
                keyCount, totalDays, bonusDays, totalDays + bonusDays,
                promo?.Name,
                licenses.Select(l => l.Key).ToList(),
                store.ExpiryDate)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error bulk activating licenses for store {StoreId}", storeId);
            return StatusCode(500, AppResponse<BulkActivationResultDto>.Fail("Error bulk activating licenses"));
        }
    }

    /// <summary>
    /// Xem trước kết quả kích nhiều key (không kích thật, chỉ tính toán)
    /// </summary>
    [HttpPost("stores/{storeId:guid}/activate-bulk-preview")]
    public async Task<ActionResult<AppResponse<BulkActivationResultDto>>> PreviewBulkActivation(
        Guid storeId, [FromBody] BulkActivateLicenseRequest request)
    {
        try
        {
            var store = await _dbContext.Stores
                .FirstOrDefaultAsync(s => s.Id == storeId);

            if (store == null)
                return NotFound(AppResponse<BulkActivationResultDto>.Fail("Store not found"));

            if (request.LicenseKeys == null || request.LicenseKeys.Count == 0)
                return BadRequest(AppResponse<BulkActivationResultDto>.Fail("Chưa nhập license key nào"));

            var licenses = await _dbContext.LicenseKeys
                .Include(l => l.ServicePackage)
                .Where(l => request.LicenseKeys.Contains(l.Key) && l.IsActive && !l.IsUsed)
                .ToListAsync();

            if (licenses.Count == 0)
                return BadRequest(AppResponse<BulkActivationResultDto>.Fail("Không có key hợp lệ"));

            var packageIds = licenses.Select(l => l.ServicePackageId).Where(id => id != null).Distinct().ToList();
            if (packageIds.Count > 1)
                return BadRequest(AppResponse<BulkActivationResultDto>.Fail(
                    "Tất cả key phải cùng một gói dịch vụ"));

            // Ưu tiên packageId từ key, nếu không có thì lấy từ store
            var packageId = packageIds.FirstOrDefault() ?? store.ServicePackageId;
            var totalDays = licenses.Sum(l => l.DurationDays);
            var keyCount = licenses.Count;

            var now = DateTime.UtcNow;
            var promo = packageId != null
                ? await _dbContext.KeyActivationPromotions
                    .Where(p => p.ServicePackageId == packageId.Value
                        && p.IsActive
                        && p.StartDate <= now
                        && p.EndDate >= now)
                    .FirstOrDefaultAsync()
                : null;

            int bonusDays = 0;
            if (promo != null)
            {
                bonusDays = keyCount switch
                {
                    1 => promo.Bonus1Key,
                    2 => promo.Bonus2Keys,
                    3 => promo.Bonus3Keys,
                    _ => promo.Bonus4Keys
                };
            }

            var baseDate = store.ExpiryDate ?? DateTime.UtcNow;
            if (baseDate < DateTime.UtcNow) baseDate = DateTime.UtcNow;
            var newExpiry = baseDate.AddDays(totalDays + bonusDays);

            return Ok(AppResponse<BulkActivationResultDto>.Success(new BulkActivationResultDto(
                keyCount, totalDays, bonusDays, totalDays + bonusDays,
                promo?.Name,
                licenses.Select(l => l.Key).ToList(),
                newExpiry)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error previewing bulk activation");
            return StatusCode(500, AppResponse<BulkActivationResultDto>.Fail("Error previewing bulk activation"));
        }
    }

    #endregion
}

public record ExtendDaysRequest(int Days);

/// <summary>
/// Request tạo SuperAdmin mới
/// </summary>
public record CreateSuperAdminRequest(
    string Email,
    string FullName,
    string Password
);

// License Key DTOs and Requests
public record LicenseKeyDto(
    Guid Id,
    string Key,
    string LicenseType,
    int DurationDays,
    int MaxUsers,
    int MaxDevices,
    bool IsUsed,
    DateTime? ActivatedAt,
    Guid? StoreId,
    string? StoreName,
    Guid? AgentId,
    string? AgentName,
    Guid? ServicePackageId,
    string? ServicePackageName,
    string? Notes,
    bool IsActive,
    DateTime CreatedAt
);

public record CreateLicenseKeyRequest(
    LicenseType LicenseType,
    int DurationDays,
    int MaxUsers,
    int MaxDevices,
    string? Notes,
    Guid? ServicePackageId
);

public record CreateBatchLicenseKeyRequest(
    int Count,
    LicenseType LicenseType,
    int DurationDays,
    int MaxUsers,
    int MaxDevices,
    string? Notes,
    Guid? ServicePackageId
);

public record ActivateLicenseRequest(string LicenseKey);

public record LockStoreRequest(string Reason);

public record ExtendSubscriptionRequest(
    int DaysToAdd,
    int? MaxUsers,
    int? MaxDevices,
    LicenseType? LicenseType
);

public record UpdateStoreLimitsRequest(int MaxUsers, int MaxDevices);

public record UpdateUserCredentialsRequest(
    string? NewEmail,
    string? NewPassword,
    string? FullName
);

public record UpdateUserRoleRequest(string Role);

public record StoreFullDetailDto(
    Guid Id,
    string Name,
    string Code,
    string? Description,
    string? Address,
    string? Phone,
    bool IsActive,
    bool IsLocked,
    string? LockReason,
    DateTime? LockedAt,
    string LicenseType,
    string? LicenseKey,
    DateTime? ExpiryDate,
    int MaxUsers,
    int MaxDevices,
    int CurrentUserCount,
    int CurrentDeviceCount,
    Guid? OwnerId,
    string? OwnerName,
    string? OwnerEmail,
    DateTime CreatedAt,
    DateTime? UpdatedAt
);

// Additional License Key DTOs
public record AssignLicenseToAgentRequest(Guid AgentId);

public record BatchAssignLicenseRequest(List<Guid> LicenseKeyIds, Guid AgentId);

public record BatchAssignByCountRequest(Guid AgentId, int Count, Guid? ServicePackageId, LicenseType? LicenseType);

public record BatchAssignLicenseToStoreRequest(List<Guid> LicenseKeyIds, Guid StoreId);

public record BatchRevokeRequest(List<Guid> LicenseKeyIds);

public record BatchAssignResult(int AssignedCount, List<Guid> FailedIds);

public record RestoreDatabaseRequest(string FileName, bool ConfirmRestore = false);

// Key Activation Promotion DTOs
public record KeyActivationPromotionDto(
    Guid Id, string Name, Guid ServicePackageId, string ServicePackageName,
    DateTime StartDate, DateTime EndDate,
    int Bonus1Key, int Bonus2Keys, int Bonus3Keys, int Bonus4Keys,
    bool IsActive, DateTime CreatedAt);

public record CreateKeyPromotionRequest(
    string Name, Guid ServicePackageId,
    DateTime StartDate, DateTime EndDate,
    int Bonus1Key, int Bonus2Keys, int Bonus3Keys, int Bonus4Keys);

public record BulkActivateLicenseRequest(List<string> LicenseKeys);

public record BulkActivationResultDto(
    int KeyCount, int TotalDays, int BonusDays, int GrandTotalDays,
    string? PromotionName, List<string> ActivatedKeys, DateTime? NewExpiryDate);
