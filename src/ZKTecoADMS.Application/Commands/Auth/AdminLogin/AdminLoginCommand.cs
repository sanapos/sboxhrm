using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Auth;
using ZKTecoADMS.Application.Models;
using FluentValidation;

namespace ZKTecoADMS.Application.Commands.Auth.AdminLogin;

/// <summary>
/// Admin Login Command - for SuperAdmin and Agent (no store code required)
/// </summary>
public record AdminLoginCommand(string UserName, string Password) : ICommand<AppResponse<AuthenticateResponse>>;

public class AdminLoginCommandValidator : AbstractValidator<AdminLoginCommand>
{
    public AdminLoginCommandValidator()
    {
        RuleFor(x => x.UserName)
            .NotEmpty()
            .WithMessage("Email không được để trống");
            
        RuleFor(x => x.Password)
            .NotEmpty()
            .WithMessage("Mật khẩu không được để trống");
    }
}
