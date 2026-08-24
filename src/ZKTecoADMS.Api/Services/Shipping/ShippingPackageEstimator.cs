using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services.Shipping;

/// <summary>
/// Ước tính kiện như sàn TMĐT: cộng khối lượng SP, quy đổi thể tích (L×W×H / 6000),
/// lấy max(thực tế, thể tích) làm trọng lượng tính cước.
/// </summary>
public static class ShippingPackageEstimator
{
    public const int DefaultWeightGrams = 500;
    public const int DefaultLengthCm = 10;
    public const int DefaultWidthCm = 10;
    public const int DefaultHeightCm = 10;
    public const int DefaultItemWeightGrams = 200;
    public const int DefaultItemLengthCm = 10;
    public const int DefaultItemWidthCm = 10;
    public const int DefaultItemHeightCm = 5;
    /// <summary>Hệ số quy đổi cm³ → gram (GHN/VTP nội địa thường 6000).</summary>
    public const int VolumetricDivisor = 6000;

    public static int ToGrams(decimal? weight, string? unit)
    {
        if (weight is null or <= 0) return 0;
        var u = (unit ?? "g").Trim().ToLowerInvariant();
        if (u is "kg" or "kilogram" or "kilograms")
            return (int)Math.Round(weight.Value * 1000m, MidpointRounding.AwayFromZero);
        return (int)Math.Round(weight.Value, MidpointRounding.AwayFromZero);
    }

    public static int VolumetricGrams(int lengthCm, int widthCm, int heightCm)
    {
        var l = Math.Max(1, lengthCm);
        var w = Math.Max(1, widthCm);
        var h = Math.Max(1, heightCm);
        return (int)Math.Ceiling(l * w * h / (double)VolumetricDivisor);
    }

    public static ShippingPackageEstimate FromOverrides(
        int? weightGrams, int? lengthCm, int? widthCm, int? heightCm, string source = "manual")
    {
        var w = Math.Max(50, weightGrams ?? DefaultWeightGrams);
        var l = Math.Max(1, lengthCm ?? DefaultLengthCm);
        var wi = Math.Max(1, widthCm ?? DefaultWidthCm);
        var h = Math.Max(1, heightCm ?? DefaultHeightCm);
        var vol = VolumetricGrams(l, wi, h);
        return new ShippingPackageEstimate(
            w, l, wi, h, vol, Math.Max(w, vol), source);
    }

    public static ShippingPackageEstimate FromOrderLines(
        IEnumerable<PosSaleOrderLine> lines,
        IReadOnlyDictionary<Guid, PosProduct> products,
        int? overrideWeightGrams = null,
        int? overrideLengthCm = null,
        int? overrideWidthCm = null,
        int? overrideHeightCm = null)
    {
        var notes = new List<string>();
        var totalWeight = 0;
        var maxL = 0;
        var maxW = 0;
        var sumH = 0;
        var anyDim = false;
        var anyWeight = false;
        var lineCount = 0;

        foreach (var line in lines.Where(l => l.Deleted == null && l.Qty > 0))
        {
            lineCount++;
            var qty = Math.Max(1, (int)Math.Ceiling(line.Qty));
            products.TryGetValue(line.ProductId, out var product);

            var unitW = product != null ? ToGrams(product.Weight, product.WeightUnit) : 0;
            if (unitW <= 0)
            {
                unitW = DefaultItemWeightGrams;
                notes.Add($"{line.ProductName}: chưa có KL → mặc định {DefaultItemWeightGrams}g");
            }
            else anyWeight = true;
            totalWeight += unitW * qty;

            var l = product?.LengthCm is > 0 ? (int)Math.Ceiling(product.LengthCm.Value) : DefaultItemLengthCm;
            var w = product?.WidthCm is > 0 ? (int)Math.Ceiling(product.WidthCm.Value) : DefaultItemWidthCm;
            var h = product?.HeightCm is > 0 ? (int)Math.Ceiling(product.HeightCm.Value) : DefaultItemHeightCm;
            if (product?.LengthCm is > 0 || product?.WidthCm is > 0 || product?.HeightCm is > 0)
                anyDim = true;
            else
                notes.Add($"{line.ProductName}: chưa có KT → mặc định {DefaultItemLengthCm}×{DefaultItemWidthCm}×{DefaultItemHeightCm}cm");

            maxL = Math.Max(maxL, l);
            maxW = Math.Max(maxW, w);
            sumH += h * qty;
        }

        if (lineCount == 0)
        {
            notes.Add("Đơn không có dòng hàng — dùng kiện mặc định");
            return FromOverrides(overrideWeightGrams, overrideLengthCm, overrideWidthCm, overrideHeightCm, "default");
        }

        if (maxL <= 0) maxL = DefaultLengthCm;
        if (maxW <= 0) maxW = DefaultWidthCm;
        if (sumH <= 0) sumH = DefaultHeightCm;
        // Trần chiều cao kiện để tránh số ảo khi nhiều món.
        sumH = Math.Min(sumH, 150);

        var weight = overrideWeightGrams is > 0
            ? overrideWeightGrams.Value
            : Math.Max(50, totalWeight);
        var length = overrideLengthCm is > 0 ? overrideLengthCm.Value : maxL;
        var width = overrideWidthCm is > 0 ? overrideWidthCm.Value : maxW;
        var height = overrideHeightCm is > 0 ? overrideHeightCm.Value : sumH;

        var source = overrideWeightGrams is > 0 || overrideLengthCm is > 0
            || overrideWidthCm is > 0 || overrideHeightCm is > 0
            ? "manual+products"
            : anyWeight || anyDim ? "products" : "defaults";

        var vol = VolumetricGrams(length, width, height);
        return new ShippingPackageEstimate(
            weight, length, width, height, vol, Math.Max(weight, vol), source, notes);
    }
}
