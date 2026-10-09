using ZKTecoADMS.Application.Authorization;
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
using Microsoft.EntityFrameworkCore;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Hosting;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[Route("api/[controller]/[action]")]
[ApiController]
public class AuthController(IMediator _bus, UserManager<ApplicationUser> _userManager, ZKTecoDbContext _dbContext, IWebHostEnvironment _env) : ControllerBase
{
    [HttpPost]
    [AllowAnonymous]
    [EnableRateLimiting("login")]
    public async Task<ActionResult<AppResponse<AuthenticateResponse>>> Login(LoginRequest loginRequest, CancellationToken cancellationToken = new())
    {
        var command = new LoginCommand(
            loginRequest.StoreCode,
            loginRequest.UserName,
            loginRequest.Password,
            loginRequest.ClientPlatform,
            loginRequest.DeviceKey,
            loginRequest.DeviceName);
        var result = await _bus.Send(command, cancellationToken);
        await AuditLoginAsync(loginRequest.StoreCode, loginRequest.UserName, result, cancellationToken);
        return result;
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
        var result = await _bus.Send(command, cancellationToken);
        await AuditLoginAsync(null, request.UserName, result, cancellationToken);
        return result;
    }

    /// <summary>
    /// Nhật ký hệ thống (Super Admin): đăng nhập thành công / sai. Không ghi mật khẩu.
    /// Không chặn đăng nhập nếu ghi lỗi.
    /// </summary>
    private async Task AuditLoginAsync(string? storeCode, string? userName, AppResponse<AuthenticateResponse> result, CancellationToken ct)
    {
        try
        {
            var login = (userName ?? "").Trim();
            if (login.Length > 200) login = login[..200];
            Store? store = null;
            if (!string.IsNullOrWhiteSpace(storeCode))
            {
                var code = storeCode.Trim().ToLower();
                store = await _dbContext.Stores.AsNoTracking().FirstOrDefaultAsync(s => s.Code.ToLower() == code, ct);
            }
            var user = string.IsNullOrEmpty(login)
                ? null
                : await _userManager.Users.AsNoTracking()
                    .Where(u => (u.UserName == login || u.Email == login || u.PhoneNumber == login)
                        && (store == null ? u.StoreId == null : u.StoreId == store.Id))
                    .Select(u => new { u.Id, u.Email, FullName = (u.LastName + " " + u.FirstName).Trim(), u.Role })
                    .FirstOrDefaultAsync(ct);
            var ok = result.IsSuccess;
            _dbContext.AuditLogs.Add(new AuditLog
            {
                Id = Guid.NewGuid(),
                Action = ok ? AuditActions.Login : AuditActions.LoginFailed,
                EntityType = AuditEntityTypes.User,
                EntityId = user?.Id.ToString(),
                EntityName = user?.Email ?? login,
                Details = ok
                    ? (store == null ? "Đăng nhập trang quản trị" : $"Đăng nhập cửa hàng «{store.Code}»")
                    : $"Đăng nhập thất bại{(store == null && !string.IsNullOrWhiteSpace(storeCode) ? $" — mã cửa hàng «{storeCode.Trim()}» không tồn tại" : "")}",
                UserId = user?.Id,
                UserEmail = user?.Email ?? login,
                UserName = user?.FullName,
                UserRole = user?.Role,
                StoreId = store?.Id,
                StoreName = store?.Name,
                IpAddress = ZKTecoADMS.Api.Services.ClientIp.Of(HttpContext),
                UserAgent = Request.Headers.UserAgent.ToString(),
                Timestamp = DateTime.UtcNow,
                Status = ok ? "Success" : "Failed",
                ErrorMessage = ok ? null : result.Message,
            });
            await _dbContext.SaveChangesAsync(ct);
        }
        catch
        {
            // Nhật ký không được làm hỏng đăng nhập.
        }
    }

    [HttpPost]
    [AllowAnonymous]
    [EnableRateLimiting("login")]
    public async Task<ActionResult<AppResponse<string>>> Register([FromBody] RegisterRequest registerRequest, CancellationToken cancellationToken = new())
    {
        var command = new RegisterCommand(registerRequest);  
        return Ok(await _bus.Send(command, cancellationToken));
    }

    [HttpGet]
    [AllowAnonymous]
    public async Task<ActionResult<AppResponse<object>>> PublicServicePackages(CancellationToken cancellationToken = default)
    {
        var rows = await _dbContext.ServicePackages
            .AsNoTracking()
            .Where(p => p.IsActive && p.IsPublic)
            .OrderBy(p => p.SortOrder)
            .ThenBy(p => p.Name)
            .ToListAsync(cancellationToken);

        var packages = rows.Select(p => new
        {
            p.Id,
            p.Name,
            p.Description,
            p.DefaultDurationDays,
            p.MaxUsers,
            p.MaxDevices,
            p.MaxAccessDevices,
            p.AllowWeb,
            p.AllowMobile,
            p.MaxBranches,
            p.AllowFcm,
            AllowedFcmCategories = Infrastructure.Helpers.StorePackageHelper.DeserializeModules(p.AllowedFcmCategories),
            AllowedModules = Infrastructure.Helpers.StorePackageHelper.DeserializeModules(p.AllowedModules),
            Modules = FeatureModuleCatalog.DescribePublicModules(
                Infrastructure.Helpers.StorePackageHelper.DeserializeModules(p.AllowedModules)),
            p.ProductLine,
            p.MonthlyPrice,
            p.YearlyPrice,
            p.TrialDays,
            p.IsFeatured,
            p.Badge,
            Highlights = string.IsNullOrWhiteSpace(p.Highlights)
                ? new List<string>()
                : p.Highlights.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList(),
        }).ToList();

        return Ok(AppResponse<object>.Success(packages));
    }

