using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Commands.DeviceUsers.Create;
using ZKTecoADMS.Application.Commands.DeviceUsers.Delete;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Gym: hội viên check-in bằng máy chấm công (vân tay / khuôn mặt / thẻ) — tách biệt chấm công nhân viên.
/// Hội viên có PIN riêng (90000001…); mỗi lượt quét ghi vào PosGymVisits, trừ buổi tối đa 1 lần / ngày.
/// </summary>
[ApiController]
[Route("api/pos/gym")]
[Authorize]
public class PosGymController(ZKTecoDbContext db, IMediator bus, IGymCheckInService gym) : AuthenticatedControllerBase
{
    public record MemberDto(
        Guid Id, Guid CustomerId, string CustomerName, string? Phone,
        Guid DeviceId, string DeviceName, bool DeviceOnline, string Pin, string? CardNumber,
        Guid? DeviceUserId, int FingerprintCount, int FaceCount,
        string? PackageName, bool Unlimited, int? RemainingSessions, DateTime? ExpiresAt,
        DateTime? LastVisitAt, DateTime CreatedAt);

    public record AddMemberDto(Guid CustomerId, List<Guid> DeviceIds, string? CardNumber = null);

    public record VisitDto(
        Guid Id, Guid CustomerId, string CustomerName, string? Phone, string? DeviceName,
        DateTime CheckInAt, DateTime? CheckOutAt, int? DurationMinutes, string? PackageName,
        bool SessionDeducted, string Status, string Source, string? Note,
        bool Unlimited, int? RemainingSessions, DateTime? ExpiresAt);

    public record CheckInDto(Guid CustomerId);

    // ── Hội viên trên máy ────────────────────────────────────────────────

