using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.Models;
using FluentValidation;

namespace ZKTecoADMS.Application.Commands.Auth.ResetPassword;

public record ResetPasswordCommand(string Email, string Token, string NewPassword, string ConfirmPassword) : ICommand<AppResponse<string>>;

public class ResetPasswordCommandValidator : AbstractValidator<ResetPasswordCommand>
{
    public ResetPasswordCommandValidator()
    {
        RuleFor(x => x.Email)
            .NotEmpty()
            .WithMessage("Email không được để trống")
            .EmailAddress()
            .WithMessage("Email không hợp lệ");

        RuleFor(x => x.Token)
            .NotEmpty()
            .WithMessage("Token không hợp lệ");

        RuleFor(x => x.NewPassword)
            .NotEmpty()
            .WithMessage("Mật khẩu mới không được để trống")
            .MinimumLength(6)
            .WithMessage("Mật khẩu phải có ít nhất 6 ký tự");

        RuleFor(x => x.ConfirmPassword)
            .NotEmpty()
            .WithMessage("Xác nhận mật khẩu không được để trống")
            .Equal(x => x.NewPassword)
            .WithMessage("Mật khẩu xác nhận không khớp");
    }
}
