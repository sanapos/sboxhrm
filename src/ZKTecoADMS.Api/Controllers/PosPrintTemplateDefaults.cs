using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Mẫu HTML mặc định theo khổ giấy (kiểu KiotViet).</summary>
public static class PosPrintTemplateDefaults
{
    public static string DocumentTitle(PosPrintDocumentType type) => type switch
    {
        PosPrintDocumentType.SaleOrder => "HÓA ĐƠN ĐẶT HÀNG",
        PosPrintDocumentType.SaleInvoice => "HÓA ĐƠN BÁN HÀNG",
        PosPrintDocumentType.Delivery => "PHIẾU GIAO HÀNG",
        PosPrintDocumentType.SaleReturn => "PHIẾU TRẢ HÀNG",
        PosPrintDocumentType.SaleExchange => "PHIẾU ĐỔI TRẢ HÀNG",
        PosPrintDocumentType.PurchaseOrder => "ĐẶT HÀNG NHẬP",
        PosPrintDocumentType.PurchaseReceipt => "PHIẾU NHẬP HÀNG",
        PosPrintDocumentType.PurchaseReturn => "TRẢ HÀNG NHẬP",
        PosPrintDocumentType.StockTransfer => "PHIẾU CHUYỂN HÀNG",
        PosPrintDocumentType.StockIssue => "PHIẾU BÁO XUẤT KHO",
        PosPrintDocumentType.KitchenSlip => "PHIẾU BÁO CHẾ BIẾN",
        PosPrintDocumentType.KitchenVoid => "PHIẾU HỦY BẾP",
        PosPrintDocumentType.BarcodeLabel => "TEM SẢN PHẨM",
        PosPrintDocumentType.ScaleLabel => "TEM CÂN",
        PosPrintDocumentType.SpecLabel => "TEM THÔNG SỐ",
        PosPrintDocumentType.KitchenLabel => "TEM BÁO BẾP",
        PosPrintDocumentType.CashReceipt => "PHIẾU THU",
        PosPrintDocumentType.CashPayment => "PHIẾU CHI",
        PosPrintDocumentType.Quote => "BÁO GIÁ",
        PosPrintDocumentType.Contract => "HỢP ĐỒNG",
        PosPrintDocumentType.Handover => "BIÊN BẢN BÀN GIAO",
        PosPrintDocumentType.Acceptance => "BIÊN BẢN NGHIỆM THU",
        PosPrintDocumentType.PaymentRequest => "ĐỀ NGHỊ THANH TOÁN",
        _ => "CHỨNG TỪ",
    };

    /// <summary>Nhãn khổ giấy ngắn in trên tên mẫu.</summary>
    public static string PaperLabel(PosPrintPaperSize size) => size switch
    {
        PosPrintPaperSize.K58 => "K58",
        PosPrintPaperSize.K80 => "K80",
        PosPrintPaperSize.A5 => "A5",
        PosPrintPaperSize.A4 => "A4",
        PosPrintPaperSize.Label50x30 => "50×30",
        PosPrintPaperSize.Label40x30 => "40×30",
        _ => size.ToString(),
    };

    /// <summary>Nhãn loại chứng từ ngắn gọn để đặt tên mẫu dễ phân biệt (vd «Hợp đồng A4»).</summary>
    public static string ShortDocLabel(PosPrintDocumentType type) => type switch
    {
        PosPrintDocumentType.SaleOrder => "Đặt hàng",
        PosPrintDocumentType.SaleInvoice => "Hóa đơn",
        PosPrintDocumentType.Delivery => "Giao hàng",
        PosPrintDocumentType.SaleReturn => "Trả hàng",
        PosPrintDocumentType.SaleExchange => "Đổi trả",
        PosPrintDocumentType.PurchaseOrder => "Đặt hàng nhập",
        PosPrintDocumentType.PurchaseReceipt => "Nhập hàng",
        PosPrintDocumentType.PurchaseReturn => "Trả hàng nhập",
        PosPrintDocumentType.StockTransfer => "Chuyển hàng",
        PosPrintDocumentType.StockIssue => "Xuất kho",
        PosPrintDocumentType.KitchenSlip => "Báo chế biến",
        PosPrintDocumentType.KitchenVoid => "Hủy bếp",
        PosPrintDocumentType.KitchenLabel => "Tem bếp",
        PosPrintDocumentType.BarcodeLabel => "Tem sản phẩm",
        PosPrintDocumentType.ScaleLabel => "Tem cân",
        PosPrintDocumentType.SpecLabel => "Tem thông số",
        PosPrintDocumentType.CashReceipt => "Phiếu thu",
        PosPrintDocumentType.CashPayment => "Phiếu chi",
        PosPrintDocumentType.Quote => "Báo giá",
        PosPrintDocumentType.Contract => "Hợp đồng",
        PosPrintDocumentType.Handover => "Bàn giao",
        PosPrintDocumentType.Acceptance => "Nghiệm thu",
        PosPrintDocumentType.PaymentRequest => "Đề nghị TT",
        _ => "Mẫu",
    };

