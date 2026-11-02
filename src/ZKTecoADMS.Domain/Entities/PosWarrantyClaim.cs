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

    /// <summary>Số phiếu tiếp nhận in cho khách, vd BH0211260001.</summary>
    [MaxLength(30)]
    public string? ClaimNo { get; set; }

    /// <summary>Người mang máy đến / liên hệ khi xong (có thể khác người mua).</summary>
    [MaxLength(150)]
    public string? ContactName { get; set; }

    [MaxLength(30)]
    public string? ContactPhone { get; set; }

    /// <summary>Tình trạng máy lúc nhận: trầy, móp, màn hình…</summary>
    [MaxLength(500)]
    public string? DeviceCondition { get; set; }

    /// <summary>Phụ kiện khách gửi kèm: sạc, hộp, ốp…</summary>
    [MaxLength(500)]
    public string? Accessories { get; set; }

    public DateTime? ExpectedReturnDate { get; set; }

    /// <summary>Người phụ trách / kỹ thuật (tên tự do).</summary>
    [MaxLength(150)]
    public string? AssignedTo { get; set; }

    /// <summary>Phí sửa (máy hết bảo hành hoặc lỗi do khách).</summary>
    public decimal Fee { get; set; }

    public bool FeePaid { get; set; }

    /// <summary>Phiếu thu đã ghi cho phí sửa.</summary>
    public Guid? CashTransactionId { get; set; }

    /// <summary>Ngày trả máy cho khách.</summary>
    public DateTime? DeliveredDate { get; set; }
}
