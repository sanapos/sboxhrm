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
        PosPrintDocumentType.CashReceipt => "PHIẾU THU",
        PosPrintDocumentType.CashPayment => "PHIẾU CHI",
        _ => "CHỨNG TỪ",
    };

    public static string TemplateName(PosPrintPaperSize size, int variant = 1) =>
        size switch
        {
            PosPrintPaperSize.K58 => $"Khổ K58 - Mẫu {variant}",
            PosPrintPaperSize.K80 => $"Khổ K80 - Mẫu {variant}",
            PosPrintPaperSize.A5 => $"Khổ A5 - Mẫu {variant}",
            PosPrintPaperSize.A4 => $"Khổ A4 - Mẫu {variant}",
            _ => $"Mẫu {variant}",
        };

    public static string BuildHtml(PosPrintDocumentType docType, PosPrintPaperSize paperSize)
    {
        var title = DocumentTitle(docType);
        return paperSize is PosPrintPaperSize.K58 or PosPrintPaperSize.K80
            ? BuildThermalHtml(title, paperSize)
            : BuildSheetHtml(title, paperSize);
    }

    static string BuildThermalHtml(string title, PosPrintPaperSize size)
    {
        var width = size == PosPrintPaperSize.K58 ? "58mm" : "80mm";
        var fs = size == PosPrintPaperSize.K58 ? "10px" : "11px";
        return
            "<div style=\"width:" + width +
            ";max-width:100%;margin:0 auto;font-family:Arial,sans-serif;font-size:" + fs + ";color:#000\">" +
            "<div style=\"text-align:center\">" +
            "<div style=\"font-weight:bold;font-size:13px\">" + title + "</div>" +
            "<div style=\"font-weight:bold;margin-top:4px\">{Ten_Cua_Hang}</div>" +
            "<div>{Dia_Chi_Chi_Nhanh}</div>" +
            "<div>ĐT: {Dien_Thoai_Chi_Nhanh}</div>" +
            "</div>" +
            "<div style=\"margin:8px 0;border-top:1px dashed #999\"></div>" +
            "<div>Số HĐ: <b>{Ma_Don_Hang}</b></div>" +
            "<div>Ngày: {Ngay} {Gio}</div>" +
            "<div>KH: {Khach_Hang}</div>" +
            "<div>SDT: {SDT}</div>" +
            "<div style=\"margin:8px 0;border-top:1px dashed #999\"></div>" +
            "<!--BEGIN_ITEMS-->" +
            "<div style=\"margin-bottom:6px\">" +
            "<div><b>{Ten_Hang_Hoa}</b> <span style=\"color:#666\">({Ma_Hang})</span></div>" +
            "<div style=\"display:flex;justify-content:space-between\">" +
            "<span>{So_Luong} {Don_Vi_Tinh} x {Don_Gia}</span>" +
            "<span><b>{Thanh_Tien}</b></span>" +
            "</div></div><!--END_ITEMS-->" +
            "<div style=\"margin:8px 0;border-top:1px dashed #999\"></div>" +
            "<div style=\"text-align:right\">" +
            "<div>Tổng tiền hàng: <b>{Tong_Tien_Hang}</b></div>" +
            "<div>Chiết khấu: {Chiet_Khau_Hoa_Don}</div>" +
            "<div style=\"font-size:12px;font-weight:bold;margin-top:4px\">Tổng cộng: {Tong_Cong}</div>" +
            "<div>Đã thanh toán: {Khach_Thanh_Toan} ({Hinh_Thuc_Thanh_Toan})</div>" +
            "<div>Tiền thừa: {Tien_Thua}</div></div>" +
            "<div style=\"margin-top:6px;font-style:italic\">{Tong_Cong_Bang_Chu}</div>" +
            "<div style=\"margin-top:8px;text-align:center\">Cảm ơn quý khách!</div>" +
            "<div style=\"margin-top:4px;font-size:9px;color:#666\">{Ghi_Chu}</div></div>";
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
