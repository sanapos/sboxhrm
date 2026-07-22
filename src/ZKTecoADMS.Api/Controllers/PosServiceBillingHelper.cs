using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Tính phút / số lượng cho dịch vụ theo giờ.</summary>
public static class PosServiceBillingHelper
{
    public static int CalcElapsedMinutes(DateTime startedAt, DateTime? endedAt)
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
        return (int)Math.Ceiling((end - start).TotalMinutes);
    }

    public static int CalcBillableMinutes(
        int elapsedMinutes,
        PosServiceBillingMode mode,
        int? minBillMinutes,
        int? billRoundMinutes)
    {
        if (mode is PosServiceBillingMode.Flat or PosServiceBillingMode.PerSession)
            return Math.Max(0, elapsedMinutes);

        var minutes = Math.Max(0, elapsedMinutes);
        var min = minBillMinutes is > 0 ? minBillMinutes.Value : 0;
        if (minutes < min) minutes = min;

        var round = billRoundMinutes is > 0 ? billRoundMinutes.Value : 0;
        if (round > 0 && minutes > 0)
        {
            var blocks = (int)Math.Ceiling(minutes / (double)round);
            minutes = blocks * round;
        }

        return minutes;
    }

    /// <summary>
    /// Qty hiển thị trên dòng: PerHour = giờ (phút/60), PerMinute = phút, Flat/Session = giữ nguyên.
    /// </summary>
    public static decimal CalcBillableQty(
        PosServiceBillingMode mode,
        int billableMinutes,
        decimal fallbackQty)
    {
        return mode switch
        {
            PosServiceBillingMode.PerHour =>
                Math.Round(billableMinutes / 60m, 4, MidpointRounding.AwayFromZero),
            PosServiceBillingMode.PerMinute => billableMinutes,
            _ => fallbackQty,
        };
    }

    public static decimal CalcLineTotal(decimal qty, decimal unitPrice, decimal discountAmount)
    {
        var gross = qty * unitPrice;
        var disc = Math.Max(0, Math.Min(discountAmount, gross));
        return gross - disc;
    }

    public static void ApplyProfileDefaults(PosStoreSellSettings s)
    {
        switch (s.SellProfile)
        {
            case PosSellProfile.Retail:
                s.EnableResources = false;
                s.EnableHourlyBilling = false;
                s.EnableSessionPacks = false;
                s.RequireResourceOnSale = false;
                s.ShowFloorPlan = false;
                s.AllowProvisionalBill = false;
                break;
            case PosSellProfile.Salon:
                s.EnableResources = true;
                s.EnableHourlyBilling = true;
                s.EnableSessionPacks = false;
                s.RequireResourceOnSale = false;
                s.ShowFloorPlan = true;
                s.AllowProvisionalBill = true;
                break;
            case PosSellProfile.RoomHourly:
                s.EnableResources = true;
                s.EnableHourlyBilling = true;
                s.EnableSessionPacks = false;
                s.RequireResourceOnSale = true;
                s.ShowFloorPlan = true;
                s.AllowProvisionalBill = true;
                break;
            case PosSellProfile.Restaurant:
                s.EnableResources = true;
                s.EnableHourlyBilling = false;
                s.EnableSessionPacks = false;
                s.RequireResourceOnSale = false;
                s.ShowFloorPlan = true;
                s.AllowProvisionalBill = true;
                break;
            case PosSellProfile.Gym:
                s.EnableResources = false;
                s.EnableHourlyBilling = false;
                s.EnableSessionPacks = true;
                s.RequireResourceOnSale = false;
                s.ShowFloorPlan = false;
                s.AllowProvisionalBill = false;
                break;
        }
    }

    public static PosStoreSellSettings CreateDefault(Guid storeId, string? createdBy)
    {
        var s = new PosStoreSellSettings
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            SellProfile = PosSellProfile.Retail,
            DefaultSellMode = "quick",
            IsActive = true,
            CreatedBy = createdBy,
        };
        ApplyProfileDefaults(s);
        return s;
    }
}
