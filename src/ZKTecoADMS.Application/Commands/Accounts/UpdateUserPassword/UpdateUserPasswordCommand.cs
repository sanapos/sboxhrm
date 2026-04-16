using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Users;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Commands.Accounts.UpdateUserPassword;

public record UpdateUserPasswordCommand : ICommand<AppResponse<UserProfileDto>>
{
    public Guid UserId { get; set; }
    public required string CurrentPassword { get; set; }
    public required string NewPassword { get; set; }
}
