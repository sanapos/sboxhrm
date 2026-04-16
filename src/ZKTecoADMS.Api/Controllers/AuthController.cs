using ZKTecoADMS.Application.Commands.Auth.AdminLogin;
using ZKTecoADMS.Application.Commands.Auth.Login;
using ZKTecoADMS.Application.Commands.Auth.Logout;
using ZKTecoADMS.Application.Commands.Auth.Refresh;
using ZKTecoADMS.Application.Commands.Auth.Register;
using ZKTecoADMS.Application.Commands.Auth.ForgotPassword;
using ZKTecoADMS.Application.Commands.Auth.ResetPassword;
using ZKTecoADMS.Application.Commands.Auth.VerifyOtp;
using ZKTecoADMS.Application.DTOs.Auth;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Constants;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.RateLimiting;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Controllers;

[Route("api/[controller]/[action]")]
[ApiController]
public class AuthController(IMediator _bus, UserManager<ApplicationUser> _userManager) : ControllerBase
{
    [HttpPost]
    [AllowAnonymous]
    [EnableRateLimiting("login")]
    public async Task<ActionResult<AppResponse<AuthenticateResponse>>> Login(LoginRequest loginRequest, CancellationToken cancellationToken = new())
    {
        var command = new LoginCommand(loginRequest.StoreCode, loginRequest.UserName, loginRequest.Password);
        return await _bus.Send(command, cancellationToken);
    }

    /// <summary>
    /// Đăng nhập dành cho SuperAdmin và Agent (không cần mã cửa hàng)
    /// </summary>
    [HttpPost]
    [AllowAnonymous]
    [EnableRateLimiting("login")]
    public async Task<ActionResult<AppResponse<AuthenticateResponse>>> AdminLogin([FromBody] AdminLoginRequest request, CancellationToken cancellationToken = new())
    {
        var command = new AdminLoginCommand(request.UserName, request.Password);
        return await _bus.Send(command, cancellationToken);
    }

    [HttpPost]
    [AllowAnonymous]
    [EnableRateLimiting("login")]
    public async Task<ActionResult<AppResponse<string>>> Register(RegisterRequest registerRequest, CancellationToken cancellationToken = new())
    {
        var command = new RegisterCommand(registerRequest);  
        return Ok(await _bus.Send(command, cancellationToken));
    }

    [HttpPost]
    [AllowAnonymous]
    [EnableRateLimiting("login")]
    public async Task<IActionResult> Refresh(RefreshRequest refreshRequest, CancellationToken cancellationToken = new())
    {
       return Ok(await _bus.Send(new RefreshCommand(refreshRequest.RefreshToken), cancellationToken));
    }

    [HttpPost]
    [Authorize]
    public async Task<ActionResult<AppResponse<bool>>> Logout(CancellationToken cancellationToken = new())
    {
        
        return Ok(await _bus.Send(new LogoutCommand(User), cancellationToken));
    }

    [Authorize]
    [HttpGet("me")]
    public Task<ActionResult> Me(CancellationToken cancellationToken = new())
    {

        return Task.FromResult<ActionResult>(Ok(User));
    }

    /// <summary>
    /// Quên mật khẩu - gửi link reset qua email
    /// </summary>
    [HttpPost]
    [AllowAnonymous]
    [EnableRateLimiting("login")]
    public async Task<ActionResult<AppResponse<string>>> ForgotPassword(ForgotPasswordRequest request, CancellationToken cancellationToken = new())
    {
        var command = new ForgotPasswordCommand(request.StoreCode, request.Email);
        return Ok(await _bus.Send(command, cancellationToken));
    }

