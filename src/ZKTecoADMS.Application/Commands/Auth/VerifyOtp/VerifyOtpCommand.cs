using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.Models;
using FluentValidation;

namespace ZKTecoADMS.Application.Commands.Auth.VerifyOtp;

public record VerifyOtpCommand(string StoreCode, string Email, string Otp, string NewPassword, string ConfirmPassword) : ICommand<AppResponse<string>>;

public class VerifyOtpCommandValidator : AbstractValidator<VerifyOtpCommand>
{
    public VerifyOtpCommandValidator()
    {
        RuleFor(x => x.StoreCode)
            .NotEmpty()
            .WithMessage("Mã cửa hàng không được để trống");

        RuleFor(x => x.Email)
            .NotEmpty()
            .WithMessage("Email không được để trống");

        RuleFor(x => x.Otp)
            .NotEmpty()
            .WithMessage("Mã OTP không được để trống")
            .Length(6)
            .WithMessage("Mã OTP phải có 6 chữ số");

        RuleFor(x => x.NewPassword)
            .NotEmpty()
            .WithMessage("Mật khẩu mới không được để trống")
            .MinimumLength(6)
            .WithMessage("Mật khẩu phải có ít nhất 6 ký tự");

        RuleFor(x => x.ConfirmPassword)
            .Equal(x => x.NewPassword)
            .WithMessage("Xác nhận mật khẩu không khớp");
    }
}
