using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Assets;

#region Asset Category DTOs
public record AssetCategoryDto
{
    public Guid Id { get; init; }
    public string CategoryCode { get; init; } = string.Empty;
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public Guid? ParentCategoryId { get; init; }
    public string? ParentCategoryName { get; init; }
    public int AssetCount { get; init; }
    public bool IsActive { get; init; }
    public DateTime CreatedAt { get; init; }
    public List<AssetCategoryDto>? SubCategories { get; init; }
}

public record CreateAssetCategoryDto
{
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public Guid? ParentCategoryId { get; init; }
}

public record UpdateAssetCategoryDto
{
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public Guid? ParentCategoryId { get; init; }
    public bool IsActive { get; init; } = true;
}
#endregion

#region Asset DTOs
public record AssetDto
{
    public Guid Id { get; init; }
    public string AssetCode { get; init; } = string.Empty;
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public string? SerialNumber { get; init; }
    public string? Model { get; init; }
    public string? Brand { get; init; }
    public AssetType AssetType { get; init; }
    public string AssetTypeName { get; init; } = string.Empty;
    public Guid? CategoryId { get; init; }
    public string? CategoryName { get; init; }
    public AssetStatus Status { get; init; }
    public string StatusName { get; init; } = string.Empty;
    public int Quantity { get; init; }
    public string Unit { get; init; } = string.Empty;
    public decimal PurchasePrice { get; init; }
    public string Currency { get; init; } = string.Empty;
    public DateTime? PurchaseDate { get; init; }
    public string? Supplier { get; init; }
    public string? InvoiceNumber { get; init; }
    public int? WarrantyMonths { get; init; }
    public DateTime? WarrantyExpiry { get; init; }
    public bool IsWarrantyExpired { get; init; }
    public int DaysUntilWarrantyExpiry { get; init; }
    public string? Location { get; init; }
    public string? Notes { get; init; }
    public decimal? DepreciationRate { get; init; }
    public decimal? CurrentValue { get; init; }
    public string? CurrentAssigneeId { get; init; }
    public string? CurrentAssigneeName { get; init; }
    public DateTime? AssignedDate { get; init; }
    public bool IsActive { get; init; }
    public DateTime CreatedAt { get; init; }
    public string? CreatedBy { get; init; }
    public List<AssetImageDto>? Images { get; init; }
    public string? PrimaryImageUrl { get; init; }
}

public record AssetDetailDto : AssetDto
{
    public List<AssetTransferDto>? TransferHistory { get; init; }
    public List<AssetInventoryItemDto>? InventoryHistory { get; init; }
}

public record CreateAssetDto
{
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public string? SerialNumber { get; init; }
    public string? Model { get; init; }
    public string? Brand { get; init; }
    public AssetType AssetType { get; init; } = AssetType.Electronics;
    public Guid? CategoryId { get; init; }
    public int Quantity { get; init; } = 1;
    public string Unit { get; init; } = "Cái";
    public decimal PurchasePrice { get; init; }
    public string Currency { get; init; } = "VND";
    public DateTime? PurchaseDate { get; init; }
    public string? Supplier { get; init; }
    public string? InvoiceNumber { get; init; }
    public int? WarrantyMonths { get; init; }
    public string? Location { get; init; }
    public string? Notes { get; init; }
    public decimal? DepreciationRate { get; init; }
}

public record UpdateAssetDto
{
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public string? SerialNumber { get; init; }
    public string? Model { get; init; }
    public string? Brand { get; init; }
    public AssetType AssetType { get; init; }
    public Guid? CategoryId { get; init; }
    public AssetStatus Status { get; init; }
    public int Quantity { get; init; }
    public string Unit { get; init; } = "Cái";
    public decimal PurchasePrice { get; init; }
    public string Currency { get; init; } = "VND";
    public DateTime? PurchaseDate { get; init; }
    public string? Supplier { get; init; }
    public string? InvoiceNumber { get; init; }
    public int? WarrantyMonths { get; init; }
    public string? Location { get; init; }
    public string? Notes { get; init; }
    public decimal? DepreciationRate { get; init; }
    public decimal? CurrentValue { get; init; }
}

public record AssetQueryParams
{
    public string? Search { get; init; }
    public AssetType? AssetType { get; init; }
    public AssetStatus? Status { get; init; }
    public Guid? CategoryId { get; init; }
    public string? AssigneeId { get; init; }
    public string? Location { get; init; }
    public bool? HasSerialNumber { get; init; }
    public bool? WarrantyExpiringSoon { get; init; } // Within 30 days
    public DateTime? PurchaseDateFrom { get; init; }
    public DateTime? PurchaseDateTo { get; init; }
    public decimal? MinPrice { get; init; }
    public decimal? MaxPrice { get; init; }
    public int Page { get; init; } = 1;
    public int PageSize { get; init; } = 20;
    public string? SortBy { get; init; }
    public bool SortDesc { get; init; }
}
#endregion

#region Asset Image DTOs
public record AssetImageDto
{
    public Guid Id { get; init; }
    public Guid AssetId { get; init; }
    public string ImageUrl { get; init; } = string.Empty;
    public string? FileName { get; init; }
    public string? Description { get; init; }
    public bool IsPrimary { get; init; }
    public int DisplayOrder { get; init; }
}

public record AddAssetImageDto
{
    public string ImageUrl { get; init; } = string.Empty;
    public string? FileName { get; init; }
    public string? Description { get; init; }
    public bool IsPrimary { get; init; }
}
#endregion