    /// <summary>Tên mẫu mặc định: «&lt;loại chứng từ&gt; &lt;khổ&gt;» (vd «Hợp đồng A4») để dễ phân biệt giữa các loại.</summary>
    public static string TemplateName(PosPrintDocumentType type, PosPrintPaperSize size, int variant = 1)
        => $"{ShortDocLabel(type)} {PaperLabel(size)}";

    [Obsolete("Use TemplateName(type, size, variant)")]
    public static string TemplateName(PosPrintPaperSize size, int variant = 1) =>
        size switch
        {
            PosPrintPaperSize.K58 => $"Khổ K57/K58 - Mẫu {variant}",
            PosPrintPaperSize.K80 => $"Khổ K80 - Mẫu {variant}",
            PosPrintPaperSize.A5 => $"Khổ A5 - Mẫu {variant}",
            PosPrintPaperSize.A4 => $"Khổ A4 - Mẫu {variant}",
            PosPrintPaperSize.Label50x30 => "Tem 50×30 mm",
            PosPrintPaperSize.Label40x30 => "Tem 40×30 mm",
            _ => $"Mẫu {variant}",
        };

    /// <summary>1–3 mẫu chung / loại chứng từ (soạn sẵn để cửa hàng chọn clone).</summary>
    public readonly record struct CatalogSpec(
        string Name, PosPrintPaperSize PaperSize, int SortOrder, bool IsRecommended);

    public static IReadOnlyList<CatalogSpec> CatalogSpecs(PosPrintDocumentType docType)
    {
        // Tên mẫu = «<loại chứng từ> <khổ>» (+ ★ cho mẫu khuyên dùng) → dễ phân biệt giữa các loại chứng từ.
        CatalogSpec Spec(PosPrintPaperSize size, int sort, bool recommended) => new(
            $"{ShortDocLabel(docType)} {PaperLabel(size)}{(recommended ? " ★" : "")}",
            size, sort, recommended);

        if (docType is PosPrintDocumentType.BarcodeLabel or PosPrintDocumentType.KitchenLabel
            or PosPrintDocumentType.ScaleLabel or PosPrintDocumentType.SpecLabel)
        {
            return new[]
            {
                Spec(PosPrintPaperSize.Label50x30, 0, true),
                Spec(PosPrintPaperSize.Label40x30, 1, false),
            };
        }

        if (docType is PosPrintDocumentType.KitchenSlip or PosPrintDocumentType.KitchenVoid)
        {
            return new[]
            {
                Spec(PosPrintPaperSize.K80, 0, true),
                Spec(PosPrintPaperSize.K58, 1, false),
            };
        }

        if (docType is PosPrintDocumentType.Quote or PosPrintDocumentType.Contract
            or PosPrintDocumentType.Handover or PosPrintDocumentType.Acceptance
            or PosPrintDocumentType.PaymentRequest)
        {
            return new[]
            {
                Spec(PosPrintPaperSize.A4, 0, true),
                Spec(PosPrintPaperSize.A5, 1, false),
            };
        }

        // Nhập hàng / kho / thu chi: chứng từ kế toán — mặc định A4 (máy in mực), vẫn giữ K80/K58 cho tiệm chỉ có máy nhiệt.
        if (IsOfficeFirstDoc(docType))
        {
            return new[]
            {
                Spec(PosPrintPaperSize.A4, 0, true),
                Spec(PosPrintPaperSize.A5, 1, false),
                Spec(PosPrintPaperSize.K80, 2, false),
                Spec(PosPrintPaperSize.K58, 3, false),
            };
        }

        // Hóa đơn / đặt / giao / trả / đổi hàng: K80 chuẩn, K58, trang A5 / A4 (máy in văn phòng)
        return new[]
        {
            Spec(PosPrintPaperSize.K80, 0, true),
            Spec(PosPrintPaperSize.K58, 1, false),
            Spec(PosPrintPaperSize.A5, 2, false),
            Spec(PosPrintPaperSize.A4, 3, false),
        };
    }

    /// <summary>Chứng từ nhập / kho / quỹ — mẫu khuyên dùng là A4.</summary>
    public static bool IsOfficeFirstDoc(PosPrintDocumentType t) => t is PosPrintDocumentType.PurchaseOrder
        or PosPrintDocumentType.PurchaseReceipt or PosPrintDocumentType.PurchaseReturn
        or PosPrintDocumentType.StockTransfer or PosPrintDocumentType.StockIssue
        or PosPrintDocumentType.CashReceipt or PosPrintDocumentType.CashPayment;

