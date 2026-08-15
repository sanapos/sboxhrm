using System.Text.Json;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Thuế QR bill — cùng quy tắc POS: giá đã gồm thuế thì không cộng;
/// chưa gồm thì cộng % thiết lập cửa hàng (hoặc % từng món).
/// </summary>
public static class QrOrderTaxHelper
{
    public readonly record struct Options(string Mode, decimal VatRate);

    public static Options Resolve(string? extraJson, PosEInvoiceSetting? einvoice)
    {
        if (TryParseExtra(extraJson, out var extra))
            return extra;
        if (einvoice != null)
        {
            var m = (einvoice.TaxMode ?? "included").Trim().ToLowerInvariant();
            var rate = einvoice.DefaultTaxPercent;
            if (m is "added" or "order_total")
                return new Options("order_total", rate);
            if (m is "per_item" or "peritem")
                return new Options("per_item", rate);
            return new Options("included", rate);
        }
        return new Options("included", 8);
    }

    public static (decimal Vat, decimal Payable) Compute(
        Options tax,
        decimal net,
        IReadOnlyList<(decimal LineTotal, decimal ProductVatRate, bool Exempt)> lines)
    {
        net = Math.Max(0, net);
        var mode = (tax.Mode ?? "included").Trim().ToLowerInvariant();
        decimal vat = 0;
        if (mode is "order_total" or "added")
        {
            if (tax.VatRate > 0)
                vat = Math.Round(net * tax.VatRate / 100m, 0, MidpointRounding.AwayFromZero);
        }
        else if (mode is "per_item" or "peritem")
        {
            vat = Math.Round(lines.Sum(l =>
            {
                if (l.Exempt || l.ProductVatRate <= 0 || l.LineTotal <= 0) return 0m;
                return l.LineTotal * l.ProductVatRate / 100m;
            }), 0, MidpointRounding.AwayFromZero);
        }
        // included / none: không cộng thuế
        var payable = mode is "included" or "none" ? net : net + vat;
        return (vat, Math.Max(0, payable));
    }

    static bool TryParseExtra(string? extraJson, out Options options)
    {
        options = default;
        if (string.IsNullOrWhiteSpace(extraJson)) return false;
        try
        {
            using var doc = JsonDocument.Parse(extraJson);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return false;
            if (!doc.RootElement.TryGetProperty("sellTax", out var tax)
                && !doc.RootElement.TryGetProperty("SellTax", out tax))
                return false;
            if (tax.ValueKind != JsonValueKind.Object) return false;
            var mode = "included";
            if (tax.TryGetProperty("mode", out var m) || tax.TryGetProperty("Mode", out m))
                mode = (m.GetString() ?? "included").Trim().ToLowerInvariant();
            decimal rate = 8;
            if (tax.TryGetProperty("vatRate", out var r) || tax.TryGetProperty("VatRate", out r))
            {
                if (r.ValueKind == JsonValueKind.Number) rate = r.GetDecimal();
                else decimal.TryParse(r.GetString(), out rate);
            }
            if (rate < 0) rate = 0;
            if (rate > 100) rate = 100;
            options = new Options(string.IsNullOrWhiteSpace(mode) ? "included" : mode, rate);
            return true;
        }
        catch
        {
            return false;
        }
    }
}
