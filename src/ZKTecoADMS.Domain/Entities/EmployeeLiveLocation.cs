using System.ComponentModel.DataAnnotations;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Vị trí GPS hiện tại của nhân viên (cập nhật liên tục khi mở app).
/// Mỗi nhân viên chỉ có 1 bản ghi, cập nhật liên tục (upsert).
/// </summary>
public class EmployeeLiveLocation
{
    [Key]
    public Guid Id { get; set; }

    [Required]
    public Guid StoreId { get; set; }

    [Required]
    [MaxLength(100)]
    public string EmployeeId { get; set; } = string.Empty;

    public double Latitude { get; set; }

    public double Longitude { get; set; }

    public double? Accuracy { get; set; }

    public DateTime UpdatedAt { get; set; }
}
