using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Transactions;

/// <summary>
/// DTO cho danh mục giao dịch
/// </summary>
public record TransactionCategoryDto
{
    public Guid Id { get; init; }
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public CashTransactionType Type { get; init; }
    public string TypeName => Type == CashTransactionType.Income ? "Thu" : "Chi";
    public string? Icon { get; init; }
    public string? Color { get; init; }
    public int SortOrder { get; init; }
    public Guid? ParentCategoryId { get; init; }
    public string? ParentCategoryName { get; init; }
    public bool IsSystem { get; init; }
    public bool IsActive { get; init; }
    public int TransactionCount { get; init; }
    public List<TransactionCategoryDto> SubCategories { get; init; } = new();
}

/// <summary>
/// DTO để tạo danh mục
/// </summary>
public record CreateTransactionCategoryDto
{
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public CashTransactionType Type { get; init; }
    public string? Icon { get; init; }
    public string? Color { get; init; }
    public int SortOrder { get; init; } = 0;
    public Guid? ParentCategoryId { get; init; }
}

/// <summary>
/// DTO để cập nhật danh mục
/// </summary>
public record UpdateTransactionCategoryDto
{
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public string? Icon { get; init; }
    public string? Color { get; init; }
    public int SortOrder { get; init; }
    public Guid? ParentCategoryId { get; init; }
    public bool IsActive { get; init; } = true;
}
