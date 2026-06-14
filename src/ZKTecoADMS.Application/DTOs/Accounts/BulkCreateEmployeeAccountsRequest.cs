namespace ZKTecoADMS.Application.DTOs.Accounts;

public class BulkCreateEmployeeAccountsRequest
{
    public List<Guid> EmployeeIds { get; set; } = [];
    public string Password { get; set; } = string.Empty;
    public string Role { get; set; } = "Employee";
}
