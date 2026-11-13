namespace ZKTecoADMS.Application.Constants;

public static class ClaimTypeNames
{
    public const string Role = "role";
    
    public const string EmployeeId = "employeeId";

    public const string ManagerId = "managerId";

    public const string EmployeeType = "employeeType";

    public const string UserName = "userName";
    
    public const string StoreId = "storeId";
    
    public const string StoreName = "storeName";

    /// <summary>Id Super Admin khi token là phiên «Đăng nhập thay» (không có ở phiên đăng nhập thật).</summary>
    public const string ImpersonatedBy = "impersonatedBy";
}