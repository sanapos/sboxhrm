using System.Security.Claims;
using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.Models;
using FluentValidation;

namespace ZKTecoADMS.Application.Commands.Auth.Logout;

public record LogoutCommand(ClaimsPrincipal User) : ICommand<AppResponse<bool>>;

public class LogoutCommandValidator : AbstractValidator<LogoutCommand>
{
    public LogoutCommandValidator()
    {
        RuleFor(x => x.User).NotNull();
    }
}