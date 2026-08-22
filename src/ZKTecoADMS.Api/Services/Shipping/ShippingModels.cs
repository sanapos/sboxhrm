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
    double? ToLng = null);

public record ShippingCreateResult(
    bool Success,
    string CarrierCode,
    string? TrackingCode = null,
    string? CarrierOrderId = null,
    string? LabelUrl = null,
    decimal? Fee = null,
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
