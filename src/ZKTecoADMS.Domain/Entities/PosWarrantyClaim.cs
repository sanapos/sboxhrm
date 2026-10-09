using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Một lần tiếp nhận / xử lý bảo hành của một máy (theo seri): sửa chữa, đổi máy, ghi chú.</summary>
public class PosWarrantyClaim : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    /// <summary>Dòng đăng ký bảo hành (máy) được tiếp nhận.</summary>
    [Required]
    public Guid RegistrationId { get; set; }
    public virtual PosProductWarrantyRegistration? Registration { get; set; }

    public PosWarrantyClaimType ClaimType { get; set; } = PosWarrantyClaimType.Repair;
    public PosWarrantyClaimStatus Status { get; set; } = PosWarrantyClaimStatus.Received;

    public DateTime ReceivedDate { get; set; }
    public DateTime? ResolvedDate { get; set; }

    /// <summary>Máy còn trong hạn bảo hành lúc tiếp nhận? (false = sửa tính phí).</summary>
    public bool InWarranty { get; set; } = true;

    [MaxLength(1000)]
    public string? Description { get; set; }

    [MaxLength(1000)]
    public string? Resolution { get; set; }

    /// <summary>Với đổi máy: dòng đăng ký của máy mới.</summary>
    public Guid? NewRegistrationId { get; set; }
}
