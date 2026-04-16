using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Auth;
using ZKTecoADMS.Application.Models;
using FluentValidation;

namespace ZKTecoADMS.Application.Commands.Auth.Register;

public record RegisterCommand(RegisterRequest RegisterRequest) : ICommand<AppResponse<string>>;

public class RegisterValidator : AbstractValidator<RegisterCommand>
{
    public RegisterValidator()
    {
        RuleFor(x => x.RegisterRequest.StoreName)
            .NotEmpty()
            .WithMessage("Tên cửa hàng không được để trống.")
            .MinimumLength(2)
            .WithMessage("Tên cửa hàng phải có ít nhất 2 ký tự.")
            .MaximumLength(100)
            .WithMessage("Tên cửa hàng không được quá 100 ký tự.");

        RuleFor(x => x.RegisterRequest.Email)
            .EmailAddress()
            .WithMessage("Email không hợp lệ.")
            .NotEmpty()
            .WithMessage("Email không được để trống.");

        RuleFor(x => x.RegisterRequest.Password)
            .NotEmpty()
            .WithMessage("Mật khẩu không được để trống.")
            .MinimumLength(6)
            .WithMessage("Mật khẩu phải có ít nhất 6 ký tự.");

        RuleFor(x => x.RegisterRequest.PhoneNumber)
            .Matches(@"^\+?[0-9]{9,15}$")
            .When(x => !string.IsNullOrEmpty(x.RegisterRequest.PhoneNumber))
            .WithMessage("Số điện thoại không hợp lệ.");

        RuleFor(x => x.RegisterRequest.StoreCode)
            .Matches(@"^[a-z0-9]+$")
            .When(x => !string.IsNullOrEmpty(x.RegisterRequest.StoreCode))
            .WithMessage("Mã cửa hàng chỉ chấp nhận chữ thường và số, không dấu.")
            .MinimumLength(2)
            .When(x => !string.IsNullOrEmpty(x.RegisterRequest.StoreCode))
            .WithMessage("Mã cửa hàng phải có ít nhất 2 ký tự.")
            .MaximumLength(20)
            .When(x => !string.IsNullOrEmpty(x.RegisterRequest.StoreCode))
            .WithMessage("Mã cửa hàng không được quá 20 ký tự.");
    }
}
