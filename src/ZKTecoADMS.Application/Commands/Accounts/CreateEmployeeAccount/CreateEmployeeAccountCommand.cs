using ZKTecoADMS.Application.DTOs.Commons;

namespace ZKTecoADMS.Application.Commands.Accounts;

public class CreateEmployeeAccountCommand : ICommand<AppResponse<AccountDto>>
{
    public string Email { get; set; } = string.Empty;

    public string UserName { get; set; } = string.Empty;
    
    public string Password { get; set; } = string.Empty;

    public string FirstName { get; set; } = string.Empty;

    public string LastName { get; set; } = string.Empty;

    public string PhoneNumber { get; set; } = string.Empty;

    public Guid ManagerId { get; set; }

    public Guid? EmployeeId { get; set; }

    // Quyền hạn: Admin, Manager, Accountant, Employee, User
    public string Role { get; set; } = "Employee";
}