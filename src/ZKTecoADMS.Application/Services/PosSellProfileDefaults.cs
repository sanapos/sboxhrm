using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Services;

/// <summary>Mặc định hồ sơ ngành — dùng khi đăng ký cửa hàng và khi đổi ngành trên POS.</summary>
public static class PosSellProfileDefaults
{
    public static bool TryParse(string? raw, out PosSellProfile profile)
    {
        profile = PosSellProfile.Retail;
        if (string.IsNullOrWhiteSpace(raw)) return false;
        var t = raw.Trim();
        if (Enum.TryParse<PosSellProfile>(t, ignoreCase: true, out profile))
            return true;
        if (int.TryParse(t, out var n) && Enum.IsDefined(typeof(PosSellProfile), n))
        {
            profile = (PosSellProfile)n;
            return true;
        }

        switch (t.ToLowerInvariant())
        {
            case "banle":
            case "bán lẻ":
            case "retail":
                profile = PosSellProfile.Retail;
                return true;
            case "salon":
            case "nail":
            case "spa":
                profile = PosSellProfile.Salon;
                return true;
            case "bia":
            case "bi-a":
            case "karaoke":
            case "room":
            case "roomhourly":
                profile = PosSellProfile.RoomHourly;
                return true;
            case "fnb":
            case "f&b":
            case "nhahang":
            case "nhà hàng":
            case "cafe":
            case "restaurant":
                profile = PosSellProfile.Restaurant;
                return true;
            case "gym":
            case "fitness":
            case "yoga":
                profile = PosSellProfile.Gym;
                return true;
            case "hotel":
            case "khachsan":
            case "khách sạn":
            case "homestay":
            case "motel":
            case "resort":
            case "luutru":
            case "lưu trú":
                profile = PosSellProfile.Hotel;
                return true;
            default:
                return false;
        }
    }

    public static void Apply(PosStoreSellSettings s)
    {
        switch (s.SellProfile)
        {
            case PosSellProfile.Retail:
                s.EnableResources = false;
                s.EnableHourlyBilling = false;
                s.EnableSessionPacks = false;
                s.RequireResourceOnSale = false;
                s.ShowFloorPlan = false;
                s.AllowProvisionalBill = true;
                s.EnableMultiDeviceDraftLock = false;
                s.PromptGuestCountOnOpen = false;
                break;
            case PosSellProfile.Salon:
                s.EnableResources = true;
                s.EnableHourlyBilling = true;
                s.EnableSessionPacks = true;
                s.RequireResourceOnSale = false;
                s.ShowFloorPlan = true;
                s.AllowProvisionalBill = true;
                s.EnableMultiDeviceDraftLock = true;
                s.PromptGuestCountOnOpen = false;
                break;
            case PosSellProfile.RoomHourly:
                s.EnableResources = true;
                s.EnableHourlyBilling = true;
                s.EnableSessionPacks = false;
                s.RequireResourceOnSale = true;
                s.ShowFloorPlan = true;
                s.AllowProvisionalBill = true;
                s.EnableMultiDeviceDraftLock = true;
                s.PromptGuestCountOnOpen = false;
                break;
            case PosSellProfile.Restaurant:
                s.EnableResources = true;
                s.EnableHourlyBilling = false;
                s.EnableSessionPacks = false;
                s.RequireResourceOnSale = false;
                s.ShowFloorPlan = true;
                s.AllowProvisionalBill = true;
                s.EnableMultiDeviceDraftLock = true;
                s.PromptGuestCountOnOpen = false;
                break;
            case PosSellProfile.Gym:
                s.EnableResources = false;
                s.EnableHourlyBilling = false;
                s.EnableSessionPacks = true;
                s.RequireResourceOnSale = false;
                s.ShowFloorPlan = false;
                s.AllowProvisionalBill = false;
                s.EnableMultiDeviceDraftLock = false;
                s.PromptGuestCountOnOpen = false;
                break;
            case PosSellProfile.Hotel:
                s.EnableResources = true;
                s.EnableHourlyBilling = true;
                s.EnableSessionPacks = false;
                s.RequireResourceOnSale = true;
                s.ShowFloorPlan = true;
                s.AllowProvisionalBill = true;
                s.EnableMultiDeviceDraftLock = true;
                s.PromptGuestCountOnOpen = true;
                s.ReportDayStartHour = 12;
                break;
        }
    }

    public static PosStoreSellSettings Create(
        Guid storeId,
        string? createdBy,
        PosSellProfile profile = PosSellProfile.Retail)
    {
        var s = new PosStoreSellSettings
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            SellProfile = profile,
            DefaultSellMode = "quick",
            IsActive = true,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = createdBy,
        };
        Apply(s);
        return s;
    }
}