    /// <summary>Khổ seed theo loại chứng từ — tem không dùng K58/K80.</summary>
    public static IReadOnlyList<PosPrintPaperSize> SizesForDocument(PosPrintDocumentType docType)
    {
        return CatalogSpecs(docType).Select(s => s.PaperSize).Distinct().ToList();
    }

    public static string BuildHtml(PosPrintDocumentType docType, PosPrintPaperSize paperSize)
    {
        var title = DocumentTitle(docType);
        // Tem thông số: mẫu HTML cũ dùng chung tem sản phẩm (mẫu V2 dựng sẵn do app tạo).
        if (docType is PosPrintDocumentType.BarcodeLabel or PosPrintDocumentType.SpecLabel)
            return BuildProductLabelHtml(paperSize);
        if (docType == PosPrintDocumentType.KitchenLabel)
            return BuildKitchenLabelHtml(paperSize);
        if (docType == PosPrintDocumentType.ScaleLabel)
            return BuildScaleLabelHtml(paperSize);
        if (docType is PosPrintDocumentType.KitchenSlip or PosPrintDocumentType.KitchenVoid)
            return BuildKitchenV2(paperSize, isCancel: docType == PosPrintDocumentType.KitchenVoid);
        if (docType is PosPrintDocumentType.Quote or PosPrintDocumentType.Contract
            or PosPrintDocumentType.Handover or PosPrintDocumentType.Acceptance
            or PosPrintDocumentType.PaymentRequest)
            return ZKTecoADMS.Api.Services.PosQuoteDocumentHtml.DefaultA4Html(title);
        if (paperSize is PosPrintPaperSize.K58 or PosPrintPaperSize.K80)
            return BuildThermalV2(docType, paperSize);
        return LoadSheet(docType, paperSize) ?? BuildSheetHtml(title, paperSize);
    }

    static readonly System.Collections.Concurrent.ConcurrentDictionary<string, string?> SheetCache = new();

    /// <summary>
    /// Mẫu khổ trang riêng từng loại chứng từ — một nguồn: PrintTemplates/Sheet/{Loại}.{A4|A5}.html
    /// (app Flutter sinh từ cùng file qua scripts/gen_commercial_templates.py).
    /// </summary>
    public static string? LoadSheet(PosPrintDocumentType docType, PosPrintPaperSize size)
    {
        if (size is not (PosPrintPaperSize.A4 or PosPrintPaperSize.A5)) return null;
        return SheetCache.GetOrAdd($"{docType}.{size}", key =>
        {
            using var stream = typeof(PosPrintTemplateDefaults).Assembly
                .GetManifestResourceStream($"Sbox.Sheet.{key}.html");
            if (stream == null) return null;
            using var reader = new StreamReader(stream);
            return reader.ReadToEnd().Trim();
        });
    }

    static string LabelWidthCss(PosPrintPaperSize size) => size switch
    {
        PosPrintPaperSize.Label40x30 => "40mm",
        PosPrintPaperSize.Label50x30 => "50mm",
        PosPrintPaperSize.K58 => "58mm",
        _ => "50mm",
    };

    static string BuildProductLabelHtml(PosPrintPaperSize size)
    {
        var width = LabelWidthCss(size);
        var compact = size == PosPrintPaperSize.Label40x30;
        var nameFs = compact ? "13px" : "14px";
        var priceFs = compact ? "13px" : "14px";
        return
            "<div style=\"width:" + width +
            ";max-width:100%;box-sizing:border-box;margin:0 auto;padding:1mm;" +
            "overflow:hidden;font-family:Arial,sans-serif;color:#000;text-align:center\">" +
            (compact ? "" : "<div style=\"font-weight:bold;font-size:10px\">{Ten_Cua_Hang}</div>") +
            "<div style=\"font-weight:bold;font-size:" + nameFs +
            ";margin:2px 0;line-height:1.15\">{Ten_Hang_Hoa}</div>" +
            "<div style=\"letter-spacing:1px;font-family:monospace;border:1px solid #000;" +
            "padding:3px 2px;margin:3px 0;font-size:11px\">|||| {Ma_Vach} ||||</div>" +
            "<div style=\"font-weight:bold;font-size:" + priceFs + "\">{Don_Gia} đ</div>" +
            "</div>";
    }

