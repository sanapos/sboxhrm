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
        PosPrintDocumentType.KitchenLabel => "TEM BÁO BẾP",
        PosPrintDocumentType.CashReceipt => "PHIẾU THU",
        PosPrintDocumentType.CashPayment => "PHIẾU CHI",
        _ => "CHỨNG TỪ",
    };

    public static string TemplateName(PosPrintDocumentType type, PosPrintPaperSize size, int variant = 1)
    {
        var doc = type switch
        {
            PosPrintDocumentType.SaleInvoice => "Hóa đơn bán hàng",
            PosPrintDocumentType.SaleOrder => "Đặt hàng",
            PosPrintDocumentType.Delivery => "Giao hàng",
            PosPrintDocumentType.SaleReturn => "Trả hàng",
            PosPrintDocumentType.SaleExchange => "Đổi trả hàng",
            PosPrintDocumentType.PurchaseOrder => "Đặt hàng nhập",
            PosPrintDocumentType.PurchaseReceipt => "Nhập hàng",
            PosPrintDocumentType.PurchaseReturn => "Trả hàng nhập",
            PosPrintDocumentType.StockTransfer => "Chuyển hàng",
            PosPrintDocumentType.StockIssue => "Xuất kho",
            PosPrintDocumentType.KitchenSlip => "Báo chế biến",
            PosPrintDocumentType.KitchenVoid => "Hủy bếp",
            PosPrintDocumentType.BarcodeLabel => "Tem sản phẩm",
            PosPrintDocumentType.KitchenLabel => "Tem ly / tem bếp",
            PosPrintDocumentType.CashReceipt => "Phiếu thu",
            PosPrintDocumentType.CashPayment => "Phiếu chi",
            _ => "Chứng từ",
        };
        var paper = size switch
        {
            PosPrintPaperSize.K58 => "K57/K58",
            PosPrintPaperSize.K80 => "K80",
            PosPrintPaperSize.A5 => "A5",
            PosPrintPaperSize.A4 => "A4",
            PosPrintPaperSize.Label50x30 => "50×30",
            PosPrintPaperSize.Label40x30 => "40×30",
            _ => size.ToString(),
        };
        return $"{doc} {variant} ({paper})";
    }

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
        if (docType is PosPrintDocumentType.BarcodeLabel or PosPrintDocumentType.KitchenLabel)
        {
            return new[]
            {
                new CatalogSpec($"{DocumentTitle(docType)} · 50×30", PosPrintPaperSize.Label50x30, 0, true),
                new CatalogSpec($"{DocumentTitle(docType)} · 40×30", PosPrintPaperSize.Label40x30, 1, false),
            };
        }

        if (docType is PosPrintDocumentType.KitchenSlip or PosPrintDocumentType.KitchenVoid)
        {
            return new[]
            {
                new CatalogSpec($"{DocumentTitle(docType)} · K80 chuẩn", PosPrintPaperSize.K80, 0, true),
                new CatalogSpec($"{DocumentTitle(docType)} · K58", PosPrintPaperSize.K58, 1, false),
            };
        }

        // Hóa đơn / xuất kho / phiếu khác: 3 mẫu (K80 chuẩn, K80 A4/A5 sheet, K58)
        return new[]
        {
            new CatalogSpec($"{DocumentTitle(docType)} · K80 chuẩn", PosPrintPaperSize.K80, 0, true),
            new CatalogSpec($"{DocumentTitle(docType)} · K58", PosPrintPaperSize.K58, 1, false),
            new CatalogSpec($"{DocumentTitle(docType)} · A5", PosPrintPaperSize.A5, 2, false),
        };
    }

    /// <summary>Khổ seed theo loại chứng từ — tem không dùng K58/K80.</summary>
    public static IReadOnlyList<PosPrintPaperSize> SizesForDocument(PosPrintDocumentType docType)
    {
        return CatalogSpecs(docType).Select(s => s.PaperSize).Distinct().ToList();
    }

    public static string BuildHtml(PosPrintDocumentType docType, PosPrintPaperSize paperSize)
    {
        var title = DocumentTitle(docType);
        if (docType == PosPrintDocumentType.BarcodeLabel)
            return BuildProductLabelHtml(paperSize);
        if (docType == PosPrintDocumentType.KitchenLabel)
            return BuildKitchenLabelHtml(paperSize);
        if (docType is PosPrintDocumentType.KitchenSlip or PosPrintDocumentType.KitchenVoid)
            return BuildKitchenSlipHtml(title, paperSize, isCancel: docType == PosPrintDocumentType.KitchenVoid);
        return paperSize is PosPrintPaperSize.K58 or PosPrintPaperSize.K80
            ? BuildThermalV2(docType, paperSize)
            : BuildSheetHtml(title, paperSize);
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

    static string BuildKitchenSlipHtml(string title, PosPrintPaperSize size, bool isCancel)
    {
        var width = size == PosPrintPaperSize.K58 ? "58mm" : "80mm";
        var fs = size == PosPrintPaperSize.K58 ? "12px" : "13px";
        var titleFs = size == PosPrintPaperSize.K58 ? "16px" : "18px";
        var badge = isCancel ? "*** PHIẾU HỦY ***" : "*** BÁO CHẾ BIẾN ***";
        return
            "<div style=\"width:" + width +
            ";max-width:100%;margin:0 auto;font-family:Arial,sans-serif;font-size:" + fs + ";color:#000\">" +
            "<div style=\"text-align:center;font-weight:bold;font-size:" + titleFs + "\">{Ten_Ban}</div>" +
            "<div style=\"text-align:center;font-weight:bold;margin:4px 0\">" + badge + "</div>" +
            "<div style=\"margin:6px 0;border-top:1px dashed #999\"></div>" +
            "<div><b>Mã HĐ:</b> {Ma_Don_Hang}</div>" +
            "<div><b>NV:</b> {Nguoi_Ban}</div>" +
            "<div><b>Ngày:</b> {Ngay} {Gio}</div>" +
            "<div style=\"margin:6px 0;border-top:1px dashed #999\"></div>" +
            "<!--BEGIN_ITEMS-->" +
            "<div style=\"margin-bottom:8px\">" +
            "<div style=\"font-weight:bold;font-size:14px\">{Ten_Hang_Hoa}</div>" +
            "<div>SL: <b>{So_Luong}</b> {Don_Vi_Tinh}</div>" +
            "<div style=\"font-style:italic\">{Ghi_Chu}</div>" +
            "</div><!--END_ITEMS-->" +
            "<div style=\"margin:6px 0;border-top:1px dashed #999\"></div>" +
            "<div style=\"text-align:center;font-weight:bold\">— Hết —</div>" +
            "</div>";
    }

    /// <summary>Mẫu nhiệt V2 gọn — ít dòng, không QR mặc định.</summary>
    static string BuildThermalV2(PosPrintDocumentType docType, PosPrintPaperSize size)
    {
        var k58 = size == PosPrintPaperSize.K58;
        var paper = k58 ? "K58" : "K80";
        var profile = k58 ? "sunmi_k58" : "sunmi_k80";
        var title = k58 ? 28 : 32;
        var body = k58 ? 20 : 22;
        var small = k58 ? 16 : 18;
        var total = k58 ? 24 : 28;
        var isReturn = docType == PosPrintDocumentType.SaleReturn;
        var name = TemplateName(docType, size);
        var totals = isReturn
            ? "{\"type\":\"totals\",\"fields\":[\"Tong_Cong\"],\"fieldLabels\":{\"Tong_Cong\":\"HOAN TIEN\"},\"style\":{\"fontSize\":" + body + ",\"bold\":true,\"align\":\"left\"},\"rightStyle\":{\"fontSize\":" + total + ",\"bold\":true,\"align\":\"right\"}}"
            : "{\"type\":\"totals\",\"fields\":[\"Tong_Tien_Hang\",\"Chiet_Khau_Hoa_Don\",\"Tong_Cong\",\"Khach_Thanh_Toan\"],\"fieldLabels\":{\"Tong_Tien_Hang\":\"Tien hang\",\"Chiet_Khau_Hoa_Don\":\"CK\",\"Tong_Cong\":\"TONG\",\"Khach_Thanh_Toan\":\"Da thu\"},\"style\":{\"fontSize\":" + body + ",\"bold\":true,\"align\":\"left\"},\"rightStyle\":{\"fontSize\":" + total + ",\"bold\":true,\"align\":\"right\"}}";
        var footer = isReturn ? "Phieu tra hang" : "Cam on quy khach!";
        return
            "<!--POS_TEMPLATE_V2-->\n" +
            "{\"version\":1,\"paperSize\":\"" + paper + "\",\"printerProfile\":\"" + profile +
            "\",\"documentType\":\"" + docType + "\",\"name\":\"" + name +
            "\",\"blocks\":[" +
            "{\"type\":\"field\",\"field\":\"Ten_Cua_Hang\",\"style\":{\"fontSize\":" + title + ",\"bold\":true,\"align\":\"center\"}}," +
            "{\"type\":\"field\",\"field\":\"Dia_Chi_Chi_Nhanh\",\"style\":{\"fontSize\":" + small + ",\"bold\":false,\"align\":\"center\"}}," +
            "{\"type\":\"divider\",\"style\":{\"fontSize\":24,\"bold\":false,\"align\":\"left\"},\"divider\":\"dash\"}," +
            "{\"type\":\"field\",\"field\":\"Tieu_De_In\",\"style\":{\"fontSize\":" + (body + 2) + ",\"bold\":true,\"align\":\"center\"}}," +
            "{\"type\":\"pair\",\"leftField\":\"Ma_Don_Hang\",\"rightField\":\"Ngay\",\"fieldLabels\":{\"Ma_Don_Hang\":\"HD:\",\"Ngay\":\"\"},\"style\":{\"fontSize\":" + body + ",\"bold\":true,\"align\":\"left\"}}," +
            "{\"type\":\"field\",\"field\":\"Ten_Ban\",\"style\":{\"fontSize\":" + body + ",\"bold\":true,\"align\":\"left\"}}," +
            "{\"type\":\"field\",\"field\":\"Khach_Hang\",\"label\":\"KH:\",\"style\":{\"fontSize\":" + small + ",\"bold\":false,\"align\":\"left\"}}," +
            "{\"type\":\"divider\",\"style\":{\"fontSize\":24,\"bold\":false,\"align\":\"left\"},\"divider\":\"dash\"}," +
            "{\"type\":\"lineItems\",\"showColumnHeader\":false,\"style\":{\"fontSize\":" + body + ",\"bold\":true,\"align\":\"left\"}}," +
            "{\"type\":\"divider\",\"style\":{\"fontSize\":24,\"bold\":false,\"align\":\"left\"},\"divider\":\"dash\"}," +
            totals + "," +
            "{\"type\":\"text\",\"text\":\"" + footer + "\",\"style\":{\"fontSize\":" + small + ",\"bold\":true,\"align\":\"center\"}}" +
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
            "<div style=\"display:flex;justify-content:space-between\"><span><b>Số HĐ:</b> {Ma_Don_Hang}</span><span><b>{Ngay}</b></span></div>" +
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

    static string BuildSheetHtml(string title, PosPrintPaperSize size)
    {
        var pad = size == PosPrintPaperSize.A5 ? "12px" : "20px";
        return
            "<div style=\"font-family:Arial,sans-serif;font-size:11px;color:#000;padding:" + pad + "\">" +
            "<table style=\"width:100%;border-collapse:collapse\"><tr>" +
            "<td style=\"width:60%;vertical-align:top\">" +
            "<div style=\"font-weight:bold;font-size:16px\">{Ten_Cua_Hang}</div>" +
            "<div>{Dia_Chi_Chi_Nhanh}</div><div>ĐT: {Dien_Thoai_Chi_Nhanh}</div></td>" +
            "<td style=\"text-align:right;vertical-align:top\">" +
            "<div style=\"font-weight:bold;font-size:18px\">" + title + "</div>" +
            "<div>Số: <b>{Ma_Don_Hang}</b></div><div>Ngày: {Ngay} {Gio}</div></td></tr></table>" +
            "<div style=\"margin:12px 0\"><b>Khách hàng:</b> {Khach_Hang} &nbsp;|&nbsp; <b>SDT:</b> {SDT}<br/>" +
            "<b>Địa chỉ:</b> {Dia_Chi_Khach_Hang}</div>" +
            "<table style=\"width:100%;border-collapse:collapse;border:1px solid #ccc\">" +
            "<thead><tr style=\"background:#f3f4f6\">" +
            "<th style=\"border:1px solid #ccc;padding:6px\">STT</th>" +
            "<th style=\"border:1px solid #ccc;padding:6px\">Mã hàng</th>" +
            "<th style=\"border:1px solid #ccc;padding:6px\">Tên hàng</th>" +
            "<th style=\"border:1px solid #ccc;padding:6px;text-align:right\">Đơn giá</th>" +
            "<th style=\"border:1px solid #ccc;padding:6px;text-align:center\">SL</th>" +
            "<th style=\"border:1px solid #ccc;padding:6px;text-align:right\">CK</th>" +
            "<th style=\"border:1px solid #ccc;padding:6px;text-align:right\">Thành tiền</th>" +
            "</tr></thead><tbody><!--BEGIN_ITEMS-->" +
            "<tr><td style=\"border:1px solid #ccc;padding:5px;text-align:center\">{STT}</td>" +
            "<td style=\"border:1px solid #ccc;padding:5px\">{Ma_Hang}</td>" +
            "<td style=\"border:1px solid #ccc;padding:5px\">{Ten_Hang_Hoa}</td>" +
            "<td style=\"border:1px solid #ccc;padding:5px;text-align:right\">{Don_Gia}</td>" +
            "<td style=\"border:1px solid #ccc;padding:5px;text-align:center\">{So_Luong}</td>" +
            "<td style=\"border:1px solid #ccc;padding:5px;text-align:right\">{Chiet_Khau}</td>" +
            "<td style=\"border:1px solid #ccc;padding:5px;text-align:right\">{Thanh_Tien}</td></tr>" +
            "<!--END_ITEMS--></tbody></table>" +
            "<table style=\"width:100%;margin-top:12px\"><tr><td style=\"width:55%\"></td>" +
            "<td style=\"width:45%;vertical-align:top\"><table style=\"width:100%;font-size:12px\">" +
            "<tr><td>Tổng tiền hàng:</td><td style=\"text-align:right\"><b>{Tong_Tien_Hang}</b></td></tr>" +
            "<tr><td>Chiết khấu:</td><td style=\"text-align:right\">{Chiet_Khau_Hoa_Don}</td></tr>" +
            "<tr><td style=\"font-weight:bold\">Tổng cộng:</td><td style=\"text-align:right;font-weight:bold\">{Tong_Cong}</td></tr>" +
            "<tr><td>Đã thanh toán:</td><td style=\"text-align:right\">{Khach_Thanh_Toan}</td></tr>" +
            "<tr><td>Còn lại:</td><td style=\"text-align:right\">{Con_Lai}</td></tr></table>" +
            "<div style=\"margin-top:8px;font-style:italic\">{Tong_Cong_Bang_Chu}</div></td></tr></table>" +
            "<div style=\"margin-top:16px\"><b>Ghi chú:</b> {Ghi_Chu}</div>" +
            "<table style=\"width:100%;margin-top:32px;text-align:center\"><tr>" +
            "<td style=\"width:50%\"><b>Khách hàng</b><br/><br/><br/>(Ký, họ tên)</td>" +
            "<td style=\"width:50%\"><b>Người bán</b><br/><br/><br/>{Nguoi_Ban}</td>" +
            "</tr></table></div>";
    }
}
