using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Tính phút / số lượng cho dịch vụ theo giờ (karaoke / bi-a / KS).</summary>
public static class PosServiceBillingHelper
{
    public static int CalcElapsedMinutes(
        DateTime startedAt,
        DateTime? endedAt,
        int accumulatedPauseMinutes = 0,
        DateTime? pausedAt = null) =>
        PosServiceBillingMath.ElapsedMinutes(startedAt, endedAt, accumulatedPauseMinutes, pausedAt);

    /// <summary>Chốt pause đang mở vào Accumulated trước khi đóng phiên / tính tiền.</summary>
    public static void FinalizeOpenPause(PosResourceSession session, DateTime? endedAt = null)
    {
        if (!session.PausedAt.HasValue) return;
        var endUtc = PosServiceBillingMath.AsUtc(endedAt ?? DateTime.UtcNow);
        var pauseStart = PosServiceBillingMath.AsUtc(session.PausedAt.Value);
        if (endUtc > pauseStart)
            session.AccumulatedPauseMinutes += PosServiceBillingMath.FloorMinutes(endUtc - pauseStart);
        session.PausedAt = null;
    }

    public static bool IsTimed(PosServiceBillingMode mode) => PosServiceBillingMath.IsTimed(mode);

    public static int CalcBillableMinutes(
        int elapsedMinutes,
        PosServiceBillingMode mode,
        int? minBillMinutes,
        int? billRoundMinutes,
        int? graceMinutes = null,
        int? roundAfterMinutes = null) =>
        PosServiceBillingMath.BillableMinutes(
            elapsedMinutes, mode, minBillMinutes, billRoundMinutes, graceMinutes, roundAfterMinutes);

    public static decimal CalcBillableQty(
        PosServiceBillingMode mode,
        int billableMinutes,
        decimal fallbackQty,
        int? billRoundMinutes = null) =>
        PosServiceBillingMath.BillableQty(mode, billableMinutes, fallbackQty, billRoundMinutes);

    public static decimal CalcTimedLineCharge(
        PosServiceBillingMode mode,
        int billableMinutes,
        decimal unitPrice,
        decimal openingFee = 0,
        int? openingMinutes = null,
        int? billRoundMinutes = null) =>
        PosServiceBillingMath.TimedLineCharge(
            mode, billableMinutes, unitPrice, openingFee, openingMinutes, billRoundMinutes);

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
        return PosServiceBillingMath.Preview(
                mode, unitPrice, minBillMinutes, billRoundMinutes,
                graceMinutes, roundAfterMinutes, openingFee, openingMinutes, elapsedSamples)
            .Select(r => new BillingPreviewRow(r.ElapsedMinutes, r.BillableMinutes, r.Qty, r.Total))
            .ToList();
    }

    public static void ApplyProfileDefaults(PosStoreSellSettings s) =>
        PosSellProfileDefaults.Apply(s);

    public static PosStoreSellSettings CreateDefault(
        Guid storeId,
        string? createdBy,
        PosSellProfile profile = PosSellProfile.Retail) =>
        PosSellProfileDefaults.Create(storeId, createdBy, profile);
}
