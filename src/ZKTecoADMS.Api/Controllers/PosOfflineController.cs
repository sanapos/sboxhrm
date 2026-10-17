using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Bán offline: thiết bị đăng ký lần cài app, xin dải số hóa đơn offline (khi còn mạng); báo cáo kiểm soát
/// cho chủ quán — lịch sử cài lại app, số đã cấp mà không đồng bộ, số nhảy cóc.
/// </summary>
[ApiController]
[Route("api/pos/offline")]
[Authorize]
public class PosOfflineController(ZKTecoDbContext db, ILogger<PosOfflineController> logger)
    : AuthenticatedControllerBase
{
    /// <summary>Giờ lưu DB là con số UTC (không múi giờ) → trả JSON kèm Z để app đổi đúng sang giờ máy.</summary>
    static DateTime U(DateTime v) => DateTime.SpecifyKind(v, DateTimeKind.Utc);
    static DateTime? U(DateTime? v) => v == null ? null : DateTime.SpecifyKind(v.Value, DateTimeKind.Utc);

    static string? Cut(string? s, int max) =>
        string.IsNullOrWhiteSpace(s) ? null : (s.Trim().Length <= max ? s.Trim() : s.Trim()[..max]);

    async Task<PosOfflineSaleRules.Settings> SettingsAsync(Guid storeId, CancellationToken ct)
    {
        var extra = await db.PosStoreSellSettings.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Deleted == null)
            .Select(s => s.ExtraJson)
            .FirstOrDefaultAsync(ct);
        return PosOfflineSaleRules.ParseSettings(extra);
    }

    public class InstallDto
    {
        public string? DeviceKey { get; set; }
        public string? InstallId { get; set; }
        public string? DeviceName { get; set; }
        public string? Platform { get; set; }
        public string? AppVersion { get; set; }
        public DateTime? OsFirstInstallAt { get; set; }
        public int PendingOfflineSales { get; set; }
        public int? LastOfflineSeq { get; set; }
    }

    /// <summary>Máy POS báo lần cài app (mỗi lần mở app khi có mạng). Trả cài đặt bán offline + dải số còn hiệu lực.</summary>
    [HttpPost("install")]
    public async Task<ActionResult<AppResponse<object>>> Install([FromBody] InstallDto? dto, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var deviceKey = Cut(dto?.DeviceKey, 128);
        var installId = Cut(dto?.InstallId, 64);
        if (deviceKey == null || installId == null)
            return BadRequest(AppResponse<object>.Fail("Thiếu mã thiết bị / mã cài đặt"));
        var now = DateTime.UtcNow;
        // AsTracking: DbContext mặc định NoTracking — thiếu thì lần báo sau (LastSeenAt, số đơn chờ, số offline cuối)
        // không được lưu → cảnh báo «chưa đồng bộ đủ» / «cài lại khi còn đơn chưa gửi» không bao giờ hiện.
        var row = await db.PosDeviceInstalls.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.DeviceKey == deviceKey && x.InstallId == installId, ct);
        var isNew = row == null;
        if (row == null)
        {
            row = new PosDeviceInstall
            {
                Id = Guid.NewGuid(), StoreId = storeId, DeviceKey = deviceKey, InstallId = installId,
                FirstSeenAt = now,
            };
            db.PosDeviceInstalls.Add(row);
        }
        row.LastSeenAt = now;
        row.DeviceName = Cut(dto!.DeviceName, 200) ?? row.DeviceName;
        row.Platform = Cut(dto.Platform, 16) ?? row.Platform;
        row.AppVersion = Cut(dto.AppVersion, 32) ?? row.AppVersion;
        if (dto.OsFirstInstallAt is { } os)
            row.OsFirstInstallAt = os.Kind == DateTimeKind.Utc ? os : DateTime.SpecifyKind(os.ToUniversalTime(), DateTimeKind.Utc);
        row.LastUserName = Cut(CurrentUserEmail, 200);
        row.PendingOfflineSales = Math.Clamp(dto.PendingOfflineSales, 0, 100_000);
        if (dto.LastOfflineSeq is { } seq) row.LastOfflineSeq = seq;
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex)
        {
            logger.LogInformation(ex, "Install upsert race {Store} {Device}", storeId, deviceKey);
        }

        var previousInstalls = await db.PosDeviceInstalls.AsNoTracking()
            .CountAsync(x => x.StoreId == storeId && x.DeviceKey == deviceKey && x.InstallId != installId, ct);
        if (isNew && previousInstalls > 0)
            logger.LogWarning("POS app reinstalled store {Store} device {Device} ({Name}) — {Prev} previous installs",
                storeId, deviceKey, row.DeviceName, previousInstalls);

        var settings = await SettingsAsync(storeId, ct);
        var blocks = await db.PosOfflineSerialBlocks.AsNoTracking()
            .Where(b => b.StoreId == storeId && b.DeviceKey == deviceKey && b.InstallId == installId)
            .OrderBy(b => b.FromSeq)
            .Select(b => new { b.FromSeq, b.ToSeq })
            .ToListAsync(ct);
        return Ok(AppResponse<object>.Success(new
        {
            offlineEnabled = settings.Enabled,
            maxHours = settings.MaxHours,
            reinstall = previousInstalls > 0,
            blocks,
            serverTime = now,
        }));
    }

    public class ReserveDto
    {
        public string? DeviceKey { get; set; }
        public string? InstallId { get; set; }
        public string? DeviceName { get; set; }
        public int Count { get; set; } = 50;
    }

    /// <summary>Cấp trước dải số hóa đơn offline cho lần cài app này (chỉ khi cửa hàng bật bán offline).</summary>
    [HttpPost("reserve")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> Reserve([FromBody] ReserveDto? dto, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var deviceKey = Cut(dto?.DeviceKey, 128);
        var installId = Cut(dto?.InstallId, 64);
        if (deviceKey == null || installId == null)
            return BadRequest(AppResponse<object>.Fail("Thiếu mã thiết bị / mã cài đặt"));
        if (!(await SettingsAsync(storeId, ct)).Enabled)
            return BadRequest(AppResponse<object>.Fail("Cửa hàng chưa bật bán offline"));
        // Chỉ máy POS Android đã báo lần cài mới được cấp số (trình duyệt web không bán offline:
        // bộ nhớ trình duyệt xóa được, không có mã máy bền để kiểm soát).
        var install = await db.PosDeviceInstalls.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.DeviceKey == deviceKey && x.InstallId == installId, ct);
        if (install == null)
            return BadRequest(AppResponse<object>.Fail("Máy chưa báo lần cài đặt"));
        if (!deviceKey.StartsWith("a:", StringComparison.Ordinal)
            || !string.Equals(install.Platform, "android", StringComparison.OrdinalIgnoreCase))
            return BadRequest(AppResponse<object>.Fail("Chỉ máy POS Android được bán offline"));
        var count = Math.Clamp(dto!.Count, 10, 200);

        await using var tx = await db.Database.BeginTransactionAsync(ct);
        // Một cửa hàng cấp số tuần tự — khóa theo cửa hàng trong giao dịch.
        await db.Database.ExecuteSqlRawAsync(
            "SELECT pg_advisory_xact_lock(hashtext({0}))", ["offline-serial:" + storeId], ct);
        var maxTo = await db.PosOfflineSerialBlocks.Where(b => b.StoreId == storeId)
            .MaxAsync(b => (int?)b.ToSeq, ct) ?? 0;
        var block = new PosOfflineSerialBlock
        {
            Id = Guid.NewGuid(), StoreId = storeId, DeviceKey = deviceKey, InstallId = installId,
            DeviceName = Cut(dto.DeviceName, 200), FromSeq = maxTo + 1, ToSeq = maxTo + count,
            ReservedBy = Cut(CurrentUserEmail, 200),
        };
        db.PosOfflineSerialBlocks.Add(block);
        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
        return Ok(AppResponse<object>.Success(new { fromSeq = block.FromSeq, toSeq = block.ToSeq, prefix = PosOfflineSaleRules.Prefix }));
    }

    /// <summary>
    /// Báo cáo kiểm soát bán offline (chủ / quản lý): kết luận dễ hiểu, cảnh báo kèm cách xử lý, đồ thị đơn offline
    /// theo ngày / thời gian chờ gửi, lịch sử cài app, số đã cấp mà chưa thấy đồng bộ, số nhảy cóc.
    /// </summary>
    [HttpGet("audit")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PosOfflineAuditBuilder.Report>>> Audit(
        [FromQuery] int days = 30, CancellationToken ct = default)
    {
        if (!IsAdmin && !IsManager)
            return StatusCode(StatusCodes.Status403Forbidden,
                AppResponse<PosOfflineAuditBuilder.Report>.Fail("Chỉ chủ / quản lý xem được"));
        var storeId = RequiredStoreId;
        var now = DateTime.UtcNow;
        var since = now.AddDays(-Math.Clamp(days, 1, 365));
        var settings = await SettingsAsync(storeId, ct);

        var installs = await db.PosDeviceInstalls.AsNoTracking()
            .Where(x => x.StoreId == storeId)
            .ToListAsync(ct);
        var blocks = await db.PosOfflineSerialBlocks.AsNoTracking()
            .Where(b => b.StoreId == storeId)
            .ToListAsync(ct);
        // Toàn bộ đơn offline (không chỉ trong kỳ) — để đối chiếu dải số đã cấp.
        var offlineOrders = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.OfflineNo != null && o.Deleted == null)
            .Select(o => new PosOfflineAuditBuilder.OrderRow(
                o.Id, o.OrderNo, o.OfflineNo, o.OfflineAt, o.OfflineDeviceKey, o.CreatedAt, o.UpdatedAt,
                o.CreatedBy, o.Total, o.Status))
            .ToListAsync(ct);

        var report = PosOfflineAuditBuilder.Build(settings, installs, blocks, offlineOrders, since, now);
        return Ok(AppResponse<PosOfflineAuditBuilder.Report>.Success(report));
    }
}
