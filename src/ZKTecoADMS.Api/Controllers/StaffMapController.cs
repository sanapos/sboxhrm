using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Bản đồ nhân sự: vị trí hiện tại của TẤT CẢ nhân viên đang làm việc (không chỉ NV chấm ngoài công ty)
/// và lộ trình di chuyển trong ca (từ lịch sử GPS app gửi định kỳ, hành trình, chấm công, check-in điểm).
/// Giờ ca lưu theo giờ Việt Nam; thời điểm GPS lưu UTC.
/// </summary>
[ApiController]
[Route("api/staff-map")]
[Authorize(Policy = PolicyNames.AtLeastManager)]
public class StaffMapController(ZKTecoDbContext db, IMemoryCache cache) : AuthenticatedControllerBase
{
    const int VnOffsetHours = 7;
    /// <summary>Có vị trí trong 10 phút gần nhất → trực tuyến.</summary>
    public const int OnlineMinutes = 10;
    /// <summary>10–60 phút → vừa mất tín hiệu; lâu hơn → ngoại tuyến.</summary>
    public const int StaleMinutes = 60;

    static DateTime VnNow => DateTime.UtcNow.AddHours(VnOffsetHours);
    static DateTime VnToUtc(DateTime vn) => DateTime.SpecifyKind(vn.AddHours(-VnOffsetHours), DateTimeKind.Utc);
    static DateTime AsUtc(DateTime d) => d.Kind switch
    {
        DateTimeKind.Utc => d,
        DateTimeKind.Local => d.ToUniversalTime(),
        _ => DateTime.SpecifyKind(d, DateTimeKind.Utc),
    };

    sealed record Emp(Guid Id, string Code, string Name, string? Department, string? Position, string? PhotoUrl, Guid? UserId)
    {
        public HashSet<string> Keys { get; } = new(StringComparer.OrdinalIgnoreCase);
    }

