using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>Phiên kiểm kho theo mã: quét seri / thẻ RFID rồi đối chiếu với sổ seri.</summary>
public class PosSerialCount : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    [MaxLength(30)]
    public string CountNo { get; set; } = string.Empty;

    [Required]
    [MaxLength(200)]
    public string Name { get; set; } = string.Empty;

    /// <summary>Chi nhánh kiểm (null = trụ sở / không dùng chi nhánh).</summary>
    public Guid? BranchId { get; set; }

    /// <summary>Chỉ kiểm một mặt hàng (null = mọi hàng quản lý theo seri).</summary>
    public Guid? ProductId { get; set; }

    /// <summary>Barcode | RFID | Manual.</summary>
    [MaxLength(20)]
    public string Source { get; set; } = "Barcode";

    public PosSerialCountStatus Status { get; set; } = PosSerialCountStatus.InProgress;

    public DateTime StartedAt { get; set; }
    public DateTime? CompletedAt { get; set; }

    [MaxLength(500)]
    public string? Note { get; set; }

    /// <summary>Chốt khi hoàn thành.</summary>
    public int ExpectedQty { get; set; }
    public int MatchedQty { get; set; }
    public int MissingQty { get; set; }
    public int UnknownQty { get; set; }
}

/// <summary>Một mã đã quét trong phiên kiểm.</summary>
public class PosSerialCountItem : AuditableEntity<Guid>
{
    [Required]
    public Guid StoreId { get; set; }

    [Required]
    public Guid CountId { get; set; }

    [Required]
    [MaxLength(100)]
    public string Code { get; set; } = string.Empty;

    public Guid? SerialId { get; set; }
    public Guid? ProductId { get; set; }

    public PosSerialScanResult Result { get; set; }
    public DateTime ScannedAt { get; set; }

    [MaxLength(100)]
    public string? DeviceName { get; set; }
}
