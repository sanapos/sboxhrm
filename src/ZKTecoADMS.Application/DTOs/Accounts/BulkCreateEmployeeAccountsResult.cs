namespace ZKTecoADMS.Application.DTOs.Accounts;

public class BulkCreateEmployeeAccountsResult
{
    public int Created { get; set; }
    public int Failed { get; set; }
    public int Skipped { get; set; }
    public List<BulkCreateEmployeeAccountItemResult> Items { get; set; } = [];
}

public class BulkCreateEmployeeAccountItemResult
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public bool Success { get; set; }
    public bool Skipped { get; set; }
    public string? UserName { get; set; }
    public string? Email { get; set; }
    public string? PhoneNumber { get; set; }
    public string? Message { get; set; }
}
