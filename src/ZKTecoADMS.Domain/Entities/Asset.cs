using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Danh mục tài sản
/// </summary>
public class AssetCategory : AuditableEntity<Guid>
{
    /// <summary>Mã danh mục</summary>
    public string CategoryCode { get; set; } = string.Empty;
    
    /// <summary>Tên danh mục</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>Mô tả</summary>
    public string? Description { get; set; }
    
    /// <summary>Danh mục cha (nếu có)</summary>
    public Guid? ParentCategoryId { get; set; }
    public AssetCategory? ParentCategory { get; set; }
    
    /// <summary>Danh mục con</summary>
    public ICollection<AssetCategory> SubCategories { get; set; } = new List<AssetCategory>();
    
    /// <summary>Tài sản thuộc danh mục</summary>
    public ICollection<Asset> Assets { get; set; } = new List<Asset>();
    
    /// <summary>Store</summary>
    public Guid StoreId { get; set; }
    public Store? Store { get; set; }
}

/// <summary>
/// Tài sản
/// </summary>
public class Asset : AuditableEntity<Guid>
{
    /// <summary>Mã tài sản (tự động tạo: TS-YYYYMMDD-XXXX)</summary>
    public string AssetCode { get; set; } = string.Empty;
    
    /// <summary>Mã QR (mặc định = AssetCode, có thể tùy chỉnh)</summary>
    public string? QrCode { get; set; }
    
    /// <summary>Tên tài sản</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>Mô tả chi tiết</summary>
    public string? Description { get; set; }
    
    /// <summary>Số serial</summary>
    public string? SerialNumber { get; set; }
    
    /// <summary>Model/Mẫu mã</summary>
    public string? Model { get; set; }
    
    /// <summary>Thương hiệu/Nhà sản xuất</summary>
    public string? Brand { get; set; }
    
    /// <summary>Kích thước/Size</summary>
    public string? Size { get; set; }
    
    /// <summary>Màu sắc</summary>
    public string? Color { get; set; }
    
    /// <summary>Loại tài sản</summary>
    public AssetType AssetType { get; set; } = AssetType.Electronics;
    
    /// <summary>Danh mục</summary>
    public Guid? CategoryId { get; set; }
    public AssetCategory? Category { get; set; }
    
    /// <summary>Trạng thái</summary>
    public AssetStatus Status { get; set; } = AssetStatus.InStock;
    
    /// <summary>Số lượng</summary>
    public int Quantity { get; set; } = 1;
    
    /// <summary>Đơn vị tính</summary>
    public string Unit { get; set; } = "Cái";
    
    /// <summary>Giá nhập</summary>
    public decimal PurchasePrice { get; set; }
    
    /// <summary>Đơn vị tiền tệ</summary>
    public string Currency { get; set; } = "VND";
    
    /// <summary>Ngày mua</summary>
    public DateTime? PurchaseDate { get; set; }
    
    /// <summary>Nhà cung cấp</summary>
    public string? Supplier { get; set; }
    
    /// <summary>Số hóa đơn</summary>
    public string? InvoiceNumber { get; set; }
    
    /// <summary>Thời hạn bảo hành (tháng)</summary>
    public int? WarrantyMonths { get; set; }
    
    /// <summary>Ngày hết bảo hành</summary>
    public DateTime? WarrantyExpiry { get; set; }
    
    /// <summary>Vị trí/Phòng ban</summary>
    public string? Location { get; set; }
    
    /// <summary>Ghi chú</summary>
    public string? Notes { get; set; }
    
    /// <summary>Giá trị khấu hao hàng năm (%)</summary>
    public decimal? DepreciationRate { get; set; }
    
    /// <summary>Giá trị hiện tại (sau khấu hao)</summary>
    public decimal? CurrentValue { get; set; }
    
    /// <summary>Người đang giữ (nếu đã cấp)</summary>
    public Guid? CurrentAssigneeId { get; set; }
    public ApplicationUser? CurrentAssignee { get; set; }
    
    /// <summary>Ngày cấp cho người hiện tại</summary>
    public DateTime? AssignedDate { get; set; }
    
    /// <summary>Store</summary>
    public Guid StoreId { get; set; }
    public Store? Store { get; set; }
    
    // Navigation properties
    public ICollection<AssetImage> Images { get; set; } = new List<AssetImage>();
    public ICollection<AssetTransfer> Transfers { get; set; } = new List<AssetTransfer>();
    public ICollection<AssetInventoryItem> InventoryItems { get; set; } = new List<AssetInventoryItem>();
    
    // Computed properties
    public string? CurrentAssigneeName => CurrentAssignee?.FullName;
    public string? CategoryName => Category?.Name;
    public bool IsWarrantyExpired => WarrantyExpiry.HasValue && WarrantyExpiry.Value < DateTime.UtcNow;
    public int DaysUntilWarrantyExpiry => WarrantyExpiry.HasValue ? (int)(WarrantyExpiry.Value - DateTime.UtcNow).TotalDays : 0;
}

/// <summary>
/// Hình ảnh tài sản
/// </summary>
public class AssetImage : Entity<Guid>
{
    public Guid AssetId { get; set; }
    public Asset? Asset { get; set; }
    
    /// <summary>URL hình ảnh</summary>
    public string ImageUrl { get; set; } = string.Empty;
    