    /// <summary>Tem cân: tên hàng · KL × đơn giá · thành tiền · mã cân · ngày giờ in · HSD.</summary>
    static string BuildScaleLabelHtml(PosPrintPaperSize size)
    {
        var width = LabelWidthCss(size);
        var compact = size == PosPrintPaperSize.Label40x30;
        return
            "<div style=\"width:" + width +
            ";max-width:100%;box-sizing:border-box;margin:0 auto;padding:1mm;" +
            "overflow:hidden;font-family:Arial,sans-serif;color:#000;text-align:center;font-size:10px\">" +
            (compact ? "" : "<div style=\"font-weight:bold\">{Ten_Cua_Hang}</div>") +
            "<div style=\"font-weight:bold;font-size:" + (compact ? "12px" : "13px") + "\">{Ten_Hang_Hoa}</div>" +
            "<div style=\"display:flex;justify-content:space-between\"><span>{Khoi_Luong}</span><span>{Don_Gia_Kg}</span></div>" +
            "<div style=\"font-weight:bold;font-size:" + (compact ? "14px" : "16px") + "\">{Thanh_Tien} đ</div>" +
            "<div style=\"letter-spacing:1px;font-family:monospace;border:1px solid #000;padding:2px;margin:2px 0\">|||| {Ma_Vach} ||||</div>" +
            "<div>In: {Ngay_Gio_In}</div>" +
            "<div style=\"font-weight:bold\">HSD: {HSD}</div>" +
            "</div>";
    }

    static string BuildKitchenLabelHtml(PosPrintPaperSize size)
    {
        var width = LabelWidthCss(size);
        var compact = size == PosPrintPaperSize.Label40x30;
        var nameFs = compact ? "14px" : "15px";
        return
            "<div style=\"width:" + width +
            ";max-width:100%;box-sizing:border-box;margin:0 auto;padding:1mm;" +
            "overflow:hidden;font-family:Arial,sans-serif;font-size:11px;color:#000\">" +
            "<div style=\"display:flex;justify-content:space-between;font-weight:bold\">" +
            "<span>{Ten_Ban}</span><span>{Gio}</span></div>" +
            "<div style=\"text-align:center;font-weight:bold;font-size:" + nameFs +
            ";margin:3px 0;line-height:1.15\">{Ten_Hang_Hoa}</div>" +
            "<div style=\"text-align:center;font-size:10px\">{Ghi_Chu}</div>" +
            "<div style=\"text-align:center;font-weight:bold;margin-top:2px\">{So_Luong} {Don_Vi_Tinh}</div>" +
            "</div>";
    }

    static string BuildKitchenV2(PosPrintPaperSize size, bool isCancel)
    {
        var k58 = size == PosPrintPaperSize.K58;
        var paper = k58 ? "K58" : "K80";
        var profile = k58 ? "sunmi_k58" : "sunmi_k80";
        var titleFs = k58 ? 32 : 36;
        var body = k58 ? 22 : 24;
        var item = k58 ? 24 : 26;
        var badge = isCancel ? "*** PHIẾU HỦY ***" : "*** BÁO CHẾ BIẾN ***";
        var doc = isCancel ? PosPrintDocumentType.KitchenVoid : PosPrintDocumentType.KitchenSlip;
        var name = TemplateName(doc, size);
        return
            "<!--POS_TEMPLATE_V2-->\n" +
            "{\"version\":1,\"paperSize\":\"" + paper + "\",\"printerProfile\":\"" + profile +
            "\",\"documentType\":\"" + doc + "\",\"name\":\"" + name +
            "\",\"blocks\":[" +
            "{\"type\":\"field\",\"field\":\"Ten_Ban\",\"style\":{\"fontSize\":" + titleFs + ",\"bold\":true,\"align\":\"center\"}}," +
            "{\"type\":\"text\",\"text\":\"" + badge + "\",\"style\":{\"fontSize\":" + (titleFs - 2) + ",\"bold\":true,\"align\":\"center\"}}," +
            "{\"type\":\"divider\"}," +
            "{\"type\":\"text\",\"text\":\"Mã HĐ: {Ma_Don_Hang}\",\"style\":{\"fontSize\":" + body + ",\"bold\":true,\"align\":\"left\"}}," +
            "{\"type\":\"text\",\"text\":\"NV: {Nguoi_Ban}\",\"style\":{\"fontSize\":" + body + ",\"bold\":true,\"align\":\"left\"}}," +
            "{\"type\":\"text\",\"text\":\"Gọi lúc: {Ngay} {Gio}\",\"style\":{\"fontSize\":" + body + ",\"bold\":true,\"align\":\"left\"}}," +
            "{\"type\":\"divider\"}," +
            "{\"type\":\"lineItemsKitchen\",\"style\":{\"fontSize\":" + item + ",\"bold\":true,\"align\":\"left\"}}" +
            "]}";
    }

    static string BuildKitchenSlipHtml(string title, PosPrintPaperSize size, bool isCancel)
    {
        return BuildKitchenV2(size, isCancel);
    }

