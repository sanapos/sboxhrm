using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Users;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Commands.Accounts.UpdateUserProfile;

public record UpdateUserProfileCommand : ICommand<AppResponse<UserProfileDto>>
{
    public Guid UserId { get; set; }
    public string? FirstName { get; set; }
    public string? LastName { get; set; }
    public string? PhoneNumber { get; set; }
}
