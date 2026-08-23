using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Xác thực nhạy cảm POS (vd. trả bàn trống cần mật khẩu chủ CH).</summary>
[ApiController]
[Route("api/pos/security")]
[Authorize]
public sealed class PosSecurityController(
    ZKTecoDbContext db,
    UserManager<ApplicationUser> userManager) : AuthenticatedControllerBase
{
    public record VerifyOwnerPasswordRequest(string? Password);

    static readonly string[] OwnerRoles =
    [
        "StoreOwner",
        "Admin",
        "Director",
        "Manager",
    ];

    /// <summary>
    /// Xác nhận mật khẩu thuộc tài khoản chủ cửa hàng / quản lý của store hiện tại.
    /// Không đổi session đăng nhập của thu ngân.
    /// </summary>
    [HttpPost("verify-owner-password")]
    [EnableRateLimiting("login")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> VerifyOwnerPassword(
        [FromBody] VerifyOwnerPasswordRequest req,
        CancellationToken ct = default)
    {
        var storeId = CurrentStoreId;
        if (storeId == null || storeId == Guid.Empty)
        {
            return Ok(AppResponse<object>.Fail("Không xác định được cửa hàng"));
        }

        var password = (req.Password ?? "").Trim();
        if (password.Length < 1)
        {
            return Ok(AppResponse<object>.Fail("Vui lòng nhập mật khẩu chủ cửa hàng"));
        }

        var candidates = await db.Users.AsNoTracking()
            .Where(u => u.StoreId == storeId
                        && u.IsActive
                        && u.Role != null
                        && OwnerRoles.Contains(u.Role))
            .OrderBy(u => u.Role == "StoreOwner" ? 0
                : u.Role == "Admin" ? 1
                : u.Role == "Director" ? 2
                : 3)
            .ThenBy(u => u.Email)
            .ToListAsync(ct);

        if (candidates.Count == 0)
        {
            return Ok(AppResponse<object>.Fail(
                "Cửa hàng chưa có tài khoản chủ / quản lý để xác nhận"));
        }

        foreach (var user in candidates)
        {
            // CheckPasswordAsync cần tracked/full user từ UserManager.
            var full = await userManager.FindByIdAsync(user.Id.ToString());
            if (full == null) continue;
            if (await userManager.CheckPasswordAsync(full, password))
            {
                return Ok(AppResponse<object>.Success(new
                {
                    verified = true,
                    verifiedByRole = full.Role,
                }));
            }
        }

        return Ok(AppResponse<object>.Fail("Mật khẩu chủ cửa hàng không đúng"));
    }
}