    /// <summary>Mẫu nhiệt V2 gọn — ít dòng, không QR mặc định.</summary>
    /// Mẫu mặc định = HĐ K80 đang thiết lập cửa hàng demopos (K58 thu nhỏ tỉ lệ).
    static string BuildThermalV2(PosPrintDocumentType docType, PosPrintPaperSize size)
    {
        var k58 = size == PosPrintPaperSize.K58;
        var paper = k58 ? "K58" : "K80";
        var profile = k58 ? "sunmi_k58" : "sunmi_k80";
        var title = k58 ? 28 : 40;
        var addr = k58 ? 18 : 24;
        var heading = k58 ? 24 : 32;
        var orderNo = k58 ? 22 : 28;
        var body = k58 ? 18 : 24;
        var totL = k58 ? 20 : 26;
        var totR = k58 ? 24 : 32;
        var thanks = k58 ? 20 : 30;
        var isReturn = docType == PosPrintDocumentType.SaleReturn;
        var name = isReturn
            ? (k58 ? "Trả K58" : "Trả K80")
            : (k58 ? "HĐ K58" : "HĐ K80");
        var totals = isReturn
            ? "{\"type\":\"totals\",\"fields\":[\"Tong_Cong\"],\"fieldLabels\":{\"Tong_Cong\":\"HOÀN TIỀN\"},\"style\":{\"fontSize\":" + totL + ",\"bold\":true,\"align\":\"left\"},\"rightStyle\":{\"fontSize\":" + totR + ",\"bold\":true,\"align\":\"right\"}}"
            : "{\"type\":\"totals\",\"fields\":[\"Tong_Tien_Hang\",\"Chiet_Khau_Hoa_Don\",\"Tien_Thue\",\"Phu_Thu\",\"Phi_Giao_Hang\",\"Tong_Cong\"],\"fieldLabels\":{\"Tong_Tien_Hang\":\"Tổng tiền hàng\",\"Chiet_Khau_Hoa_Don\":\"Chiết khấu\",\"Tien_Thue\":\"Thuế\",\"Phu_Thu\":\"Phụ thu\",\"Phi_Giao_Hang\":\"Phí GH\",\"Tong_Cong\":\"TỔNG CỘNG\"},\"style\":{\"fontSize\":" + totL + ",\"bold\":true,\"align\":\"left\"},\"rightStyle\":{\"fontSize\":" + totR + ",\"bold\":true,\"align\":\"right\"}}";
        var footer = isReturn ? "Phiếu trả hàng" : "Cảm ơn quý khách!";
        return
            "<!--POS_TEMPLATE_V2-->\n" +
            "{\"version\":1,\"paperSize\":\"" + paper + "\",\"printerProfile\":\"" + profile +
            "\",\"documentType\":\"" + docType + "\",\"name\":\"" + name +
            "\",\"blocks\":[" +
            "{\"type\":\"field\",\"field\":\"Ten_Cua_Hang\",\"style\":{\"fontSize\":" + title + ",\"bold\":true,\"align\":\"center\"}}," +
            "{\"type\":\"field\",\"field\":\"Dia_Chi_Chi_Nhanh\",\"style\":{\"fontSize\":" + addr + ",\"bold\":false,\"align\":\"center\"}}," +
            "{\"type\":\"field\",\"field\":\"Dien_Thoai_Chi_Nhanh\",\"style\":{\"fontSize\":" + addr + ",\"bold\":false,\"align\":\"center\"}}," +
            "{\"type\":\"divider\",\"style\":{\"fontSize\":24,\"bold\":false,\"align\":\"left\"},\"divider\":\"dash\"}," +
            "{\"type\":\"field\",\"field\":\"Tieu_De_In\",\"style\":{\"fontSize\":" + heading + ",\"bold\":true,\"align\":\"center\"}}," +
            "{\"type\":\"field\",\"field\":\"Ma_Don_Hang\",\"label\":\"Số HĐ\",\"style\":{\"fontSize\":" + orderNo + ",\"bold\":false,\"align\":\"left\"}}," +
            "{\"type\":\"field\",\"field\":\"Ten_Ban\",\"style\":{\"fontSize\":" + body + ",\"bold\":false,\"align\":\"left\"}}," +
            "{\"type\":\"field\",\"field\":\"Ngay\",\"label\":\"Ngày\",\"style\":{\"fontSize\":" + body + ",\"bold\":false,\"align\":\"left\"}}," +
            "{\"type\":\"field\",\"field\":\"Khach_Hang\",\"label\":\"Khách hàng\",\"style\":{\"fontSize\":" + body + ",\"bold\":false,\"align\":\"left\"}}," +
            "{\"type\":\"divider\",\"style\":{\"fontSize\":24,\"bold\":false,\"align\":\"left\"},\"divider\":\"dash\"}," +
            "{\"type\":\"lineItems\",\"fieldLabels\":{\"Ten_Hang_Hoa\":\"Tên hàng\",\"So_Luong\":\"SL\",\"Don_Gia\":\"Đ.giá\",\"Thanh_Tien\":\"T.T\"},\"showColumnHeader\":true,\"style\":{\"fontSize\":" + body + ",\"bold\":false,\"align\":\"left\"},\"rightStyle\":{\"fontSize\":" + body + ",\"bold\":true,\"align\":\"left\"}}," +
            "{\"type\":\"divider\",\"style\":{\"fontSize\":24,\"bold\":false,\"align\":\"left\"},\"divider\":\"dash\"}," +
            totals + "," +
            "{\"type\":\"field\",\"field\":\"Tong_Cong_Bang_Chu\",\"style\":{\"fontSize\":" + body + ",\"bold\":false,\"align\":\"center\"}}," +
            "{\"type\":\"text\",\"text\":\"" + footer + "\",\"style\":{\"fontSize\":" + thanks + ",\"bold\":true,\"align\":\"center\"}}" +
            "]}";
    }

