using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Helpers;

public static class StoreLicenseHelper
{
    public const string ExpiredErrorCode = "LICENSE_EXPIRED";

    public const string ExpiredMessage =
        "Cửa hàng đã hết hạn sử dụng. Vui lòng liên hệ quản trị viên để gia hạn.";

    /// <summary>
    /// Cùng logic với LoginCommandHandler: ExpiryDate hoặc hết trial.
    /// </summary>
    public static bool IsExpired(Store store, DateTime? utcNow = null)
    {
        var now = (utcNow ?? DateTime.UtcNow).Date;

        if (store.ExpiryDate.HasValue)
            return store.ExpiryDate.Value.Date < now;

        if (store.TrialStartDate.HasValue && store.TrialDays > 0)
        {
            var trialEnd = store.TrialStartDate.Value.Date.AddDays(store.TrialDays);
            return trialEnd < now;
        }

        return false;
    }

    /// <summary>
    /// Ngày hết hạn hiệu lực (ExpiryDate hoặc cuối trial).
    /// </summary>
    public static DateTime? GetEffectiveExpiryDate(Store store)
    {
        if (store.ExpiryDate.HasValue)
            return store.ExpiryDate.Value.Date;

        if (store.TrialStartDate.HasValue && store.TrialDays > 0)
            return store.TrialStartDate.Value.Date.AddDays(store.TrialDays);

        return null;
    }

    /// <summary>
    /// Ngày gốc để cộng thêm khi gia hạn — giữ số ngày còn lại (kể cả trial).
    /// </summary>
    public static DateTime GetRenewalBaseDate(Store store, DateTime? utcNow = null)
    {
        var today = (utcNow ?? DateTime.UtcNow).Date;
        var effective = GetEffectiveExpiryDate(store);
        if (!effective.HasValue || effective.Value < today)
            return today;

        return effective.Value;
    }

    public static DateTime ComputeExtendedExpiryDate(Store store, int daysToAdd, DateTime? utcNow = null)
    {
        if (daysToAdd <= 0)
            throw new ArgumentOutOfRangeException(nameof(daysToAdd));

        return GetRenewalBaseDate(store, utcNow).AddDays(daysToAdd);
    }
}
