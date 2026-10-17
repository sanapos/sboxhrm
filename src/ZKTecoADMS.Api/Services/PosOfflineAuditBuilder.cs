using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Báo cáo kiểm soát bán offline (chủ / quản lý): kết luận dễ hiểu, cảnh báo kèm cách xử lý, số liệu vẽ đồ thị
/// (đơn offline theo ngày, thời gian chờ gửi), lịch sử cài app, dải số đã cấp — số nhảy cóc / chưa đồng bộ.
/// Thuần tính toán (không DB) để test.
/// </summary>
public static class PosOfflineAuditBuilder
{
    static readonly TimeSpan Vn = TimeSpan.FromHours(7);
    const int MaxSalesRows = 500;

    public record OrderRow(
        Guid Id, string OrderNo, string? OfflineNo, DateTime? OfflineAt, string? OfflineDeviceKey,
        DateTime CreatedAt, DateTime? UpdatedAt, string? CreatedBy, decimal Total, PosSaleOrderStatus Status);

    public record SettingsInfo(bool Enabled, int MaxHours);

    public record Summary(
        int OfflineSales, decimal OfflineTotal, int Devices, int Reinstalls, int Alerts,
        int MediumAlerts, int PendingOnDevices, int SerialsIssued, int SerialsUsed, int Gaps,
        int? AvgDelayMinutes, int? MaxDelayMinutes);

    /// <summary>[Kind]: GAP / REINSTALL_PENDING / NOT_SYNCED / OUT_OF_RANGE / REINSTALL. [Action] = cách xử lý.</summary>
    public record Alert(string Level, string Kind, string? Device, string Text, string? Range, string Action);

    public record InstallRow(
        string InstallId, string? Platform, string? AppVersion, DateTime FirstSeenAt, DateTime LastSeenAt,
        DateTime? OsFirstInstallAt, string? LastUserName, int PendingOfflineSales, string? LastOfflineSeq);

    public record DeviceRow(string DeviceKey, string? DeviceName, int Reinstalls, int PendingOfflineSales,
        DateTime LastSeenAt, List<InstallRow> Installs);

    public record BlockRow(
        string DeviceKey, string? DeviceName, string InstallId, DateTime ReservedAt, string? ReservedBy,
        string From, string To, int Size, int Used, string? LastUsed, List<string> Gaps, int GapCount,
        List<string> MissingReported, bool InstallReplaced, List<string> Suspicious);

    public record SaleRow(
        Guid Id, string OrderNo, string? OfflineNo, DateTime? OfflineAt, DateTime SyncedAt, decimal Total,
        string? CreatedBy, string? Device, int DelayMinutes, PosSaleOrderStatus Status);

    public record DayRow(DateTime DateVn, int Count, decimal Total);

    public record DelayBucket(string Label, int Count);

    public record Report(
        string Verdict, string VerdictText, string VerdictDetail, SettingsInfo Settings, Summary Summary,
        List<Alert> Alerts, List<DeviceRow> Devices, List<BlockRow> Blocks, List<SaleRow> Sales,
        List<DayRow> Daily, List<DelayBucket> DelayBuckets);

    /// <summary>Giờ lưu DB là con số UTC (không múi giờ) > Kind Utc để JSON kèm Z.</summary>
    static DateTime U(DateTime v) => DateTime.SpecifyKind(v, DateTimeKind.Utc);
    static DateTime? U(DateTime? v) => v == null ? null : U(v.Value);

    /// <summary>
    /// Giờ đơn về máy chủ. Đơn offline chốt trên bàn đã mở từ trước (đơn tạm có sẵn trên máy chủ) có
    /// CreatedAt sớm hơn giờ bán > lấy giờ cập nhật.
    /// </summary>
    public static DateTime SyncedAtOf(OrderRow o) =>
        o.OfflineAt != null && o.CreatedAt < o.OfflineAt && o.UpdatedAt != null ? o.UpdatedAt.Value : o.CreatedAt;

