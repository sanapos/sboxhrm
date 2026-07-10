using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Thống kê cửa hàng theo đại lý — đăng ký / đã kích hoạt key / đang dùng thử.
/// </summary>
public static class AgentStoreStatsHelper
{
    public static bool IsStoreActivated(Store store) =>
        !string.IsNullOrWhiteSpace(store.LicenseKey);

    /// <summary>
    /// Cửa hàng chưa kích hoạt key, chưa gán gói trả phí, còn trong hạn trial.
    /// </summary>
    public static bool IsStoreOnTrial(Store store, DateTime? utcNow = null)
    {
        if (IsStoreActivated(store))
            return false;
        if (store.ServicePackageId.HasValue)
            return false;

        var now = (utcNow ?? DateTime.UtcNow).Date;
        if (store.TrialStartDate.HasValue && store.TrialDays > 0)
        {
            var trialEnd = store.TrialStartDate.Value.Date.AddDays(store.TrialDays);
            return trialEnd >= now;
        }

        return false;
    }

    public static int CountRegistered(IEnumerable<Store>? stores) =>
        stores?.Count() ?? 0;

    public static int CountActivated(IEnumerable<Store>? stores) =>
        stores?.Count(IsStoreActivated) ?? 0;

    public static int CountTrial(IEnumerable<Store>? stores, DateTime? utcNow = null) =>
        stores?.Count(s => IsStoreOnTrial(s, utcNow)) ?? 0;
}
