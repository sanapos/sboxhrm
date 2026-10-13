using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Mạng cửa hàng: thiết bị POS gửi số liệu mạng 5 phút / lần (ping, lỗi gọi server, rớt realtime, máy in LAN);
/// báo cáo kết luận mạng có đủ ổn định để order / in qua mạng không.
/// </summary>
[ApiController]
[Route("api/pos/network")]
[Authorize]
public class PosNetworkController(ZKTecoDbContext db, ILogger<PosNetworkController> logger)
    : AuthenticatedControllerBase
{
    const int MaxPad = 256 * 1024;
    static readonly TimeSpan Retention = TimeSpan.FromDays(35);

    /// <summary>Đo độ trễ (rất nhẹ, không truy vấn CSDL). [pad] = số byte trả thêm để đo tốc độ tải về.</summary>
    [HttpGet("ping")]
    public IActionResult Ping([FromQuery] int pad = 0)
    {
        Response.Headers.CacheControl = "no-store";
        var n = Math.Clamp(pad, 0, MaxPad);
        return Ok(new { t = DateTime.UtcNow, pad = n == 0 ? null : new string('x', n) });
    }

    /// <summary>Đo tốc độ tải lên — nhận rồi bỏ.</summary>
    [HttpPost("ping")]
    [RequestSizeLimit(MaxPad + 4096)]
    public async Task<IActionResult> PingUpload(CancellationToken ct)
    {
        long n = 0;
        var buf = new byte[16 * 1024];
        int r;
        while ((r = await Request.Body.ReadAsync(buf, ct)) > 0) n += r;
        return Ok(new { t = DateTime.UtcNow, bytes = n });
    }

    public class SampleDto
    {
        public DateTime BucketStart { get; set; }
        public string? ConnType { get; set; }
        public int? WifiRssi { get; set; }
        public int ApiCalls { get; set; }
        public int ApiErrors { get; set; }
        public int ApiTimeouts { get; set; }
        public int PingSent { get; set; }
        public int PingFailed { get; set; }
        public int? PingP50Ms { get; set; }
        public int? PingP95Ms { get; set; }
        public int? PingMaxMs { get; set; }
        public int OfflineSec { get; set; }
        public int RealtimeDisconnects { get; set; }
        public int RealtimeDownSec { get; set; }
        public int PrinterChecks { get; set; }
        public int PrinterFailed { get; set; }
        public int? PrinterAvgMs { get; set; }
    }

    public class SamplesDto
    {
        public string? DeviceId { get; set; }
        public string? DeviceName { get; set; }
        public string? Platform { get; set; }
        public string? AppVersion { get; set; }
        public bool IsAgent { get; set; }
        public List<SampleDto>? Samples { get; set; }
    }

    static string? Cut(string? s, int max) =>
        string.IsNullOrWhiteSpace(s) ? null : (s.Trim().Length <= max ? s.Trim() : s.Trim()[..max]);

    static int C(int v, int max) => Math.Clamp(v, 0, max);
    static int? C(int? v, int min, int max) => v == null ? null : Math.Clamp(v.Value, min, max);

    internal static DateTime AlignBucket(DateTime t)
    {
        var u = t.Kind == DateTimeKind.Unspecified ? DateTime.SpecifyKind(t, DateTimeKind.Utc) : t.ToUniversalTime();
        return new DateTime(u.Year, u.Month, u.Day, u.Hour, u.Minute / 5 * 5, 0, DateTimeKind.Utc);
    }

    /// <summary>Nhận số liệu các khung 5 phút đã đóng (gửi lại cùng khung = ghi đè, không nhân đôi).</summary>
    [HttpPost("samples")]
    public async Task<ActionResult<AppResponse<object>>> PostSamples([FromBody] SamplesDto? dto, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var deviceId = Cut(dto?.DeviceId, 128);
        if (deviceId == null || dto?.Samples == null || dto.Samples.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Thiếu thiết bị / số liệu"));
        var now = DateTime.UtcNow;
        var rows = dto.Samples
            .Take(600)
            .Select(s => (Bucket: AlignBucket(s.BucketStart), S: s))
            .Where(x => x.Bucket > now - Retention && x.Bucket <= now.AddMinutes(10))
            .GroupBy(x => x.Bucket)
            .Select(g => g.Last())
            .ToList();
        if (rows.Count == 0) return Ok(AppResponse<object>.Success(new { saved = 0 }));

        var buckets = rows.Select(r => r.Bucket).ToList();
        var existing = await db.PosNetworkSamples
            .Where(x => x.StoreId == storeId && x.DeviceId == deviceId && buckets.Contains(x.BucketStart))
            .ToDictionaryAsync(x => x.BucketStart, ct);
        foreach (var (bucket, s) in rows)
        {
            if (!existing.TryGetValue(bucket, out var e))
            {
                e = new PosNetworkSample { Id = Guid.NewGuid(), StoreId = storeId, DeviceId = deviceId, BucketStart = bucket };
                db.PosNetworkSamples.Add(e);
            }
            else
            {
                e.UpdatedAt = now;
            }
            e.DeviceName = Cut(dto.DeviceName, 200);
            e.Platform = Cut(dto.Platform, 16);
            e.AppVersion = Cut(dto.AppVersion, 32);
            e.IsAgent = dto.IsAgent;
            e.ConnType = Cut(s.ConnType, 16);
            e.WifiRssi = C(s.WifiRssi, -127, 0);
            e.ApiCalls = C(s.ApiCalls, 100_000);
            e.ApiErrors = C(s.ApiErrors, 100_000);
            e.ApiTimeouts = C(s.ApiTimeouts, 100_000);
            e.PingSent = C(s.PingSent, 1000);
            e.PingFailed = Math.Min(C(s.PingFailed, 1000), e.PingSent);
            e.PingP50Ms = C(s.PingP50Ms, 0, 120_000);
            e.PingP95Ms = C(s.PingP95Ms, 0, 120_000);
            e.PingMaxMs = C(s.PingMaxMs, 0, 120_000);
            e.OfflineSec = C(s.OfflineSec, 300);
            e.RealtimeDisconnects = C(s.RealtimeDisconnects, 1000);
            e.RealtimeDownSec = C(s.RealtimeDownSec, 300);
            e.PrinterChecks = C(s.PrinterChecks, 1000);
            e.PrinterFailed = Math.Min(C(s.PrinterFailed, 1000), e.PrinterChecks);
            e.PrinterAvgMs = C(s.PrinterAvgMs, 0, 60_000);
        }
        try
        {
            await db.SaveChangesAsync(ct);
        }
        catch (DbUpdateException ex)
        {
            // Hai lần gửi cùng khung chạy song song — bỏ qua, lần sau gửi lại.
            logger.LogInformation(ex, "Network samples upsert race store {StoreId} device {DeviceId}", storeId, deviceId);
            return Ok(AppResponse<object>.Success(new { saved = 0, retry = true }));
        }

        // Dọn số liệu cũ (thỉnh thoảng — tránh quét mỗi lần gửi).
        if (Random.Shared.Next(50) == 0)
        {
            var cutoff = now - Retention;
            await db.PosNetworkSamples.Where(x => x.StoreId == storeId && x.BucketStart < cutoff)
                .ExecuteDeleteAsync(ct);
        }
        return Ok(AppResponse<object>.Success(new { saved = rows.Count }));
    }

    /// <summary>
    /// Báo cáo mạng cửa hàng. [from]/[to] = ngày giờ VN (yyyy-MM-dd); mặc định hôm nay. Tối đa 31 ngày.
    /// </summary>
    [HttpGet("report")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<PosNetworkReportBuilder.Report>>> Report(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var vnToday = DateTime.UtcNow.AddHours(7).Date;
        var fromVn = (from ?? vnToday).Date;
        var toVnEx = (to ?? fromVn).Date.AddDays(1);
        if (toVnEx <= fromVn) toVnEx = fromVn.AddDays(1);
        if ((toVnEx - fromVn).TotalDays > 31) fromVn = toVnEx.AddDays(-31);
        var fromUtc = DateTime.SpecifyKind(fromVn.AddHours(-7), DateTimeKind.Utc);
        var toUtc = DateTime.SpecifyKind(toVnEx.AddHours(-7), DateTimeKind.Utc);

        var samples = await db.PosNetworkSamples.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.BucketStart >= fromUtc && x.BucketStart < toUtc)
            .ToListAsync(ct);
        var orderTimes = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.CreatedAt >= fromUtc && o.CreatedAt < toUtc)
            .Select(o => o.CreatedAt)
            .ToListAsync(ct);
        var jobs = await db.PosPrintJobs.AsNoTracking()
            .Where(j => j.StoreId == storeId && j.Deleted == null && j.CreatedAt >= fromUtc && j.CreatedAt < toUtc)
            .Select(j => new PosNetworkReportBuilder.JobRow(j.CreatedAt, j.CompletedAt, j.Status, j.ErrorCode))
            .ToListAsync(ct);

        var report = PosNetworkReportBuilder.Build(samples, orderTimes, jobs, fromUtc, toUtc);
        return Ok(AppResponse<PosNetworkReportBuilder.Report>.Success(report));
    }
}