    static string BuildThermalHtml(string title, PosPrintPaperSize size)
    {
        var width = size == PosPrintPaperSize.K58 ? "58mm" : "80mm";
        var fs = size == PosPrintPaperSize.K58 ? "13px" : "14px";
        var titleFs = size == PosPrintPaperSize.K58 ? "18px" : "20px";
        var storeFs = size == PosPrintPaperSize.K58 ? "16px" : "18px";
        var totalFs = size == PosPrintPaperSize.K58 ? "16px" : "18px";
        return
            "<div style=\"width:" + width +
            ";max-width:100%;box-sizing:border-box;margin:0 auto;padding:0 1mm;" +
            "font-family:Arial,sans-serif;font-size:" + fs + ";color:#000\">" +
            "<div style=\"text-align:center\">" +
            "<div style=\"font-weight:bold;font-size:" + storeFs + "\">{Ten_Cua_Hang}</div>" +
            "<div style=\"margin-top:2px\">{Dia_Chi_Chi_Nhanh}</div>" +
            "<div>ĐT: {Dien_Thoai_Chi_Nhanh}</div>" +
            "<div style=\"font-weight:bold;font-size:" + titleFs + ";margin-top:6px\">" + title + "</div>" +
            "</div>" +
            "<div style=\"margin:6px 0;border-top:2px solid #000\"></div>" +
            "<div><b>Bàn:</b> {Ten_Ban}</div>" +
            "<div><b>Số HĐ:</b> {Ma_Don_Hang}</div>" +
            "<div><b>Ngày:</b> {Ngay}</div>" +
            "<div>KH: {Khach_Hang}</div>" +
            "<div style=\"margin:6px 0;border-top:2px solid #000\"></div>" +
            "<table style=\"width:100%;border-collapse:collapse;font-size:" + fs + "\">" +
            "<thead><tr style=\"border-bottom:2px solid #000\">" +
            "<th style=\"text-align:left;padding:3px 2px\">Tên hàng</th>" +
            "<th style=\"text-align:center;width:12%;padding:3px 2px\">SL</th>" +
            "<th style=\"text-align:right;width:24%;padding:3px 2px\">Đ.giá</th>" +
            "<th style=\"text-align:right;width:26%;padding:3px 2px\">TT</th>" +
            "</tr></thead><tbody><!--BEGIN_ITEMS-->" +
            "<tr style=\"border-bottom:1px dotted #555\">" +
            "<td style=\"padding:5px 2px 3px;font-weight:bold;vertical-align:top\">{Ten_Hang_Hoa}</td>" +
            "<td style=\"text-align:center;vertical-align:top;padding:5px 2px\">{So_Luong}</td>" +
            "<td style=\"text-align:right;vertical-align:top;padding:5px 2px\">{Don_Gia}</td>" +
            "<td style=\"text-align:right;vertical-align:top;padding:5px 2px;font-weight:bold\">{Thanh_Tien}</td>" +
            "</tr><!--END_ITEMS--></tbody></table>" +
            "<div style=\"margin:6px 0;border-top:2px solid #000\"></div>" +
            "<div style=\"display:flex;justify-content:space-between\"><span>Tổng tiền hàng</span><b>{Tong_Tien_Hang}</b></div>" +
            "<div style=\"display:flex;justify-content:space-between\"><span>Chiết khấu</span><span>{Chiet_Khau_Hoa_Don}</span></div>" +
            "<div style=\"display:flex;justify-content:space-between;font-size:" + totalFs +
            ";font-weight:bold;margin-top:4px\"><span>TỔNG CỘNG</span><span>{Tong_Cong}</span></div>" +
            "<div style=\"display:flex;justify-content:space-between\"><span>Đã thanh toán</span><span>{Khach_Thanh_Toan}</span></div>" +
            "<div style=\"display:flex;justify-content:space-between\"><span>Tiền thừa</span><span>{Tien_Thua}</span></div>" +
            "<div style=\"margin-top:6px;font-style:italic;text-align:center\">{Tong_Cong_Bang_Chu}</div>" +
            "<div style=\"margin-top:8px;text-align:center;font-weight:bold\">Cảm ơn quý khách!</div>" +
            "<div style=\"margin-top:4px;font-size:11px;text-align:center\">{Ghi_Chu}</div></div>";
    }

