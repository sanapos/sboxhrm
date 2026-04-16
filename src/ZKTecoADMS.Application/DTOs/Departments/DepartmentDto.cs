namespace ZKTecoADMS.Application.DTOs.Departments;

/// <summary>
/// DTO cho thông tin phòng ban
/// </summary>
public class DepartmentDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public Guid? ParentDepartmentId { get; set; }
    public string? ParentDepartmentName { get; set; }
    public Guid? ManagerId { get; set; }
    public string? ManagerName { get; set; }
    public int Level { get; set; }
    public int SortOrder { get; set; }
    public Guid? StoreId { get; set; }
    public string? StoreName { get; set; }
    public string? HierarchyPath { get; set; }
    public int DirectEmployeeCount { get; set; }
    public int TotalEmployeeCount { get; set; }
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public List<string>? Positions { get; set; }
}

/// <summary>
/// DTO cho cây phòng ban (tree view)
/// </summary>
public class DepartmentTreeNodeDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public Guid? ParentDepartmentId { get; set; }
    public Guid? ManagerId { get; set; }
    public string? ManagerName { get; set; }
    public int Level { get; set; }
    public int SortOrder { get; set; }
    public int DirectEmployeeCount { get; set; }
    public int TotalEmployeeCount { get; set; }
    public bool IsActive { get; set; }
    public bool HasChildren { get; set; }
    public bool IsExpanded { get; set; }
    public List<DepartmentTreeNodeDto> Children { get; set; } = new();
}

/// <summary>
/// DTO tạo phòng ban mới
/// </summary>
public class CreateDepartmentDto
{
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public Guid? ParentDepartmentId { get; set; }
    public Guid? ManagerId { get; set; }
    public int SortOrder { get; set; }
    public Guid? StoreId { get; set; }
    public List<string>? Positions { get; set; }
}

/// <summary>
/// DTO cập nhật phòng ban
/// </summary>
public class UpdateDepartmentDto
{
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string? Description { get; set; }
    public Guid? ParentDepartmentId { get; set; }
    public Guid? ManagerId { get; set; }
    public int SortOrder { get; set; }
    public bool IsActive { get; set; }
    public List<string>? Positions { get; set; }
}

/// <summary>
/// DTO cho dropdown phòng ban
/// </summary>
public class DepartmentSelectDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string DisplayName => $"{Code} - {Name}";
    public int Level { get; set; }
    public Guid? ParentDepartmentId { get; set; }
    public List<string>? Positions { get; set; }
}

/// <summary>
/// DTO di chuyển phòng ban trong cây
/// </summary>
public class MoveDepartmentDto
{
    public Guid DepartmentId { get; set; }
    public Guid? NewParentDepartmentId { get; set; }
    public int NewSortOrder { get; set; }
}

/// <summary>
/// DTO cho thống kê phòng ban
/// </summary>
public class DepartmentStatisticsDto
{
    public Guid DepartmentId { get; set; }
    public string DepartmentName { get; set; } = string.Empty;
    public int TotalEmployees { get; set; }
    public int ActiveEmployees { get; set; }
    public int OnLeaveEmployees { get; set; }
    public int SubDepartmentsCount { get; set; }
}
