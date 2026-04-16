namespace ZKTecoADMS.Domain.Enums;

/// <summary>
/// Trạng thái tài sản
/// </summary>
public enum AssetStatus
{
    /// <summary>Còn tốt, đang sử dụng</summary>
    Active = 0,
    /// <summary>Đang bảo trì/sửa chữa</summary>
    InMaintenance = 1,
    /// <summary>Hỏng</summary>
    Broken = 2,
    /// <summary>Đã thanh lý</summary>
    Disposed = 3,
    /// <summary>Đã mất</summary>
    Lost = 4,
    /// <summary>Trong kho (chưa cấp)</summary>
    InStock = 5
}

/// <summary>
/// Loại chuyển giao tài sản
/// </summary>
public enum AssetTransferType
{
    /// <summary>Cấp mới cho nhân viên</summary>
    Assignment = 0,
    /// <summary>Chuyển giao giữa nhân viên</summary>
    Transfer = 1,
    /// <summary>Thu hồi về kho</summary>
    Return = 2,
    /// <summary>Bảo trì</summary>
    Maintenance = 3,
    /// <summary>Thanh lý</summary>
    Disposal = 4
}

/// <summary>
/// Tình trạng tài sản khi kiểm kê
/// </summary>
public enum InventoryCondition
{
    /// <summary>Tốt</summary>
    Good = 0,
    /// <summary>Bình thường</summary>
    Fair = 1,
    /// <summary>Kém</summary>
    Poor = 2,
    /// <summary>Hỏng</summary>
    Damaged = 3,
    /// <summary>Không tìm thấy</summary>
    NotFound = 4
}

/// <summary>
/// Loại tài sản
/// </summary>
public enum AssetType
{
    /// <summary>Thiết bị điện tử</summary>
    Electronics = 0,
    /// <summary>Nội thất</summary>
    Furniture = 1,
    /// <summary>Phương tiện</summary>
    Vehicle = 2,
    /// <summary>Công cụ dụng cụ</summary>
    Tool = 3,
    /// <summary>Máy móc</summary>
    Machinery = 4,
    /// <summary>Phần mềm</summary>
    Software = 5,
    /// <summary>Khác</summary>
    Other = 6
}
