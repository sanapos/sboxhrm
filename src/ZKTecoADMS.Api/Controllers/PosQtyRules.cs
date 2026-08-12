using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Quy tắc số lượng nguyên / thập phân theo cấu hình hàng hóa.</summary>
public static class PosQtyRules
{
    public static bool IsWhole(decimal qty) => qty == decimal.Truncate(qty);

    /// <summary>
    /// Null = hợp lệ. Không cho thập phân nếu hàng chưa bật AllowDecimalQty.
    /// Hàng bắt buộc seri luôn phải số nguyên.
    /// </summary>
    public static string? ValidateLineQty(PosProduct product, decimal qty, string actionLabel)
    {
        if (qty <= 0)
            return $"{actionLabel}: số lượng phải > 0 («{product.Name}»).";

        var mustBeWhole = product.RequiresSerial || !product.AllowDecimalQty;
        if (mustBeWhole && !IsWhole(qty))
        {
            if (product.RequiresSerial)
                return $"{actionLabel}: «{product.Name}» bắt buộc seri — số lượng phải là số nguyên.";
            return $"{actionLabel}: «{product.Name}» chưa cho phép SL thập phân. Bật trong hàng hóa để bán/nhập {qty}.";
        }

        return null;
    }
}
