using System.Text.RegularExpressions;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services.Shipping;

/// <summary>
/// Chuẩn hóa địa chỉ nhận: đơn QR thường chỉ có Tỉnh + Phường (đơn vị hành chính 2 cấp),
/// trong khi GHTK/GHN vẫn cần Quận/Huyện.
/// </summary>
public static class ShippingAddressNormalizer
{
    public readonly record struct ReceiverParts(
        string Address,
        string? Province,
        string? District,
        string? Ward);

    public static ReceiverParts FromOrder(PosSaleOrder order) =>
        Normalize(
            order.DeliveryAddress,
            order.DeliveryProvince,
            order.DeliveryDistrict,
            order.DeliveryWard);

    public static ReceiverParts Normalize(
        string? address,
        string? province,
        string? district,
        string? ward)
    {
        var addr = (address ?? "").Trim();
        var prov = NullIfEmpty(province);
        var dist = NullIfEmpty(district);
        var w = NullIfEmpty(ward);

        if ((prov == null || dist == null || w == null) && addr.Length > 0)
        {
            var parsed = ParseCommaAddress(addr);
            prov ??= parsed.Province;
            dist ??= parsed.District;
            w ??= parsed.Ward;
            if (string.IsNullOrWhiteSpace(addr) && !string.IsNullOrWhiteSpace(parsed.Address))
                addr = parsed.Address!;
        }

        // Hành chính 2 cấp: không có quận — dùng phường làm quận để gọi API cũ (GHTK/GHN).
        if (dist == null && w != null)
            dist = w;

        return new ReceiverParts(addr, prov, dist, w);
    }

    static string? NullIfEmpty(string? s) =>
        string.IsNullOrWhiteSpace(s) ? null : s.Trim();

    /// <summary>
    /// "số nhà…, Phường X, Quận Y, Thành phố Z" hoặc "…, Phường X, Thành phố Z".
    /// </summary>
    public static ReceiverParts ParseCommaAddress(string address)
    {
        var parts = address.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Select(p => p.Trim())
            .Where(p => p.Length > 0)
            .ToList();
        if (parts.Count == 0)
            return new ReceiverParts(address, null, null, null);

        string? province = null, district = null, ward = null;
        var street = new List<string>();

        foreach (var p in parts)
        {
            if (IsProvince(p))
            {
                province ??= p;
                continue;
            }
            if (IsDistrict(p))
            {
                district ??= p;
                continue;
            }
            if (IsWard(p))
            {
                ward ??= p;
                continue;
            }
            street.Add(p);
        }

        // "A, Phường X, Thành phố Y" — phần giữa không khớp prefix vẫn có thể là phường nếu 3 phần.
        if (ward == null && district == null && parts.Count >= 3 && province != null)
        {
            var mid = parts[^2];
            if (!IsProvince(mid))
                ward = mid;
        }

        var streetText = street.Count > 0 ? string.Join(", ", street) : address;
        return new ReceiverParts(streetText, province, district, ward);
    }

    static bool IsProvince(string p)
    {
        var n = p.ToLowerInvariant();
        return n.StartsWith("tỉnh ") || n.StartsWith("thành phố ") || n.StartsWith("tp ") ||
               n.StartsWith("tp.") || Regex.IsMatch(n, @"^(tỉnh|thành phố)\b");
    }

    static bool IsDistrict(string p)
    {
        var n = p.ToLowerInvariant();
        return n.StartsWith("quận ") || n.StartsWith("huyện ") || n.StartsWith("thị xã ") ||
               n.StartsWith("quan ") || n.StartsWith("huyen ");
    }

    static bool IsWard(string p)
    {
        var n = p.ToLowerInvariant();
        return n.StartsWith("phường ") || n.StartsWith("xã ") || n.StartsWith("thị trấn ") ||
               n.StartsWith("phuong ") || n.StartsWith("xa ");
    }

    /// <summary>Bỏ tiền tố hành chính để so khớp tên ("Thành phố Đà Nẵng" ↔ "Đà Nẵng").</summary>
    public static string CompactName(string? name)
    {
        if (string.IsNullOrWhiteSpace(name)) return "";
        var s = name.Trim();
        foreach (var prefix in new[]
                 {
                     "Thành phố ", "Tỉnh ", "Quận ", "Huyện ", "Thị xã ",
                     "Phường ", "Xã ", "Thị trấn ", "TP. ", "TP ",
                 })
        {
            if (s.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                s = s[prefix.Length..].Trim();
                break;
            }
        }
        return s;
    }
}
