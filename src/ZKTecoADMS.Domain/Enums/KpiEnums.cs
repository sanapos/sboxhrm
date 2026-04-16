namespace ZKTecoADMS.Domain.Enums;

/// <summary>
/// Loại KPI
/// </summary>
public enum KpiType
{
    /// <summary>Số lượng (ví dụ: số sản phẩm bán được)</summary>
    Quantity = 0,
    /// <summary>Phần trăm (ví dụ: tỷ lệ hoàn thành)</summary>
    Percentage = 1,
    /// <summary>Tiền tệ (ví dụ: doanh thu)</summary>
    Currency = 2,
    /// <summary>Điểm số (ví dụ: đánh giá khách hàng)</summary>
    Score = 3,
    /// <summary>Có/Không (ví dụ: hoàn thành chứng chỉ)</summary>
    Boolean = 4
}

/// <summary>
/// Trạng thái kỳ đánh giá KPI
/// </summary>
public enum KpiPeriodStatus
{
    /// <summary>Đang mở - nhập liệu</summary>
    Open = 0,
    /// <summary>Đã khóa - tính lương</summary>
    Locked = 1,
    /// <summary>Đã tính lương xong</summary>
    Calculated = 2,
    /// <summary>Đã duyệt</summary>
    Approved = 3
}

/// <summary>
/// Tần suất đánh giá KPI
/// </summary>
public enum KpiFrequency
{
    Monthly = 0,
    Quarterly = 1,
    HalfYearly = 2,
    Yearly = 3
}