    /// <summary>Tên file</summary>
    public string? FileName { get; set; }
    
    /// <summary>Mô tả hình ảnh</summary>
    public string? Description { get; set; }
    
    /// <summary>Là hình chính</summary>
    public bool IsPrimary { get; set; }
    
    /// <summary>Thứ tự hiển thị</summary>
    public int DisplayOrder { get; set; }
}

/// <summary>
/// Lịch sử chuyển giao tài sản
/// </summary>
public class AssetTransfer : Entity<Guid>
{
    public Guid AssetId { get; set; }
    public Asset? Asset { get; set; }
    
    /// <summary>Loại chuyển giao</summary>
    public AssetTransferType TransferType { get; set; }
    
    /// <summary>Người giao</summary>
    public Guid? FromUserId { get; set; }
    public ApplicationUser? FromUser { get; set; }
    
    /// <summary>Người nhận</summary>
    public Guid? ToUserId { get; set; }
    public ApplicationUser? ToUser { get; set; }
    
    /// <summary>Số lượng chuyển giao</summary>
    public int Quantity { get; set; } = 1;
    
    /// <summary>Ngày chuyển giao</summary>
    public DateTime TransferDate { get; set; } = DateTime.UtcNow;
    
    /// <summary>Lý do</summary>
    public string? Reason { get; set; }
    
    /// <summary>Ghi chú</summary>
    public string? Notes { get; set; }
    
    /// <summary>Người thực hiện chuyển giao</summary>
    public Guid? PerformedById { get; set; }
    public ApplicationUser? PerformedBy { get; set; }
    
    /// <summary>Xác nhận bởi người nhận</summary>
    public bool IsConfirmed { get; set; }
    
    /// <summary>Ngày xác nhận</summary>
    public DateTime? ConfirmedAt { get; set; }
    
    // Computed
    public string? FromUserName => FromUser?.FullName;
    public string? ToUserName => ToUser?.FullName;
    public string? PerformedByName => PerformedBy?.FullName;
    public string? AssetName => Asset?.Name;
    public string? AssetCode => Asset?.AssetCode;
}

/// <summary>
/// Đợt kiểm kê tài sản
/// </summary>
public class AssetInventory : AuditableEntity<Guid>
{
    /// <summary>Mã đợt kiểm kê (KK-YYYYMMDD-XXX)</summary>
    public string InventoryCode { get; set; } = string.Empty;
    
    /// <summary>Tên đợt kiểm kê</summary>
    public string Name { get; set; } = string.Empty;
    
    /// <summary>Mô tả</summary>
    public string? Description { get; set; }
    
    /// <summary>Ngày bắt đầu</summary>
    public DateTime StartDate { get; set; }
    
    /// <summary>Ngày kết thúc</summary>
    public DateTime? EndDate { get; set; }
    
    /// <summary>Trạng thái: 0=Đang tiến hành, 1=Hoàn thành, 2=Đã hủy</summary>
    public int Status { get; set; }
    
    /// <summary>Người phụ trách</summary>
    public Guid? ResponsibleUserId { get; set; }
    public ApplicationUser? ResponsibleUser { get; set; }
    
    /// <summary>Ghi chú</summary>
    public string? Notes { get; set; }
    
    /// <summary>Store</summary>
    public Guid StoreId { get; set; }
    public Store? Store { get; set; }
    
    // Navigation
    public ICollection<AssetInventoryItem> Items { get; set; } = new List<AssetInventoryItem>();
    
    // Computed
    public int TotalAssets => Items.Count;
    public int CheckedCount => Items.Count(i => i.IsChecked);
    public int IssueCount => Items.Count(i => i.HasIssue);
}

/// <summary>
/// Chi tiết kiểm kê từng tài sản
/// </summary>
public class AssetInventoryItem : Entity<Guid>
{
    public Guid InventoryId { get; set; }
    public AssetInventory? Inventory { get; set; }
    
    public Guid AssetId { get; set; }
    public Asset? Asset { get; set; }
    
    /// <summary>Đã kiểm tra chưa</summary>
    public bool IsChecked { get; set; }
    
    /// <summary>Ngày kiểm tra</summary>
    public DateTime? CheckedAt { get; set; }
    
    /// <summary>Người kiểm tra</summary>
    public Guid? CheckedById { get; set; }
    public ApplicationUser? CheckedBy { get; set; }
    
    /// <summary>Tình trạng khi kiểm</summary>
    public InventoryCondition? Condition { get; set; }
    
    /// <summary>Số lượng thực tế</summary>
    public int? ActualQuantity { get; set; }
    
    /// <summary>Vị trí thực tế</summary>
    public string? ActualLocation { get; set; }
    
    /// <summary>Có vấn đề không</summary>
    public bool HasIssue { get; set; }
    
    /// <summary>Mô tả vấn đề</summary>
    public string? IssueDescription { get; set; }
    
    /// <summary>Ghi chú</summary>
    public string? Notes { get; set; }
    
    // Computed
    public string? AssetCode => Asset?.AssetCode;
    public string? AssetName => Asset?.Name;
    public int ExpectedQuantity => Asset?.Quantity ?? 0;
    public bool QuantityMismatch => ActualQuantity.HasValue && ActualQuantity.Value != ExpectedQuantity;
}
