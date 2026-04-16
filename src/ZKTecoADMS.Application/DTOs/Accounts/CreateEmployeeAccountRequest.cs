namespace ZKTecoADMS.Application.DTOs.Accounts;

public class CreateEmployeeAccountRequest
{
    public Guid EmployeeId { get; set; }

    public string Password { get; set; } = string.Empty;
    public string UserName { get; set; } = string.Empty;
    public string FirstName { get; set; } = string.Empty;
    public string LastName { get; set; } = string.Empty;
    public string? PhoneNumber { get; set; }
    public string Email { get; set; } = string.Empty;

    // Quyền hạn: Admin, Manager, Accountant, Employee, User
    public string Role { get; set; } = "Employee";
}