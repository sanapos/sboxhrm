namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Mã phiếu chi nhân sự (lương, ứng lương, công tác): «CH-yyyyMMdd-XXXXXXXX», ngày theo giờ VN.
/// Trước đây đuôi 4 ký tự hex (65.536 giá trị) và ngày UTC: trả lương ~200 nhân viên trong một ngày thì
/// khoảng 70% có lần trùng unique (StoreId, TransactionCode) → lỗi 500 giữa vòng trả lương. 8 ký tự hex
/// (~4,3 tỉ) không cần thử lại.
/// </summary>
public static class HrmVoucherCode
{
    public static string New(DateTime utcNow) =>
        $"CH-{VnTimeHelper.UtcToVn(utcNow):yyyyMMdd}-{Guid.NewGuid().ToString("N")[..8].ToUpperInvariant()}";
}