    async Task<List<Emp>> EmployeesAsync(Guid storeId, Guid? onlyId = null)
    {
        var q = db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null && e.WorkStatus == EmployeeWorkStatus.Active);
        if (onlyId.HasValue) q = db.Employees.AsNoTracking().Where(e => e.StoreId == storeId && e.Id == onlyId.Value);
        var rows = await q
            .Select(e => new { e.Id, e.EmployeeCode, e.LastName, e.FirstName, e.Department, e.Position, e.PhotoUrl, e.ApplicationUserId })
            .ToListAsync();
        return rows.Select(e =>
        {
            var emp = new Emp(e.Id, e.EmployeeCode, $"{e.LastName} {e.FirstName}".Trim(), e.Department, e.Position, e.PhotoUrl, e.ApplicationUserId);
            emp.Keys.Add(e.Id.ToString());
            if (!string.IsNullOrWhiteSpace(e.EmployeeCode)) emp.Keys.Add(e.EmployeeCode);
            if (e.ApplicationUserId.HasValue) emp.Keys.Add(e.ApplicationUserId.Value.ToString());
            return emp;
        }).ToList();
    }

    static List<RouteAnalyzer.GeoPoint> ParseJourney(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            return (JsonSerializer.Deserialize<List<RoutePoint>>(json) ?? [])
                .Where(p => p.Lat != 0 || p.Lng != 0)
                .Select(p => new RouteAnalyzer.GeoPoint(p.Lat, p.Lng, AsUtc(p.Time)))
                .ToList();
        }
        catch { return []; }
    }

    static string StatusOf(DateTime? lastUtc, DateTime nowUtc)
    {
        if (lastUtc == null) return "none";
        var min = (nowUtc - lastUtc.Value).TotalMinutes;
        return min <= OnlineMinutes ? "online" : min <= StaleMinutes ? "stale" : "offline";
    }

    // ═════════════ VỊ TRÍ HIỆN TẠI ═════════════

    /// <summary>
    /// Vị trí mới nhất hôm nay của mọi nhân viên đang làm việc + ca hôm nay + trạng thái tín hiệu +
    /// quãng đường hôm nay + đang ở nơi làm việc nào; kèm danh sách nơi làm việc (vẽ vòng bán kính).
    /// </summary>
    [HttpGet("live")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
    public async Task<IActionResult> GetLive(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var nowUtc = DateTime.UtcNow;
        var vnToday = VnNow.Date;
        var dayStartUtc = VnToUtc(vnToday);
        var dayEndUtc = dayStartUtc.AddDays(1);

        var emps = await EmployeesAsync(storeId);
        var keyToEmp = new Dictionary<string, Emp>(StringComparer.OrdinalIgnoreCase);
        foreach (var e in emps)
            foreach (var k in e.Keys) keyToEmp.TryAdd(k, e);
        var userToEmp = emps.Where(e => e.UserId.HasValue).GroupBy(e => e.UserId!.Value).ToDictionary(g => g.Key, g => g.First());

        // Nguồn vị trí: điểm lộ trình (mới nhất / người), vị trí trực tuyến, chấm công GPS, check-in điểm, hành trình
        var lastPoints = await db.EmployeeLocationPoints.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.RecordedAt >= dayStartUtc && p.RecordedAt < dayEndUtc)
            .GroupBy(p => p.UserId)
            .Select(g => new
            {
                UserId = g.Key,
                Count = g.Count(),
                First = g.Min(x => x.RecordedAt),
                Last = g.OrderByDescending(x => x.RecordedAt)
                    .Select(x => new { x.Latitude, x.Longitude, x.Accuracy, x.Speed, x.Battery, x.RecordedAt })
                    .First(),
            })
            .ToListAsync(ct);
        var live = await db.EmployeeLiveLocations.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.UpdatedAt >= dayStartUtc)
            .ToListAsync(ct);
        var punches = await db.MobileAttendanceRecords.AsNoTracking()
            .Where(m => m.StoreId == storeId && m.Deleted == null && m.PunchTime >= dayStartUtc && m.PunchTime < dayEndUtc
                        && m.Latitude != null && m.Longitude != null)
            .Select(m => new { m.OdooEmployeeId, m.Latitude, m.Longitude, m.PunchTime, m.PunchType, m.LocationName })
            .ToListAsync(ct);
        var visits = await db.VisitReports.AsNoTracking()
            .Where(v => v.StoreId == storeId && v.Deleted == null && v.CheckInTime >= dayStartUtc && v.CheckInTime < dayEndUtc
                        && v.CheckInLatitude != null)
            .Select(v => new { v.EmployeeId, v.LocationName, v.CheckInTime, v.CheckOutTime, v.CheckInLatitude, v.CheckInLongitude, v.Status })
            .ToListAsync(ct);
        var journeys = await db.JourneyTrackings.AsNoTracking()
            .Where(j => j.StoreId == storeId && j.Deleted == null && j.JourneyDate == vnToday)
            .Select(j => new { j.EmployeeId, j.RoutePointsJson, j.Status })
            .ToListAsync(ct);

        // Ca hôm nay (đã duyệt)
        var shifts = await db.Shifts.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.Status == ShiftStatus.Approved
                        && s.StartTime >= vnToday.AddHours(-12) && s.StartTime < vnToday.AddDays(1))
            .Select(s => new { s.Id, s.EmployeeUserId, s.StartTime, s.EndTime })
            .ToListAsync(ct);

        var workLocations = await db.MobileWorkLocations.AsNoTracking()
            .Where(w => w.StoreId == storeId && w.Deleted == null && w.IsActive && (w.Latitude != 0 || w.Longitude != 0))
            .Select(w => new { w.Id, w.Name, w.Address, w.Latitude, w.Longitude, w.Radius })
            .ToListAsync(ct);

        var distances = await TodayDistancesAsync(storeId, dayStartUtc, dayEndUtc, ct);
        var vnNow = VnNow;

        var result = emps.Select(e =>
        {
            double? lat = null, lng = null, acc = null, speed = null;
            int? battery = null;
            DateTime? last = null;
            string? source = null;
            void Consider(double la, double ln, DateTime t, string src, double? a = null)
            {
                if (la == 0 && ln == 0) return;
                t = AsUtc(t);
                if (last == null || t > last) { lat = la; lng = ln; last = t; source = src; acc = a; }
            }

            var pt = e.UserId.HasValue ? lastPoints.FirstOrDefault(p => p.UserId == e.UserId.Value) : null;
            if (pt != null)
            {
                Consider(pt.Last.Latitude, pt.Last.Longitude, pt.Last.RecordedAt, "gps", pt.Last.Accuracy);
                if (source == "gps") { speed = pt.Last.Speed; battery = pt.Last.Battery; }
            }
            foreach (var l in live.Where(l => e.Keys.Contains(l.EmployeeId)))
                Consider(l.Latitude, l.Longitude, l.UpdatedAt, "gps", l.Accuracy);
            foreach (var p in punches.Where(p => e.Keys.Contains(p.OdooEmployeeId)))
                Consider(p.Latitude!.Value, p.Longitude!.Value, p.PunchTime, "punch");
            foreach (var v in visits.Where(v => e.Keys.Contains(v.EmployeeId)))
                Consider(v.CheckInLatitude!.Value, v.CheckInLongitude ?? 0, v.CheckOutTime ?? v.CheckInTime!.Value, "checkin");
            var journey = journeys.FirstOrDefault(j => e.Keys.Contains(j.EmployeeId));
            var jp = ParseJourney(journey?.RoutePointsJson);
            if (jp.Count > 0) Consider(jp[^1].Lat, jp[^1].Lng, jp[^1].TimeUtc, "journey");

            var empShifts = e.UserId.HasValue ? shifts.Where(s => s.EmployeeUserId == e.UserId.Value).OrderBy(s => s.StartTime).ToList() : [];
            var current = empShifts.FirstOrDefault(s => s.StartTime.AddMinutes(-30) <= vnNow && s.EndTime.AddMinutes(15) >= vnNow);
            var shown = current ?? empShifts.FirstOrDefault(s => s.StartTime > vnNow) ?? empShifts.LastOrDefault();
            var status = StatusOf(last, nowUtc);

            string? atWork = null;
            if (lat.HasValue)
            {
                var near = workLocations
                    .Select(w => new { w.Name, w.Radius, D = RouteAnalyzer.DistanceMeters(w.Latitude, w.Longitude, lat.Value, lng!.Value) })
                    .Where(x => x.D <= Math.Max(x.Radius, 50) + (acc ?? 0))
                    .OrderBy(x => x.D).FirstOrDefault();
                atWork = near?.Name;
            }

            return new
            {
                employeeId = e.Id,
                employeeCode = e.Code,
                employeeName = e.Name,
                department = string.IsNullOrWhiteSpace(e.Department) ? "Chưa phân phòng" : e.Department,
                position = e.Position,
                photoUrl = e.PhotoUrl,
                hasAccount = e.UserId.HasValue,
                latitude = lat,
                longitude = lng,
                accuracy = acc,
                speedKmh = speed.HasValue ? Math.Round(speed.Value * 3.6, 1) : (double?)null,
                battery,
                lastUpdate = last,
                minutesAgo = last.HasValue ? (int)(nowUtc - last.Value).TotalMinutes : (int?)null,
                source,
                status,
                onShift = current != null,
                // Đang trong ca mà không có tín hiệu → cần kiểm tra (tắt app / tắt định vị / hết pin)
                signalLostOnShift = current != null && status != "online",
                shiftId = shown?.Id,
                shiftStart = shown?.StartTime,
                shiftEnd = shown?.EndTime,
                atWorkLocation = atWork,
                pointsToday = pt?.Count ?? 0,
                firstSeenToday = pt?.First,
                distanceTodayKm = e.UserId.HasValue ? distances.GetValueOrDefault(e.UserId.Value) : 0,
                journeyStatus = journey?.Status,
                activeCheckin = visits.Where(v => e.Keys.Contains(v.EmployeeId) && v.Status == "checked_in")
                    .Select(v => v.LocationName).FirstOrDefault(),
            };
        })
        .OrderBy(x => x.status switch { "online" => 0, "stale" => 1, "offline" => 2, _ => 3 })
        .ThenBy(x => x.department).ThenBy(x => x.employeeName)
        .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            serverTimeUtc = nowUtc,
            date = vnToday,
            onlineMinutes = OnlineMinutes,
            staleMinutes = StaleMinutes,
            summary = new
            {
                total = result.Count,
                online = result.Count(r => r.status == "online"),
                stale = result.Count(r => r.status == "stale"),
                offline = result.Count(r => r.status == "offline"),
                noLocation = result.Count(r => r.status == "none"),
                onShift = result.Count(r => r.onShift),
                signalLostOnShift = result.Count(r => r.signalLostOnShift),
                atWork = result.Count(r => r.atWorkLocation != null && r.status == "online"),
                noAccount = result.Count(r => !r.hasAccount),
            },
            departments = result.Select(r => r.department).Distinct().OrderBy(d => d),
            workLocations,
            employees = result,
        }));
    }

    /// <summary>Quãng đường hôm nay theo tài khoản (cache 2 phút — tránh tính lại mỗi lần bản đồ tự làm mới).</summary>
    async Task<Dictionary<Guid, double>> TodayDistancesAsync(Guid storeId, DateTime fromUtc, DateTime toUtc, CancellationToken ct)
    {
        var key = $"staffmap:dist:{storeId}:{fromUtc:yyyyMMdd}";
        if (cache.TryGetValue(key, out Dictionary<Guid, double>? cached) && cached != null) return cached;
        var pts = await db.EmployeeLocationPoints.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.RecordedAt >= fromUtc && p.RecordedAt < toUtc)
            .Select(p => new { p.UserId, p.Latitude, p.Longitude, p.Accuracy, p.RecordedAt })
            .ToListAsync(ct);
        var map = pts.GroupBy(p => p.UserId).ToDictionary(
            g => g.Key,
            g => RouteAnalyzer.DistanceKm(RouteAnalyzer.Clean(
                g.Select(p => new RouteAnalyzer.GeoPoint(p.Latitude, p.Longitude, AsUtc(p.RecordedAt), p.Accuracy)))));
        // MemoryCache của API có SizeLimit → bắt buộc khai báo Size.
        cache.Set(key, map, new MemoryCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(2),
            Size = 1,
        });
        return map;
    }

    // ═════════════ LỘ TRÌNH TRONG CA ═════════════

    /// <summary>
    /// Lộ trình di chuyển của 1 nhân viên trong ngày / trong ca: đường đi, điểm dừng, mất tín hiệu,
    /// chấm công vào/ra, check-in điểm bán, dòng thời gian và tổng hợp (km, thời gian di chuyển / dừng).
    /// </summary>
    [HttpGet("route")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
    public async Task<IActionResult> GetRoute(
        [FromQuery] Guid employeeId, [FromQuery] DateTime? date, [FromQuery] Guid? shiftId,
        [FromQuery] bool wholeDay = false, CancellationToken ct = default)
    {
        var storeId = RequiredStoreId;
        var emp = (await EmployeesAsync(storeId, employeeId)).FirstOrDefault();
        if (emp == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy nhân viên"));

        var day = (date ?? VnNow).Date;
        var shifts = emp.UserId.HasValue
            ? await db.Shifts.AsNoTracking()
                .Where(s => s.StoreId == storeId && s.EmployeeUserId == emp.UserId.Value && s.Status == ShiftStatus.Approved
                            && s.StartTime >= day && s.StartTime < day.AddDays(1))
                .OrderBy(s => s.StartTime)
                .Select(s => new { s.Id, s.StartTime, s.EndTime, s.Description })
                .ToListAsync(ct)
            : [];

        // Khung thời gian: ca được chọn → các ca trong ngày → cả ngày
        DateTime fromVn, toVn;
        var selected = shiftId.HasValue ? shifts.FirstOrDefault(s => s.Id == shiftId) : null;
        if (!wholeDay && selected != null) { fromVn = selected.StartTime.AddMinutes(-30); toVn = selected.EndTime.AddMinutes(15); }
        else if (!wholeDay && shifts.Count > 0) { fromVn = shifts.Min(s => s.StartTime).AddMinutes(-30); toVn = shifts.Max(s => s.EndTime).AddMinutes(15); }
        else { fromVn = day; toVn = day.AddDays(1); }
        var fromUtc = VnToUtc(fromVn);
        var toUtc = VnToUtc(toVn);

        var raw = new List<RouteAnalyzer.GeoPoint>();
        if (emp.UserId.HasValue)
        {
            var uid = emp.UserId.Value;
            raw.AddRange(await db.EmployeeLocationPoints.AsNoTracking()
                .Where(p => p.StoreId == storeId && (p.UserId == uid || p.EmployeeId == emp.Id)
                            && p.RecordedAt >= fromUtc && p.RecordedAt < toUtc)
                .Select(p => new RouteAnalyzer.GeoPoint(p.Latitude, p.Longitude, p.RecordedAt, p.Accuracy))
                .ToListAsync(ct));
        }
        var keys = emp.Keys.ToList();
        var journeyJson = await db.JourneyTrackings.AsNoTracking()
            .Where(j => j.StoreId == storeId && j.Deleted == null && j.JourneyDate == day && keys.Contains(j.EmployeeId))
            .Select(j => j.RoutePointsJson).ToListAsync(ct);
        foreach (var js in journeyJson)
            raw.AddRange(ParseJourney(js).Where(p => p.TimeUtc >= fromUtc && p.TimeUtc < toUtc));
        raw = raw.Select(p => p with { TimeUtc = AsUtc(p.TimeUtc) }).ToList();

        var punches = await db.MobileAttendanceRecords.AsNoTracking()
            .Where(m => m.StoreId == storeId && m.Deleted == null && keys.Contains(m.OdooEmployeeId)
                        && m.PunchTime >= fromUtc && m.PunchTime < toUtc)
            .OrderBy(m => m.PunchTime)
            .Select(m => new { m.PunchTime, m.PunchType, m.Latitude, m.Longitude, m.LocationName, m.Status })
            .ToListAsync(ct);
        var visits = await db.VisitReports.AsNoTracking()
            .Where(v => v.StoreId == storeId && v.Deleted == null && keys.Contains(v.EmployeeId)
                        && v.CheckInTime >= fromUtc && v.CheckInTime < toUtc)
            .OrderBy(v => v.CheckInTime)
            .Select(v => new { v.LocationName, v.CheckInTime, v.CheckOutTime, v.TimeSpentMinutes, v.CheckInLatitude, v.CheckInLongitude, v.OutsideRadius })
            .ToListAsync(ct);
        var workLocations = await db.MobileWorkLocations.AsNoTracking()
            .Where(w => w.StoreId == storeId && w.Deleted == null && w.IsActive)
            .Select(w => new { w.Name, w.Latitude, w.Longitude, w.Radius })
            .ToListAsync(ct);

        // Điểm chấm công / check-in có GPS cũng là vị trí thực tế của người đó
        raw.AddRange(punches.Where(p => p.Latitude.HasValue && p.Longitude.HasValue)
            .Select(p => new RouteAnalyzer.GeoPoint(p.Latitude!.Value, p.Longitude!.Value, AsUtc(p.PunchTime))));
        raw.AddRange(visits.Where(v => v.CheckInLatitude.HasValue && v.CheckInLongitude.HasValue)
            .Select(v => new RouteAnalyzer.GeoPoint(v.CheckInLatitude!.Value, v.CheckInLongitude!.Value, AsUtc(v.CheckInTime!.Value))));

        var analysis = RouteAnalyzer.Analyze(raw);
        var clean = RouteAnalyzer.Clean(raw);
        var shown = RouteAnalyzer.Downsample(clean);

        string? PlaceName(double lat, double lng)
        {
            var v = visits.Where(x => x.CheckInLatitude.HasValue && x.CheckInLongitude.HasValue)
                .Select(x => new { x.LocationName, D = RouteAnalyzer.DistanceMeters(x.CheckInLatitude!.Value, x.CheckInLongitude!.Value, lat, lng) })
                .Where(x => x.D <= 150).OrderBy(x => x.D).FirstOrDefault();
            if (v != null) return v.LocationName;
            var w = workLocations
                .Select(x => new { x.Name, x.Radius, D = RouteAnalyzer.DistanceMeters(x.Latitude, x.Longitude, lat, lng) })
                .Where(x => x.D <= Math.Max(x.Radius, 80)).OrderBy(x => x.D).FirstOrDefault();
            return w?.Name;
        }

        var stops = analysis.Stops.Select((s, i) => new
        {
            index = i + 1,
            lat = s.Lat,
            lng = s.Lng,
            start = s.StartUtc,
            end = s.EndUtc,
            minutes = Math.Round(s.Minutes),
            place = PlaceName(s.Lat, s.Lng),
        }).ToList();

        // Dòng thời gian
        var timeline = new List<(DateTime t, object e)>();
        foreach (var s in shifts)
        {
            timeline.Add((VnToUtc(s.StartTime), new { type = "shift_start", time = VnToUtc(s.StartTime), title = $"Bắt đầu ca {s.StartTime:HH:mm}–{s.EndTime:HH:mm}" }));
            timeline.Add((VnToUtc(s.EndTime), new { type = "shift_end", time = VnToUtc(s.EndTime), title = "Kết thúc ca" }));
        }
        foreach (var p in punches)
        {
            var label = p.PunchType switch { 0 => "Chấm công vào", 1 => "Chấm công ra", 2 => "Bắt đầu đi công tác", 3 => "Đến điểm làm việc", _ => "Chấm công" };
            timeline.Add((AsUtc(p.PunchTime), new
            {
                type = p.PunchType == 1 ? "punch_out" : "punch_in",
                time = AsUtc(p.PunchTime),
                title = label,
                detail = p.LocationName,
                lat = p.Latitude, lng = p.Longitude,
            }));
        }
        foreach (var v in visits)
        {
            timeline.Add((AsUtc(v.CheckInTime!.Value), new
            {
                type = "checkin",
                time = AsUtc(v.CheckInTime!.Value),
                title = $"Check-in {v.LocationName}",
                detail = v.CheckOutTime.HasValue ? $"Ở lại {v.TimeSpentMinutes ?? (int)(v.CheckOutTime.Value - v.CheckInTime.Value).TotalMinutes} phút"
                    : "Đang ở điểm",
                warning = v.OutsideRadius ? "Ngoài bán kính điểm" : null,
                lat = v.CheckInLatitude, lng = v.CheckInLongitude,
            }));
        }
        foreach (var s in stops)
            timeline.Add((s.start, new
            {
                type = "stop",
                time = s.start,
                end = s.end,
                title = $"Dừng {s.minutes} phút" + (s.place != null ? $" tại {s.place}" : ""),
                index = s.index,
                lat = s.lat, lng = s.lng,
            }));
        foreach (var g in analysis.Gaps)
            timeline.Add((g.FromUtc, new
            {
                type = "gap",
                time = g.FromUtc,
                end = g.ToUtc,
                title = $"Mất tín hiệu {Math.Round(g.Minutes)} phút",
                detail = "App bị tắt, mất mạng hoặc tắt định vị",
            }));
        if (clean.Count > 0)
        {
            timeline.Add((clean[0].TimeUtc, new { type = "first", time = clean[0].TimeUtc, title = "Vị trí đầu tiên", lat = clean[0].Lat, lng = clean[0].Lng }));
            timeline.Add((clean[^1].TimeUtc, new { type = "last", time = clean[^1].TimeUtc, title = "Vị trí cuối cùng", lat = clean[^1].Lat, lng = clean[^1].Lng }));
        }

        return Ok(AppResponse<object>.Success(new
        {
            employee = new { id = emp.Id, code = emp.Code, name = emp.Name, department = emp.Department, position = emp.Position, photoUrl = emp.PhotoUrl },
            date = day,
            fromUtc,
            toUtc,
            windowLabel = selected != null ? $"Ca {selected.StartTime:HH:mm}–{selected.EndTime:HH:mm}"
                : !wholeDay && shifts.Count > 0 ? $"Trong ca ({shifts.Min(s => s.StartTime):HH:mm}–{shifts.Max(s => s.EndTime):HH:mm})"
                : "Cả ngày",
            shifts = shifts.Select(s => new { id = s.Id, start = s.StartTime, end = s.EndTime, label = $"{s.StartTime:HH:mm}–{s.EndTime:HH:mm}" }),
            summary = new
            {
                distanceKm = analysis.DistanceKm,
                movingMinutes = analysis.MovingMinutes,
                stoppedMinutes = analysis.StoppedMinutes,
                trackedMinutes = analysis.TrackedMinutes,
                gapMinutes = Math.Round(analysis.Gaps.Sum(g => g.Minutes)),
                first = analysis.FirstUtc,
                last = analysis.LastUtc,
                stops = stops.Count,
                gaps = analysis.Gaps.Count,
                rawPoints = analysis.RawPoints,
                droppedPoints = analysis.DroppedPoints,
                maxSpeedKmh = analysis.MaxSpeedKmh,
                punches = punches.Count,
                checkins = visits.Count,
            },
            points = shown.Select(p => new { lat = p.Lat, lng = p.Lng, t = p.TimeUtc, acc = p.Accuracy }),
            stops,
            gaps = analysis.Gaps.Select(g => new { from = g.FromUtc, to = g.ToUtc, minutes = Math.Round(g.Minutes) }),
            workLocations,
            timeline = timeline.OrderBy(x => x.t).Select(x => x.e),
        }));
    }
}