    [HttpPost]
    [AllowAnonymous]
    [EnableRateLimiting(ZKTecoADMS.Api.Services.RefreshTokenRateKey.Policy)]
    public async Task<IActionResult> Refresh(RefreshRequest refreshRequest, CancellationToken cancellationToken = new())
    {
       return Ok(await _bus.Send(new RefreshCommand(refreshRequest.RefreshToken, refreshRequest.DeviceKey), cancellationToken));
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
        // Trả danh sách claim (trước đây trả thẳng ClaimsPrincipal — dễ lỗi tuần tự hoá / lộ dữ liệu thừa)
        var claims = User.Claims
            .GroupBy(c => c.Type)
            .ToDictionary(g => g.Key, g => g.Count() == 1 ? (object)g.First().Value : g.Select(c => c.Value).ToList());
        return Task.FromResult<ActionResult>(Ok(AppResponse<object>.Success(claims)));
    }

    /// <summary>
    /// Màn đăng nhập: gõ mã cửa hàng → xác nhận tên cửa hàng (tránh gõ nhầm mã).
    /// Không trả gì nhạy cảm ngoài tên hiển thị.
    /// </summary>
    [HttpGet]
    [AllowAnonymous]
    [EnableRateLimiting("auth-lookup")]
    public async Task<ActionResult<AppResponse<object>>> StoreLookup([FromQuery] string code, CancellationToken ct = default)
    {
        var c = (code ?? "").Trim().ToLower();
        if (c.Length < 2) return Ok(AppResponse<object>.Success(new { exists = false }));
        var store = await _dbContext.Stores.AsNoTracking()
            .Where(x => x.Code.ToLower() == c)
            .Select(x => new { x.Name, x.IsActive, x.ExpiryDate })
            .FirstOrDefaultAsync(ct);
        if (store == null) return Ok(AppResponse<object>.Success(new { exists = false }));
        return Ok(AppResponse<object>.Success(new
        {
            exists = true,
            name = store.Name,
            active = store.IsActive,
            expired = store.ExpiryDate.HasValue && store.ExpiryDate.Value < DateTime.UtcNow,
        }));
    }

    /// <summary>Màn đăng ký: kiểm tra mã cửa hàng còn trống + gợi ý mã khác.</summary>
    [HttpGet]
    [AllowAnonymous]
    [EnableRateLimiting("auth-lookup")]
    public async Task<ActionResult<AppResponse<object>>> CheckStoreCode(
        [FromQuery] string? code, [FromQuery] string? storeName, [FromQuery] string? province, CancellationToken ct = default)
    {
        var normalized = Application.Services.StoreCodeRules.Sanitize(string.IsNullOrWhiteSpace(code) ? storeName : code);
        var error = Application.Services.StoreCodeRules.FormatError(normalized);
        var taken = await _dbContext.Stores.AsNoTracking().Select(x => x.Code.ToLower())
            .Where(x => x.StartsWith(normalized.Length > 3 ? normalized.Substring(0, 3) : normalized))
            .ToListAsync(ct);
        var takenSet = taken.ToHashSet();
        var available = error == null && !takenSet.Contains(normalized);
        var suggestions = available
            ? new List<string>()
            : Application.Services.StoreCodeRules.Suggest(normalized, storeName, province,
                c => takenSet.Contains(c) || _dbContext.Stores.Any(x => x.Code.ToLower() == c));
        return Ok(AppResponse<object>.Success(new
        {
            code = normalized,
            available,
            message = error ?? (available ? "Mã có thể sử dụng" : $"Mã «{normalized}» đã có cửa hàng khác dùng"),
            suggestions,
        }));
    }

    /// <summary>Màn đăng ký: email đã dùng để đăng ký cửa hàng khác chưa.</summary>
    [HttpGet]
    [AllowAnonymous]
    [EnableRateLimiting("auth-lookup")]
    public async Task<ActionResult<AppResponse<object>>> CheckEmail([FromQuery] string email, CancellationToken ct = default)
    {
        var e = (email ?? "").Trim();
        if (e.Length < 5 || !e.Contains('@')) return Ok(AppResponse<object>.Success(new { available = false, valid = false }));
        var used = await _userManager.FindByEmailAsync(e) != null;
        return Ok(AppResponse<object>.Success(new { available = !used, valid = true }));
    }

    /// <summary>
    /// Quên mật khẩu — gửi mã OTP 6 số qua email (hiệu lực 5 phút).
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

    /// <summary>
    /// DEV ONLY: Reset password for any user by username. Remove after use.
    /// </summary>
    [HttpPost]
    [AllowAnonymous]
    public async Task<ActionResult<AppResponse<string>>> DevResetPassword([FromBody] DevResetRequest request)
    {
        if (!_env.IsDevelopment())
            return NotFound();

        var user = await _userManager.FindByNameAsync(request.UserName);
        if (user == null)
            return NotFound(AppResponse<string>.Error("User not found"));

        // Unlock account
        user.LockoutEnd = null;
        user.AccessFailedCount = 0;
        await _userManager.UpdateAsync(user);

        var token = await _userManager.GeneratePasswordResetTokenAsync(user);
        var result = await _userManager.ResetPasswordAsync(user, token, request.NewPassword);
        if (!result.Succeeded)
            return BadRequest(AppResponse<string>.Error(string.Join(", ", result.Errors.Select(e => e.Description))));

        return Ok(AppResponse<string>.Success($"Password reset OK for {request.UserName}"));
    }
}

public record SetupSuperAdminRequest(string Email, string Password, string? FullName);
public record DevResetRequest(string UserName, string NewPassword);

