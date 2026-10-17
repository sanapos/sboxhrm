using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosPrintersController
{
    public record StalePrinterDto(Guid Id, string Name, string ConnectionType, bool IsDeviceLocal,
        string? OwnerDeviceId, DateTime? LastActivityAt, string Reason);

    /// <summary>
    /// Máy in cũ: máy in nội bộ của thiết bị đã lâu không hoạt động (không Agent nào của thiết bị đó báo về,
    /// máy không được thấy, không có lệnh in) và máy cloud không Agent nào nhận, không có lệnh in, lâu không
    /// thấy. Mỗi lần cài lại app / đổi máy trước đây đều để lại bản ghi → máy thu ngân / web thấy hàng chục máy
    /// trùng tên, gửi nhầm vào máy đã bỏ.
    /// </summary>
    async Task<List<StalePrinterDto>> FindStalePrintersAsync(Guid storeId, int days, CancellationToken ct)
    {
        var cutoff = DateTime.UtcNow.AddDays(-days);
        var agents = await db.PosPrintAgents.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.Deleted == null)
            .Select(a => new { a.DeviceId, a.LastHeartbeatAt, a.AssignedPrinterIdsJson })
            .ToListAsync(ct);
        var liveDevices = agents
            .Where(a => a.LastHeartbeatAt >= cutoff)
            .Select(a => a.DeviceId.Trim().ToLowerInvariant())
            .ToHashSet();
        var assigned = new HashSet<Guid>();
        foreach (var a in agents.Where(a => a.LastHeartbeatAt >= cutoff))
        {
            try
            {
                foreach (var id in JsonSerializer.Deserialize<List<string>>(a.AssignedPrinterIdsJson ?? "[]") ?? [])
                    if (Guid.TryParse(id, out var g)) assigned.Add(g);
            }
            catch (JsonException) { }
        }
        var recentJobPrinters = (await db.PosPrintJobs.AsNoTracking()
                .Where(j => j.StoreId == storeId && j.CreatedAt >= cutoff)
                .Select(j => j.PrinterId)
                .Distinct()
                .ToListAsync(ct))
            .ToHashSet();

        var printers = await db.PosStorePrinters.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive)
            .ToListAsync(ct);
        var result = new List<StalePrinterDto>();
        foreach (var p in printers)
        {
            var last = new[] { p.LastSeenAt, p.UpdatedAt, (DateTime?)p.CreatedAt }.Max();
            if (last >= cutoff || recentJobPrinters.Contains(p.Id) || assigned.Contains(p.Id)) continue;
            if (p.IsDeviceLocal)
            {
                var owner = (p.OwnerDeviceId ?? "").Trim().ToLowerInvariant();
                if (owner.Length > 0 && liveDevices.Contains(owner)) continue;
                result.Add(new(p.Id, p.Name, p.ConnectionType.ToString(), true, p.OwnerDeviceId, last,
                    $"Máy nội bộ của thiết bị không hoạt động {days} ngày"));
            }
            else
            {
                result.Add(new(p.Id, p.Name, p.ConnectionType.ToString(), false, null, last,
                    $"Không Agent nào nhận, không có lệnh in {days} ngày"));
            }
        }
        // Bản trùng do cài lại app / xóa dữ liệu: mỗi lần cài lại máy POS từng có mã máy mới →
        // máy in nội bộ bị tạo lại, bản cũ nằm đó. Bản cũ = cùng tên + kiểu + địa chỉ với một máy
        // nội bộ mới hơn đang bật, và bản cũ không hoạt động 3 ngày (không chờ đủ [days]).
        var dupCutoff = DateTime.UtcNow.AddDays(-Math.Min(days, 3));
        var dupLive = agents.Where(a => a.LastHeartbeatAt >= dupCutoff)
            .Select(a => a.DeviceId.Trim().ToLowerInvariant()).ToHashSet();
        var dupJobs = (await db.PosPrintJobs.AsNoTracking()
                .Where(j => j.StoreId == storeId && j.CreatedAt >= dupCutoff)
                .Select(j => j.PrinterId).Distinct().ToListAsync(ct))
            .ToHashSet();
        string DupKey(ZKTecoADMS.Domain.Entities.PosStorePrinter p) => string.Join('|',
            p.Name.Trim().ToLowerInvariant(),
            p.ConnectionType,
            string.Equals(p.PrinterBrand, "label", StringComparison.OrdinalIgnoreCase),
            (p.LanHost ?? "").Trim().ToLowerInvariant(),
            p.LanPort <= 0 ? 9100 : p.LanPort,
            (p.BluetoothAddress ?? "").Trim().ToUpperInvariant(),
            (p.UsbDeviceName ?? "").Trim().ToLowerInvariant());
        var already = result.Select(r => r.Id).ToHashSet();
        foreach (var grp in printers.Where(p => p.IsDeviceLocal).GroupBy(DupKey))
        {
            var ordered = grp.OrderByDescending(p =>
                    new[] { p.LastSeenAt, p.UpdatedAt, (DateTime?)p.CreatedAt }.Max())
                .ToList();
            if (ordered.Count < 2) continue;
            var newest = ordered[0];
            foreach (var p in ordered.Skip(1))
            {
                if (already.Contains(p.Id)) continue;
                if (string.Equals((p.OwnerDeviceId ?? "").Trim(), (newest.OwnerDeviceId ?? "").Trim(),
                        StringComparison.OrdinalIgnoreCase)) continue;
                var last = new[] { p.LastSeenAt, p.UpdatedAt, (DateTime?)p.CreatedAt }.Max();
                var owner = (p.OwnerDeviceId ?? "").Trim().ToLowerInvariant();
                if (last >= dupCutoff || dupJobs.Contains(p.Id) || assigned.Contains(p.Id) ||
                    (owner.Length > 0 && dupLive.Contains(owner))) continue;
                result.Add(new(p.Id, p.Name, p.ConnectionType.ToString(), true, p.OwnerDeviceId, last,
                    "Bản trùng (máy cài lại app) — đã có máy cùng tên, cùng kết nối mới hơn"));
                already.Add(p.Id);
            }
        }

        if (result.Count > 0)
        {
            // Máy còn được gán món / nhóm hàng: tắt rồi thì món đó in ở máy bếp mặc định — ghi rõ để chủ quán biết.
            var ids = result.Select(r => r.Id).ToList();
            var refs = await db.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null &&
                            ((p.DefaultPrinterId != null && ids.Contains(p.DefaultPrinterId.Value)) ||
                             (p.DefaultLabelPrinterId != null && ids.Contains(p.DefaultLabelPrinterId.Value))))
                .Select(p => new { p.DefaultPrinterId, p.DefaultLabelPrinterId })
                .ToListAsync(ct);
            var catRefs = await db.PosProductCategories.AsNoTracking()
                .Where(c => c.StoreId == storeId && c.Deleted == null &&
                            ((c.DefaultPrinterId != null && ids.Contains(c.DefaultPrinterId.Value)) ||
                             (c.DefaultLabelPrinterId != null && ids.Contains(c.DefaultLabelPrinterId.Value))))
                .Select(c => new { c.DefaultPrinterId, c.DefaultLabelPrinterId })
                .ToListAsync(ct);
            result = result.Select(r =>
            {
                var n = refs.Count(x => x.DefaultPrinterId == r.Id || x.DefaultLabelPrinterId == r.Id);
                var c = catRefs.Count(x => x.DefaultPrinterId == r.Id || x.DefaultLabelPrinterId == r.Id);
                if (n + c == 0) return r;
                var what = string.Join(", ", new[] { n > 0 ? $"{n} món" : null, c > 0 ? $"{c} nhóm hàng" : null }
                    .Where(x => x != null));
                return r with { Reason = $"{r.Reason} · còn gán {what} → sẽ in ở máy bếp mặc định" };
            }).ToList();
        }
        return result.OrderBy(x => x.LastActivityAt).ToList();
    }

    /// <summary>Xem trước danh sách máy in cũ (không đổi gì).</summary>
    [HttpGet("stale")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<StalePrinterDto>>>> GetStalePrinters(
        [FromQuery] int days = 14, CancellationToken ct = default)
    {
        var storeId = RequiredStoreId;
        return Ok(AppResponse<List<StalePrinterDto>>.Success(
            await FindStalePrintersAsync(storeId, Math.Clamp(days, 7, 365), ct)));
    }

    /// <summary>Tắt (không xóa) các máy in cũ — bật lại được trong danh sách máy in.</summary>
    [HttpPost("stale/deactivate")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> DeactivateStalePrinters(
        [FromQuery] int days = 14, CancellationToken ct = default)
    {
        var storeId = RequiredStoreId;
        var stale = await FindStalePrintersAsync(storeId, Math.Clamp(days, 7, 365), ct);
        var ids = stale.Select(s => s.Id).ToList();
        var now = DateTime.UtcNow;
        var n = ids.Count == 0
            ? 0
            : await db.PosStorePrinters
                .Where(p => p.StoreId == storeId && ids.Contains(p.Id))
                .ExecuteUpdateAsync(s => s
                    .SetProperty(p => p.IsActive, false)
                    .SetProperty(p => p.IsDefault, false)
                    .SetProperty(p => p.UpdatedAt, now)
                    .SetProperty(p => p.UpdatedBy, CurrentUserId.ToString()), ct);
        return Ok(AppResponse<object>.Success(new { deactivated = n, printers = stale }));
    }
}
