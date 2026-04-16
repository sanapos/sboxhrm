namespace ZKTecoADMS.Application.Commands.Accounts.UpdateEmployeeAccount;

public class UpdateEmployeeAccountCommand : ICommand<AppResponse<bool>>
{
    public Guid UserId { get; set; }
    public Guid StoreId { get; set; }

    public required string Email { get; set; }

    public required string FirstName { get; set; }

    public required string LastName { get; set; }

    public string? UserName {get;set;}

    public string? PhoneNumber { get; set; }

    public string? Role { get; set; }
}
