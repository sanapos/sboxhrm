using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Hồ sơ ngành, khu vực/bàn/phòng, phiên mở bàn, gói buổi gym.
/// Thống nhất với bán lẻ: Draft order + resource session + billing helper.
/// </summary>
[ApiController]
[Route("api/pos")]
[Authorize]
public partial class PosSellIndustryController(
    ZKTecoDbContext db,
    IHubContext<AttendanceHub> hub) : AuthenticatedControllerBase
{
    void NotifyFloorChanged(
        Guid storeId,
        string reason,
        Guid? orderId = null,
        Guid? resourceId = null,
        Guid? sessionId = null)
        => PosFloorRealtimeHelper.Notify(hub, storeId, reason, orderId, resourceId, sessionId);

    bool TryGetStoreId(out Guid storeId)
    {
        storeId = CurrentStoreId ?? Guid.Empty;
        return storeId != Guid.Empty;
    }

    // ── Sell settings ────────────────────────────────────────────────────────

    public record SellSettingsDto(
        Guid Id,
        string SellProfile,
        string DefaultSellMode,
        bool EnableResources,
        bool EnableHourlyBilling,
        bool EnableSessionPacks,
        bool RequireResourceOnSale,
        bool ShowFloorPlan,
        bool AllowProvisionalBill,
        bool EnableMultiDeviceDraftLock,
        bool PromptGuestCountOnOpen,
        bool AllowNegativeStock,
        Guid? DefaultHourlyProductId,
        string? ExtraJson);

    public record SellSettingsSaveDto(
        string? SellProfile = null,
        string? DefaultSellMode = null,
        bool? EnableResources = null,
        bool? EnableHourlyBilling = null,
        bool? EnableSessionPacks = null,
        bool? RequireResourceOnSale = null,
        bool? ShowFloorPlan = null,
        bool? AllowProvisionalBill = null,
        bool? EnableMultiDeviceDraftLock = null,
        bool? PromptGuestCountOnOpen = null,
        bool? AllowNegativeStock = null,
        Guid? DefaultHourlyProductId = null,
        bool SetDefaultHourlyProductId = false,
        string? ExtraJson = null,
        bool? ApplyProfileDefaults = null);

    [HttpGet("sell-settings")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<SellSettingsDto>>> GetSellSettings()
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<SellSettingsDto>.Fail("Thiếu cửa hàng"));

        var s = await db.PosStoreSellSettings
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);
        if (s == null)
        {
            s = PosServiceBillingHelper.CreateDefault(storeId, CurrentUserEmail);
            db.PosStoreSellSettings.Add(s);
            await db.SaveChangesAsync();
        }

        return Ok(AppResponse<SellSettingsDto>.Success(MapSettings(s)));
    }

    [HttpPut("sell-settings")]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "PosSell", "PosProducts")]
    public async Task<ActionResult<AppResponse<SellSettingsDto>>> SaveSellSettings(
        [FromBody] SellSettingsSaveDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<SellSettingsDto>.Fail("Thiếu cửa hàng"));

        // DbContext mặc định NoTracking — bắt buộc AsTracking để SaveChangesAsync thực sự ghi settings.
        var s = await db.PosStoreSellSettings.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);
        if (s == null)
        {
            s = PosServiceBillingHelper.CreateDefault(storeId, CurrentUserEmail);
            db.PosStoreSellSettings.Add(s);
        }

        if (!TryParseSellProfile(dto.SellProfile, out var profile))
            return BadRequest(AppResponse<SellSettingsDto>.Fail(
                $"Hồ sơ ngành không hợp lệ: {dto.SellProfile ?? "(null)"}"));

        // Preview cờ sau khi đổi — chặn tắt bàn khi còn phiên mở.
        var preview = new PosStoreSellSettings
        {
            SellProfile = profile,
            EnableResources = s.EnableResources,
            EnableHourlyBilling = s.EnableHourlyBilling,
            EnableSessionPacks = s.EnableSessionPacks,
            RequireResourceOnSale = s.RequireResourceOnSale,
            ShowFloorPlan = s.ShowFloorPlan,
            AllowProvisionalBill = s.AllowProvisionalBill,
            EnableMultiDeviceDraftLock = s.EnableMultiDeviceDraftLock,
            PromptGuestCountOnOpen = s.PromptGuestCountOnOpen,
            AllowNegativeStock = s.AllowNegativeStock,
        };
        var applyDefaults = dto.ApplyProfileDefaults != false;
        if (applyDefaults)
            PosServiceBillingHelper.ApplyProfileDefaults(preview);
        ApplySellSettingsFlags(preview, dto, applyDefaults);

        if (s.EnableResources && !preview.EnableResources)
        {
            var openCount = await CountLiveResourceSessionsAsync(storeId);
            if (openCount > 0)
            {
                return BadRequest(AppResponse<SellSettingsDto>.Fail(
                    $"Còn {openCount} bàn/phiên đang mở. Thanh toán hoặc đóng bàn trước khi đổi sang chế độ không dùng bàn."));
            }
        }

        s.SellProfile = profile;
        if (applyDefaults)
            PosServiceBillingHelper.ApplyProfileDefaults(s);
        ApplySellSettingsFlags(s, dto, applyDefaults);

        if (!string.IsNullOrWhiteSpace(dto.DefaultSellMode))
            s.DefaultSellMode = dto.DefaultSellMode.Trim().ToLowerInvariant();
        if (dto.ExtraJson != null) s.ExtraJson = dto.ExtraJson;
        if (dto.SetDefaultHourlyProductId)
        {
            var pid = dto.DefaultHourlyProductId;
            if (pid is null || pid == Guid.Empty)
                s.DefaultHourlyProductId = null;
            else
            {
                var ok = await db.PosProducts.AnyAsync(p =>
                    p.Id == pid && p.StoreId == storeId && p.Deleted == null
                    && p.ProductType == PosProductType.Service
                    && (p.ServiceBillingMode == PosServiceBillingMode.PerHour
                        || p.ServiceBillingMode == PosServiceBillingMode.PerMinute));
                if (!ok)
                    return BadRequest(AppResponse<SellSettingsDto>.Fail(
                        "SP tính giờ mặc định không hợp lệ (cần dịch vụ PerHour/PerMinute)"));
                s.DefaultHourlyProductId = pid;
            }
        }

        s.IsActive = true;
        s.UpdatedAt = DateTime.UtcNow;
        s.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<SellSettingsDto>.Success(MapSettings(s)));
    }

    static void ApplySellSettingsFlags(
        PosStoreSellSettings s, SellSettingsSaveDto dto, bool applyDefaults)
    {
        // applyDefaults: client có thể gửi kèm cờ sau withProfileDefaults — ưu tiên nếu có.
        // !applyDefaults: chỉ patch các cờ được gửi.
        if (applyDefaults || dto.EnableResources.HasValue)
        {
            if (dto.EnableResources.HasValue) s.EnableResources = dto.EnableResources.Value;
        }
        if (applyDefaults || dto.EnableHourlyBilling.HasValue)
        {
            if (dto.EnableHourlyBilling.HasValue) s.EnableHourlyBilling = dto.EnableHourlyBilling.Value;
        }
        if (applyDefaults || dto.EnableSessionPacks.HasValue)
        {
            if (dto.EnableSessionPacks.HasValue) s.EnableSessionPacks = dto.EnableSessionPacks.Value;
        }
        if (applyDefaults || dto.RequireResourceOnSale.HasValue)
        {
            if (dto.RequireResourceOnSale.HasValue) s.RequireResourceOnSale = dto.RequireResourceOnSale.Value;
        }
        if (applyDefaults || dto.ShowFloorPlan.HasValue)
        {
            if (dto.ShowFloorPlan.HasValue) s.ShowFloorPlan = dto.ShowFloorPlan.Value;
        }
        if (applyDefaults || dto.AllowProvisionalBill.HasValue)
        {
            if (dto.AllowProvisionalBill.HasValue) s.AllowProvisionalBill = dto.AllowProvisionalBill.Value;
        }
        if (applyDefaults || dto.EnableMultiDeviceDraftLock.HasValue)
        {
            if (dto.EnableMultiDeviceDraftLock.HasValue)
                s.EnableMultiDeviceDraftLock = dto.EnableMultiDeviceDraftLock.Value;
        }
        if (applyDefaults || dto.PromptGuestCountOnOpen.HasValue)
        {
            if (dto.PromptGuestCountOnOpen.HasValue)
                s.PromptGuestCountOnOpen = dto.PromptGuestCountOnOpen.Value;
        }
        if (applyDefaults || dto.AllowNegativeStock.HasValue)
        {
            if (dto.AllowNegativeStock.HasValue)
                s.AllowNegativeStock = dto.AllowNegativeStock.Value;
        }
    }

    async Task<int> CountLiveResourceSessionsAsync(Guid storeId) =>
        await db.PosResourceSessions.AsNoTracking().CountAsync(s =>
            s.StoreId == storeId && s.Deleted == null
            && (s.Status == PosResourceSessionStatus.Open
                || s.Status == PosResourceSessionStatus.Paused));

    async Task<PosStoreSellSettings?> LoadSellSettingsAsync(Guid storeId) =>
        await db.PosStoreSellSettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);

    async Task<ActionResult?> RequireResourcesEnabledAsync(Guid storeId)
    {
        var s = await LoadSellSettingsAsync(storeId);
        if (s == null || !s.EnableResources)
        {
            return BadRequest(AppResponse<object>.Fail(
                "Hồ sơ ngành hiện tại không bật bàn/tài nguyên phục vụ."));
        }
        return null;
    }

    async Task<ActionResult?> RequireRestaurantKitchenAsync(Guid storeId)
    {
        var s = await LoadSellSettingsAsync(storeId);
        if (s == null || s.SellProfile != PosSellProfile.Restaurant)
        {
            return BadRequest(AppResponse<object>.Fail(
                "Báo chế biến chỉ dùng với hồ sơ Nhà hàng / F&B."));
        }
        return null;
    }

    async Task<ActionResult?> RequireProvisionalBillAsync(Guid storeId)
    {
        var s = await LoadSellSettingsAsync(storeId);
        if (s == null || !s.AllowProvisionalBill)
        {
            return BadRequest(AppResponse<object>.Fail(
                "Hồ sơ ngành hiện tại không cho phép tạm tính."));
        }
        return null;
    }

    async Task<ActionResult?> RequireSessionPacksAsync(Guid storeId)
    {
        var s = await LoadSellSettingsAsync(storeId);
        if (s == null || !s.EnableSessionPacks)
        {
            return BadRequest(AppResponse<object>.Fail(
                "Hồ sơ ngành hiện tại không bật gói buổi."));
        }
        return null;
    }

    static bool TryParseSellProfile(string? raw, out PosSellProfile profile)
    {
        profile = PosSellProfile.Retail;
        if (string.IsNullOrWhiteSpace(raw)) return false;
        var t = raw.Trim();
        if (Enum.TryParse<PosSellProfile>(t, ignoreCase: true, out profile))
            return true;
        if (int.TryParse(t, out var n) && Enum.IsDefined(typeof(PosSellProfile), n))
        {
            profile = (PosSellProfile)n;
            return true;
        }
        // Alias tiếng Việt / viết tắt
        switch (t.ToLowerInvariant())
        {
            case "banle":
            case "bán lẻ":
            case "retail":
                profile = PosSellProfile.Retail;
                return true;
            case "salon":
            case "nail":
                profile = PosSellProfile.Salon;
                return true;
            case "bia":
            case "bi-a":
            case "karaoke":
            case "room":
            case "roomhourly":
                profile = PosSellProfile.RoomHourly;
                return true;
            case "fnb":
            case "f&b":
            case "nhahang":
            case "nhà hàng":
            case "restaurant":
                profile = PosSellProfile.Restaurant;
                return true;
            case "gym":
            case "fitness":
                profile = PosSellProfile.Gym;
                return true;
            default:
                return false;
        }
    }

    static SellSettingsDto MapSettings(PosStoreSellSettings s) => new(
        s.Id, s.SellProfile.ToString(), s.DefaultSellMode,
        s.EnableResources, s.EnableHourlyBilling, s.EnableSessionPacks,
        s.RequireResourceOnSale, s.ShowFloorPlan, s.AllowProvisionalBill,
        s.EnableMultiDeviceDraftLock, s.PromptGuestCountOnOpen,
        s.AllowNegativeStock, s.DefaultHourlyProductId, s.ExtraJson);

    // ── Areas / resources ─────────────────────────────────────────────────────

    public record AreaDto(Guid Id, string Name, string? Code, int SortOrder, string? AreaType, bool IsActive);

    /// <summary>DTO class — tránh JSON bind sai với positional record (giống layout).</summary>
    public class AreaSaveDto
    {
        public string Name { get; set; } = "";
        public string? Code { get; set; }
        public int SortOrder { get; set; }
        public string? AreaType { get; set; }
        public bool IsActive { get; set; } = true;
    }

    public class AreaSortItemDto
    {
        public Guid Id { get; set; }
        public int SortOrder { get; set; }
    }

    public class AreaSortBatchDto
    {
        public List<AreaSortItemDto> Items { get; set; } = [];
    }

    public record ResourceDto(
        Guid Id, Guid AreaId, string AreaName, string Code, string Name,
        string ResourceKind, int Capacity, int SortOrder, decimal? DefaultHourlyRate,
        bool IsActive, string OccupancyStatus, Guid? OpenSessionId, Guid? OpenOrderId,
        DateTime? SessionStartedAt,
        int ElapsedMinutes = 0,
        decimal Subtotal = 0,
        int LineCount = 0,
        int PendingKitchenCount = 0,
        int GuestCount = 0,
        bool BillRequested = false,
        bool NeedsCleaning = false,
        string? OrderNo = null,
        double? LayoutX = null,
        double? LayoutY = null,
        double LayoutW = 120,
        double LayoutH = 100,
        Guid? ReservationId = null,
        string? ReservationCustomerName = null,
        string? ReservationPhone = null,
        int ReservationGuestCount = 0,
        int ReservationPreOrderCount = 0,
        DateTime? ReservationReservedUntil = null,
        string? LockedByDeviceId = null,
        string? LockedByDeviceName = null,
        string? LockedByDisplayName = null,
        DateTime? LockExpiresAt = null,
        /// <summary>Máy đang giữ khóa sửa đơn (≠ phiên mở bàn).</summary>
        bool TableSessionOpen = false,
        /// <summary>Còn phiên/đơn nhưng không ai đang sửa (đã về sơ đồ).</summary>
        bool HasParkedBill = false,
        int AccumulatedPauseMinutes = 0,
        DateTime? PausedAt = null,
        Guid? DefaultServiceProductId = null,
        decimal ReservationDepositPaid = 0,
        decimal ReservationDepositAmount = 0,
        string? ReservationDepositStatus = null);

    /// <summary>Khóa còn TTL nhưng heartbeat (LockedAt) quá cũ → coi là tạm rời.</summary>
    const int ActiveTableEditSeconds = 45;

    static int ResolveOpenGuestCount(int? guestCount) =>
        guestCount is > 0 ? guestCount.Value : 1;

    static bool IsActiveTableEdit(DateTime? lockExpiresAt, DateTime? lockedAt, DateTime utcNow)
    {
        if (lockExpiresAt == null || lockExpiresAt.Value <= utcNow) return false;
        if (!lockedAt.HasValue) return true;
        return (utcNow - lockedAt.Value).TotalSeconds <= ActiveTableEditSeconds;
    }

    /// <summary>DTO class — ResourceKind dạng string để bind chắc chắn từ Flutter.</summary>
    public class ResourceSaveDto
    {
        public Guid AreaId { get; set; }
        public string Code { get; set; } = "";
        public string Name { get; set; } = "";
        public string? ResourceKind { get; set; }
        public int Capacity { get; set; } = 1;
        public int SortOrder { get; set; }
        public decimal? DefaultHourlyRate { get; set; }
        public Guid? DefaultServiceProductId { get; set; }
        public bool IsActive { get; set; } = true;
        public double? LayoutX { get; set; }
        public double? LayoutY { get; set; }
        public double? LayoutW { get; set; }
        public double? LayoutH { get; set; }
    }

    static PosResourceKind ParseResourceKind(string? raw) =>
        Enum.TryParse<PosResourceKind>(raw, ignoreCase: true, out var k) ? k : PosResourceKind.Table;

    [HttpGet("service-areas")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<AreaDto>>>> GetAreas()
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<List<AreaDto>>.Fail("Thiếu cửa hàng"));
        var q = db.PosServiceAreas.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.Deleted == null);
        var restricted = await GetRestrictedAreaIdsAsync(storeId);
        if (restricted != null)
            q = q.Where(a => restricted.Contains(a.Id));
        var list = await q
            .OrderBy(a => a.SortOrder).ThenBy(a => a.Name)
            .Select(a => new AreaDto(a.Id, a.Name, a.Code, a.SortOrder, a.AreaType, a.IsActive))
            .ToListAsync();
        return Ok(AppResponse<List<AreaDto>>.Success(list));
    }

    [HttpPost("service-areas")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<AreaDto>>> CreateArea([FromBody] AreaSaveDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<AreaDto>.Fail("Thiếu cửa hàng"));
        if (dto == null)
            return BadRequest(AppResponse<AreaDto>.Fail("Thiếu dữ liệu"));
        var name = dto.Name?.Trim() ?? "";
        if (name.Length == 0)
            return BadRequest(AppResponse<AreaDto>.Fail("Tên khu vực bắt buộc"));

        var entity = new PosServiceArea
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = name,
            Code = string.IsNullOrWhiteSpace(dto.Code) ? null : dto.Code.Trim(),
            SortOrder = dto.SortOrder,
            AreaType = string.IsNullOrWhiteSpace(dto.AreaType) ? null : dto.AreaType.Trim(),
            IsActive = dto.IsActive,
            CreatedBy = CurrentUserEmail,
        };
        db.PosServiceAreas.Add(entity);
        await db.SaveChangesAsync();
        return Ok(AppResponse<AreaDto>.Success(
            new AreaDto(entity.Id, entity.Name, entity.Code, entity.SortOrder, entity.AreaType, entity.IsActive)));
    }

    /// <summary>Sắp xếp thứ tự nhóm/khu vực — đặt trước route {id}.</summary>
    [HttpPut("service-areas/sort")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SortAreas([FromBody] AreaSortBatchDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (dto?.Items == null || dto.Items.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Không có thứ tự"));

        var saved = 0;
        var now = DateTime.UtcNow;
        var by = CurrentUserEmail;
        foreach (var item in dto.Items)
        {
            if (item.Id == Guid.Empty) continue;
            saved += await db.PosServiceAreas
                .Where(a => a.Id == item.Id && a.StoreId == storeId && a.Deleted == null)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(a => a.SortOrder, item.SortOrder)
                    .SetProperty(a => a.UpdatedAt, now)
                    .SetProperty(a => a.UpdatedBy, by));
        }

        if (saved == 0)
            return BadRequest(AppResponse<object>.Fail("Không khớp khu vực nào"));
        return Ok(AppResponse<object>.Success(new { saved }));
    }

    [HttpPut("service-areas/{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<AreaDto>>> UpdateArea(Guid id, [FromBody] AreaSaveDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<AreaDto>.Fail("Thiếu cửa hàng"));
        if (dto == null)
            return BadRequest(AppResponse<AreaDto>.Fail("Thiếu dữ liệu"));

        var name = dto.Name?.Trim() ?? "";
        if (name.Length == 0)
            return BadRequest(AppResponse<AreaDto>.Fail("Tên khu vực bắt buộc"));

        var code = string.IsNullOrWhiteSpace(dto.Code) ? null : dto.Code.Trim();
        var areaType = string.IsNullOrWhiteSpace(dto.AreaType) ? null : dto.AreaType.Trim();
        var now = DateTime.UtcNow;
        var by = CurrentUserEmail;

        var n = await db.PosServiceAreas
            .Where(a => a.Id == id && a.StoreId == storeId && a.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(a => a.Name, name)
                .SetProperty(a => a.Code, code)
                .SetProperty(a => a.SortOrder, dto.SortOrder)
                .SetProperty(a => a.AreaType, areaType)
                .SetProperty(a => a.IsActive, dto.IsActive)
                .SetProperty(a => a.UpdatedAt, now)
                .SetProperty(a => a.UpdatedBy, by));
        if (n == 0)
            return NotFound(AppResponse<AreaDto>.Fail("Không tìm thấy khu vực"));

        return Ok(AppResponse<AreaDto>.Success(
            new AreaDto(id, name, code, dto.SortOrder, areaType, dto.IsActive)));
    }

    [HttpDelete("service-areas/{id:guid}")]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "PosSell", "PosProducts")]
    public async Task<ActionResult<AppResponse<object>>> DeleteArea(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));

        var exists = await db.PosServiceAreas.AnyAsync(a =>
            a.Id == id && a.StoreId == storeId && a.Deleted == null);
        if (!exists)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy khu vực"));

        var resourceIds = await db.PosServiceResources
            .Where(r => r.AreaId == id && r.StoreId == storeId && r.Deleted == null)
            .Select(r => r.Id)
            .ToListAsync();

        if (resourceIds.Count > 0)
        {
            var busy = await db.PosResourceSessions.AnyAsync(s =>
                s.StoreId == storeId && s.Deleted == null
                && resourceIds.Contains(s.ResourceId)
                && (s.Status == PosResourceSessionStatus.Open
                    || s.Status == PosResourceSessionStatus.Paused));
            if (busy)
                return BadRequest(AppResponse<object>.Fail(
                    "Nhóm còn bàn đang dùng — thanh toán / đóng bàn trước khi xóa"));
        }

        var now = DateTime.UtcNow;
        var by = CurrentUserEmail;

        // Soft-delete toàn bộ bàn/ghế/phòng trong nhóm (trống).
        if (resourceIds.Count > 0)
        {
            await db.PosServiceResources
                .Where(r => resourceIds.Contains(r.Id) && r.StoreId == storeId && r.Deleted == null)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(r => r.Deleted, now)
                    .SetProperty(r => r.DeletedBy, by)
                    .SetProperty(r => r.UpdatedAt, now)
                    .SetProperty(r => r.UpdatedBy, by));
        }

        var n = await db.PosServiceAreas
            .Where(a => a.Id == id && a.StoreId == storeId && a.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(a => a.Deleted, now)
                .SetProperty(a => a.DeletedBy, by)
                .SetProperty(a => a.UpdatedAt, now)
                .SetProperty(a => a.UpdatedBy, by));

        if (n == 0)
            return NotFound(AppResponse<object>.Fail("Không xóa được khu vực"));

        return Ok(AppResponse<object>.Success(new { deleted = true, id }));
    }

    [HttpGet("service-resources")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<ResourceDto>>>> GetResources(
        [FromQuery] Guid? areaId = null,
        [FromQuery] bool heal = true)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<List<ResourceDto>>.Fail("Thiếu cửa hàng"));

        await ExpireOverdueReservationsAsync(storeId);

        var q = db.PosServiceResources.AsNoTracking()
            .Include(r => r.Area)
            .Where(r => r.StoreId == storeId && r.Deleted == null);
        var restricted = await GetRestrictedAreaIdsAsync(storeId);
        if (restricted != null)
            q = q.Where(r => restricted.Contains(r.AreaId));
        if (areaId.HasValue)
        {
            if (restricted != null && !restricted.Contains(areaId.Value))
                return Ok(AppResponse<List<ResourceDto>>.Success([]));
            q = q.Where(r => r.AreaId == areaId);
        }

        var resources = await q.OrderBy(r => r.SortOrder).ThenBy(r => r.Code).ToListAsync();
        var resourceIds = resources.Select(r => r.Id).ToList();
        var openSessions = await db.PosResourceSessions.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null
                && (s.Status == PosResourceSessionStatus.Open || s.Status == PosResourceSessionStatus.Paused)
                && resourceIds.Contains(s.ResourceId))
            .ToListAsync();

        // Heal orphan chỉ khi heal=true (mở sơ đồ / thao tác). Poll silent gửi heal=false.
        var orphanOrderIds = openSessions
            .Where(s => s.SaleOrderId.HasValue)
            .Select(s => s.SaleOrderId!.Value)
            .Distinct()
            .ToList();
        if (heal && (orphanOrderIds.Count > 0 || openSessions.Any(s => !s.SaleOrderId.HasValue)))
        {
            var draftAlive = await db.PosSaleOrders.AsNoTracking()
                .Where(o => orphanOrderIds.Contains(o.Id) && o.StoreId == storeId
                    && o.Deleted == null && o.Status == PosSaleOrderStatus.Draft)
                .Select(o => o.Id)
                .ToListAsync();
            var draftSet = draftAlive.ToHashSet();
            var orphanSessionIds = openSessions
                .Where(s => !s.SaleOrderId.HasValue || !draftSet.Contains(s.SaleOrderId.Value))
                .Select(s => s.Id)
                .ToList();
            if (orphanSessionIds.Count > 0)
            {
                var nowHeal = DateTime.UtcNow;
                var dirtyResourceIds = openSessions
                    .Where(s => orphanSessionIds.Contains(s.Id))
                    .Select(s => s.ResourceId)
                    .Distinct()
                    .ToList();
                // ExecuteUpdate — tránh lỗi tracking AsNoTracking khi heal.
                await db.PosResourceSessions
                    .Where(s => orphanSessionIds.Contains(s.Id) && s.StoreId == storeId
                        && s.Deleted == null
                        && (s.Status == PosResourceSessionStatus.Open
                            || s.Status == PosResourceSessionStatus.Paused))
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(x => x.Status, PosResourceSessionStatus.Closed)
                        .SetProperty(x => x.EndedAt, nowHeal)
                        .SetProperty(x => x.UpdatedAt, nowHeal)
                        .SetProperty(x => x.UpdatedBy, CurrentUserEmail));
                if (dirtyResourceIds.Count > 0)
                {
                    await db.PosServiceResources
                        .Where(r => dirtyResourceIds.Contains(r.Id) && r.StoreId == storeId
                            && r.Deleted == null)
                        .ExecuteUpdateAsync(r => r
                            .SetProperty(x => x.NeedsCleaning, false)
                            .SetProperty(x => x.UpdatedAt, nowHeal)
                            .SetProperty(x => x.UpdatedBy, CurrentUserEmail));
                }
                openSessions = await db.PosResourceSessions.AsNoTracking()
                    .Where(s => s.StoreId == storeId && s.Deleted == null
                        && (s.Status == PosResourceSessionStatus.Open || s.Status == PosResourceSessionStatus.Paused)
                        && resourceIds.Contains(s.ResourceId))
                    .ToListAsync();
                resources = await q.OrderBy(r => r.SortOrder).ThenBy(r => r.Code).ToListAsync();
            }
        }

        // Ưu tiên phiên đã xin tạm tính — tránh chọn nhầm phiên mới hơn chưa gắn cờ.
        var openByResource = openSessions.GroupBy(s => s.ResourceId)
            .ToDictionary(
                g => g.Key,
                g => g.OrderByDescending(x => x.BillRequested)
                    .ThenByDescending(x => x.StartedAt)
                    .First());

        var orderIds = openByResource.Values
            .Where(s => s.SaleOrderId.HasValue)
            .Select(s => s.SaleOrderId!.Value)
            .Distinct()
            .ToList();
        // Chỉ meta đơn Draft còn sống — đơn đã TT không được hiện Occupied.
        var orderMeta = orderIds.Count == 0
            ? new Dictionary<Guid, (string OrderNo, decimal Subtotal, int LineCount, int PendingKitchen,
                string? LockedByDeviceId, string? LockedByDeviceName, string? LockedByDisplayName,
                DateTime? LockExpiresAt, DateTime? LockedAt)>()
            : await db.PosSaleOrders.AsNoTracking()
                .Where(o => orderIds.Contains(o.Id) && o.StoreId == storeId
                    && o.Deleted == null && o.Status == PosSaleOrderStatus.Draft)
                .Select(o => new
                {
                    o.Id,
                    o.OrderNo,
                    Subtotal = o.Lines.Where(l => l.Deleted == null).Sum(l => l.LineTotal),
                    LineCount = o.Lines.Count(l => l.Deleted == null),
                    PendingKitchen = o.Lines.Count(l =>
                        l.Deleted == null && (l.Qty - l.KitchenSentQty) > 0.0001m),
                    o.LockedByDeviceId,
                    o.LockedByDeviceName,
                    o.LockedByDisplayName,
                    o.LockExpiresAt,
                    o.LockedAt,
                })
                .ToDictionaryAsync(
                    x => x.Id,
                    x => (x.OrderNo, x.Subtotal, x.LineCount, x.PendingKitchen,
                        x.LockedByDeviceId, x.LockedByDeviceName, x.LockedByDisplayName,
                        x.LockExpiresAt, x.LockedAt));

        // Draft mồ côi trên bàn (không phải đơn phiên hiện tại) — tránh hiện Holding giả.
        // Không lọc theo còn món: bàn vừa claim (chưa chọn món) vẫn phải lộ khóa ngay,
        // nếu không máy khác chỉ thấy «đang sửa» sau khi có món đầu tiên.
        var orphanDraftMeta = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null
                && o.Status == PosSaleOrderStatus.Draft
                && o.ServiceResourceId != null
                && resourceIds.Contains(o.ServiceResourceId.Value)
                && (o.Lines.Any(l => l.Deleted == null) || o.LockExpiresAt != null))
            .Select(o => new
            {
                ResourceId = o.ServiceResourceId!.Value,
                o.Id,
                o.OrderNo,
                LineCount = o.Lines.Count(l => l.Deleted == null),
                Subtotal = o.Lines.Where(l => l.Deleted == null).Sum(l => l.LineTotal),
                PendingKitchen = o.Lines.Count(l =>
                    l.Deleted == null && (l.Qty - l.KitchenSentQty) > 0.0001m),
                o.LockedByDeviceId,
                o.LockedByDeviceName,
                o.LockedByDisplayName,
                o.LockExpiresAt,
                o.LockedAt,
            })
            .ToListAsync();
        var orphanByResource = orphanDraftMeta
            .GroupBy(x => x.ResourceId)
            .ToDictionary(
                g => g.Key,
                g => g.OrderByDescending(x => x.LineCount).First());

        // Phiên còn Open nhưng đơn không còn Draft → bỏ khỏi map (không hiện đang dùng).
        foreach (var kv in openByResource.ToList())
        {
            var sess = kv.Value;
            if (!sess.SaleOrderId.HasValue) continue;
            if (!orderMeta.ContainsKey(sess.SaleOrderId.Value))
                openByResource.Remove(kv.Key);
        }

        var reservations = await db.PosResourceReservations.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null
                && x.Status == PosResourceReservationStatus.Booked
                && resourceIds.Contains(x.ResourceId))
            .OrderByDescending(x => x.ReservedAt)
            .ToListAsync();

        // Heal: classic / timed đang chồng phiên → Seated. Không đụng lịch timed tương lai.
        if (reservations.Count > 0)
        {
            var bookResourceIds = reservations.Select(b => b.ResourceId).Distinct().ToList();
            var sessionsAfterBook = await db.PosResourceSessions.AsNoTracking()
                .Where(s => bookResourceIds.Contains(s.ResourceId) && s.Deleted == null)
                .Select(s => new { s.ResourceId, s.StartedAt })
                .ToListAsync();
            var nowHealBook = DateTime.UtcNow;
            var staleIds = reservations
                .Where(b => sessionsAfterBook.Any(s =>
                    s.ResourceId == b.ResourceId
                    && ReservationConflictsWithLiveSession(b, s.StartedAt, nowHealBook)))
                .Select(b => b.Id)
                .ToList();
            if (staleIds.Count > 0)
            {
                await db.PosResourceReservations
                    .Where(x => staleIds.Contains(x.Id) && x.Deleted == null
                        && x.Status == PosResourceReservationStatus.Booked)
                    .ExecuteUpdateAsync(s => s
                        .SetProperty(x => x.Status, PosResourceReservationStatus.Seated)
                        .SetProperty(x => x.UpdatedAt, nowHealBook)
                        .SetProperty(x => x.UpdatedBy, CurrentUserEmail)
                        .SetProperty(x => x.Deleted, nowHealBook));
                reservations = reservations.Where(b => !staleIds.Contains(b.Id)).ToList();
            }
        }

        var nowFloor = DateTime.UtcNow;
        var reserveByResource = reservations.GroupBy(x => x.ResourceId)
            .ToDictionary(g => g.Key, g => PickFloorBooking(g, nowFloor)!);

        var list = resources.Select(r =>
        {
            openByResource.TryGetValue(r.Id, out var sess);
            reserveByResource.TryGetValue(r.Id, out var booking);

            var elapsed = 0;
            decimal subtotal = 0;
            var lineCount = 0;
            var pendingKitchen = 0;
            string? orderNo = null;
            string? lockedByDeviceId = null;
            string? lockedByDeviceName = null;
            string? lockedByDisplayName = null;
            DateTime? lockExpiresAt = null;
            DateTime? lockedAt = null;
            Guid? displayOrderId = sess?.SaleOrderId;
            if (sess != null)
            {
                elapsed = PosServiceBillingHelper.CalcElapsedMinutes(
                    sess.StartedAt,
                    null,
                    sess.AccumulatedPauseMinutes,
                    sess.Status == PosResourceSessionStatus.Paused ? sess.PausedAt : null);
                if (sess.SaleOrderId.HasValue &&
                    orderMeta.TryGetValue(sess.SaleOrderId.Value, out var meta))
                {
                    orderNo = meta.OrderNo;
                    subtotal = meta.Subtotal;
                    lineCount = meta.LineCount;
                    pendingKitchen = meta.PendingKitchen;
                    lockedByDeviceId = meta.LockedByDeviceId;
                    lockedByDeviceName = meta.LockedByDeviceName;
                    lockedByDisplayName = meta.LockedByDisplayName;
                    lockExpiresAt = meta.LockExpiresAt;
                    lockedAt = meta.LockedAt;
                }
            }

            // Đơn mồ côi còn món trên bàn nhưng phiên đang trống → hiện Occupied đúng sự thật.
            // sessHasOrderMeta=false (phiên không gắn đơn / đơn không resolve được) → không có gì
            // để bảo vệ, lấy khóa của mồ côi luôn kể cả khi mồ côi chưa có món (mới Lấy quyền).
            var sessHasOrderMeta = sess?.SaleOrderId.HasValue == true
                && orderMeta.ContainsKey(sess.SaleOrderId.Value);
            if (orphanByResource.TryGetValue(r.Id, out var orphan)
                && (sess == null || sess.SaleOrderId != orphan.Id)
                && (!sessHasOrderMeta || orphan.LineCount > lineCount))
            {
                lineCount = orphan.LineCount;
                subtotal = orphan.Subtotal;
                pendingKitchen = Math.Max(pendingKitchen, orphan.PendingKitchen);
                orderNo ??= orphan.OrderNo;
                displayOrderId ??= orphan.Id;
                lockedByDeviceId = orphan.LockedByDeviceId;
                lockedByDeviceName = orphan.LockedByDeviceName;
                lockedByDisplayName = orphan.LockedByDisplayName;
                lockExpiresAt = orphan.LockExpiresAt;
                lockedAt = orphan.LockedAt;
            }
            else if (displayOrderId == null
                     && orphanByResource.TryGetValue(r.Id, out var orphanOnly)
                     && orphanOnly.LineCount > 0)
            {
                displayOrderId = orphanOnly.Id;
            }

            // Khóa hết TTL hoặc heartbeat cũ → «tạm rời», không hiện «đang sửa».
            var nowUtc = DateTime.UtcNow;
            var tableSessionOpen =
                IsActiveTableEdit(lockExpiresAt, lockedAt, nowUtc);
            if (!tableSessionOpen)
            {
                lockedByDeviceId = null;
                lockedByDeviceName = null;
                lockedByDisplayName = null;
                lockExpiresAt = null;
            }

            var preOrderCount = 0;
            if (!string.IsNullOrWhiteSpace(booking?.PreOrderJson))
            {
                try
                {
                    using var doc = System.Text.Json.JsonDocument.Parse(booking.PreOrderJson);
                    if (doc.RootElement.ValueKind == System.Text.Json.JsonValueKind.Array)
                        preOrderCount = doc.RootElement.GetArrayLength();
                }
                catch { /* ignore */ }
            }

            string status;
            if (sess == null && booking != null && lineCount <= 0) status = "Reserved";
            else if (sess == null && lineCount <= 0) status = "Free";
            else if (sess == null && lineCount > 0) status = "Occupied"; // draft mồ côi còn món
            else if (sess!.Status == PosResourceSessionStatus.Paused) status = "Paused";
            else if (sess.BillRequested) status = "BillRequested";
            else if (lineCount <= 0 && !tableSessionOpen) status = "Parked";
            else if (lineCount <= 0) status = "Holding";
            else status = "Occupied";

            var hasParkedBill = sess != null && !tableSessionOpen
                && status is "Parked" or "Occupied";

            return new ResourceDto(
                r.Id, r.AreaId, r.Area?.Name ?? "", r.Code, r.Name,
                r.ResourceKind.ToString(), r.Capacity, r.SortOrder, r.DefaultHourlyRate,
                r.IsActive,
                status,
                sess?.Id, displayOrderId ?? sess?.SaleOrderId, sess?.StartedAt,
                elapsed, subtotal, lineCount, pendingKitchen,
                sess?.GuestCount ?? booking?.GuestCount ?? 0,
                sess?.BillRequested ?? false,
                r.NeedsCleaning,
                orderNo,
                r.LayoutX, r.LayoutY, r.LayoutW, r.LayoutH,
                booking?.Id, booking?.CustomerName, booking?.Phone,
                booking?.GuestCount ?? 0, preOrderCount,
                booking?.ReservedUntil,
                lockedByDeviceId, lockedByDeviceName, lockedByDisplayName, lockExpiresAt,
                tableSessionOpen, hasParkedBill,
                sess?.AccumulatedPauseMinutes ?? 0,
                sess?.Status == PosResourceSessionStatus.Paused ? sess.PausedAt : null,
                r.DefaultServiceProductId,
                booking?.DepositPaid ?? 0,
                booking?.DepositAmount ?? 0,
                booking?.DepositStatus.ToString());
        }).ToList();

        return Ok(AppResponse<List<ResourceDto>>.Success(list));
    }

    [HttpPost("service-resources")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> CreateResource([FromBody] ResourceSaveDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (dto == null)
            return BadRequest(AppResponse<object>.Fail("Thiếu dữ liệu"));
        var areaOk = await db.PosServiceAreas.AnyAsync(a =>
            a.Id == dto.AreaId && a.StoreId == storeId && a.Deleted == null);
        if (!areaOk) return BadRequest(AppResponse<object>.Fail("Khu vực không hợp lệ"));

        var code = dto.Code?.Trim() ?? "";
        var name = dto.Name?.Trim() ?? "";
        if (code.Length == 0 || name.Length == 0)
            return BadRequest(AppResponse<object>.Fail("Mã và tên bắt buộc"));

        var dup = await db.PosServiceResources.AnyAsync(r =>
            r.StoreId == storeId && r.Code == code && r.Deleted == null);
        if (dup) return BadRequest(AppResponse<object>.Fail("Mã bàn/phòng đã tồn tại"));

        var kind = ParseResourceKind(dto.ResourceKind);
        Guid? defaultServiceProductId = dto.DefaultServiceProductId is null
            || dto.DefaultServiceProductId == Guid.Empty
            ? null
            : dto.DefaultServiceProductId;
        if (defaultServiceProductId.HasValue)
        {
            var productOk = await db.PosProducts.AnyAsync(p =>
                p.Id == defaultServiceProductId && p.StoreId == storeId && p.Deleted == null
                && p.ProductType == PosProductType.Service
                && (p.ServiceBillingMode == PosServiceBillingMode.PerHour
                    || p.ServiceBillingMode == PosServiceBillingMode.PerMinute));
            if (!productOk)
                return BadRequest(AppResponse<object>.Fail(
                    "SP tính giờ của bàn không hợp lệ (cần dịch vụ PerHour/PerMinute)"));
        }

        var entity = new PosServiceResource
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            AreaId = dto.AreaId,
            Code = code,
            Name = name,
            ResourceKind = kind,
            Capacity = Math.Max(1, dto.Capacity),
            SortOrder = dto.SortOrder,
            DefaultHourlyRate = dto.DefaultHourlyRate,
            DefaultServiceProductId = defaultServiceProductId,
            IsActive = dto.IsActive,
            LayoutX = dto.LayoutX,
            LayoutY = dto.LayoutY,
            LayoutW = dto.LayoutW ?? 120,
            LayoutH = dto.LayoutH ?? 100,
            CreatedBy = CurrentUserEmail,
        };
        db.PosServiceResources.Add(entity);
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id = entity.Id, name = entity.Name, code = entity.Code }));
    }

    [HttpPut("service-resources/{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> UpdateResource(Guid id, [FromBody] ResourceSaveDto? dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (dto == null)
            return BadRequest(AppResponse<object>.Fail("Thiếu dữ liệu"));

        var areaOk = await db.PosServiceAreas.AnyAsync(a =>
            a.Id == dto.AreaId && a.StoreId == storeId && a.Deleted == null);
        if (!areaOk) return BadRequest(AppResponse<object>.Fail("Khu vực không hợp lệ"));

        var code = dto.Code?.Trim() ?? "";
        var name = dto.Name?.Trim() ?? "";
        if (code.Length == 0 || name.Length == 0)
            return BadRequest(AppResponse<object>.Fail("Mã và tên bắt buộc"));

        var exists = await db.PosServiceResources.AnyAsync(r =>
            r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (!exists) return NotFound(AppResponse<object>.Fail("Không tìm thấy"));

        var dup = await db.PosServiceResources.AnyAsync(r =>
            r.StoreId == storeId && r.Code == code && r.Id != id && r.Deleted == null);
        if (dup) return BadRequest(AppResponse<object>.Fail("Mã bàn/phòng đã tồn tại"));

        var kind = ParseResourceKind(dto.ResourceKind);
        var capacity = Math.Max(1, dto.Capacity);
        var now = DateTime.UtcNow;
        var by = CurrentUserEmail;
        var layoutW = dto.LayoutW ?? 120;
        var layoutH = dto.LayoutH ?? 100;
        Guid? defaultServiceProductId = dto.DefaultServiceProductId is null
            || dto.DefaultServiceProductId == Guid.Empty
            ? null
            : dto.DefaultServiceProductId;
        if (defaultServiceProductId.HasValue)
        {
            var productOk = await db.PosProducts.AnyAsync(p =>
                p.Id == defaultServiceProductId && p.StoreId == storeId && p.Deleted == null
                && p.ProductType == PosProductType.Service
                && (p.ServiceBillingMode == PosServiceBillingMode.PerHour
                    || p.ServiceBillingMode == PosServiceBillingMode.PerMinute));
            if (!productOk)
                return BadRequest(AppResponse<object>.Fail(
                    "SP tính giờ của bàn không hợp lệ (cần dịch vụ PerHour/PerMinute)"));
        }

        // ExecuteUpdate — ghi thẳng DB (cùng cách đã sửa layoutX/Y).
        var n = await db.PosServiceResources
            .Where(r => r.Id == id && r.StoreId == storeId && r.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(r => r.AreaId, dto.AreaId)
                .SetProperty(r => r.Code, code)
                .SetProperty(r => r.Name, name)
                .SetProperty(r => r.ResourceKind, kind)
                .SetProperty(r => r.Capacity, capacity)
                .SetProperty(r => r.SortOrder, dto.SortOrder)
                .SetProperty(r => r.DefaultHourlyRate, dto.DefaultHourlyRate)
                .SetProperty(r => r.DefaultServiceProductId, defaultServiceProductId)
                .SetProperty(r => r.IsActive, dto.IsActive)
                .SetProperty(r => r.LayoutW, layoutW)
                .SetProperty(r => r.LayoutH, layoutH)
                .SetProperty(r => r.UpdatedAt, now)
                .SetProperty(r => r.UpdatedBy, by));

        if (n == 0)
            return NotFound(AppResponse<object>.Fail("Không cập nhật được"));

        if (dto.LayoutX.HasValue)
        {
            var lx = dto.LayoutX;
            await db.PosServiceResources
                .Where(r => r.Id == id && r.StoreId == storeId && r.Deleted == null)
                .ExecuteUpdateAsync(s => s.SetProperty(r => r.LayoutX, lx));
        }
        if (dto.LayoutY.HasValue)
        {
            var ly = dto.LayoutY;
            await db.PosServiceResources
                .Where(r => r.Id == id && r.StoreId == storeId && r.Deleted == null)
                .ExecuteUpdateAsync(s => s.SetProperty(r => r.LayoutY, ly));
        }

        return Ok(AppResponse<object>.Success(new { id, name, code, updated = n }));
    }

    [HttpDelete("service-resources/{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<object>>> DeleteResource(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));

        var open = await db.PosResourceSessions.AnyAsync(s =>
            s.ResourceId == id && s.StoreId == storeId
            && (s.Status == PosResourceSessionStatus.Open || s.Status == PosResourceSessionStatus.Paused)
            && s.Deleted == null);
        if (open) return BadRequest(AppResponse<object>.Fail("Đang có phiên mở — đóng trước khi xóa"));

        var now = DateTime.UtcNow;
        var by = CurrentUserEmail;
        var n = await db.PosServiceResources
            .Where(r => r.Id == id && r.StoreId == storeId && r.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(r => r.Deleted, now)
                .SetProperty(r => r.DeletedBy, by)
                .SetProperty(r => r.UpdatedAt, now)
                .SetProperty(r => r.UpdatedBy, by));
        if (n == 0)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy"));

        return Ok(AppResponse<object>.Success(new { deleted = true, id }));
    }

    // ── Sessions ─────────────────────────────────────────────────────────────

    public record OpenSessionDto(
        Guid ResourceId,
        Guid? CustomerId = null,
        string? Note = null,
        string? DeviceId = null,
        string? DeviceName = null,
        int? GuestCount = null);
    public record SessionDto(
        Guid Id, Guid ResourceId, string ResourceCode, string ResourceName,
        Guid? SaleOrderId, string? OrderNo, Guid? CustomerId, string? CustomerName,
        DateTime StartedAt, DateTime? EndedAt, string Status, int ElapsedMinutes, string? Note);

    [HttpPost("resource-sessions/open")]
    [RequireAnyModulePermission(ModulePermissionAction.Create, "PosSell", "PosProducts")]
    public async Task<ActionResult<AppResponse<object>>> OpenSession([FromBody] OpenSessionDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (await RequireResourcesEnabledAsync(storeId) is { } denied)
            return denied;
        var resource = await db.PosServiceResources
            .AsTracking()
            .FirstOrDefaultAsync(r => r.Id == dto.ResourceId && r.StoreId == storeId
                && r.Deleted == null && r.IsActive);
        if (resource == null)
            return BadRequest(AppResponse<object>.Fail("Bàn/phòng không hợp lệ"));
        if (!await CanOperateAreaAsync(storeId, resource.AreaId))
            return BadRequest(AppResponse<object>.Fail("Bạn không được phép mở bàn ở khu vực này"));

        // Classic / timed đang diễn ra → Seated. Giữ nguyên lịch timed tương lai trên ghế.
        await ClearBookedReservationsOnResourceAsync(storeId, resource.Id, asSeated: true);

        var existing = await db.PosResourceSessions
            .AsTracking()
            .FirstOrDefaultAsync(s =>
                s.ResourceId == dto.ResourceId
                && (s.Status == PosResourceSessionStatus.Open || s.Status == PosResourceSessionStatus.Paused)
                && s.Deleted == null);
        if (existing != null)
        {
            PosSaleOrder? existingOrder = null;
            if (existing.SaleOrderId.HasValue)
            {
                existingOrder = await db.PosSaleOrders
                    .AsTracking()
                    .FirstOrDefaultAsync(o => o.Id == existing.SaleOrderId && o.StoreId == storeId);
            }

            // Đơn đã thanh toán/hủy → đóng phiên orphan rồi mở mới bên dưới.
            if (existingOrder == null
                || existingOrder.Deleted != null
                || existingOrder.Status != PosSaleOrderStatus.Draft)
            {
                existing.Status = PosResourceSessionStatus.Closed;
                existing.EndedAt = DateTime.UtcNow;
                existing.UpdatedAt = DateTime.UtcNow;
                existing.UpdatedBy = CurrentUserEmail;
                resource.NeedsCleaning = false;
                resource.UpdatedAt = DateTime.UtcNow;
                await db.SaveChangesAsync();
            }
            else
            {
                var lineCount = await db.PosSaleOrderLines.CountAsync(l =>
                    l.SaleOrderId == existing.SaleOrderId && l.StoreId == storeId && l.Deleted == null);

                // Phiên trống (Holding) — nếu còn draft mồ côi có món trên bàn → gắn lại đơn đó.
                if (lineCount <= 0)
                {
                    var orphanBusy = await db.PosSaleOrders
                        .AsTracking()
                        .Where(o => o.StoreId == storeId && o.Deleted == null
                            && o.Status == PosSaleOrderStatus.Draft
                            && o.ServiceResourceId == resource.Id
                            && o.Id != existingOrder!.Id
                            && o.Lines.Any(l => l.Deleted == null))
                        .OrderByDescending(o => o.UpdatedAt ?? o.CreatedAt)
                        .FirstOrDefaultAsync();
                    if (orphanBusy != null)
                    {
                        var orphanActor = new PosDraftLockHelper.LockActor(
                            CurrentUserId, EmployeeId,
                            string.IsNullOrWhiteSpace(CurrentUserEmail)
                                ? CurrentUserId.ToString("N")[..8]
                                : CurrentUserEmail!,
                            dto.DeviceId, dto.DeviceName);
                        if (PosDraftLockHelper.IsLockActive(orphanBusy)
                            && !PosDraftLockHelper.IsHeldBy(orphanBusy, orphanActor))
                        {
                            var who = orphanBusy.LockedByDisplayName ?? "máy khác";
                            return BadRequest(AppResponse<object>.Fail(
                                $"Bàn đang được mở bởi {who} — lấy quyền trên máy kia hoặc đợi nhả khóa"));
                        }

                        // Soft-delete draft Holding trống, gắn phiên vào đơn còn món.
                        var nowHeal = DateTime.UtcNow;
                        existingOrder.Deleted = nowHeal;
                        existingOrder.DeletedBy = CurrentUserEmail;
                        existingOrder.UpdatedAt = nowHeal;
                        existingOrder.ServiceResourceId = null;
                        existingOrder.ResourceSessionId = null;

                        existing.SaleOrderId = orphanBusy.Id;
                        existing.UpdatedAt = nowHeal;
                        orphanBusy.ResourceSessionId = existing.Id;
                        orphanBusy.ServiceResourceId = resource.Id;
                        orphanBusy.UpdatedAt = nowHeal;
                        var orphanLines = await db.PosSaleOrderLines.CountAsync(l =>
                            l.SaleOrderId == orphanBusy.Id && l.StoreId == storeId && l.Deleted == null);
                        PosDraftLockHelper.TryAcquire(
                            orphanBusy, orphanActor, force: false, bumpVersion: false,
                            lineCount: orphanLines);
                        await db.SaveChangesAsync();
                        return Ok(AppResponse<object>.Success(new
                        {
                            sessionId = existing.Id,
                            saleOrderId = orphanBusy.Id,
                            orderNo = orphanBusy.OrderNo,
                            resourceId = resource.Id,
                            resourceCode = resource.Code,
                            resourceName = resource.Name,
                            startedAt = existing.StartedAt,
                            guestCount = existing.GuestCount,
                            resumedOrphan = true,
                        }));
                    }

                    var resumeActor = new PosDraftLockHelper.LockActor(
                        CurrentUserId, EmployeeId,
                        string.IsNullOrWhiteSpace(CurrentUserEmail)
                            ? CurrentUserId.ToString("N")[..8]
                            : CurrentUserEmail!,
                        dto.DeviceId, dto.DeviceName);
                    if (existingOrder != null
                        && PosDraftLockHelper.IsLockActive(existingOrder)
                        && !PosDraftLockHelper.IsHeldBy(existingOrder, resumeActor))
                    {
                        var who = existingOrder.LockedByDisplayName ?? "máy khác";
                        return BadRequest(AppResponse<object>.Fail(
                            $"Bàn đang được mở bởi {who} — lấy quyền trên máy kia hoặc đợi nhả khóa"));
                    }

                    var nowResume = DateTime.UtcNow;
                    if ((nowResume - existing.StartedAt).TotalMinutes > 5)
                    {
                        existing.StartedAt = nowResume;
                        existing.AccumulatedPauseMinutes = 0;
                        existing.UpdatedAt = nowResume;
                        if (existingOrder != null)
                        {
                            existingOrder.ServiceStartedAt = nowResume;
                            existingOrder.UpdatedAt = nowResume;
                        }
                    }
                    if (existingOrder != null)
                    {
                        PosDraftLockHelper.TryAcquire(
                            existingOrder, resumeActor, force: false, bumpVersion: false, lineCount: 0);
                        await TryAutoAddHourlyLineAsync(storeId, resource, existingOrder, existing.StartedAt);
                    }
                    await db.SaveChangesAsync();
                    return Ok(AppResponse<object>.Success(new
                    {
                        sessionId = existing.Id,
                        saleOrderId = existing.SaleOrderId,
                        orderNo = existingOrder?.OrderNo,
                        resourceId = resource.Id,
                        resourceCode = resource.Code,
                        resourceName = resource.Name,
                        startedAt = existing.StartedAt,
                        guestCount = existing.GuestCount,
                        resumedEmpty = true,
                    }));
                }

                return BadRequest(AppResponse<object>.Fail("Bàn/phòng đang được sử dụng"));
            }
        }

        try
        {
            await using var tx = await db.Database.BeginTransactionAsync();
            var now = DateTime.UtcNow;

            // Draft mồ côi còn món trên bàn (đóng phiên giữ đơn / race) → mở lại đơn đó, không tạo Holding trống.
            var orphanWithLines = await db.PosSaleOrders
                .AsTracking()
                .Where(o => o.StoreId == storeId && o.Deleted == null
                    && o.Status == PosSaleOrderStatus.Draft
                    && o.ServiceResourceId == resource.Id
                    && o.Lines.Any(l => l.Deleted == null))
                .OrderByDescending(o => o.UpdatedAt ?? o.CreatedAt)
                .FirstOrDefaultAsync();
            if (orphanWithLines != null)
            {
                var resumeActor = new PosDraftLockHelper.LockActor(
                    CurrentUserId, EmployeeId,
                    string.IsNullOrWhiteSpace(CurrentUserEmail)
                        ? CurrentUserId.ToString("N")[..8]
                        : CurrentUserEmail!,
                    dto.DeviceId, dto.DeviceName);
                if (PosDraftLockHelper.IsLockActive(orphanWithLines)
                    && !PosDraftLockHelper.IsHeldBy(orphanWithLines, resumeActor))
                {
                    var who = orphanWithLines.LockedByDisplayName ?? "máy khác";
                    return BadRequest(AppResponse<object>.Fail(
                        $"Bàn đang được mở bởi {who} — lấy quyền trên máy kia hoặc đợi nhả khóa"));
                }

                var orphanLineCount = await db.PosSaleOrderLines.CountAsync(l =>
                    l.SaleOrderId == orphanWithLines.Id && l.StoreId == storeId && l.Deleted == null);
                PosDraftLockHelper.TryAcquire(
                    orphanWithLines, resumeActor, force: false, bumpVersion: false,
                    lineCount: orphanLineCount);

                var orphanSession = new PosResourceSession
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    ResourceId = resource.Id,
                    SaleOrderId = orphanWithLines.Id,
                    CustomerId = orphanWithLines.CustomerId ?? dto.CustomerId,
                    StartedAt = orphanWithLines.ServiceStartedAt ?? now,
                    Status = PosResourceSessionStatus.Open,
                    GuestCount = ResolveOpenGuestCount(dto.GuestCount),
                    Note = dto.Note?.Trim(),
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                    CreatedAt = now,
                };
                db.PosResourceSessions.Add(orphanSession);
                await db.SaveChangesAsync();

                orphanWithLines.ResourceSessionId = orphanSession.Id;
                orphanWithLines.ServiceResourceId = resource.Id;
                orphanWithLines.UpdatedAt = now;
                await db.SaveChangesAsync();
                await tx.CommitAsync();

                return Ok(AppResponse<object>.Success(new
                {
                    sessionId = orphanSession.Id,
                    saleOrderId = orphanWithLines.Id,
                    orderNo = orphanWithLines.OrderNo,
                    resourceId = resource.Id,
                    resourceCode = resource.Code,
                    resourceName = resource.Name,
                    startedAt = orphanSession.StartedAt,
                    guestCount = orphanSession.GuestCount,
                    resumedOrphan = true,
                }));
            }

            var (orderNo, invoiceSlot) = await AllocateTableDraftNoAsync(storeId);

            // Bước 1: tạo Draft trước — không gắn ResourceSessionId (tránh vòng FK).
            var order = new PosSaleOrder
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                OrderNo = orderNo,
                InvoiceSlot = invoiceSlot,
                Status = PosSaleOrderStatus.Draft,
                PaymentMethod = "Tiền mặt",
                CustomerId = dto.CustomerId,
                CustomerName = "Bán cho người tiêu dùng",
                ServiceResourceId = resource.Id,
                ServiceStartedAt = now,
                SaleDate = now,
                SalesChannel = "Tại chỗ",
                IsActive = true,
                CreatedBy = CurrentUserEmail,
                CreatedAt = now,
            };
            var lockDisplay = CurrentUserEmail;
            if (string.IsNullOrWhiteSpace(lockDisplay))
                lockDisplay = CurrentUserId.ToString("N")[..8];
            PosDraftLockHelper.AssignOnCreate(
                order,
                new PosDraftLockHelper.LockActor(
                    CurrentUserId, EmployeeId, lockDisplay!, dto.DeviceId, dto.DeviceName));
            if (dto.CustomerId.HasValue)
            {
                var cust = await db.PosCustomers.AsNoTracking()
                    .FirstOrDefaultAsync(c => c.Id == dto.CustomerId && c.StoreId == storeId && c.Deleted == null);
                if (cust != null) order.CustomerName = cust.Name;
            }

            db.PosSaleOrders.Add(order);
            await db.SaveChangesAsync();

            // Bước 2: tạo phiên gắn đơn đã lưu.
            var session = new PosResourceSession
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                ResourceId = resource.Id,
                SaleOrderId = order.Id,
                CustomerId = dto.CustomerId,
                StartedAt = now,
                Status = PosResourceSessionStatus.Open,
                GuestCount = ResolveOpenGuestCount(dto.GuestCount),
                Note = dto.Note?.Trim(),
                IsActive = true,
                CreatedBy = CurrentUserEmail,
                CreatedAt = now,
            };
            db.PosResourceSessions.Add(session);
            await db.SaveChangesAsync();

            // Bước 3: cập nhật ngược ResourceSessionId trên đơn.
            order.ResourceSessionId = session.Id;
            order.UpdatedAt = now;
            await TryAutoAddHourlyLineAsync(storeId, resource, order, now);
            await db.SaveChangesAsync();
            await tx.CommitAsync();

            NotifyFloorChanged(storeId, "openSession",
                orderId: order.Id, resourceId: resource.Id, sessionId: session.Id);

            return Ok(AppResponse<object>.Success(new
            {
                sessionId = session.Id,
                saleOrderId = order.Id,
                orderNo = order.OrderNo,
                resourceId = resource.Id,
                resourceCode = resource.Code,
                resourceName = resource.Name,
                startedAt = session.StartedAt,
                guestCount = session.GuestCount,
            }));
        }
        catch (DbUpdateException ex)
        {
            var detail = ex.InnerException?.Message ?? ex.Message;
            // 23505 = unique_violation Postgres
            var msg = detail.Contains("23505", StringComparison.Ordinal)
                ? "Mã đơn tạm bị trùng — thử lại lần nữa"
                : "Không mở được bàn. Thử lại hoặc tải lại sơ đồ.";
            return BadRequest(AppResponse<object>.Fail(msg));
        }
    }

    /// <summary>
    /// Tự thêm SP tính giờ khi mở bàn trống (resource override → settings cửa hàng).
    /// Bỏ qua nếu đã có dòng timed hoặc chưa cấu hình / tắt hourly.
    /// </summary>
    async Task TryAutoAddHourlyLineAsync(
        Guid storeId, PosServiceResource resource, PosSaleOrder order, DateTime startedAt)
    {
        var settings = await db.PosStoreSellSettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);
        if (settings?.EnableHourlyBilling != true) return;

        var productId = resource.DefaultServiceProductId ?? settings.DefaultHourlyProductId;
        if (productId is null || productId == Guid.Empty) return;

        var lineProductIds = await db.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.SaleOrderId == order.Id && l.Deleted == null)
            .Select(l => l.ProductId)
            .ToListAsync();
        if (lineProductIds.Count > 0)
        {
            var hasTimed = await db.PosProducts.AsNoTracking().AnyAsync(p =>
                lineProductIds.Contains(p.Id)
                && p.ProductType == PosProductType.Service
                && (p.ServiceBillingMode == PosServiceBillingMode.PerHour
                    || p.ServiceBillingMode == PosServiceBillingMode.PerMinute));
            if (hasTimed) return;
        }

        var product = await db.PosProducts.AsNoTracking().FirstOrDefaultAsync(p =>
            p.Id == productId && p.StoreId == storeId && p.Deleted == null && p.IsActive
            && p.ProductType == PosProductType.Service
            && (p.ServiceBillingMode == PosServiceBillingMode.PerHour
                || p.ServiceBillingMode == PosServiceBillingMode.PerMinute));
        if (product == null) return;

        var unitPrice = product.BasePrice;
        if (unitPrice <= 0 && resource.DefaultHourlyRate is > 0)
            unitPrice = resource.DefaultHourlyRate.Value;

        var billable = PosServiceBillingHelper.CalcBillableMinutes(
            0,
            product.ServiceBillingMode,
            product.MinBillMinutes,
            product.BillRoundMinutes,
            product.GraceMinutes,
            product.RoundAfterMinutes);
        var qty = PosServiceBillingHelper.CalcBillableQty(
            product.ServiceBillingMode, billable, 1m);
        var lineTotal = PosServiceBillingHelper.CalcLineTotal(qty, unitPrice, 0);

        db.PosSaleOrderLines.Add(new PosSaleOrderLine
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            SaleOrderId = order.Id,
            ProductId = product.Id,
            ProductName = product.Name,
            UnitName = product.BaseUnitName,
            Qty = qty,
            UnitPrice = unitPrice,
            DiscountAmount = 0,
            LineTotal = lineTotal,
            DurationMinutes = billable,
            BillableMinutes = billable,
            ServiceStartedAt = startedAt,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
            CreatedAt = DateTime.UtcNow,
        });
        order.SubTotal += lineTotal;
        order.UpdatedAt = DateTime.UtcNow;
    }

    [HttpPost("resource-sessions/{id:guid}/close")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> CloseSession(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        var session = await db.PosResourceSessions
            .AsTracking()
            .FirstOrDefaultAsync(s => s.Id == id && s.StoreId == storeId && s.Deleted == null);
        if (session == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy phiên"));
        if (session.Status == PosResourceSessionStatus.Closed)
            return Ok(AppResponse<object>.Success(new { alreadyClosed = true, saleOrderId = session.SaleOrderId }));

        session.Status = PosResourceSessionStatus.Closed;
        session.EndedAt = DateTime.UtcNow;
        session.UpdatedAt = DateTime.UtcNow;
        session.UpdatedBy = CurrentUserEmail;

        if (session.SaleOrderId.HasValue)
        {
            var order = await db.PosSaleOrders
                .AsTracking()
                .FirstOrDefaultAsync(o => o.Id == session.SaleOrderId && o.StoreId == storeId);
            if (order != null)
            {
                order.ServiceEndedAt = session.EndedAt;
                order.UpdatedAt = DateTime.UtcNow;
                order.UpdatedBy = CurrentUserEmail;
            }
        }

        var hadLines = session.SaleOrderId.HasValue && await db.PosSaleOrderLines.AnyAsync(l =>
            l.SaleOrderId == session.SaleOrderId && l.StoreId == storeId && l.Deleted == null);

        var res = await db.PosServiceResources
            .AsTracking()
            .FirstOrDefaultAsync(r => r.Id == session.ResourceId && r.StoreId == storeId);
        if (res != null)
        {
            // Thanh toán xong → bàn trống dùng ngay (không «cần dọn»).
            res.NeedsCleaning = false;
            res.UpdatedAt = DateTime.UtcNow;
        }

        // Đóng bàn trống: soft-delete draft BAN* để không để đơn mồ côi.
        if (!hadLines && session.SaleOrderId.HasValue)
        {
            var orphanDraft = await db.PosSaleOrders
                .AsTracking()
                .FirstOrDefaultAsync(o => o.Id == session.SaleOrderId && o.StoreId == storeId
                    && o.Deleted == null && o.Status == PosSaleOrderStatus.Draft);
            if (orphanDraft != null)
            {
                orphanDraft.Deleted = DateTime.UtcNow;
                orphanDraft.DeletedBy = CurrentUserEmail;
                orphanDraft.UpdatedAt = DateTime.UtcNow;
                orphanDraft.UpdatedBy = CurrentUserEmail;
                PosDraftLockHelper.Release(orphanDraft);
            }
        }

        await db.SaveChangesAsync();
        var elapsed = PosServiceBillingHelper.CalcElapsedMinutes(session.StartedAt, session.EndedAt);
        NotifyFloorChanged(storeId, "closeSession",
            orderId: session.SaleOrderId, resourceId: session.ResourceId, sessionId: session.Id);
        return Ok(AppResponse<object>.Success(new
        {
            sessionId = session.Id,
            saleOrderId = session.SaleOrderId,
            endedAt = session.EndedAt,
            elapsedMinutes = elapsed,
            needsCleaning = hadLines,
        }));
    }

    /// <summary>
    /// Trả bàn về trống: đóng mọi phiên Open/Paused + soft-delete mọi draft trống gắn bàn.
    /// Dùng ExecuteUpdate để chắc chắn ghi DB (tránh tracker stale).
    /// </summary>
    [HttpPost("service-resources/{id:guid}/free")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> FreeResource(Guid id)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));

        var resource = await db.PosServiceResources.AsNoTracking()
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (resource == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy bàn/phòng"));

        // Chặn trả trống khi còn draft có món — tránh mất bàn trên sơ đồ trong khi đơn vẫn còn dòng.
        var busyDrafts = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null
                && o.Status == PosSaleOrderStatus.Draft
                && o.ServiceResourceId == id
                && o.Lines.Any(l => l.Deleted == null))
            .Select(o => new { o.OrderNo, LineCount = o.Lines.Count(l => l.Deleted == null) })
            .Take(5)
            .ToListAsync();
        if (busyDrafts.Count > 0)
        {
            var detail = string.Join(", ",
                busyDrafts.Select(d =>
                    $"{(string.IsNullOrWhiteSpace(d.OrderNo) ? "Đơn tạm" : d.OrderNo)} ({d.LineCount} món)"));
            return BadRequest(AppResponse<object>.Fail(
                $"Bàn còn món — không trả trống được. Còn: {detail}. Mở bàn → thanh toán hoặc xóa món trước."));
        }

        var now = DateTime.UtcNow;
        var by = CurrentUserEmail;

        // 1) Đóng mọi phiên đang mở trên bàn (không phụ thuộc StoreId lệch).
        var closed = await db.PosResourceSessions
            .Where(s => s.ResourceId == id && s.Deleted == null
                && (s.Status == PosResourceSessionStatus.Open
                    || s.Status == PosResourceSessionStatus.Paused))
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.Status, PosResourceSessionStatus.Closed)
                .SetProperty(x => x.EndedAt, now)
                .SetProperty(x => x.UpdatedAt, now)
                .SetProperty(x => x.UpdatedBy, by));

        // 2) Soft-delete draft trống gắn bàn (kể cả đơn mồ côi không còn phiên).
        var emptyDraftIds = await db.PosSaleOrders
            .Where(o => o.StoreId == storeId && o.Deleted == null
                && o.Status == PosSaleOrderStatus.Draft
                && o.ServiceResourceId == id
                && !o.Lines.Any(l => l.Deleted == null))
            .Select(o => o.Id)
            .ToListAsync();

        var draftsRemoved = 0;
        if (emptyDraftIds.Count > 0)
        {
            draftsRemoved = await db.PosSaleOrders
                .Where(o => emptyDraftIds.Contains(o.Id) && o.StoreId == storeId)
                .ExecuteUpdateAsync(o => o
                    .SetProperty(x => x.Deleted, now)
                    .SetProperty(x => x.DeletedBy, by)
                    .SetProperty(x => x.UpdatedAt, now)
                    .SetProperty(x => x.UpdatedBy, by)
                    .SetProperty(x => x.ServiceEndedAt, now)
                    .SetProperty(x => x.LockedByUserId, (Guid?)null)
                    .SetProperty(x => x.LockedByEmployeeId, (Guid?)null)
                    .SetProperty(x => x.LockedByDeviceId, (string?)null)
                    .SetProperty(x => x.LockedByDeviceName, (string?)null)
                    .SetProperty(x => x.LockedByDisplayName, (string?)null)
                    .SetProperty(x => x.LockedAt, (DateTime?)null)
                    .SetProperty(x => x.LockExpiresAt, (DateTime?)null));
        }

        await db.PosServiceResources
            .Where(r => r.Id == id && r.StoreId == storeId && r.Deleted == null)
            .ExecuteUpdateAsync(r => r
                .SetProperty(x => x.NeedsCleaning, false)
                .SetProperty(x => x.UpdatedAt, now)
                .SetProperty(x => x.UpdatedBy, by));

        // 3) Xác nhận không còn phiên mở.
        var stillOpen = await db.PosResourceSessions.AsNoTracking()
            .AnyAsync(s => s.ResourceId == id && s.Deleted == null
                && (s.Status == PosResourceSessionStatus.Open
                    || s.Status == PosResourceSessionStatus.Paused));

        NotifyFloorChanged(storeId, "freeResource", resourceId: id);
        return Ok(AppResponse<object>.Success(new
        {
            resourceId = id,
            closedSessions = closed,
            draftsRemoved,
            occupancyStatus = stillOpen ? "Holding" : "Free",
            freed = !stillOpen,
        }));
    }

    [HttpGet("resource-sessions/open")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<SessionDto>>>> ListOpenSessions()
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<List<SessionDto>>.Fail("Thiếu cửa hàng"));
        var list = await db.PosResourceSessions.AsNoTracking()
            .Include(s => s.Resource)
            .Include(s => s.SaleOrder)
            .Include(s => s.Customer)
            .Where(s => s.StoreId == storeId && s.Deleted == null
                && s.Status == PosResourceSessionStatus.Open)
            .OrderBy(s => s.StartedAt)
            .ToListAsync();

        var dtos = list.Select(s => new SessionDto(
            s.Id, s.ResourceId, s.Resource?.Code ?? "", s.Resource?.Name ?? "",
            s.SaleOrderId, s.SaleOrder?.OrderNo, s.CustomerId, s.Customer?.Name ?? s.SaleOrder?.CustomerName,
            s.StartedAt, s.EndedAt, s.Status.ToString(),
            PosServiceBillingHelper.CalcElapsedMinutes(
                s.StartedAt, null, s.AccumulatedPauseMinutes,
                s.Status == PosResourceSessionStatus.Paused ? s.PausedAt : null),
            s.Note)).ToList();
        return Ok(AppResponse<List<SessionDto>>.Success(dtos));
    }

    /// <summary>
    /// Mã đơn tạm cho bàn/phòng — không dùng TMP01..TMP24 (xung đột slot bán hàng
    /// và bản ghi soft-delete vẫn giữ OrderNo trên unique index).
    /// </summary>
    async Task<(string OrderNo, int? InvoiceSlot)> AllocateTableDraftNoAsync(Guid storeId)
    {
        // Cùng format HĐ ngắn: HD + ddMMyyyy + 0001…1111 (reset theo ngày VN).
        var orderNo = await PosSaleStockHelper.NextOrderNoAsync(db, storeId);
        return (orderNo, null);
    }

    async Task<string> NextDraftOrderNoAsync(Guid storeId)
    {
        var today = DateTime.UtcNow.ToString("yyMMdd");
        var prefix = $"TMP{today}";
        var last = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.OrderNo.StartsWith(prefix))
            .OrderByDescending(o => o.OrderNo)
            .Select(o => o.OrderNo)
            .FirstOrDefaultAsync();
        var seq = 1;
        if (last != null && last.Length > prefix.Length
            && int.TryParse(last[prefix.Length..], out var n))
            seq = n + 1;
        return $"{prefix}{seq:D4}";
    }

    // ── Gym session packs ────────────────────────────────────────────────────

    public record SessionBalanceDto(
        Guid Id, Guid CustomerId, string CustomerName, Guid? ProductId, string PackageName,
        int TotalSessions, int RemainingSessions, DateTime? ExpiresAt);

    public record RedeemSessionDto(Guid BalanceId, int Sessions = 1, string? Note = null, Guid? SaleOrderId = null);

    [HttpGet("session-balances")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<SessionBalanceDto>>>> GetSessionBalances(
        [FromQuery] Guid? customerId = null)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<List<SessionBalanceDto>>.Fail("Thiếu cửa hàng"));
        var q = db.PosCustomerSessionBalances.AsNoTracking()
            .Include(b => b.Customer)
            .Where(b => b.StoreId == storeId && b.Deleted == null && b.RemainingSessions > 0);
        if (customerId.HasValue) q = q.Where(b => b.CustomerId == customerId);

        var list = await q.OrderByDescending(b => b.CreatedAt)
            .Select(b => new SessionBalanceDto(
                b.Id, b.CustomerId, b.Customer != null ? b.Customer.Name : "",
                b.ProductId, b.PackageName, b.TotalSessions, b.RemainingSessions, b.ExpiresAt))
            .ToListAsync();
        return Ok(AppResponse<List<SessionBalanceDto>>.Success(list));
    }

    [HttpPost("session-balances/redeem")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> RedeemSession([FromBody] RedeemSessionDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu cửa hàng"));
        if (await RequireSessionPacksAsync(storeId) is { } denied)
            return denied;
        var sessions = Math.Max(1, dto.Sessions);
        // DbContext mặc định NoTracking — bắt buộc AsTracking để SaveChangesAsync thực sự trừ buổi.
        var balance = await db.PosCustomerSessionBalances.AsTracking()
            .FirstOrDefaultAsync(b => b.Id == dto.BalanceId && b.StoreId == storeId && b.Deleted == null);
        if (balance == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy gói buổi"));
        if (balance.ExpiresAt.HasValue && balance.ExpiresAt.Value < DateTime.UtcNow)
            return BadRequest(AppResponse<object>.Fail("Gói buổi đã hết hạn"));
        if (balance.RemainingSessions < sessions)
            return BadRequest(AppResponse<object>.Fail($"Chỉ còn {balance.RemainingSessions} buổi"));

        balance.RemainingSessions -= sessions;
        balance.UpdatedAt = DateTime.UtcNow;
        balance.UpdatedBy = CurrentUserEmail;

        db.PosCustomerSessionTransactions.Add(new PosCustomerSessionTransaction
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            BalanceId = balance.Id,
            CustomerId = balance.CustomerId,
            SaleOrderId = dto.SaleOrderId,
            TransactionType = PosSessionTxnType.Redeem,
            SessionDelta = -sessions,
            RemainingAfter = balance.RemainingSessions,
            Note = dto.Note?.Trim(),
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        });
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new
        {
            balanceId = balance.Id,
            remaining = balance.RemainingSessions,
        }));
    }

    /// <summary>Cộng buổi khi bán gói (gọi từ sale complete).</summary>
    public static async Task GrantSessionPacksOnSaleCompleteAsync(
        ZKTecoDbContext dbContext,
        Guid storeId,
        PosSaleOrder order,
        List<PosSaleOrderLine> lines,
        string? actorEmail)
    {
        if (!order.CustomerId.HasValue) return;

        var settings = await dbContext.PosStoreSellSettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);
        if (settings == null || !settings.EnableSessionPacks) return;

        var productIds = lines.Select(l => l.ProductId).Distinct().ToList();
        var packs = await dbContext.PosProducts.AsNoTracking()
            .Where(p => productIds.Contains(p.Id) && p.StoreId == storeId
                && p.Deleted == null && p.SessionPackCount > 0)
            .ToDictionaryAsync(p => p.Id);

        foreach (var line in lines)
        {
            if (!packs.TryGetValue(line.ProductId, out var product)) continue;
            var grant = product.SessionPackCount * (int)Math.Max(1, Math.Round(line.Qty));
            if (grant <= 0) continue;

            var balance = new PosCustomerSessionBalance
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                CustomerId = order.CustomerId.Value,
                ProductId = product.Id,
                PackageName = product.Name,
                TotalSessions = grant,
                RemainingSessions = grant,
                IsActive = true,
                CreatedBy = actorEmail,
            };
            dbContext.PosCustomerSessionBalances.Add(balance);
            dbContext.PosCustomerSessionTransactions.Add(new PosCustomerSessionTransaction
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                BalanceId = balance.Id,
                CustomerId = order.CustomerId.Value,
                SaleOrderId = order.Id,
                TransactionType = PosSessionTxnType.Purchase,
                SessionDelta = grant,
                RemainingAfter = grant,
                Note = $"Mua gói {product.Name}",
                IsActive = true,
                CreatedBy = actorEmail,
            });
        }
    }
}
