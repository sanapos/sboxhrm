namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Gia hạn cửa hàng — đại lý / SuperAdmin thường chỉ preset; SuperAdmin toàn quyền nhập tùy chỉnh.
/// </summary>
public static class StoreRenewalHelper
{
    public static readonly int[] DayPresets = [7, 14, 21, 30];

    public const string PresetOnlyMessage =
        "Chỉ được gia hạn 7, 14, 21 hoặc 30 ngày. Chỉ Super Admin toàn quyền mới nhập số ngày tùy chỉnh.";

    public static bool IsPresetDay(int days) => DayPresets.Contains(days);

    public static bool IsAllowedRenewalDays(int days, bool allowCustomDays) =>
        days > 0 && (allowCustomDays || IsPresetDay(days));

    public static string InsufficientAgentBalanceMessage(int balance, int requested) =>
        $"Quỹ gia hạn đại lý không đủ. Còn {balance} ngày, cần {requested} ngày. Liên hệ Super Admin để cấp thêm.";
}
