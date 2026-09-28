using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services.Assets;

/// <summary>
/// Giá trị còn lại của tài sản.
/// Có «tỷ lệ khấu hao %/năm» + ngày mua → khấu hao đường thẳng theo số ngày đã dùng
/// (trước đây ô Giá trị hiện tại luôn = giá mua vì không ai tính khấu hao).
/// Không có tỷ lệ → dùng giá trị hiện tại nhập tay, hoặc giá mua.
/// Đã thanh lý / mất → 0.
/// </summary>
public static class AssetValuation
{
    /// <summary>Giá trị còn lại của 1 đơn vị.</summary>
    public static decimal UnitBookValue(Asset a, DateTime asOfUtc)
    {
        if (a.Status is AssetStatus.Disposed or AssetStatus.Lost) return 0;
        if (a.DepreciationRate is > 0 && a.PurchaseDate.HasValue && a.PurchasePrice > 0)
        {
            var years = (decimal)Math.Max(0, (asOfUtc - a.PurchaseDate.Value).TotalDays) / 365m;
            var ratio = Math.Max(0m, 1m - a.DepreciationRate.Value / 100m * years);
            return Math.Round(a.PurchasePrice * ratio, 0);
        }
        return a.CurrentValue ?? a.PurchasePrice;
    }

    public static decimal BookValue(Asset a, DateTime asOfUtc) => UnitBookValue(a, asOfUtc) * a.Quantity;

    public static decimal PurchaseValue(Asset a) => a.PurchasePrice * a.Quantity;

    /// <summary>Tuổi tài sản (năm) tính từ ngày mua; chưa có ngày mua → ngày tạo.</summary>
    public static double AgeYears(Asset a, DateTime asOfUtc) =>
        Math.Max(0, (asOfUtc - (a.PurchaseDate ?? a.CreatedAt)).TotalDays / 365.0);
}
