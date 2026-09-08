namespace ZKTecoADMS.Application.DTOs.Permissions;

/// <summary>
/// Phạm vi chi nhánh / phòng ban mà tài khoản được xem dữ liệu.
/// </summary>
public class UserDataScopeDto
{
    public Guid UserId { get; set; }
    public string? UserName { get; set; }
    public string? FullName { get; set; }
    public string? Role { get; set; }
    public bool IsAdmin { get; set; }

    public bool AllBranches { get; set; }
    public bool IncludeChildBranches { get; set; } = true;
    public List<Guid> BranchIds { get; set; } = [];
    public List<Guid> InheritedBranchIds { get; set; } = [];

    public bool AllDepartments { get; set; }
    public bool IncludeChildDepartments { get; set; } = true;
    public List<Guid> DepartmentIds { get; set; } = [];
    public List<Guid> InheritedDepartmentIds { get; set; } = [];
}

public class UpdateUserDataScopeRequest
{
    public bool AllBranches { get; set; }
    public bool IncludeChildBranches { get; set; } = true;
    public List<Guid> BranchIds { get; set; } = [];

    public bool AllDepartments { get; set; }
    public bool IncludeChildDepartments { get; set; } = true;
    public List<Guid> DepartmentIds { get; set; } = [];
}
