namespace ZKTecoADMS.Application.Constants;

public static class PolicyNames
{
    public const string AdminOnly = "AdminOnly";
    public const string AtLeastAdmin = "AtLeastAdmin";
    public const string AtLeastManager = "AtLeastManager";
    /// <summary>Quản lý trở lên + Kế toán — dữ liệu lương / thưởng phạt cả cửa hàng.</summary>
    public const string ManagerOrAccountant = "ManagerOrAccountant";
    public const string AtLeastEmployee = "AtLeastEmployee";
    public const string HourlyEmployeeOnly = "HourlyEmployeeOnly";
}