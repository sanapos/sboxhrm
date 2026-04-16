using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Auth;
using ZKTecoADMS.Application.Models;
using FluentValidation;

namespace ZKTecoADMS.Application.Commands.Auth.Login;

public record LoginCommand(string StoreCode, string UserName, string Password) : ICommand<AppResponse<AuthenticateResponse>>;

public class LoginCommandValidator : AbstractValidator<LoginCommand>
{
    public LoginCommandValidator()
    {
        RuleFor(x => x.StoreCode)
            .NotEmpty()
            .WithMessage("Mã cửa hàng không được để trống.");

        RuleFor(x => x.UserName)
            .NotEmpty()
            .WithMessage("Email không được để trống.");

        RuleFor(x => x.Password)
            .NotEmpty()
            .WithMessage("Mật khẩu không được để trống.");
    }
}