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
}
