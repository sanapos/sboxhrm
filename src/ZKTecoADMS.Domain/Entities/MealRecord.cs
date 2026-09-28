using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Bản ghi chấm cơm - tạo khi nhân viên quẹt thẻ tại máy chấm cơm
/// </summary>
public class MealRecord : Entity<Guid>
{
    public Guid? AttendanceId { get; set; }
    public virtual Attendance? Attendance { get; set; }

    [Required]
    public Guid EmployeeUserId { get; set; }
    public virtual ApplicationUser EmployeeUser { get; set; } = null!;

    [MaxLength(20)]
    public string? PIN { get; set; }

    [Required]
    public Guid MealSessionId { get; set; }
    public virtual MealSession MealSession { get; set; } = null!;

    [Required]
    public DateTime MealTime { get; set; }

    [Required]
    public DateTime Date { get; set; }

    public Guid? ShiftId { get; set; }

    public Guid? DeviceId { get; set; }
    public virtual Device? Device { get; set; }

    /// <summary>Số phiếu ăn trong ngày (theo cửa hàng), in trên phiếu: 1, 2, 3…</summary>
    public int TicketNo { get; set; }

    /// <summary>Giá suất ăn chốt tại thời điểm chấm (null = bản ghi cũ → lấy giá buổi ăn hiện tại).</summary>
    public decimal? Price { get; set; }

    /// <summary>Nguồn: 0 = máy chấm công căn tin, 1 = QR trên điện thoại, 2 = quản lý nhập tay.</summary>
    public int Source { get; set; }

    /// <summary>Lần đầu trạm in căn tin in phiếu ăn (null = chưa in).</summary>
    public DateTime? PrintedAt { get; set; }

    public int PrintCount { get; set; }

    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}
