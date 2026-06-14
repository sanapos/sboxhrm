using ZKTecoADMS.Application.DTOs.Accounts;
using ZKTecoADMS.Application.DTOs.Commons;

namespace ZKTecoADMS.Application.Commands.Accounts.BulkCreateEmployeeAccounts;

public class BulkCreateEmployeeAccountsCommand : ICommand<AppResponse<BulkCreateEmployeeAccountsResult>>
{
    public List<Guid> EmployeeIds { get; set; } = [];
    public string Password { get; set; } = string.Empty;
    public string Role { get; set; } = "Employee";
    public Guid ManagerId { get; set; }
}
