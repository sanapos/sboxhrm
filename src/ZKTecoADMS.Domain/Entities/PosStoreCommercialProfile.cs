using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Thông tin pháp lý cửa hàng in trên báo giá / HĐ A4 (công ty bên shop).</summary>
public class PosStoreCommercialProfile : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    [MaxLength(300)]
    public string? CompanyName { get; set; }

    [MaxLength(30)]
    public string? TaxCode { get; set; }

    [MaxLength(500)]
    public string? Address { get; set; }

    [MaxLength(50)]
    public string? Phone { get; set; }

    [MaxLength(200)]
    public string? Email { get; set; }

    [MaxLength(50)]
    public string? BankAccountNumber { get; set; }

    [MaxLength(200)]
    public string? BankName { get; set; }

    [MaxLength(200)]
    public string? BankAccountHolder { get; set; }

    [MaxLength(200)]
    public string? LegalRepresentative { get; set; }

    [MaxLength(100)]
    public string? LegalTitle { get; set; }

    /// <summary>PNG con dấu (base64, không kèm tiền tố data-url). In treo lên chữ ký báo giá.</summary>
    public string? StampPngBase64 { get; set; }

    /// <summary>Logo công ty (base64, không kèm tiền tố data-url). In ở đầu báo giá.</summary>
    public string? LogoPngBase64 { get; set; }

    /// <summary>Điều khoản mặc định in trên báo giá khi phiếu không ghi riêng.</summary>
    public string? DefaultTerms { get; set; }

    /// <summary>Chính sách bảo hành in trên báo giá.</summary>
    public string? WarrantyPolicy { get; set; }
}