    static int DelayOf(OrderRow o) =>
        o.OfflineAt == null ? 0 : (int)Math.Max(0, (SyncedAtOf(o) - o.OfflineAt.Value).TotalMinutes);

    public static Report Build(
        PosOfflineSaleRules.Settings settings,
        IReadOnlyList<PosDeviceInstall> installs,
        IReadOnlyList<PosOfflineSerialBlock> blocks,
        IReadOnlyList<OrderRow> offlineOrders,
        DateTime sinceUtc,
        DateTime nowUtc)
    {
        installs = installs.OrderBy(i => i.FirstSeenAt).ToList();
        blocks = blocks.OrderBy(b => b.FromSeq).ToList();
        var usedSeqs = offlineOrders
            .Select(o => PosOfflineSaleRules.SeqOf(o.OfflineNo))
            .Where(s => s != null).Select(s => s!.Value).ToHashSet();

        var alerts = new List<Alert>();
        var totalGaps = 0;
        var serialsUsed = 0;
        var blockRows = blocks.Select(b =>
        {
            var used = Enumerable.Range(b.FromSeq, b.ToSeq - b.FromSeq + 1).Where(usedSeqs.Contains).ToList();
            serialsUsed += used.Count;
            var maxUsed = used.Count == 0 ? (int?)null : used.Max();
            // Số trong khoảng đã dùng mà không có đơn = nhảy cóc (đơn đã in cho khách nhưng không về server).
            var gaps = maxUsed == null
                ? new List<int>()
                : Enumerable.Range(b.FromSeq, maxUsed.Value - b.FromSeq + 1).Where(s => !usedSeqs.Contains(s)).ToList();
            totalGaps += gaps.Count;
            var install = installs.FirstOrDefault(i => i.DeviceKey == b.DeviceKey && i.InstallId == b.InstallId);
            var replaced = installs.Any(i => i.DeviceKey == b.DeviceKey && i.InstallId != b.InstallId
                && i.FirstSeenAt > (install?.FirstSeenAt ?? b.CreatedAt));
            var reportedLast = install?.LastOfflineSeq;
            var reportedPending = install?.PendingOfflineSales ?? 0;
            // Máy từng báo đã dùng tới số X nhưng server chỉ có tới Y (< X) > còn đơn chưa đồng bộ.
            var reportedMissing = reportedLast is { } rl && rl >= b.FromSeq && rl <= b.ToSeq
                ? Enumerable.Range(b.FromSeq, rl - b.FromSeq + 1).Where(s => !usedSeqs.Contains(s)).ToList()
                : [];
            var device = b.DeviceName ?? b.DeviceKey;
            var range = $"{PosOfflineSaleRules.Format(b.FromSeq)} – {PosOfflineSaleRules.Format(b.ToSeq)}";
            var who = install?.LastUserName == null ? "" : $" (người dùng gần nhất: {install.LastUserName})";
            var suspicious = new List<string>();
            if (gaps.Count > 0)
            {
                var text = $"{gaps.Count} số nhảy cóc (đã in cho khách nhưng không về máy chủ)";
                suspicious.Add(text);
                alerts.Add(new Alert("high", "GAP", device, text, range,
                    $"Mở app trên máy «{device}» khi có mạng > «Bán offline & kiểm soát» > «Gửi ngay». " +
                    $"Nếu máy không còn đơn: hỏi thu ngân{who} về các số " +
                    $"{string.Join(", ", gaps.Take(5).Select(PosOfflineSaleRules.Format))}" +
                    $"{(gaps.Count > 5 ? "…" : "")}, đối chiếu tiền mặt két ca."));
            }
            if (replaced && (reportedPending > 0 || reportedMissing.Count > 0))
            {
                const string text = "Cài lại app / xóa dữ liệu khi còn đơn offline chưa gửi";
                suspicious.Add(text);
                alerts.Add(new Alert("high", "REINSTALL_PENDING", device, text, range,
                    $"Trên máy «{device}» mở thư mục Download/SBOX_POS (bản sao đơn offline) rồi mở lại app để khôi phục; " +
                    $"hỏi người dùng gần nhất{who} vì sao xóa dữ liệu / cài lại; đối chiếu két ca."));
            }
            else if (reportedMissing.Count > gaps.Count)
            {
                var text = $"Máy báo đã bán tới {PosOfflineSaleRules.Format(reportedLast!.Value)} — chưa đồng bộ đủ";
                suspicious.Add(text);
                alerts.Add(new Alert("high", "NOT_SYNCED", device, text, range,
                    $"Mở app trên máy «{device}» khi có mạng > «Bán offline & kiểm soát» > «Gửi ngay» " +
                    "(đơn lỗi: xử lý nguyên nhân rồi «Gửi lại đơn lỗi»)."));
            }
            return new BlockRow(
                b.DeviceKey, b.DeviceName, b.InstallId, U(b.CreatedAt), b.ReservedBy,
                PosOfflineSaleRules.Format(b.FromSeq), PosOfflineSaleRules.Format(b.ToSeq),
                b.ToSeq - b.FromSeq + 1, used.Count,
                maxUsed == null ? null : PosOfflineSaleRules.Format(maxUsed.Value),
                gaps.Take(50).Select(PosOfflineSaleRules.Format).ToList(), gaps.Count,
                reportedMissing.Take(50).Select(PosOfflineSaleRules.Format).ToList(),
                replaced, suspicious);
        }).ToList();

        // Số offline không thuộc dải nào đã cấp > bất thường.
        foreach (var o in offlineOrders)
        {
            var s = PosOfflineSaleRules.SeqOf(o.OfflineNo);
            if (s != null && !blocks.Any(b => s >= b.FromSeq && s <= b.ToSeq))
                alerts.Add(new Alert("medium", "OUT_OF_RANGE", o.OfflineDeviceKey,
                    $"{o.OfflineNo} không thuộc dải số đã cấp", o.OrderNo,
                    $"Mở hóa đơn {o.OrderNo} kiểm tra người tạo, giờ bán, tiền — số này không do máy chủ cấp."));
        }

        var devices = installs.GroupBy(i => i.DeviceKey).Select(g =>
        {
            var list = g.OrderBy(i => i.FirstSeenAt).ToList();
            var latest = list.Last();
            var reinstalls = list.Count - 1;
            if (reinstalls > 0)
                alerts.Add(new Alert("info", "REINSTALL", latest.DeviceName ?? g.Key,
                    $"Cài lại app {reinstalls} lần (gần nhất {latest.FirstSeenAt + Vn:dd/MM HH:mm})", null,
                    "Bình thường nếu đổi máy / sửa lỗi app. Nếu không ai báo — hỏi quản lý ca."));
            return new DeviceRow(
                g.Key, latest.DeviceName, reinstalls, latest.PendingOfflineSales,
                U(list.Max(i => i.LastSeenAt)),
                list.Select(i => new InstallRow(
                    i.InstallId, i.Platform, i.AppVersion, U(i.FirstSeenAt), U(i.LastSeenAt), U(i.OsFirstInstallAt),
                    i.LastUserName, i.PendingOfflineSales,
                    i.LastOfflineSeq == null ? null : PosOfflineSaleRules.Format(i.LastOfflineSeq.Value))).ToList());
        }).ToList();

        // Kỳ báo cáo theo giờ bán (đơn chốt trên bàn mở sẵn có CreatedAt sớm hơn giờ bán).
        var inPeriod = offlineOrders.Where(o => (o.OfflineAt ?? o.CreatedAt) >= sinceUtc)
            .OrderByDescending(o => o.OfflineAt ?? o.CreatedAt)
            .ToList();
        var nameOf = installs.GroupBy(i => i.DeviceKey).ToDictionary(g => g.Key, g => g.Last().DeviceName);
        var sales = inPeriod.Take(MaxSalesRows).Select(o => new SaleRow(
                o.Id, o.OrderNo, o.OfflineNo, U(o.OfflineAt), U(SyncedAtOf(o)), o.Total, o.CreatedBy,
                o.OfflineDeviceKey != null && nameOf.TryGetValue(o.OfflineDeviceKey, out var n) && n != null
                    ? n
                    : o.OfflineDeviceKey,
                DelayOf(o), o.Status))
            .ToList();

        // Đồ thị: đơn offline theo ngày (giờ VN, đủ các ngày trong kỳ) + thời gian chờ gửi lên.
        var firstDay = (sinceUtc + Vn).Date;
        var lastDay = (nowUtc + Vn).Date;
        var byDay = inPeriod.GroupBy(o => ((o.OfflineAt ?? o.CreatedAt) + Vn).Date)
            .ToDictionary(g => g.Key, g => (Count: g.Count(), Total: g.Sum(x => x.Total)));
        var daily = new List<DayRow>();
        for (var d = firstDay; d <= lastDay; d = d.AddDays(1))
        {
            byDay.TryGetValue(d, out var v);
            daily.Add(new DayRow(DateTime.SpecifyKind(d, DateTimeKind.Utc), v.Count, v.Total));
        }
        var delays = inPeriod.Select(DelayOf).ToList();
        var delayBuckets = new List<DelayBucket>
        {
            new("Dưới 5 phút", delays.Count(x => x < 5)),
            new("5 – 60 phút", delays.Count(x => x is >= 5 and < 60)),
            new("1 – 24 giờ", delays.Count(x => x is >= 60 and < 1440)),
            new("Trên 1 ngày", delays.Count(x => x >= 1440)),
        };

        var high = alerts.Count(a => a.Level == "high");
        var medium = alerts.Count(a => a.Level == "medium");
        var pendingOnDevices = devices.Sum(d => d.PendingOfflineSales);
        var summary = new Summary(
            inPeriod.Count, inPeriod.Sum(o => o.Total), devices.Count, devices.Sum(d => d.Reinstalls), high, medium,
            pendingOnDevices, blocks.Sum(b => b.ToSeq - b.FromSeq + 1), serialsUsed, totalGaps,
            delays.Count == 0 ? null : (int)Math.Round(delays.Average()),
            delays.Count == 0 ? null : delays.Max());

        string verdict, verdictText, verdictDetail;
        if (high > 0)
        {
            verdict = "red";
            verdictText = $"Có {high} dấu hiệu bất thường — cần kiểm tra ngay";
            verdictDetail = "Có số hóa đơn offline đã dùng (đã in cho khách) mà chưa thấy đơn trên máy chủ. " +
                            "Làm theo «Cách xử lý» ở từng cảnh báo bên dưới.";
        }
        else if (medium > 0 || pendingOnDevices > 0)
        {
            verdict = "yellow";
            verdictText = pendingOnDevices > 0
                ? $"Còn {pendingOnDevices} đơn offline nằm trên máy, chưa gửi về"
                : "Có điểm cần xem lại";
            verdictDetail = "Chưa phát hiện mất đơn. Mở app trên các máy đó khi có mạng để đơn tự gửi về.";
        }
        else if (!settings.Enabled && offlineOrders.Count == 0 && blocks.Count == 0)
        {
            verdict = "off";
            verdictText = "Cửa hàng chưa bật bán offline";
            verdictDetail = "Mất mạng thì máy chỉ giữ giỏ hàng, không thu tiền được. Bật ở Thiết lập > Ngành hàng & cách bán.";
        }
        else
        {
            verdict = "green";
            verdictText = "Bán offline minh bạch — không có bất thường";
            verdictDetail = $"Mọi số hóa đơn offline đã dùng đều đã về máy chủ ({serialsUsed} số).";
        }

        return new Report(verdict, verdictText, verdictDetail, new SettingsInfo(settings.Enabled, settings.MaxHours),
            summary, alerts.OrderBy(a => a.Level switch { "high" => 0, "medium" => 1, _ => 2 }).ToList(),
            devices, blockRows, sales, daily, delayBuckets);
    }
}