#region Asset Transfer DTOs
public record AssetTransferDto
{
    public Guid Id { get; init; }
    public Guid AssetId { get; init; }
    public string? AssetCode { get; init; }
    public string? AssetName { get; init; }
    public AssetTransferType TransferType { get; init; }
    public string TransferTypeName { get; init; } = string.Empty;
    public string? FromUserId { get; init; }
    public string? FromUserName { get; init; }
    public string? ToUserId { get; init; }
    public string? ToUserName { get; init; }
    public int Quantity { get; init; }
    public DateTime TransferDate { get; init; }
    public string? Reason { get; init; }
    public string? Notes { get; init; }
    public string? PerformedById { get; init; }
    public string? PerformedByName { get; init; }
    public bool IsConfirmed { get; init; }
    public DateTime? ConfirmedAt { get; init; }
    public DateTime CreatedAt { get; init; }
}

public record AssignAssetDto
{
    public Guid AssetId { get; init; }
    public string ToUserId { get; init; } = string.Empty;
    public int Quantity { get; init; } = 1;
    public string? Reason { get; init; }
    public string? Notes { get; init; }
}

public record TransferAssetDto
{
    public Guid AssetId { get; init; }
    public string FromUserId { get; init; } = string.Empty;
    public string ToUserId { get; init; } = string.Empty;
    public int Quantity { get; init; } = 1;
    public string? Reason { get; init; }
    public string? Notes { get; init; }
}

public record ReturnAssetDto
{
    public Guid AssetId { get; init; }
    public string FromUserId { get; init; } = string.Empty;
    public int Quantity { get; init; } = 1;
    public string? Reason { get; init; }
    public string? Notes { get; init; }
}

public record ConfirmTransferDto
{
    public Guid TransferId { get; init; }
    public string? Notes { get; init; }
}
#endregion

#region Asset Inventory DTOs
public record AssetInventoryDto
{
    public Guid Id { get; init; }
    public string InventoryCode { get; init; } = string.Empty;
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public DateTime StartDate { get; init; }
    public DateTime? EndDate { get; init; }
    public int Status { get; init; }
    public string StatusName { get; init; } = string.Empty;
    public string? ResponsibleUserId { get; init; }
    public string? ResponsibleUserName { get; init; }
    public string? Notes { get; init; }
    public int TotalAssets { get; init; }
    public int CheckedCount { get; init; }
    public int IssueCount { get; init; }
    public double ProgressPercent { get; init; }
    public DateTime CreatedAt { get; init; }
}

public record AssetInventoryDetailDto : AssetInventoryDto
{
    public List<AssetInventoryItemDto>? Items { get; init; }
}

public record CreateAssetInventoryDto
{
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public DateTime StartDate { get; init; }
    public DateTime? EndDate { get; init; }
    public string? ResponsibleUserId { get; init; }
    public string? Notes { get; init; }
    public List<Guid>? AssetIds { get; init; } // If empty, include all assets
}

public record AssetInventoryItemDto
{
    public Guid Id { get; init; }
    public Guid InventoryId { get; init; }
    public Guid AssetId { get; init; }
    public string? AssetCode { get; init; }
    public string? AssetName { get; init; }
    public bool IsChecked { get; init; }
    public DateTime? CheckedAt { get; init; }
    public string? CheckedById { get; init; }
    public string? CheckedByName { get; init; }
    public InventoryCondition? Condition { get; init; }
    public string? ConditionName { get; init; }
    public int ExpectedQuantity { get; init; }
    public int? ActualQuantity { get; init; }
    public bool QuantityMismatch { get; init; }
    public string? ActualLocation { get; init; }
    public bool HasIssue { get; init; }
    public string? IssueDescription { get; init; }
    public string? Notes { get; init; }
}

public record CheckInventoryItemDto
{
    public Guid InventoryItemId { get; init; }
    public InventoryCondition Condition { get; init; }
    public int ActualQuantity { get; init; }
    public string? ActualLocation { get; init; }
    public bool HasIssue { get; init; }
    public string? IssueDescription { get; init; }
    public string? Notes { get; init; }
}
#endregion

#region Statistics DTOs
public record AssetStatisticsDto
{
    public int TotalAssets { get; init; }
    public int ActiveAssets { get; init; }
    public int InStockAssets { get; init; }
    public int AssignedAssets { get; init; }
    public int MaintenanceAssets { get; init; }
    public int BrokenAssets { get; init; }
    public int DisposedAssets { get; init; }
    public decimal TotalPurchaseValue { get; init; }
    public decimal TotalCurrentValue { get; init; }
    public int WarrantyExpiringSoon { get; init; }
    public List<AssetByTypeDto>? ByType { get; init; }
    public List<AssetByCategoryDto>? ByCategory { get; init; }
    public List<AssetByAssigneeDto>? ByAssignee { get; init; }
    public List<AssetByStatusDto>? ByStatus { get; init; }
}

public record AssetByTypeDto
{
    public AssetType AssetType { get; init; }
    public string AssetTypeName { get; init; } = string.Empty;
    public int Count { get; init; }
    public decimal TotalValue { get; init; }
}

public record AssetByCategoryDto
{
    public Guid? CategoryId { get; init; }
    public string CategoryName { get; init; } = string.Empty;
    public int Count { get; init; }
    public decimal TotalValue { get; init; }
}

public record AssetByAssigneeDto
{
    public string? AssigneeId { get; init; }
    public string AssigneeName { get; init; } = string.Empty;
    public int Count { get; init; }
    public decimal TotalValue { get; init; }
}

public record AssetByStatusDto
{
    public AssetStatus Status { get; init; }
    public string StatusName { get; init; } = string.Empty;
    public int Count { get; init; }
}
#endregion
