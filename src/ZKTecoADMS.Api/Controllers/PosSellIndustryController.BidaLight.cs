using System.Collections.Concurrent;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Đèn bàn bi-a: ESP32-C3 + relay hỏi trạng thái bàn — mở bàn → đèn sáng, thanh toán (phiên Closed) → tắt.
/// </summary>
public partial class PosSellIndustryController
{
    public record BidaLightDto(bool Enabled, string? DeviceKey, bool PausedOn);

    public record BidaLightSaveDto(bool Enabled, bool Rotate = false, bool? PausedOn = null);

    [HttpGet("bida-light")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<BidaLightDto>>> GetBidaLight()
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<BidaLightDto>.Fail("Thiếu cửa hàng"));
        var s = await LoadSellSettingsAsync(storeId);
        var cfg = PosBidaLightHelper.Read(s?.ExtraJson);
        return Ok(AppResponse<BidaLightDto>.Success(ToDto(storeId, cfg)));
    }

    /// <summary>Bật / tắt / đổi khóa thiết bị. Đổi khóa → thiết bị cũ bị từ chối ngay.</summary>
    [HttpPost("bida-light")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<BidaLightDto>>> SaveBidaLight([FromBody] BidaLightSaveDto dto)
    {
        if (!TryGetStoreId(out var storeId))
            return BadRequest(AppResponse<BidaLightDto>.Fail("Thiếu cửa hàng"));
        var s = await db.PosStoreSellSettings
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);
        if (s == null)
        {
            s = PosServiceBillingHelper.CreateDefault(storeId, CurrentUserEmail);
            db.PosStoreSellSettings.Add(s);
        }

        var cur = PosBidaLightHelper.Read(s.ExtraJson);
        var next = !dto.Enabled
            ? new PosBidaLightHelper.Config(null, cur.PausedOn)
            : new PosBidaLightHelper.Config(
                dto.Rotate || cur.Secret == null ? PosBidaLightHelper.NewSecret() : cur.Secret,
                dto.PausedOn ?? cur.PausedOn);
        s.ExtraJson = PosBidaLightHelper.Write(s.ExtraJson, next);
        await db.SaveChangesAsync();
        bidaLightCache.TryRemove(storeId, out _);
        return Ok(AppResponse<BidaLightDto>.Success(ToDto(storeId, next)));
    }

    static BidaLightDto ToDto(Guid storeId, PosBidaLightHelper.Config cfg) =>
        new(cfg.Secret != null,
            cfg.Secret == null ? null : PosBidaLightHelper.DeviceKey(storeId, cfg.Secret),
            cfg.PausedOn);

    sealed record BidaLightSnapshot(DateTime At, string? Secret, object Body);

    /// <summary>Nhiều bộ relay cùng cửa hàng hỏi mỗi 2 giây — gom lại 1 truy vấn / 1,5 giây.</summary>
    static readonly ConcurrentDictionary<Guid, BidaLightSnapshot> bidaLightCache = new();

    /// <summary>
    /// Thiết bị relay hỏi trạng thái — không đăng nhập, xác thực bằng khóa thiết bị.
    /// t[i] = { c: mã bàn, n: tên bàn, on: 1 sáng / 0 tắt }.
    /// </summary>
    [HttpGet("bida-light/state")]
    [AllowAnonymous]
    public async Task<ActionResult<object>> GetBidaLightState([FromQuery] string? key)
    {
        if (!PosBidaLightHelper.TryParseDeviceKey(key, out var storeId, out var secret))
            return Unauthorized(new { ok = false, msg = "Sai khoa thiet bi" });

        var now = DateTime.UtcNow;
        if (!bidaLightCache.TryGetValue(storeId, out var snap) || now - snap.At > TimeSpan.FromSeconds(1.5))
        {
            var s = await LoadSellSettingsAsync(storeId);
            var cfg = PosBidaLightHelper.Read(s?.ExtraJson);
            object body = new { ok = false };
            if (cfg.Secret != null)
            {
                var resources = await db.PosServiceResources.AsNoTracking()
                    .Where(r => r.StoreId == storeId && r.Deleted == null)
                    .OrderBy(r => r.SortOrder).ThenBy(r => r.Code)
                    .Select(r => new { r.Id, r.Code, r.Name })
                    .ToListAsync();
                var lit = (await db.PosResourceSessions.AsNoTracking()
                        .Where(x => x.StoreId == storeId && x.Deleted == null
                            && (x.Status == PosResourceSessionStatus.Open
                                || (cfg.PausedOn && x.Status == PosResourceSessionStatus.Paused)))
                        .Select(x => x.ResourceId)
                        .ToListAsync())
                    .ToHashSet();
                body = new
                {
                    ok = true,
                    t = resources.Select(r => new { c = r.Code, n = r.Name, on = lit.Contains(r.Id) ? 1 : 0 }),
                };
            }
            snap = new BidaLightSnapshot(now, cfg.Secret, body);
            // Khóa rác (GUID bất kỳ) không được nằm lại trong bộ nhớ.
            if (cfg.Secret != null) bidaLightCache[storeId] = snap;
            else bidaLightCache.TryRemove(storeId, out _);
        }

        if (!PosBidaLightHelper.SecretMatches(snap.Secret, secret))
            return Unauthorized(new { ok = false, msg = "Sai khoa thiet bi hoac chua bat den bida" });
        return Ok(snap.Body);
    }
}
