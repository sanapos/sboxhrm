using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services;

/// <summary>Máy tem hay máy nhiệt (phiếu) — theo phần cứng, và loại chứng từ nào là tem.</summary>
public static class PosPrinterKind
{
    public static bool IsLabelBrand(string? brand) =>
        string.Equals(brand, "label", StringComparison.OrdinalIgnoreCase);

    public static bool LooksLikeLabelPaper(string? paperSize) =>
        !string.IsNullOrWhiteSpace(paperSize) &&
        (paperSize.StartsWith("roll_", StringComparison.OrdinalIgnoreCase) ||
         paperSize.Contains("50x30", StringComparison.OrdinalIgnoreCase) ||
         paperSize.Contains("40x30", StringComparison.OrdinalIgnoreCase) ||
         paperSize.Contains("x30", StringComparison.OrdinalIgnoreCase));

    /// <summary>Máy tem theo hãng / khổ giấy (chưa xét vai trò đã cấu hình).</summary>
    public static bool IsLabelHardware(PosStorePrinter p) =>
        IsLabelBrand(p.PrinterBrand) || LooksLikeLabelPaper(p.PaperSize);

    public static bool IsLabelDocument(PosPrintDocumentType dt) =>
        dt is PosPrintDocumentType.BarcodeLabel
            or PosPrintDocumentType.KitchenLabel
            or PosPrintDocumentType.ShippingLabel
            or PosPrintDocumentType.ScaleLabel
            or PosPrintDocumentType.SpecLabel;
}
