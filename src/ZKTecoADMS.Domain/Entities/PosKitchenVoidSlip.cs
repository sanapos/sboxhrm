using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Phiếu hủy món đã báo chế biến — lưu để đối soát / chống gian lận.</summary>
public class PosKitchenVoidSlip : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }
    public virtual Store? Store { get; set; }

    public Guid? SaleOrderId { get; set; }
    [MaxLength(40)]
    public string? OrderNo { get; set; }

    public Guid? ResourceSessionId { get; set; }
    public Guid? ServiceResourceId { get; set; }
    [MaxLength(120)]
    public string? ResourceName { get; set; }

    public Guid? ProductId { get; set; }
    [Required, MaxLength(200)]
    public string ProductName { get; set; } = "";
    [MaxLength(40)]
    public string? UnitName { get; set; }
    public decimal Qty { get; set; }
    [MaxLength(300)]
    public string? LineNote { get; set; }

    /// <summary>Lý do hủy (Thao tác sai / Khách yêu cầu…).</summary>
    [MaxLength(80)]
    public string? Reason { get; set; }
    [MaxLength(500)]
    public string? DetailNote { get; set; }

    /// <summary>Hủy sau khi đã in / xin tạm tính — cần kiểm soát chặt.</summary>
    public bool AfterBillRequested { get; set; }

    public bool Printed { get; set; }
    public DateTime VoidedAt { get; set; } = DateTime.UtcNow;
    /// <summary>Bếp đã bấm Đồng ý / xong bàn — không hiện trên KDS nữa.</summary>
    public DateTime? KdsAckedAt { get; set; }
    [MaxLength(200)]
    public string? VoidedBy { get; set; }
    [MaxLength(120)]
    public string? DeviceName { get; set; }
}
