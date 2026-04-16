using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.HrDocuments;

/// <summary>
/// DTO chi tiết tài liệu HR
/// </summary>
public class HrDocumentDto
{
    public Guid Id { get; set; }
    public Guid StoreId { get; set; }
    public Guid EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string EmployeeCode { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public HrDocumentType DocumentType { get; set; }
    public string DocumentTypeText { get; set; } = string.Empty;
    public string FilePath { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public string? ContentType { get; set; }
    public long FileSize { get; set; }
    public string FileSizeText { get; set; } = string.Empty;
    public DateTime? EffectiveDate { get; set; }
    public DateTime? ExpiryDate { get; set; }
    public bool IsExpired { get; set; }
    public int DaysUntilExpiry { get; set; }
    public string? DocumentNumber { get; set; }
    public string? IssuedBy { get; set; }
    public string? Notes { get; set; }
    public Guid? UploadedByUserId { get; set; }
    public string? UploadedByName { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

/// <summary>
/// DTO tạo tài liệu mới
/// </summary>
public class CreateHrDocumentDto
{
    public Guid EmployeeUserId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public HrDocumentType DocumentType { get; set; }
    public string FilePath { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public string? ContentType { get; set; }
    public long FileSize { get; set; }
    public DateTime? EffectiveDate { get; set; }
    public DateTime? ExpiryDate { get; set; }
    public string? DocumentNumber { get; set; }
    public string? IssuedBy { get; set; }
    public string? Notes { get; set; }
}

/// <summary>
/// DTO cập nhật tài liệu
/// </summary>
public class UpdateHrDocumentDto
{
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public HrDocumentType DocumentType { get; set; }
    public DateTime? EffectiveDate { get; set; }
    public DateTime? ExpiryDate { get; set; }
    public string? DocumentNumber { get; set; }
    public string? IssuedBy { get; set; }
    public string? Notes { get; set; }
}

/// <summary>
/// DTO cho danh sách tài liệu sắp hết hạn
/// </summary>
public class ExpiringDocumentDto
{
    public Guid Id { get; set; }
    public Guid EmployeeUserId { get; set; }
    public string EmployeeName { get; set; } = string.Empty;
    public string EmployeeCode { get; set; } = string.Empty;
    public string DocumentName { get; set; } = string.Empty;
    public HrDocumentType DocumentType { get; set; }
    public string DocumentTypeText { get; set; } = string.Empty;
    public DateTime ExpiryDate { get; set; }
    public int DaysUntilExpiry { get; set; }
}

/// <summary>
/// Thống kê tài liệu theo loại
/// </summary>
public class DocumentTypeSummaryDto
{
    public HrDocumentType DocumentType { get; set; }
    public string DocumentTypeText { get; set; } = string.Empty;
    public int TotalCount { get; set; }
    public int ExpiredCount { get; set; }
    public int ExpiringCount { get; set; } // Within 30 days
}
