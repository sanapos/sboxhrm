using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Auth;
using ZKTecoADMS.Application.Models;
using FluentValidation;

namespace ZKTecoADMS.Application.Commands.Auth.Refresh;

public record RefreshCommand(string RefreshToken) : ICommand<AppResponse<AuthenticateResponse>>;

public class RefreshCommandValidator : AbstractValidator<RefreshCommand>
{
    public RefreshCommandValidator()
    {
        RuleFor(x => x.RefreshToken)
            .NotEmpty()
            .WithMessage("Refresh token is required.");
    }
}