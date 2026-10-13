using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Báo cáo «Mạng cửa hàng»: từ số liệu 5 phút của các thiết bị POS + số đơn + lệnh in, kết luận mạng có đủ
/// ổn định để order / in qua mạng không, giờ nào tệ, máy nào tệ, và nên làm gì. Thuần tính toán (không DB) để test.
/// </summary>
public static class PosNetworkReportBuilder
{
    static readonly TimeSpan Vn = TimeSpan.FromHours(7);

    // Ngưỡng — chỉnh ở một chỗ.
    public const int GoodP95Ms = 800;
    public const double WarnFailPct = 1;
    public const double BadFailPct = 5;
    public const int WarnOutageSec = 30;
    public const int BadOutageSec = 120;
    public const int WeakWifiDbm = -70;
    public const double SlowPrintSec = 8;

    public record JobRow(DateTime CreatedAt, DateTime? CompletedAt, PosPrintJobStatus Status, string? ErrorCode);

    public record HourRow(
        DateTime HourVn, int Devices, int PingSent, int PingFailed, double FailPct, int? LatencyP95Ms,
        int MaxDeviceOfflineSec, int Disconnects, int Orders, int PrintJobs, double? PrintP95Sec, string Health);

    public record DeviceRow(
        string DeviceId, string? DeviceName, string? Platform, bool IsAgent, DateTime LastSeenVn, int Samples,
        int PingSent, double FailPct, int? LatencyP95Ms, int OfflineSec, int Outages, int Disconnects,
        int? WifiRssi, string? ConnType, int PrinterChecks, int PrinterFailed, string Health);

    public record Outage(string DeviceId, string? DeviceName, bool IsAgent, DateTime StartVn, int Seconds, string Kind);

    public record PrintStats(
        int Total, int Completed, int Failed, int Cancelled, int StaleQueued, int StuckNoRequeue,
        double? P50Sec, double? P95Sec);

    public record Recommendation(string Code, string Level, string Title, string Detail);

    public record Report(
        string Verdict, string VerdictText, int Score, int SampleCount, int DeviceCount,
        double FailPct, int? LatencyP95Ms, int OutageCount, int OutageSeconds, int Disconnects,
        bool DegradesAtPeak, string? PeakNote,
        List<HourRow> Hours, List<DeviceRow> Devices, List<Outage> Outages, PrintStats Print,
        List<Recommendation> Recommendations);

    static int? Pct(IEnumerable<int> values, double p)
    {
        var a = values.OrderBy(x => x).ToList();
        if (a.Count == 0) return null;
        var idx = (int)Math.Ceiling(p * a.Count) - 1;
        return a[Math.Clamp(idx, 0, a.Count - 1)];
    }

    static double? PctD(IEnumerable<double> values, double p)
    {
        var a = values.OrderBy(x => x).ToList();
        if (a.Count == 0) return null;
        var idx = (int)Math.Ceiling(p * a.Count) - 1;
        return Math.Round(a[Math.Clamp(idx, 0, a.Count - 1)], 1);
    }

    static double FailPctOf(int sent, int failed) => sent <= 0 ? 0 : Math.Round(100.0 * failed / sent, 1);

    static string HealthOf(double failPct, int? p95, int maxOffline, int disconnects)
    {
        if (failPct > BadFailPct || maxOffline >= BadOutageSec) return "red";
        if (failPct >= WarnFailPct || (p95 ?? 0) > GoodP95Ms || maxOffline >= WarnOutageSec || disconnects > 0)
            return "yellow";
        return "green";
    }

    static DateTime HourUtc(DateTime t) => new(t.Year, t.Month, t.Day, t.Hour, 0, 0, DateTimeKind.Utc);

