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
        var row = await db.PosDeviceInstalls
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
    /// Báo cáo kiểm soát bán offline (chủ / quản lý): đơn offline đã đồng bộ, lịch sử cài app, số đã cấp
    /// mà chưa thấy đồng bộ (đặc biệt khi máy đã cài lại / xóa dữ liệu), số nhảy cóc.
    /// </summary>
    [HttpGet("audit")]
    [RequireModulePermission("PosSalesReport", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Audit([FromQuery] int days = 30, CancellationToken ct = default)
    {
        if (!IsAdmin && !IsManager)
            return StatusCode(StatusCodes.Status403Forbidden, AppResponse<object>.Fail("Chỉ chủ / quản lý xem được"));
        var storeId = RequiredStoreId;
        var since = DateTime.UtcNow.AddDays(-Math.Clamp(days, 1, 365));
        var settings = await SettingsAsync(storeId, ct);

        var installs = await db.PosDeviceInstalls.AsNoTracking()
            .Where(x => x.StoreId == storeId)
            .OrderBy(x => x.FirstSeenAt)
            .ToListAsync(ct);
        var blocks = await db.PosOfflineSerialBlocks.AsNoTracking()
            .Where(b => b.StoreId == storeId)
            .OrderBy(b => b.FromSeq)
            .ToListAsync(ct);
        var offlineOrders = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.OfflineNo != null && o.Deleted == null)
            .Select(o => new
            {
                o.Id, o.OrderNo, o.OfflineNo, o.OfflineAt, o.OfflineDeviceKey, o.CreatedAt, o.CreatedBy,
                o.Total, o.Status,
            })
            .ToListAsync(ct);
        var usedSeqs = offlineOrders
            .Select(o => PosOfflineSaleRules.SeqOf(o.OfflineNo))
            .Where(s => s != null).Select(s => s!.Value).ToHashSet();

        var alerts = new List<object>();
        var blockRows = blocks.Select(b =>
        {
            var used = Enumerable.Range(b.FromSeq, b.ToSeq - b.FromSeq + 1).Where(usedSeqs.Contains).ToList();
            var maxUsed = used.Count == 0 ? (int?)null : used.Max();
            // Số trong khoảng đã dùng mà không có đơn = nhảy cóc (đơn đã in cho khách nhưng không về server).
            var gaps = maxUsed == null
                ? new List<int>()
                : Enumerable.Range(b.FromSeq, maxUsed.Value - b.FromSeq + 1).Where(s => !usedSeqs.Contains(s)).ToList();
            var install = installs.FirstOrDefault(i => i.DeviceKey == b.DeviceKey && i.InstallId == b.InstallId);
            var replaced = installs.Any(i => i.DeviceKey == b.DeviceKey && i.InstallId != b.InstallId
                && i.FirstSeenAt > (install?.FirstSeenAt ?? b.CreatedAt));
            var reportedLast = install?.LastOfflineSeq;
            var reportedPending = install?.PendingOfflineSales ?? 0;
            // Máy từng báo đã dùng tới số X nhưng server chỉ có tới Y (< X) → còn đơn chưa đồng bộ.
            var reportedMissing = reportedLast is { } rl && rl >= b.FromSeq && rl <= b.ToSeq
                ? Enumerable.Range(b.FromSeq, rl - b.FromSeq + 1).Where(s => !usedSeqs.Contains(s)).ToList()
                : [];
            var suspicious = new List<string>();
            if (gaps.Count > 0)
                suspicious.Add($"{gaps.Count} số nhảy cóc (đã in cho khách nhưng không về máy chủ)");
            if (replaced && (reportedPending > 0 || reportedMissing.Count > 0))
                suspicious.Add("Cài lại app / xóa dữ liệu khi còn đơn offline chưa gửi");
            else if (reportedMissing.Count > gaps.Count)
                suspicious.Add($"Máy báo đã bán tới {PosOfflineSaleRules.Format(reportedLast!.Value)} — chưa đồng bộ đủ");
            if (suspicious.Count > 0)
                alerts.Add(new
                {
                    level = "high",
                    device = b.DeviceName ?? b.DeviceKey,
                    text = string.Join("; ", suspicious),
                    range = $"{PosOfflineSaleRules.Format(b.FromSeq)} – {PosOfflineSaleRules.Format(b.ToSeq)}",
                });
            return new
            {
                b.DeviceKey, b.DeviceName, b.InstallId, reservedAt = b.CreatedAt, b.ReservedBy,
                from = PosOfflineSaleRules.Format(b.FromSeq), to = PosOfflineSaleRules.Format(b.ToSeq),
                used = used.Count,
                lastUsed = maxUsed == null ? null : PosOfflineSaleRules.Format(maxUsed.Value),
                gaps = gaps.Take(50).Select(PosOfflineSaleRules.Format).ToList(),
                missingReported = reportedMissing.Take(50).Select(PosOfflineSaleRules.Format).ToList(),
                installReplaced = replaced,
                suspicious,
            };
        }).ToList();

        // Số offline không thuộc dải nào đã cấp → bất thường.
        var allRanges = blocks.Select(b => (b.FromSeq, b.ToSeq)).ToList();
        foreach (var o in offlineOrders)
        {
            var s = PosOfflineSaleRules.SeqOf(o.OfflineNo);
            if (s != null && !allRanges.Any(r => s >= r.FromSeq && s <= r.ToSeq))
                alerts.Add(new { level = "medium", device = o.OfflineDeviceKey, text = $"{o.OfflineNo} không thuộc dải số đã cấp", range = o.OrderNo });
        }

        var devices = installs.GroupBy(i => i.DeviceKey).Select(g =>
        {
            var list = g.OrderBy(i => i.FirstSeenAt).ToList();
            var reinstalls = list.Count - 1;
            if (reinstalls > 0)
                alerts.Add(new
                {
                    level = "info",
                    device = list.Last().DeviceName ?? g.Key,
                    text = $"Cài lại app {reinstalls} lần (gần nhất {list.Last().FirstSeenAt.AddHours(7):dd/MM HH:mm})",
                    range = (string?)null,
                });
            return new
            {
                deviceKey = g.Key,
                deviceName = list.Last().DeviceName,
                reinstalls,
                installs = list.Select(i => new
                {
                    i.InstallId, i.Platform, i.AppVersion, i.FirstSeenAt, i.LastSeenAt, i.OsFirstInstallAt,
                    i.LastUserName, i.PendingOfflineSales,
                    lastOfflineSeq = i.LastOfflineSeq == null ? null : PosOfflineSaleRules.Format(i.LastOfflineSeq.Value),
                }).ToList(),
            };
        }).ToList();

        var sales = offlineOrders.Where(o => o.CreatedAt >= since)
            .OrderByDescending(o => o.OfflineAt)
            .Select(o => new
            {
                o.Id, o.OrderNo, o.OfflineNo, o.OfflineAt, syncedAt = o.CreatedAt, o.Total, o.CreatedBy,
                device = installs.FirstOrDefault(i => i.DeviceKey == o.OfflineDeviceKey)?.DeviceName ?? o.OfflineDeviceKey,
                delayMinutes = o.OfflineAt == null ? 0 : (int)Math.Max(0, (o.CreatedAt - o.OfflineAt.Value).TotalMinutes),
                status = o.Status.ToString(),
            })
            .Take(500)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            settings = new { settings.Enabled, settings.MaxHours },
            summary = new
            {
                offlineSales = sales.Count,
                offlineTotal = sales.Sum(s => s.Total),
                devices = devices.Count,
                reinstalls = devices.Sum(d => d.reinstalls),
                alerts = alerts.Count(a => ((dynamic)a).level == "high"),
            },
            alerts,
            devices,
            blocks = blockRows,
            sales,
        }));
    }
}