    /// <summary>
    /// Đặt lại mật khẩu bằng token từ email
    /// </summary>
    [HttpPost]
    [AllowAnonymous]
    [EnableRateLimiting("login")]
    public async Task<ActionResult<AppResponse<string>>> ResetPassword(Application.DTOs.Auth.ResetPasswordRequest request, CancellationToken cancellationToken = new())
    {
        var command = new ResetPasswordCommand(request.Email, request.Token, request.NewPassword, request.ConfirmPassword);
        return Ok(await _bus.Send(command, cancellationToken));
    }

    /// <summary>
    /// Xác nhận OTP và đặt lại mật khẩu
    /// </summary>
    [HttpPost]
    [AllowAnonymous]
    [EnableRateLimiting("login")]
    public async Task<ActionResult<AppResponse<string>>> VerifyOtp(VerifyOtpRequest request, CancellationToken cancellationToken = new())
    {
        var command = new VerifyOtpCommand(request.StoreCode, request.Email, request.Otp, request.NewPassword, request.ConfirmPassword);
        return Ok(await _bus.Send(command, cancellationToken));
    }

    /// <summary>
    /// Khởi tạo SuperAdmin đầu tiên khi hệ thống chưa có tài khoản SuperAdmin nào.
    /// Endpoint này chỉ hoạt động 1 lần duy nhất — sau khi đã tạo SuperAdmin thì sẽ bị khóa.
    /// </summary>
    [HttpPost]
    [AllowAnonymous]
    [EnableRateLimiting("login")]
    public async Task<ActionResult<AppResponse<string>>> Setup([FromBody] SetupSuperAdminRequest request)
    {
        try
        {
            // Kiểm tra đã có SuperAdmin chưa
            var superAdmins = await _userManager.GetUsersInRoleAsync(nameof(Roles.SuperAdmin));
            if (superAdmins.Any())
            {
                return BadRequest(AppResponse<string>.Fail("Hệ thống đã có SuperAdmin. Endpoint này đã bị khóa."));
            }

            // Validate input
            if (string.IsNullOrWhiteSpace(request.Email) || string.IsNullOrWhiteSpace(request.Password))
            {
                return BadRequest(AppResponse<string>.Fail("Email và mật khẩu không được để trống."));
            }

            if (request.Password.Length < 6)
            {
                return BadRequest(AppResponse<string>.Fail("Mật khẩu phải có ít nhất 6 ký tự."));
            }

            // Đảm bảo role SuperAdmin tồn tại
            var roleManager = HttpContext.RequestServices.GetRequiredService<RoleManager<IdentityRole<Guid>>>();
            if (!await roleManager.RoleExistsAsync(nameof(Roles.SuperAdmin)))
            {
                await roleManager.CreateAsync(new IdentityRole<Guid>(nameof(Roles.SuperAdmin)));
            }

            var user = new ApplicationUser
            {
                Id = Guid.NewGuid(),
                UserName = request.Email,
                Email = request.Email,
                FirstName = request.FullName?.Split(' ').FirstOrDefault() ?? "Super",
                LastName = request.FullName?.Split(' ').Skip(1).FirstOrDefault() ?? "Admin",
                Role = nameof(Roles.SuperAdmin),
                EmailConfirmed = true,
                PhoneNumberConfirmed = true,
                LockoutEnabled = false,
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = "Setup"
            };

            var result = await _userManager.CreateAsync(user, request.Password);
            if (!result.Succeeded)
            {
                var errors = string.Join("; ", result.Errors.Select(e => e.Description));
                return BadRequest(AppResponse<string>.Fail($"Không thể tạo tài khoản: {errors}"));
            }

            await _userManager.AddToRoleAsync(user, nameof(Roles.SuperAdmin));

            return Ok(AppResponse<string>.Success($"Đã tạo tài khoản SuperAdmin: {request.Email}. Hãy đăng nhập tại trang Admin."));
        }
        catch (Exception ex)
        {
            return StatusCode(500, AppResponse<string>.Fail($"Lỗi hệ thống: {ex.Message}"));
        }
    }
}

public record SetupSuperAdminRequest(string Email, string Password, string? FullName);