    public static Report Build(
        IReadOnlyList<PosNetworkSample> samples,
        IReadOnlyList<DateTime> orderTimesUtc,
        IReadOnlyList<JobRow> jobs,
        DateTime fromUtc,
        DateTime toUtc)
    {
        var ordersByHour = orderTimesUtc.GroupBy(HourUtc).ToDictionary(g => g.Key, g => g.Count());
        var jobsByHour = jobs.GroupBy(j => HourUtc(j.CreatedAt)).ToDictionary(g => g.Key, g => g.ToList());

        // ── Theo giờ ─────────────────────────────────────────────────────────────
        var hours = new List<HourRow>();
        var byHour = samples.GroupBy(s => HourUtc(s.BucketStart)).ToDictionary(g => g.Key, g => g.ToList());
        for (var h = HourUtc(fromUtc); h < toUtc; h = h.AddHours(1))
        {
            byHour.TryGetValue(h, out var hs);
            hs ??= [];
            ordersByHour.TryGetValue(h, out var orders);
            jobsByHour.TryGetValue(h, out var hj);
            hj ??= [];
            if (hs.Count == 0 && orders == 0 && hj.Count == 0) continue;
            var sent = hs.Sum(s => s.PingSent);
            var failed = hs.Sum(s => s.PingFailed);
            var p95 = Pct(hs.Where(s => s.PingP95Ms != null).Select(s => s.PingP95Ms!.Value), 0.95);
            var maxOff = hs.GroupBy(s => s.DeviceId).Select(g => g.Sum(x => x.OfflineSec)).DefaultIfEmpty(0).Max();
            var disc = hs.Sum(s => s.RealtimeDisconnects);
            var failPct = FailPctOf(sent, failed);
            var printP95 = PctD(hj.Where(j => j.CompletedAt != null)
                .Select(j => (j.CompletedAt!.Value - j.CreatedAt).TotalSeconds), 0.95);
            hours.Add(new HourRow(h + Vn, hs.Select(s => s.DeviceId).Distinct().Count(), sent, failed, failPct, p95,
                maxOff, disc, orders, hj.Count, printP95,
                hs.Count == 0 ? "none" : HealthOf(failPct, p95, maxOff, disc)));
        }

        // ── Mất kết nối (gộp các khung 5 phút liền nhau) ─────────────────────────
        var outages = new List<Outage>();
        foreach (var dev in samples.GroupBy(s => s.DeviceId))
        {
            var list = dev.OrderBy(s => s.BucketStart).ToList();
            var name = list.LastOrDefault(s => !string.IsNullOrWhiteSpace(s.DeviceName))?.DeviceName;
            var isAgent = list.Any(s => s.IsAgent);
            void Collect(Func<PosNetworkSample, int> secOf, int minSec, string kind)
            {
                DateTime? start = null;
                DateTime last = default;
                var sec = 0;
                void Flush()
                {
                    if (start != null && sec >= minSec)
                        outages.Add(new Outage(dev.Key, name, isAgent, start.Value + Vn, sec, kind));
                    start = null;
                    sec = 0;
                }
                foreach (var s in list)
                {
                    var v = secOf(s);
                    if (v <= 0)
                    {
                        Flush();
                        continue;
                    }
                    if (start != null && s.BucketStart - last > TimeSpan.FromMinutes(5)) Flush();
                    start ??= s.BucketStart;
                    last = s.BucketStart;
                    sec += v;
                }
                Flush();
            }
            Collect(s => s.OfflineSec, WarnOutageSec, "Mất kết nối máy chủ");
            // Realtime rớt mà vẫn gọi được server (phiếu / bàn cập nhật chậm) — chỉ ghi khi đáng kể.
            Collect(s => s.OfflineSec > 0 ? 0 : s.RealtimeDownSec, 60, "Mất kết nối tức thời (realtime)");
        }
        outages = outages.OrderByDescending(o => o.StartVn).ToList();

        // ── Theo thiết bị ────────────────────────────────────────────────────────
        var devices = samples.GroupBy(s => s.DeviceId).Select(g =>
        {
            var list = g.ToList();
            var sent = list.Sum(s => s.PingSent);
            var failed = list.Sum(s => s.PingFailed);
            var p95 = Pct(list.Where(s => s.PingP95Ms != null).Select(s => s.PingP95Ms!.Value), 0.95);
            var off = list.Sum(s => s.OfflineSec);
            var disc = list.Sum(s => s.RealtimeDisconnects);
            var rssi = list.Where(s => s.WifiRssi != null).Select(s => s.WifiRssi!.Value).ToList();
            var maxOff = outages.Where(o => o.DeviceId == g.Key && o.Kind.StartsWith("Mất kết nối máy"))
                .Select(o => o.Seconds).DefaultIfEmpty(0).Max();
            var failPct = FailPctOf(sent, failed);
            var lastS = list.MaxBy(s => s.BucketStart)!;
            return new DeviceRow(
                g.Key,
                list.LastOrDefault(s => !string.IsNullOrWhiteSpace(s.DeviceName))?.DeviceName,
                lastS.Platform, list.Any(s => s.IsAgent), lastS.BucketStart + Vn, list.Count,
                sent, failPct, p95, off,
                outages.Count(o => o.DeviceId == g.Key && o.Kind.StartsWith("Mất kết nối máy")),
                disc,
                rssi.Count == 0 ? null : (int)Math.Round(rssi.Average()),
                list.Where(s => s.ConnType != null).GroupBy(s => s.ConnType).MaxBy(x => x.Count())?.Key,
                list.Sum(s => s.PrinterChecks), list.Sum(s => s.PrinterFailed),
                HealthOf(failPct, p95, maxOff, disc));
        }).OrderByDescending(d => d.IsAgent).ThenBy(d => d.DeviceName).ToList();

        // ── Lệnh in ──────────────────────────────────────────────────────────────
        var done = jobs.Where(j => j.Status == PosPrintJobStatus.Completed && j.CompletedAt != null)
            .Select(j => (j.CompletedAt!.Value - j.CreatedAt).TotalSeconds).ToList();
        var print = new PrintStats(
            jobs.Count,
            jobs.Count(j => j.Status == PosPrintJobStatus.Completed),
            jobs.Count(j => j.Status == PosPrintJobStatus.Failed),
            jobs.Count(j => j.Status == PosPrintJobStatus.Cancelled),
            jobs.Count(j => j.ErrorCode == "STALE_QUEUED"),
            jobs.Count(j => j.ErrorCode == "STUCK_NO_REQUEUE"),
            PctD(done, 0.5), PctD(done, 0.95));

        // ── Tổng ─────────────────────────────────────────────────────────────────
        var totalSent = samples.Sum(s => s.PingSent);
        var totalFailed = samples.Sum(s => s.PingFailed);
        var failAll = FailPctOf(totalSent, totalFailed);
        var p95All = Pct(samples.Where(s => s.PingP95Ms != null).Select(s => s.PingP95Ms!.Value), 0.95);
        var netOutages = outages.Where(o => o.Kind.StartsWith("Mất kết nối máy")).ToList();
        var outageSec = netOutages.Sum(o => o.Seconds);
        var discAll = samples.Sum(s => s.RealtimeDisconnects);

        // Giờ đông (25% giờ nhiều đơn nhất) so với giờ còn lại.
        // Độ bận = đơn mới + lệnh in (đơn QR gọi thêm vào đơn đang mở không tạo đơn mới nhưng có phiếu in).
        static int Busy(HourRow h) => h.Orders + h.PrintJobs;
        var busy = hours.Where(h => Busy(h) > 0 && h.PingSent > 0).OrderByDescending(Busy).ToList();
        var degrades = false;
        string? peakNote = null;
        if (busy.Count >= 4)
        {
            var top = busy.Take(Math.Max(1, busy.Count / 4)).ToList();
            var rest = busy.Skip(top.Count).ToList();
            var topFail = FailPctOf(top.Sum(h => h.PingSent), top.Sum(h => h.PingFailed));
            var restFail = FailPctOf(rest.Sum(h => h.PingSent), rest.Sum(h => h.PingFailed));
            var topP95 = Pct(top.Where(h => h.LatencyP95Ms != null).Select(h => h.LatencyP95Ms!.Value), 0.5) ?? 0;
            var restP95 = Pct(rest.Where(h => h.LatencyP95Ms != null).Select(h => h.LatencyP95Ms!.Value), 0.5) ?? 0;
            degrades = topFail >= restFail + 2 || (topP95 > GoodP95Ms && topP95 >= restP95 * 1.5 + 200);
            peakNote = $"Giờ đông: lỗi {topFail}% · trễ {topP95} ms — giờ khác: lỗi {restFail}% · trễ {restP95} ms";
        }

        var businessHours = hours.Where(h => Busy(h) > 0).Select(h => h.HourVn).ToHashSet();
        bool InBusiness(Outage o) => businessHours.Contains(new DateTime(o.StartVn.Year, o.StartVn.Month,
            o.StartVn.Day, o.StartVn.Hour, 0, 0, o.StartVn.Kind));
        var printIssues = print.Failed + print.StaleQueued + print.StuckNoRequeue;
        var printIssuePct = print.Total < 10 ? 0 : 100.0 * printIssues / print.Total;

        string verdict;
        if (samples.Count < 12)
            verdict = "insufficient";
        else if (failAll > BadFailPct
                 || netOutages.Any(o => o.Seconds >= BadOutageSec && (businessHours.Count == 0 || InBusiness(o)))
                 || printIssuePct > 5)
            verdict = "red";
        else if (hours.Any(h => Busy(h) > 0 && h.Health is "yellow" or "red")
                 || netOutages.Count > 0 || degrades || (print.P95Sec ?? 0) > SlowPrintSec
                 || failAll >= WarnFailPct || (p95All ?? 0) > GoodP95Ms)
            verdict = "yellow";
        else
            verdict = "green";

        var score = 100.0;
        score -= Math.Min(40, failAll * 5);
        score -= Math.Min(30, outageSec / 60.0 * 2);
        score -= Math.Min(20, Math.Max(0, ((p95All ?? 0) - GoodP95Ms) / 50.0));
        score -= Math.Min(10, printIssuePct * 2);
        if (degrades) score -= 5;
        var scoreInt = verdict == "insufficient" ? 0 : (int)Math.Clamp(Math.Round(score), 0, 100);

        var verdictText = verdict switch
        {
            "green" => "Mạng ổn định — dùng order / in qua mạng được",
            "yellow" => "Mạng chập chờn lúc cao điểm / có lúc rớt — dùng được nhưng nên khắc phục",
            "red" => "Mạng không ổn định — order / in qua mạng dễ chậm, treo phiếu",
            _ => "Chưa đủ số liệu — mở app bán hàng trên các máy ít nhất 1 giờ",
        };

        // ── Gợi ý ────────────────────────────────────────────────────────────────
        var recs = new List<Recommendation>();
        if (degrades)
            recs.Add(new("PEAK", "high", "Mạng tệ đúng giờ đông khách",
                "Router quá tải khi khách dùng chung Wi‑Fi. Tách Wi‑Fi riêng cho máy POS / máy in (SSID hoặc VLAN riêng), " +
                "giới hạn băng thông Wi‑Fi khách, dùng router chịu được nhiều thiết bị."));
        foreach (var d in devices.Where(d => d.WifiRssi != null && d.WifiRssi <= WeakWifiDbm))
            recs.Add(new("WEAK_WIFI", "medium", $"Sóng Wi‑Fi yếu ở «{d.DeviceName ?? d.DeviceId}» ({d.WifiRssi} dBm)",
                "Đặt máy gần router / thêm bộ phát, hoặc cắm dây LAN."));
        foreach (var d in devices.Where(d => d.IsAgent && (d.Outages > 0 || d.Disconnects > 3)))
            recs.Add(new("AGENT", "high", $"Máy giữ máy in (Agent) «{d.DeviceName ?? d.DeviceId}» hay mất kết nối",
                "Máy khác in qua máy này — nên cắm dây LAN, tắt tiết kiệm pin / tự tắt màn hình, không dùng 4G."));
        foreach (var d in devices.Where(d => d.PrinterChecks >= 6 && d.PrinterFailed * 10 > d.PrinterChecks))
            recs.Add(new("PRINTER_LAN", "medium", $"Máy in LAN hay không kết nối được từ «{d.DeviceName ?? d.DeviceId}»",
                "Đặt IP cố định cho máy in (giữ IP trên router theo MAC), kiểm tra dây mạng / nguồn máy in. " +
                "Router đổi IP máy in là nguyên nhân hay gặp."));
        if (netOutages.Any(o => o.Seconds >= BadOutageSec))
            recs.Add(new("OUTAGE", "high", "Có lúc mất mạng lâu",
                "Dùng router 4G dự phòng tự chuyển khi mất Internet; gán món vào máy in nội bộ trên máy cạnh máy in " +
                "để vẫn in được khi mất Internet (mạng trong quán vẫn chạy)."));
        if (!degrades && (p95All ?? 0) > 1500)
            recs.Add(new("ISP", "medium", "Đường truyền chậm cả lúc vắng khách",
                "Kiểm tra gói Internet / gọi nhà mạng; khởi động lại router định kỳ."));
        if (print.StaleQueued + print.StuckNoRequeue > 0)
            recs.Add(new("PRINT_JOBS", "medium",
                $"{print.StaleQueued + print.StuckNoRequeue} lệnh in bị hủy vì máy Agent tắt / mất mạng",
                "Giữ máy Agent luôn mở app, cắm sạc; kiểm tra «In treo» trên máy gửi để in lại."));
        if (recs.Count == 0 && verdict == "green")
            recs.Add(new("OK", "info", "Mạng đang tốt", "Tiếp tục theo dõi vào giờ cao điểm cuối tuần."));

        return new Report(verdict, verdictText, scoreInt, samples.Count, devices.Count, failAll, p95All,
            netOutages.Count, outageSec, discAll, degrades, peakNote, hours, devices, outages.Take(100).ToList(),
            print, recs);
    }
}
