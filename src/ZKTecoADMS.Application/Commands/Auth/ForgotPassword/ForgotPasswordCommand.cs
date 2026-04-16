using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.Models;
using FluentValidation;

namespace ZKTecoADMS.Application.Commands.Auth.ForgotPassword;

public record ForgotPasswordCommand(string StoreCode, string Email) : ICommand<AppResponse<string>>;

public class ForgotPasswordCommandValidator : AbstractValidator<ForgotPasswordCommand>
{
    public ForgotPasswordCommandValidator()
    {
        RuleFor(x => x.StoreCode)
            .NotEmpty()
            .WithMessage("Mã cửa hàng không được để trống");

        RuleFor(x => x.Email)
            .NotEmpty()
            .WithMessage("Email không được để trống")
            .EmailAddress()
            .WithMessage("Email không hợp lệ");
    }
}
