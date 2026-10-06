using System.Text.Json.Nodes;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Thiết lập bán hàng (PosStoreSellSettings) dùng chung cả cửa hàng nhưng được sửa từ nhiều màn.
/// Mỗi nhóm trường cần quyền riêng — thu ngân sửa được màn phụ / gọi món QR,
/// không sửa được thuế, tên in hóa đơn, ngành hàng…
/// </summary>
public static class SellSettingsAccess
{
    public sealed record Section(string Key, string Label, ModulePermissionAction[] Actions, string[] Modules);

    /// <summary>Ngành hàng, thuế, tên in hóa đơn, phụ thu, tích điểm, hủy/trả… — chỉ người quản lý thiết lập.</summary>
    public static readonly Section Store = new("store", "thiết lập cửa hàng",
        [ModulePermissionAction.Edit], ["SettingsHub"]);

    public static readonly Section Stock = new("stock", "cho bán âm kho / cân điện tử",
        [ModulePermissionAction.Edit], ["SettingsHub", "PosProducts"]);

    public static readonly Section QrOrder = new("qrOrder", "gọi món QR",
        [ModulePermissionAction.Edit], ["SettingsHub", "PosQrOrder"]);

    public static readonly Section CustomerDisplay = new("customerDisplay", "màn hình phụ",
        [ModulePermissionAction.Edit, ModulePermissionAction.Create], ["SettingsHub", "PosCustomerDisplay"]);

    public static readonly Section EndOfDay = new("endOfDay", "giờ chốt ngày",
        [ModulePermissionAction.Edit], ["SettingsHub", "PosReportEndOfDay"]);

    /// <summary>Khóa trong ExtraJson thuộc nhóm riêng; khóa khác (sellTax, receiptStore, fees, vietQr…) thuộc «cửa hàng».</summary>
    static readonly Dictionary<string, Section> ExtraKeySections = new(StringComparer.OrdinalIgnoreCase)
    {
        ["qrOrder"] = QrOrder,
        ["customerDisplay"] = CustomerDisplay,
        ["scale"] = Stock,
    };

    /// <summary>Bản sao các trường so sánh — chụp trước khi áp thay đổi.</summary>
    public static PosStoreSellSettings Snapshot(PosStoreSellSettings s) => new()
    {
        SellProfile = s.SellProfile,
        DefaultSellMode = s.DefaultSellMode,
        EnableResources = s.EnableResources,
        EnableHourlyBilling = s.EnableHourlyBilling,
        EnableSessionPacks = s.EnableSessionPacks,
        RequireResourceOnSale = s.RequireResourceOnSale,
        ShowFloorPlan = s.ShowFloorPlan,
        AllowProvisionalBill = s.AllowProvisionalBill,
        EnableMultiDeviceDraftLock = s.EnableMultiDeviceDraftLock,
        PromptGuestCountOnOpen = s.PromptGuestCountOnOpen,
        AllowNegativeStock = s.AllowNegativeStock,
        ReportDayStartHour = s.ReportDayStartHour,
        EnableCashierShift = s.EnableCashierShift,
        EnableQrTableOrder = s.EnableQrTableOrder,
        EnableQrOrderAutoPrint = s.EnableQrOrderAutoPrint,
        DefaultHourlyProductId = s.DefaultHourlyProductId,
        LoyaltyEnabled = s.LoyaltyEnabled,
        LoyaltyEarnPerAmount = s.LoyaltyEarnPerAmount,
        LoyaltyRedeemValue = s.LoyaltyRedeemValue,
        LoyaltyMaxRedeemPercent = s.LoyaltyMaxRedeemPercent,
        LoyaltyRefundRedeemOnReturn = s.LoyaltyRefundRedeemOnReturn,
        EnableStaffCommission = s.EnableStaffCommission,
        RequireStaffOnService = s.RequireStaffOnService,
        ExtraJson = s.ExtraJson,
    };

    /// <summary>Các nhóm bị thay đổi khi áp <paramref name="after"/> lên <paramref name="before"/>.</summary>
    public static IReadOnlyList<Section> ChangedSections(PosStoreSellSettings before, PosStoreSellSettings after)
    {
        var set = new List<Section>();
        void Add(Section s)
        {
            if (!set.Contains(s)) set.Add(s);
        }

        if (before.SellProfile != after.SellProfile
            || !string.Equals(before.DefaultSellMode, after.DefaultSellMode, StringComparison.OrdinalIgnoreCase)
            || before.EnableResources != after.EnableResources
            || before.EnableHourlyBilling != after.EnableHourlyBilling
            || before.EnableSessionPacks != after.EnableSessionPacks
            || before.RequireResourceOnSale != after.RequireResourceOnSale
            || before.ShowFloorPlan != after.ShowFloorPlan
            || before.AllowProvisionalBill != after.AllowProvisionalBill
            || before.EnableMultiDeviceDraftLock != after.EnableMultiDeviceDraftLock
            || before.PromptGuestCountOnOpen != after.PromptGuestCountOnOpen
            || before.EnableCashierShift != after.EnableCashierShift
            || before.DefaultHourlyProductId != after.DefaultHourlyProductId
            || before.LoyaltyEnabled != after.LoyaltyEnabled
            || before.LoyaltyEarnPerAmount != after.LoyaltyEarnPerAmount
            || before.LoyaltyRedeemValue != after.LoyaltyRedeemValue
            || before.LoyaltyMaxRedeemPercent != after.LoyaltyMaxRedeemPercent
            || before.LoyaltyRefundRedeemOnReturn != after.LoyaltyRefundRedeemOnReturn
            || before.EnableStaffCommission != after.EnableStaffCommission
            || before.RequireStaffOnService != after.RequireStaffOnService)
            Add(Store);

        if (before.AllowNegativeStock != after.AllowNegativeStock) Add(Stock);
        if (before.EnableQrTableOrder != after.EnableQrTableOrder
            || before.EnableQrOrderAutoPrint != after.EnableQrOrderAutoPrint)
            Add(QrOrder);
        if (before.ReportDayStartHour != after.ReportDayStartHour) Add(EndOfDay);

        foreach (var key in ChangedExtraKeys(before.ExtraJson, after.ExtraJson))
            Add(ExtraKeySections.TryGetValue(key, out var s) ? s : Store);

        return set;
    }

    /// <summary>Khóa gốc của ExtraJson có giá trị khác nhau (JSON hỏng coi như đổi cả cửa hàng).</summary>
    public static IEnumerable<string> ChangedExtraKeys(string? before, string? after)
    {
        if (string.Equals(before ?? "", after ?? "", StringComparison.Ordinal)) yield break;
        var a = Parse(before);
        var b = Parse(after);
        if (a == null || b == null)
        {
            yield return "*";
            yield break;
        }
        foreach (var key in a.Select(p => p.Key).Union(b.Select(p => p.Key), StringComparer.Ordinal))
        {
            a.TryGetPropertyValue(key, out var va);
            b.TryGetPropertyValue(key, out var vb);
            if (!JsonNode.DeepEquals(va, vb)) yield return key;
        }
    }

    static JsonObject? Parse(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return new JsonObject();
        try
        {
            return JsonNode.Parse(raw) as JsonObject;
        }
        catch
        {
            return null;
        }
    }
}
