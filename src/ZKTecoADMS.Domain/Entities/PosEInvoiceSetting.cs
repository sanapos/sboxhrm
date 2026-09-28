using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Cấu hình hóa đơn điện tử theo cửa hàng (Viettel SInvoice, Easy Invoice, MISA meInvoice, VNPT Invoice).</summary>
public class PosEInvoiceSetting : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public bool Enabled { get; set; }

    /// <summary>Viettel | Easy | Misa | Vnpt</summary>
    [Required]
    [MaxLength(20)]
    public string Provider { get; set; } = "Viettel";

    [MaxLength(300)]
    public string ApiBaseUrl { get; set; } = "https://api-vinvoice.viettel.vn";

    [MaxLength(100)]
    public string Username { get; set; } = string.Empty;

    [MaxLength(200)]
    public string Password { get; set; } = string.Empty;

    [MaxLength(20)]
    public string SupplierTaxCode { get; set; } = string.Empty;

    /// <summary>Ký hiệu mẫu, ví dụ 1/001 (TT78).</summary>
    [MaxLength(20)]
    public string TemplateCode { get; set; } = "1/001";

    /// <summary>Ký hiệu hóa đơn, ví dụ C24AAA.</summary>
    [MaxLength(25)]
    public string InvoiceSeries { get; set; } = string.Empty;

    /// <summary>Loại HĐ TT78: 1 = GTGT, 2 = bán hàng, …</summary>
    [MaxLength(10)]
    public string InvoiceType { get; set; } = "1";

    /// <summary>Hiện chip «Xuất HĐĐT» lúc thanh toán.</summary>
    public bool AskAtCheckout { get; set; } = true;

    /// <summary>Mặc định bật chip khi AskAtCheckout; nếu Ask=false thì xuất tự động khi DefaultIssue.</summary>
    public bool DefaultIssueAtCheckout { get; set; }

    /// <summary>included | added | none — cách quy đổi VAT gửi Viettel.</summary>
    [MaxLength(20)]
    public string TaxMode { get; set; } = "included";

    public decimal DefaultTaxPercent { get; set; } = 10;

    /// <summary>MISA meInvoice: AppID do MISA cấp cho đơn vị tích hợp.</summary>
    [MaxLength(200)]
    public string AppId { get; set; } = string.Empty;

    /// <summary>VNPT: tài khoản web service (Account); MISA/Viettel/Easy không dùng.</summary>
    [MaxLength(100)]
    public string ServiceAccount { get; set; } = string.Empty;

    /// <summary>VNPT: mật khẩu web service (ACpass).</summary>
    [MaxLength(200)]
    public string ServicePassword { get; set; } = string.Empty;

    /// <summary>MISA: 2 = ký HSM, 5 = HĐ máy tính tiền (không ký).</summary>
    public int SignType { get; set; } = 2;

    /// <summary>Link trang quản lý HĐĐT của hãng (để trống = mặc định theo nhà cung cấp).</summary>
    [MaxLength(300)]
    public string PortalUrl { get; set; } = string.Empty;

    /// <summary>In khối HĐĐT (ký hiệu, số, mã CQT, mã tra cứu, QR tra cứu) trên bill bán hàng.</summary>
    public bool PrintQrOnReceipt { get; set; } = true;
}
