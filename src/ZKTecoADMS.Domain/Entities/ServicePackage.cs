using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Gói dịch vụ - định nghĩa các chức năng được phép sử dụng
/// </summary>
public class ServicePackage : Entity<Guid>
{
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public bool IsActive { get; set; } = true;

    /// <summary>
    /// Hiện trên màn đăng ký công khai. False = gói nội bộ, Super Admin gán tay cho cửa hàng.
    /// </summary>
    public bool IsPublic { get; set; } = true;

    /// <summary>
    /// Số ngày mặc định khi kích hoạt gói (0 = không giới hạn)
    /// </summary>
    public int DefaultDurationDays { get; set; } = 30;

    public int MaxUsers { get; set; } = 10;

    /// <summary>Số máy chấm công ZKTeco được nhận (0 = không giới hạn).</summary>
    public int MaxDevices { get; set; } = 2;

    /// <summary>Số thiết bị đăng nhập (web/app/POS) — 0 = không giới hạn.</summary>
    public int MaxAccessDevices { get; set; } = 0;

    public bool AllowWeb { get; set; } = true;
    public bool AllowMobile { get; set; } = true;

    /// <summary>Số chi nhánh (0 = không giới hạn).</summary>
    public int MaxBranches { get; set; } = 0;

    public bool AllowFcm { get; set; } = true;

    /// <summary>JSON array mã nhóm FCM; rỗng = mọi nhóm (khi AllowFcm).</summary>
    public string AllowedFcmCategories { get; set; } = "[]";

    /// <summary>
    /// Danh sách module được phép, lưu dạng JSON array: ["Employee","Attendance","Salary",...]
    /// </summary>
    public string AllowedModules { get; set; } = "[]";

    /// <summary>
    /// Xóa dữ liệu cũ theo gói. JSON: runHour, attendanceMonths, saleOrderMonths.
    /// Tháng = 0 nghĩa là không xóa loại đó.
    /// </summary>
    public string DataRetentionJson { get; set; } = "{}";

    // ─── Thông tin kinh doanh (v2) ───

    /// <summary>pos / hrm / both</summary>
    public string ProductLine { get; set; } = "both";

    /// <summary>Giá theo tháng (VNĐ). null = liên hệ</summary>
    public decimal? MonthlyPrice { get; set; }

    /// <summary>Giá theo năm (VNĐ). null = không bán theo năm</summary>
    public decimal? YearlyPrice { get; set; }

    /// <summary>Số ngày dùng thử khi đăng ký gói này (0 = không dùng thử)</summary>
    public int TrialDays { get; set; }

    /// <summary>Thứ tự hiển thị trên bảng giá</summary>
    public int SortOrder { get; set; }

    /// <summary>Đánh dấu «Phổ biến» trên bảng giá</summary>
    public bool IsFeatured { get; set; }

    /// <summary>Nhãn ngắn (VD: «Tiết kiệm 20%»)</summary>
    public string? Badge { get; set; }

    /// <summary>Các dòng điểm nổi bật hiển thị trên bảng giá (mỗi dòng một ý)</summary>
    public string? Highlights { get; set; }

    /// <summary>
    /// Stores đang sử dụng gói này
    /// </summary>
    public virtual ICollection<Store> Stores { get; set; } = [];
}
