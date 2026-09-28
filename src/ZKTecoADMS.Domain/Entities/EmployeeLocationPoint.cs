using System.ComponentModel.DataAnnotations;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Lịch sử vị trí GPS của nhân viên trong ca làm việc — mỗi lần app gửi vị trí là 1 điểm.
/// Dùng để vẽ lộ trình di chuyển trong ca trên Bản đồ nhân sự (EmployeeLiveLocation chỉ giữ điểm mới nhất).
/// </summary>
public class EmployeeLocationPoint
{
    [Key]
    public Guid Id { get; set; }

    public Guid StoreId { get; set; }

    /// <summary>Tài khoản đăng nhập của nhân viên.</summary>
    public Guid UserId { get; set; }

    /// <summary>Hồ sơ nhân viên (nếu có).</summary>
    public Guid? EmployeeId { get; set; }

    public double Latitude { get; set; }
    public double Longitude { get; set; }

    /// <summary>Sai số GPS (mét).</summary>
    public double? Accuracy { get; set; }

    /// <summary>Tốc độ thiết bị báo (m/s), nếu có.</summary>
    public double? Speed { get; set; }

    /// <summary>% pin thiết bị, nếu có.</summary>
    public int? Battery { get; set; }

    /// <summary>Thời điểm ghi nhận (UTC).</summary>
    public DateTime RecordedAt { get; set; }

    /// <summary>Ca làm việc đang diễn ra lúc ghi (nếu có).</summary>
    public Guid? ShiftId { get; set; }
}
