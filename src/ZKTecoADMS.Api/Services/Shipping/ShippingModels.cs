using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services.Shipping;

public static class ShippingCarrierCodes
{
    public const string Ghn = "Ghn";
    public const string Ghtk = "Ghtk";
    public const string ViettelPost = "ViettelPost";
    public const string Ahamove = "Ahamove";

    public static readonly string[] All = [Ghn, Ghtk, ViettelPost, Ahamove];

    public static string DisplayName(string code) => code switch
    {
        Ghn => "Giao Hàng Nhanh (GHN)",
        Ghtk => "Giao Hàng Tiết Kiệm (GHTK)",
        ViettelPost => "Viettel Post",
        Ahamove => "AhaMove",
        _ => code,
    };

    public static string Normalize(string? code)
    {
        var c = (code ?? "").Trim();
        if (c.Equals("ghn", StringComparison.OrdinalIgnoreCase)) return Ghn;
        if (c.Equals("ghtk", StringComparison.OrdinalIgnoreCase) ||
            c.Equals("giaohangtietkiem", StringComparison.OrdinalIgnoreCase)) return Ghtk;
        if (c.Equals("viettel", StringComparison.OrdinalIgnoreCase) ||
            c.Equals("viettelpost", StringComparison.OrdinalIgnoreCase) ||
            c.Equals("vtp", StringComparison.OrdinalIgnoreCase)) return ViettelPost;
        if (c.Equals("ahamove", StringComparison.OrdinalIgnoreCase) ||
            c.Equals("aha", StringComparison.OrdinalIgnoreCase)) return Ahamove;
        return All.FirstOrDefault(a => a.Equals(c, StringComparison.OrdinalIgnoreCase)) ?? c;
    }
}

public record ShippingQuoteRequest(
    string CarrierCode,
    string ToName,
    string ToPhone,
    string ToAddress,
    string? ToProvince,
    string? ToDistrict,
    string? ToWard,
    int WeightGrams = 500,
    decimal CodAmount = 0,
    decimal InsuranceValue = 0,
    int LengthCm = 10,
    int WidthCm = 10,
    int HeightCm = 10);

public record ShippingQuoteResult(
    bool Success,
    string CarrierCode,
    decimal Fee,
    string? ServiceName = null,
    string? ServiceCode = null,
    string? Message = null,
    string? RawJson = null);

public record ShippingCreateRequest(
    string CarrierCode,
    Guid OrderId,
    string? Note = null,
    decimal? CodAmount = null,
    int WeightGrams = 500,
    string? ServiceCode = null,
    string? ToProvince = null,
    string? ToDistrict = null,
    string? ToWard = null,
    double? ToLat = null,
    double? ToLng = null,
    int LengthCm = 10,
    int WidthCm = 10,
    int HeightCm = 10,
    /// <summary>customer | shop | fixed — mặc định shop (freeship phía khách với hãng).</summary>
    string? ShipFeePayer = null,
    /// <summary>Khi ShipFeePayer=fixed: phí cố định cộng vào đơn; hãng vẫn shop trả cước.</summary>
    decimal? FixedShipFee = null);

/// <summary>Ai trả phí ship với hãng vận chuyển.</summary>
public static class ShippingFeePayer
{
    public const string Customer = "customer";
    public const string Shop = "shop";
    public const string Fixed = "fixed";

    public static string Normalize(string? raw)
    {
        var s = (raw ?? "").Trim().ToLowerInvariant();
        return s switch
        {
            "customer" or "buyer" or "receiver" or "khach" => Customer,
            "fixed" or "flat" or "codinh" => Fixed,
            _ => Shop,
        };
    }

    /// <summary>true = cửa hàng trả cước cho hãng (freeship / payment_type shop).</summary>
    public static bool ShopPaysCarrier(string? raw)
    {
        var m = Normalize(raw);
        return m is Shop or Fixed;
    }
}

/// <summary>Ước tính kiện hàng từ dòng đơn / override tay.</summary>
public record ShippingPackageEstimate(
    int WeightGrams,
    int LengthCm,
    int WidthCm,
    int HeightCm,
    int VolumetricWeightGrams,
    int ChargeableWeightGrams,
    string Source,
    IReadOnlyList<string>? Notes = null);

public record ShippingCompareRequest(
    Guid OrderId,
    int? WeightGrams = null,
    int? LengthCm = null,
    int? WidthCm = null,
    int? HeightCm = null,
    decimal? CodAmount = null);

public record ShippingCompareQuoteItem(
    string CarrierCode,
    string CarrierName,
    bool Success,
    decimal Fee,
    string? ServiceName = null,
    string? ServiceCode = null,
    string? Message = null,
    int? EtaHours = null);

public record ShippingCompareResult(
    Guid OrderId,
    ShippingPackageEstimate Package,
    IReadOnlyList<ShippingCompareQuoteItem> Quotes);

public record ShippingCreateResult(
    bool Success,
    string CarrierCode,
    string? TrackingCode = null,
    string? CarrierOrderId = null,
    string? LabelUrl = null,
    decimal? Fee = null,
    string? Message = null,
    string? RawJson = null);

public record ShippingAddressItem(
    string Id,
    string Name,
    string? Code = null,
    string? ParentId = null);

public record ShippingLabelResult(
    bool Success,
    string CarrierCode,
    string? LabelUrl = null,
    string? PrintCode = null,
    string? Message = null);

public record ShippingCancelResult(
    bool Success,
    string CarrierCode,
    string? Message = null);

public record ShippingTrackingEvent(
    int? StatusCode,
    string? StatusName,
    string? EventTime,
    string? Location,
    string? Note);

public record ShippingTrackingResult(
    bool Success,
    string CarrierCode,
    int? StatusCode = null,
    string? StatusName = null,
    string? MappedOnlineStatus = null,
    IReadOnlyList<ShippingTrackingEvent>? Events = null,
    string? Message = null,
    string? RawJson = null);

public interface IShippingCarrierClient
{
    string CarrierCode { get; }
    Task<ShippingQuoteResult> QuoteAsync(
        PosShippingCarrierSetting settings,
        ShippingQuoteRequest request,
        CancellationToken ct = default);
    Task<ShippingCreateResult> CreateAsync(
        PosShippingCarrierSetting settings,
        PosSaleOrder order,
        ShippingCreateRequest request,
        CancellationToken ct = default);
}
