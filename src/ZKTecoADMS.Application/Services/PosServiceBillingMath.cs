using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Services;

/// <summary>
/// Công thức tiền giờ karaoke / bi-a / KS — client Flutter phải khớp từng bước.
/// </summary>
public static class PosServiceBillingMath
{
    public static DateTime AsUtc(DateTime value) =>
        value.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(value, DateTimeKind.Utc)
            : value.ToUniversalTime();

    /// <summary>Số phút nguyên từ TimeSpan: phần lẻ giây làm tròn lên.</summary>
    public static int CeilingMinutes(TimeSpan span)
    {
        if (span.Ticks <= 0) return 0;
        var minutes = span.Ticks / TimeSpan.TicksPerMinute;
        var rem = span.Ticks % TimeSpan.TicksPerMinute;
        return (int)(minutes + (rem > 0 ? 1 : 0));
    }

    /// <summary>Phút pause cộng vào Accumulated — cắt xuống để không trừ quá giờ dùng.</summary>
    public static int FloorMinutes(TimeSpan span)
    {
        if (span.Ticks <= 0) return 0;
        return (int)(span.Ticks / TimeSpan.TicksPerMinute);
    }

    /// <summary>
    /// Phút sử dụng thực = (end − start) − pause đã cộng − pause đang mở, rồi làm tròn lên phút.
    /// </summary>
    public static int ElapsedMinutes(
        DateTime startedAt,
        DateTime? endedAt,
        int accumulatedPauseMinutes = 0,
        DateTime? pausedAt = null)
    {
        var start = AsUtc(startedAt);
        var end = AsUtc(endedAt ?? DateTime.UtcNow);
        if (end <= start) return 0;

        var pause = TimeSpan.FromMinutes(Math.Max(0, accumulatedPauseMinutes));
        if (pausedAt.HasValue)
        {
            var pauseStart = AsUtc(pausedAt.Value);
            if (pauseStart < end)
                pause += end - pauseStart;
        }

        return CeilingMinutes((end - start) - pause);
    }

    public static bool IsTimed(PosServiceBillingMode mode) =>
        mode is PosServiceBillingMode.PerHour
            or PosServiceBillingMode.PerMinute
            or PosServiceBillingMode.PerBlock
            or PosServiceBillingMode.PerDay;

    public static int BillableMinutes(
        int elapsedMinutes,
        PosServiceBillingMode mode,
        int? minBillMinutes,
        int? billRoundMinutes,
        int? graceMinutes = null,
        int? roundAfterMinutes = null)
    {
        if (mode is PosServiceBillingMode.Flat or PosServiceBillingMode.PerSession)
            return Math.Max(0, elapsedMinutes);

        var raw = Math.Max(0, elapsedMinutes);
        // Chưa dùng (preview 0p / chưa bấm bắt đầu) → 0 giờ; min chỉ khi elapsed > 0.
        if (raw <= 0) return 0;

        var grace = graceMinutes is > 0 ? graceMinutes.Value : 0;

        // Còn trong cửa sổ miễn → 0 giờ (phí mở phòng vẫn cộng riêng).
        if (grace > 0 && raw <= grace)
            return 0;

        var minutes = Math.Max(0, raw - grace);
        var min = minBillMinutes is > 0 ? minBillMinutes.Value : 0;
        if (min > 0 && minutes < min)
            minutes = min;

        var round = billRoundMinutes is > 0 ? billRoundMinutes.Value : 0;
        if (mode == PosServiceBillingMode.PerDay)
            round = round >= 60 ? round : 1440;
        if (mode == PosServiceBillingMode.PerBlock && round <= 0)
            round = 5;

        var roundAfter = roundAfterMinutes is > 0 ? roundAfterMinutes.Value : 0;
        var applyRound = round > 0 && minutes > 0
            && (roundAfter <= 0 || raw > roundAfter);
        if (applyRound)
        {
            var blocks = (int)Math.Ceiling(minutes / (double)round);
            minutes = blocks * round;
        }

        return minutes;
    }

    public static decimal BillableQty(
        PosServiceBillingMode mode,
        int billableMinutes,
        decimal fallbackQty,
        int? billRoundMinutes = null)
    {
        return mode switch
        {
            PosServiceBillingMode.PerHour =>
                Math.Round(billableMinutes / 60m, 4, MidpointRounding.AwayFromZero),
            PosServiceBillingMode.PerMinute => billableMinutes,
            PosServiceBillingMode.PerBlock => BlockQty(billableMinutes, billRoundMinutes),
            PosServiceBillingMode.PerDay => Math.Max(1,
                (int)Math.Ceiling(Math.Max(0, billableMinutes) / 1440m)),
            _ => fallbackQty,
        };
    }

    /// <summary>Số block nguyên — phần lẻ tính thêm 1 block (karaoke / bi-a).</summary>
    public static decimal BlockQty(int minutes, int? billRoundMinutes)
    {
        var block = billRoundMinutes is > 0 ? billRoundMinutes.Value : 5;
        if (minutes <= 0 || block <= 0) return 0;
        return (int)Math.Ceiling(minutes / (decimal)block);
    }

    public static decimal ExtraQty(
        PosServiceBillingMode mode,
        int billableMinutes,
        int? openingMinutes,
        int? billRoundMinutes,
        decimal fallbackQty = 0)
    {
        var included = openingMinutes is > 0 ? openingMinutes.Value : 0;
        var extra = Math.Max(0, billableMinutes - included);
        if (extra <= 0) return 0;
        return BillableQty(mode, extra, fallbackQty, billRoundMinutes);
    }

    public static decimal TimedLineCharge(
        PosServiceBillingMode mode,
        int billableMinutes,
        decimal unitPrice,
        decimal openingFee = 0,
        int? openingMinutes = null,
        int? billRoundMinutes = null)
    {
        var qty = ExtraQty(mode, billableMinutes, openingMinutes, billRoundMinutes);
        return Math.Max(0, openingFee) + qty * unitPrice;
    }

    public record PreviewRow(int ElapsedMinutes, int BillableMinutes, decimal Qty, decimal Total);

    public static readonly int[] DefaultPreviewSamples =
    [
        0, 1, 5, 6, 10, 15, 16, 30, 31, 45, 59, 60, 61, 90, 120, 180, 240, 420
    ];

    public static List<PreviewRow> Preview(
        PosServiceBillingMode mode,
        decimal unitPrice,
        int? minBillMinutes,
        int? billRoundMinutes,
        int? graceMinutes,
        int? roundAfterMinutes,
        decimal openingFee,
        int? openingMinutes,
        IReadOnlyList<int>? elapsedSamples = null)
    {
        var samples = elapsedSamples is { Count: > 0 }
            ? elapsedSamples
            : DefaultPreviewSamples;
        var rows = new List<PreviewRow>(samples.Count);
        foreach (var elapsed in samples)
        {
            var billable = BillableMinutes(
                elapsed, mode, minBillMinutes, billRoundMinutes, graceMinutes, roundAfterMinutes);
            var qty = ExtraQty(mode, billable, openingMinutes, billRoundMinutes);
            rows.Add(new PreviewRow(elapsed, billable, qty, Math.Max(0, openingFee) + qty * unitPrice));
        }
        return rows;
    }
}