    [HttpGet("members")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<MemberDto>>>> Members([FromQuery] string? search = null)
    {
        var storeId = RequiredStoreId;
        var q = db.PosGymMemberDevices.AsNoTracking()
            .Where(m => m.StoreId == storeId && m.Deleted == null);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(m => m.Pin.Contains(s)
                || (m.Customer != null && (m.Customer.Name.ToLower().Contains(s)
                    || (m.Customer.Phone != null && m.Customer.Phone.Contains(s)))));
        }
        var rows = await q
            .OrderByDescending(m => m.CreatedAt)
            .Select(m => new
            {
                m.Id, m.CustomerId,
                CustomerName = m.Customer != null ? m.Customer.Name : "",
                Phone = m.Customer != null ? m.Customer.Phone : null,
                m.DeviceId,
                DeviceName = m.Device != null ? m.Device.DeviceName : "",
                DeviceStatus = m.Device != null ? m.Device.DeviceStatus : "",
                LastOnline = m.Device != null ? m.Device.LastOnline : null,
                m.Pin, m.CardNumber, m.DeviceUserId, m.CreatedAt,
            })
            .Take(1000)
            .ToListAsync();

        var customerIds = rows.Select(r => r.CustomerId).Distinct().ToList();
        var duIds = rows.Where(r => r.DeviceUserId.HasValue).Select(r => r.DeviceUserId!.Value).ToList();
        var fp = await db.FingerprintTemplates.AsNoTracking()
            .Where(f => duIds.Contains(f.EmployeeId))
            .GroupBy(f => f.EmployeeId).Select(g => new { g.Key, C = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.C);
        var face = await db.FaceTemplates.AsNoTracking()
            .Where(f => duIds.Contains(f.EmployeeId))
            .GroupBy(f => f.EmployeeId).Select(g => new { g.Key, C = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.C);
        var packs = await BestPackagesAsync(storeId, customerIds);
        var lastVisits = await db.PosGymVisits.AsNoTracking()
            .Where(v => v.StoreId == storeId && customerIds.Contains(v.CustomerId))
            .GroupBy(v => v.CustomerId).Select(g => new { g.Key, At = g.Max(v => v.CheckInAt) })
            .ToDictionaryAsync(x => x.Key, x => (DateTime?)x.At);

        var now = DateTime.UtcNow;
        var list = rows.Select(r =>
        {
            packs.TryGetValue(r.CustomerId, out var p);
            var online = r.LastOnline.HasValue && (now - r.LastOnline.Value) < TimeSpan.FromMinutes(5);
            return new MemberDto(
                r.Id, r.CustomerId, r.CustomerName, r.Phone, r.DeviceId, r.DeviceName, online,
                r.Pin, r.CardNumber, r.DeviceUserId,
                r.DeviceUserId is Guid a && fp.TryGetValue(a, out var fc) ? fc : 0,
                r.DeviceUserId is Guid b && face.TryGetValue(b, out var fcc) ? fcc : 0,
                p?.PackageName, p != null && PosCustomerSessionBalance.IsUnlimitedCount(p.TotalSessions),
                p?.RemainingSessions, p?.ExpiresAt,
                lastVisits.TryGetValue(r.CustomerId, out var lv) ? lv : null, r.CreatedAt);
        }).ToList();
        return Ok(AppResponse<List<MemberDto>>.Success(list));
    }

    /// <summary>Đăng ký khách lên máy: tạo người dùng trên máy với PIN hội viên (cùng PIN trên mọi máy chọn).</summary>
    [HttpPost("members")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<List<MemberDto>>>> AddMember([FromBody] AddMemberDto dto)
    {
        var storeId = RequiredStoreId;
        var customer = await db.PosCustomers.AsNoTracking()
            .FirstOrDefaultAsync(c => c.Id == dto.CustomerId && c.StoreId == storeId && c.Deleted == null);
        if (customer == null)
            return BadRequest(AppResponse<List<MemberDto>>.Fail("Không tìm thấy khách hàng"));
        var deviceIds = (dto.DeviceIds ?? []).Distinct().ToList();
        if (deviceIds.Count == 0)
            return BadRequest(AppResponse<List<MemberDto>>.Fail("Chọn ít nhất một máy chấm công"));
        var devices = await db.Devices.AsNoTracking()
            .Where(d => deviceIds.Contains(d.Id) && d.StoreId == storeId && d.Deleted == null)
            .ToListAsync();
        if (devices.Count != deviceIds.Count)
            return BadRequest(AppResponse<List<MemberDto>>.Fail("Máy chấm công không thuộc cửa hàng"));

        var existing = await db.PosGymMemberDevices.AsNoTracking()
            .Where(m => m.StoreId == storeId && m.CustomerId == customer.Id && m.Deleted == null)
            .ToListAsync();
        var targets = devices.Where(d => existing.All(e => e.DeviceId != d.Id)).ToList();
        if (targets.Count == 0)
            return BadRequest(AppResponse<List<MemberDto>>.Fail("Khách đã có trên các máy đã chọn"));

        // Giữ cùng một PIN cho khách trên mọi máy (dễ tra cứu); lấy PIN cũ nếu đã có.
        var targetIds = targets.Select(t => t.Id).ToList();
        var usedPins = (await db.DeviceUsers.AsNoTracking()
                .Where(u => targetIds.Contains(u.DeviceId))
                .Select(u => u.Pin).ToListAsync())
            .ToHashSet(StringComparer.Ordinal);
        var pin = existing.Select(e => e.Pin).FirstOrDefault(p => !usedPins.Contains(p))
            ?? DeviceUserPinAllocator.AllocateMember(usedPins);

        var card = string.IsNullOrWhiteSpace(dto.CardNumber) ? null : dto.CardNumber.Trim();
        var name = ToDeviceName(customer.Name);
        foreach (var d in targets)
        {
            var res = await bus.Send(new CreateDeviceUserCommand(pin, name, card, null, 0, d.Id));
            if (!res.IsSuccess || res.Data == null)
                return BadRequest(AppResponse<List<MemberDto>>.Fail(
                    $"Không tạo được người dùng trên máy {d.DeviceName}: {res.Message}"));
            if (!PosGymMemberDevice.IsMemberPin(res.Data.Pin))
            {
                await bus.Send(new DeleteDeviceUserCommand(res.Data.Id, true));
                return BadRequest(AppResponse<List<MemberDto>>.Fail(
                    $"PIN hội viên đã bị dùng trên máy {d.DeviceName}, thử lại"));
            }
            db.PosGymMemberDevices.Add(new PosGymMemberDevice
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                CustomerId = customer.Id,
                DeviceId = d.Id,
                DeviceUserId = res.Data.Id,
                Pin = res.Data.Pin,
                CardNumber = card,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });
        }
        await db.SaveChangesAsync();
        return await Members(customer.Name);
    }

    /// <summary>Gỡ hội viên khỏi máy (xóa người dùng trên máy). Lịch sử lượt tập giữ nguyên.</summary>
    [HttpDelete("members/{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> RemoveMember(Guid id)
    {
        var storeId = RequiredStoreId;
        var m = await db.PosGymMemberDevices.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (m == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy hội viên trên máy"));
        if (m.DeviceUserId is Guid du)
            await bus.Send(new DeleteDeviceUserCommand(du, true));
        m.Deleted = DateTime.UtcNow;
        m.DeletedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id }));
    }

    // ── Lượt tập ─────────────────────────────────────────────────────────

    /// <summary>Lượt tập trong kỳ (ngày VN). Mặc định hôm nay.</summary>
    [HttpGet("visits")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Visits(
        [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null, [FromQuery] Guid? customerId = null)
    {
        var storeId = RequiredStoreId;
        var (fromUtc, toUtc) = RangeUtc(from, to);
        var q = db.PosGymVisits.AsNoTracking()
            .Where(v => v.StoreId == storeId && v.CheckInAt >= fromUtc && v.CheckInAt < toUtc);
        if (customerId.HasValue) q = q.Where(v => v.CustomerId == customerId);
        var visits = await LoadVisitsAsync(storeId, q.OrderByDescending(v => v.CheckInAt).Take(2000));
        return Ok(AppResponse<object>.Success(new
        {
            total = visits.Count,
            inside = visits.Count(v => v.CheckOutAt == null
                && DateTime.UtcNow - v.CheckInAt < GymVisitRules.MaxOpenVisit),
            customers = visits.Select(v => v.CustomerId).Distinct().Count(),
            warnings = visits.Count(v => v.Status != "Ok"),
            avgMinutes = visits.Where(v => v.DurationMinutes > 0).Select(v => v.DurationMinutes!.Value)
                .DefaultIfEmpty().Average(),
            items = visits,
        }));
    }

    /// <summary>Check-in tại quầy (khách quên thẻ / chưa lấy vân tay) — cùng quy tắc với máy.</summary>
    [HttpPost("check-in")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<VisitDto>>> CheckIn([FromBody] CheckInDto dto)
    {
        var storeId = RequiredStoreId;
        var exists = await db.PosCustomers.AsNoTracking()
            .AnyAsync(c => c.Id == dto.CustomerId && c.StoreId == storeId && c.Deleted == null);
        if (!exists) return BadRequest(AppResponse<VisitDto>.Fail("Không tìm thấy khách hàng"));
        var visit = await gym.RecordPunchAsync(storeId, dto.CustomerId, DateTime.UtcNow, null, null,
            "Manual", CurrentUserEmail);
        if (visit == null)
            return BadRequest(AppResponse<VisitDto>.Fail("Khách vừa check-in, thử lại sau vài phút"));
        var row = (await LoadVisitsAsync(storeId, db.PosGymVisits.AsNoTracking().Where(v => v.Id == visit.Id)))
            .First();
        return Ok(AppResponse<VisitDto>.Success(row));
    }

    [HttpPost("visits/{id:guid}/check-out")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> CheckOut(Guid id)
    {
        var storeId = RequiredStoreId;
        var v = await db.PosGymVisits.AsTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (v == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy lượt tập"));
        if (v.CheckOutAt.HasValue) return BadRequest(AppResponse<object>.Fail("Lượt tập đã kết thúc"));
        v.CheckOutAt = DateTime.UtcNow;
        v.DurationMinutes = (int)Math.Round((v.CheckOutAt.Value - v.CheckInAt).TotalMinutes);
        v.UpdatedAt = DateTime.UtcNow;
        v.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id, v.CheckOutAt, v.DurationMinutes }));
    }

    /// <summary>Tổng hợp theo hội viên: số lượt, tổng / trung bình thời gian tập. <c>format=excel</c> xuất file.</summary>
    [HttpGet("report")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<IActionResult> Report(
        [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null, [FromQuery] string? format = null)
    {
        var storeId = RequiredStoreId;
        var (fromUtc, toUtc) = RangeUtc(from, to ?? DateTime.UtcNow.AddHours(7).Date,
            defaultFrom: DateTime.UtcNow.AddHours(7).Date.AddDays(1 - DateTime.UtcNow.AddHours(7).Day));
        var raw = await db.PosGymVisits.AsNoTracking()
            .Where(v => v.StoreId == storeId && v.CheckInAt >= fromUtc && v.CheckInAt < toUtc)
            .Select(v => new
            {
                v.CustomerId,
                Name = v.Customer != null ? v.Customer.Name : "",
                Phone = v.Customer != null ? v.Customer.Phone : null,
                v.CheckInAt, v.DurationMinutes, v.Status,
            })
            .ToListAsync();
        var packs = await BestPackagesAsync(storeId, raw.Select(r => r.CustomerId).Distinct().ToList());
        var rows = raw.GroupBy(r => r.CustomerId).Select(g =>
        {
            packs.TryGetValue(g.Key, out var p);
            var dur = g.Where(x => x.DurationMinutes > 0).Select(x => x.DurationMinutes!.Value).ToList();
            return new
            {
                customerName = g.First().Name,
                phone = g.First().Phone,
                visits = g.Count(),
                days = g.Select(x => x.CheckInAt.AddHours(7).Date).Distinct().Count(),
                totalHours = Math.Round(dur.Sum() / 60.0, 1),
                avgMinutes = dur.Count == 0 ? 0 : (int)Math.Round(dur.Average()),
                warnings = g.Count(x => x.Status != "Ok"),
                lastVisit = ReportHelpers.ToVn(g.Max(x => x.CheckInAt)).ToString("dd/MM/yyyy HH:mm"),
                package = p?.PackageName ?? "Chưa có thẻ / gói",
                remaining = p == null ? "" : PosCustomerSessionBalance.IsUnlimitedCount(p.TotalSessions)
                    ? "Không giới hạn" : $"{p.RemainingSessions}",
                expiresAt = p?.ExpiresAt is DateTime e ? ReportHelpers.ToVn(e).ToString("dd/MM/yyyy") : "",
                customerId = g.Key,
            };
        }).OrderByDescending(x => x.visits).ToList();

        var fromVn = fromUtc.AddHours(7);
        var toVn = toUtc.AddHours(7).AddDays(-1);
        if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
        {
            return ReportHelpers.ExcelFile("Luot tap hoi vien",
                new[] { "STT", "Hội viên", "Điện thoại", "Số lượt", "Số ngày tập", "Tổng giờ", "TB phút/lượt",
                        "Cảnh báo", "Lần cuối", "Thẻ / gói", "Còn lại", "Hết hạn" },
                (ws, start) =>
                {
                    var r = start;
                    var i = 1;
                    foreach (var x in rows)
                    {
                        ws.Cell(r, 1).Value = i++;
                        ws.Cell(r, 2).Value = x.customerName;
                        ws.Cell(r, 3).Value = x.phone ?? "";
                        ws.Cell(r, 4).Value = x.visits;
                        ws.Cell(r, 5).Value = x.days;
                        ws.Cell(r, 6).Value = x.totalHours;
                        ws.Cell(r, 7).Value = x.avgMinutes;
                        ws.Cell(r, 8).Value = x.warnings;
                        ws.Cell(r, 9).Value = x.lastVisit;
                        ws.Cell(r, 10).Value = x.package;
                        ws.Cell(r, 11).Value = x.remaining;
                        ws.Cell(r, 12).Value = x.expiresAt;
                        r++;
                    }
                },
                $"luot-tap-hoi-vien-{fromVn:yyyyMMdd}-{toVn:yyyyMMdd}.xlsx", user: User);
        }
        return Ok(AppResponse<object>.Success(new
        {
            from = fromVn, to = toVn,
            totalVisits = raw.Count,
            members = rows.Count,
            totalHours = Math.Round(raw.Where(x => x.DurationMinutes > 0).Sum(x => x.DurationMinutes!.Value) / 60.0, 1),
            items = rows,
        }));
    }

    // ── helpers ──────────────────────────────────────────────────────────

    static (DateTime FromUtc, DateTime ToUtc) RangeUtc(DateTime? from, DateTime? to, DateTime? defaultFrom = null)
    {
        var todayVn = DateTime.UtcNow.AddHours(7).Date;
        var f = (from ?? defaultFrom ?? todayVn).Date;
        var t = (to ?? f).Date;
        if (t < f) (f, t) = (t, f);
        if ((t - f).TotalDays > 366) f = t.AddDays(-366);
        return (f.AddHours(-7), t.AddDays(1).AddHours(-7));
    }

    /// <summary>Tên hiển thị trên máy: bỏ dấu tiếng Việt (nhiều máy không hiển thị được), tối đa 24 ký tự.</summary>
    static string ToDeviceName(string name)
    {
        var normalized = (name ?? "").Replace('đ', 'd').Replace('Đ', 'D').Normalize(System.Text.NormalizationForm.FormD);
        var chars = normalized.Where(c =>
            System.Globalization.CharUnicodeInfo.GetUnicodeCategory(c) != System.Globalization.UnicodeCategory.NonSpacingMark);
        var s = new string(chars.ToArray()).Trim();
        if (s.Length == 0) s = "Hoi vien";
        return s.Length > 24 ? s[..24] : s;
    }

    /// <summary>Thẻ / gói nên dùng của mỗi khách: còn hạn, ưu tiên thẻ thời gian, rồi gói hết hạn sớm nhất.</summary>
    async Task<Dictionary<Guid, PosCustomerSessionBalance>> BestPackagesAsync(Guid storeId, List<Guid> customerIds)
    {
        if (customerIds.Count == 0) return [];
        var now = DateTime.UtcNow;
        var balances = await db.PosCustomerSessionBalances.AsNoTracking()
            .Where(b => b.StoreId == storeId && customerIds.Contains(b.CustomerId) && b.Deleted == null)
            .ToListAsync();
        return balances
            .GroupBy(b => b.CustomerId)
            .ToDictionary(g => g.Key, g =>
            {
                var active = g.Where(b => b.RemainingSessions > 0 && (b.ExpiresAt == null || b.ExpiresAt > now))
                    .OrderByDescending(b => PosCustomerSessionBalance.IsUnlimitedCount(b.TotalSessions))
                    .ThenBy(b => b.ExpiresAt ?? DateTime.MaxValue)
                    .FirstOrDefault();
                // Không còn gói hợp lệ → trả gói gần nhất để hiển thị "hết hạn / hết buổi".
                return active ?? g.OrderByDescending(b => b.ExpiresAt ?? b.CreatedAt).First();
            });
    }

    async Task<List<VisitDto>> LoadVisitsAsync(Guid storeId, IQueryable<PosGymVisit> q)
    {
        var rows = await q.Select(v => new
        {
            v.Id, v.CustomerId,
            CustomerName = v.Customer != null ? v.Customer.Name : "",
            Phone = v.Customer != null ? v.Customer.Phone : null,
            v.DeviceId, v.CheckInAt, v.CheckOutAt, v.DurationMinutes, v.PackageName,
            v.SessionDeducted, v.Status, v.Source, v.Note, v.BalanceId,
        }).ToListAsync();
        var deviceIds = rows.Where(r => r.DeviceId.HasValue).Select(r => r.DeviceId!.Value).Distinct().ToList();
        var deviceNames = await db.Devices.AsNoTracking()
            .Where(d => deviceIds.Contains(d.Id))
            .ToDictionaryAsync(d => d.Id, d => d.DeviceName);
        var packs = await BestPackagesAsync(storeId, rows.Select(r => r.CustomerId).Distinct().ToList());
        return rows.Select(r =>
        {
            packs.TryGetValue(r.CustomerId, out var p);
            return new VisitDto(
                r.Id, r.CustomerId, r.CustomerName, r.Phone,
                r.DeviceId is Guid d && deviceNames.TryGetValue(d, out var dn) ? dn : (r.Source == "Manual" ? "Tại quầy" : null),
                r.CheckInAt, r.CheckOutAt, r.DurationMinutes, r.PackageName, r.SessionDeducted,
                r.Status, r.Source, r.Note,
                p != null && PosCustomerSessionBalance.IsUnlimitedCount(p.TotalSessions),
                p?.RemainingSessions, p?.ExpiresAt);
        }).ToList();
    }
}