    /// <summary>
    /// Phiếu khổ trang (máy in văn phòng). A4: đủ cột (mã hàng, ĐVT, CK); A5 (nửa A4): bỏ mã hàng / ĐVT / CK cho gọn.
    /// Dòng chiết khấu / phụ thu / phí giao / VAT / còn nợ chỉ in khi khác 0 (<!--IF:…-->).
    /// </summary>
    static string BuildSheetHtml(string title, PosPrintPaperSize size)
    {
        var a5 = size == PosPrintPaperSize.A5;
        var fs = a5 ? "11px" : "12.5px";
        var cell = a5 ? "padding:3px 4px" : "padding:5px 6px";
        var th = "border:1px solid #000;" + cell + ";font-weight:bold;white-space:nowrap";
        var td = "border:1px solid #000;" + cell;
        var signGap = a5 ? "36px" : "60px";

        string Row(string label, string field, bool bold = false)
        {
            var w = bold ? ";font-weight:bold" : "";
            return "<!--IF:" + field + "--><tr><td style=\"padding:2px 0" + w + "\">" + label +
                "</td><td style=\"padding:2px 0;text-align:right" + w + "\">{" + field +
                "}</td></tr><!--ENDIF:" + field + "-->";
        }

        string If(string field, string inner) => "<!--IF:" + field + "-->" + inner + "<!--ENDIF:" + field + "-->";

        var head =
            "<div style=\"font-family:Arial,sans-serif;font-size:" + fs + ";color:#000;line-height:1.35\">" +
            "<table style=\"width:100%;border-collapse:collapse\"><tr>" +
            "<td style=\"vertical-align:top\">" +
            "<div style=\"font-weight:bold;font-size:" + (a5 ? "15px" : "18px") + "\">{Ten_Cua_Hang}</div>" +
            If("Dia_Chi_Chi_Nhanh", "<div>{Dia_Chi_Chi_Nhanh}</div>") +
            If("Dien_Thoai_Chi_Nhanh", "<div>ĐT: {Dien_Thoai_Chi_Nhanh}</div>") +
            "</td><td style=\"text-align:right;vertical-align:top;white-space:nowrap\">" +
            "<div style=\"font-weight:bold;font-size:" + (a5 ? "16px" : "20px") + "\">" + title.ToUpperInvariant() + "</div>" +
            "<div>Số: <b>{Ma_Don_Hang}</b></div><div>Ngày: {Ngay} {Gio}</div>" +
            If("In_Lai", "<div style=\"font-weight:bold\">{In_Lai}</div>") +
            "</td></tr></table>" +
            "<div style=\"border-top:2px solid #000;margin:6px 0\"></div>" +
            "<table style=\"width:100%;border-collapse:collapse;margin-bottom:6px\"><tr><td style=\"vertical-align:top\">" +
            "<div><b>Khách hàng:</b> " + If("Khach_Hang", "{Khach_Hang}") +
            "<!--IFNOT:Khach_Hang-->Khách lẻ<!--ENDIFNOT:Khach_Hang--></div>" +
            If("SDT", "<div><b>Điện thoại:</b> {SDT}</div>") +
            If("Dia_Chi_Khach_Hang", "<div><b>Địa chỉ:</b> {Dia_Chi_Khach_Hang}</div>") +
            "</td><td style=\"vertical-align:top;text-align:right\">" +
            If("Ten_Ban", "<div><b>Bàn/Phòng:</b> {Ten_Ban}</div>") +
            If("Nguoi_Ban", "<div><b>Người bán:</b> {Nguoi_Ban}</div>") +
            "</td></tr></table>";

        var noteCell = If("Ghi_Chu", "<div style=\"font-size:90%;font-style:italic\">{Ghi_Chu}</div>");
        var cols = a5
            ? "<th style=\"" + th + ";width:7%\">STT</th>" +
              "<th style=\"" + th + ";text-align:left\">Tên hàng</th>" +
              "<th style=\"" + th + ";width:9%\">SL</th>" +
              "<th style=\"" + th + ";text-align:right;width:19%\">Đơn giá</th>" +
              "<th style=\"" + th + ";text-align:right;width:22%\">Thành tiền</th>"
            : "<th style=\"" + th + ";width:6%\">STT</th>" +
              "<th style=\"" + th + ";width:12%\">Mã hàng</th>" +
              "<th style=\"" + th + ";text-align:left\">Tên hàng</th>" +
              "<th style=\"" + th + ";width:8%\">ĐVT</th>" +
              "<th style=\"" + th + ";width:7%\">SL</th>" +
              "<th style=\"" + th + ";text-align:right;width:13%\">Đơn giá</th>" +
              "<th style=\"" + th + ";text-align:right;width:10%\">CK</th>" +
              "<th style=\"" + th + ";text-align:right;width:15%\">Thành tiền</th>";
        var line = a5
            ? "<tr><td style=\"" + td + ";text-align:center\">{STT}</td>" +
              "<td style=\"" + td + "\">{Ten_Hang_Hoa}" + noteCell + "</td>" +
              "<td style=\"" + td + ";text-align:center\">{So_Luong}</td>" +
              "<td style=\"" + td + ";text-align:right\">{Don_Gia}</td>" +
              "<td style=\"" + td + ";text-align:right\">{Thanh_Tien}</td></tr>"
            : "<tr><td style=\"" + td + ";text-align:center\">{STT}</td>" +
              "<td style=\"" + td + "\">{Ma_Hang}</td>" +
              "<td style=\"" + td + "\">{Ten_Hang_Hoa}" + noteCell + "</td>" +
              "<td style=\"" + td + ";text-align:center\">{Don_Vi_Tinh}</td>" +
              "<td style=\"" + td + ";text-align:center\">{So_Luong}</td>" +
              "<td style=\"" + td + ";text-align:right\">{Don_Gia}</td>" +
              "<td style=\"" + td + ";text-align:right\">{Chiet_Khau}</td>" +
              "<td style=\"" + td + ";text-align:right\">{Thanh_Tien}</td></tr>";

        var items =
            "<table style=\"width:100%;border-collapse:collapse\"><thead><tr>" + cols +
            "</tr></thead><tbody><!--BEGIN_ITEMS-->" + line + "<!--END_ITEMS--></tbody></table>";

        var totals =
            "<table style=\"width:100%;border-collapse:collapse;margin-top:8px\"><tr>" +
            "<td style=\"width:" + (a5 ? "40%" : "52%") + ";vertical-align:top;padding-right:10px\">" +
            If("Hinh_Thuc_Thanh_Toan", "<div><b>Thanh toán:</b> {Hinh_Thuc_Thanh_Toan}</div>") +
            If("HDDT_So", "<div style=\"margin-top:4px\"><b>HĐĐT:</b> {HDDT_Ky_Hieu} số {HDDT_So}" +
                If("HDDT_Ma_Tra_Cuu", " · Mã tra cứu: {HDDT_Ma_Tra_Cuu}") + "</div>") +
            "</td><td style=\"vertical-align:top\"><table style=\"width:100%;border-collapse:collapse\">" +
            Row("Tổng tiền hàng:", "Tong_Tien_Hang") +
            Row("Chiết khấu:", "Chiet_Khau_Hoa_Don") +
            Row("Phụ thu:", "Phu_Thu") +
            Row("Phí giao hàng:", "Phi_Giao_Hang") +
            Row("Thuế GTGT:", "VAT") +
            "<tr><td colspan=\"2\" style=\"border-top:1px solid #000\"></td></tr>" +
            "<tr><td style=\"padding:3px 0;font-weight:bold;font-size:115%\">TỔNG CỘNG:</td>" +
            "<td style=\"padding:3px 0;text-align:right;font-weight:bold;font-size:115%\">{Tong_Cong}</td></tr>" +
            Row("Khách thanh toán:", "Khach_Thanh_Toan") +
            Row("Tiền thừa:", "Tien_Thua") +
            Row("Còn nợ:", "Con_Lai", bold: true) +
            "</table></td></tr></table>" +
            "<div style=\"margin-top:4px;font-style:italic\">Bằng chữ: {Tong_Cong_Bang_Chu}</div>";

        var sign =
            "<table style=\"width:100%;margin-top:" + (a5 ? "14px" : "28px") + ";text-align:center\"><tr>" +
            "<td style=\"width:50%;vertical-align:top\"><b>Khách hàng</b><div style=\"font-style:italic\">(Ký, ghi rõ họ tên)</div>" +
            "<div style=\"height:" + signGap + "\"></div></td>" +
            "<td style=\"width:50%;vertical-align:top\"><b>Người bán</b><div style=\"font-style:italic\">(Ký, ghi rõ họ tên)</div>" +
            "<div style=\"height:" + signGap + "\"></div><div>{Nguoi_Ban}</div></td>" +
            "</tr></table>" +
            "<div style=\"text-align:center;margin-top:6px;font-style:italic\">Cảm ơn quý khách!</div></div>";

        return head + items + totals + sign;
    }
}
