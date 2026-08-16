using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Tính phút / số lượng cho dịch vụ theo giờ.</summary>
public static class PosServiceBillingHelper
{
    /// <summary>
    /// Phút sử dụng thực = (end − start) − pause đã cộng − pause đang mở (PausedAt → end).
    /// </summary>
    public static int CalcElapsedMinutes(
        DateTime startedAt,
        DateTime? endedAt,
        int accumulatedPauseMinutes = 0,
        DateTime? pausedAt = null)
    {
        // timestamp without time zone thường mất Kind — coi là UTC nếu Unspecified.
        var start = startedAt.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(startedAt, DateTimeKind.Utc)
            : startedAt.ToUniversalTime();
        var endRaw = endedAt ?? DateTime.UtcNow;
        var end = endRaw.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(endRaw, DateTimeKind.Utc)
            : endRaw.ToUniversalTime();
        if (end < start) return 0;

        var raw = (int)Math.Ceiling((end - start).TotalMinutes);
        var pause = Math.Max(0, accumulatedPauseMinutes);
        if (pausedAt.HasValue)
        {
            var pauseStart = pausedAt.Value.Kind == DateTimeKind.Unspecified
                ? DateTime.SpecifyKind(pausedAt.Value, DateTimeKind.Utc)
                : pausedAt.Value.ToUniversalTime();
            if (pauseStart < end)
                pause += (int)Math.Max(0, (end - pauseStart).TotalMinutes);
        }

        return Math.Max(0, raw - pause);
    }

    /// <summary>Chốt pause đang mở vào Accumulated trước khi đóng phiên / tính tiền.</summary>
    public static void FinalizeOpenPause(PosResourceSession session, DateTime? endedAt = null)
    {
        if (!session.PausedAt.HasValue) return;
        var end = endedAt ?? DateTime.UtcNow;
        var pauseStart = session.PausedAt.Value.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(session.PausedAt.Value, DateTimeKind.Utc)
            : session.PausedAt.Value.ToUniversalTime();
        var endUtc = end.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(end, DateTimeKind.Utc)
            : end.ToUniversalTime();
        if (endUtc > pauseStart)
            session.AccumulatedPauseMinutes += (int)Math.Max(0, (endUtc - pauseStart).TotalMinutes);
        session.PausedAt = null;
    }

    public static bool IsTimed(PosServiceBillingMode mode) =>
        mode is PosServiceBillingMode.PerHour
            or PosServiceBillingMode.PerMinute
            or PosServiceBillingMode.PerBlock
            or PosServiceBillingMode.PerDay;

    public static int CalcBillableMinutes(
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
        var grace = graceMinutes is > 0 ? graceMinutes.Value : 0;
        var minutes = Math.Max(0, raw - grace);

        var min = minBillMinutes is > 0 ? minBillMinutes.Value : 0;
        if (minutes < min) minutes = min;

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

    /// <summary>
    /// Qty hiển thị trên dòng: PerHour = giờ, PerMinute = phút, PerBlock = số block,
    /// PerDay = số ngày, Flat/Session = giữ nguyên.
    /// </summary>
    public static decimal CalcBillableQty(
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
            PosServiceBillingMode.PerBlock => CalcBlockQty(billableMinutes, billRoundMinutes),
            PosServiceBillingMode.PerDay => Math.Max(1,
                (int)Math.Ceiling(Math.Max(0, billableMinutes) / 1440m)),
            _ => fallbackQty,
        };
    }

    static decimal CalcBlockQty(int billableMinutes, int? billRoundMinutes)
    {
        var block = billRoundMinutes is > 0 ? billRoundMinutes.Value : 5;
        if (billableMinutes <= 0) return 0;
        return Math.Round(billableMinutes / (decimal)block, 4, MidpointRounding.AwayFromZero);
    }

    /// <summary>
    /// Thành tiền giờ: phí mở + qty phần vượt OpeningMinutes × đơn giá.
    /// </summary>
    public static decimal CalcTimedLineCharge(
        PosServiceBillingMode mode,
        int billableMinutes,
        decimal unitPrice,
        decimal openingFee = 0,
        int? openingMinutes = null,
        int? billRoundMinutes = null)
    {
        var included = openingMinutes is > 0 ? openingMinutes.Value : 0;
        var extra = Math.Max(0, billableMinutes - included);
        var qty = extra <= 0
            ? 0m
            : CalcBillableQty(mode, extra, extra, billRoundMinutes);
        return Math.Max(0, openingFee) + qty * unitPrice;
    }

    public static decimal CalcLineTotal(decimal qty, decimal unitPrice, decimal discountAmount)
    {
        var gross = qty * unitPrice;
        var disc = Math.Max(0, Math.Min(discountAmount, gross));
        return gross - disc;
    }

    public record BillingPreviewRow(int ElapsedMinutes, int BillableMinutes, decimal Qty, decimal Total);

    public static List<BillingPreviewRow> Preview(
        PosServiceBillingMode mode,
        decimal unitPrice,
        int? minBillMinutes,
        int? billRoundMinutes,
        int? graceMinutes,
        int? roundAfterMinutes,
        decimal openingFee,
        int? openingMinutes,
        IReadOnlyList<int> elapsedSamples)
    {
        var rows = new List<BillingPreviewRow>();
        foreach (var elapsed in elapsedSamples)
        {
            var billable = CalcBillableMinutes(
                elapsed, mode, minBillMinutes, billRoundMinutes, graceMinutes, roundAfterMinutes);
            var included = openingMinutes is > 0 ? openingMinutes.Value : 0;
            var extra = Math.Max(0, billable - included);
            var qty = extra <= 0 ? 0m : CalcBillableQty(mode, extra, extra, billRoundMinutes);
            var total = Math.Max(0, openingFee) + qty * unitPrice;
            rows.Add(new BillingPreviewRow(elapsed, billable, qty, total));
        }
        return rows;
    }

    public static void ApplyProfileDefaults(PosStoreSellSettings s) =>
        PosSellProfileDefaults.Apply(s);

    public static PosStoreSellSettings CreateDefault(
        Guid storeId,
        string? createdBy,
        PosSellProfile profile = PosSellProfile.Retail) =>
        PosSellProfileDefaults.Create(storeId, createdBy, profile);
}
