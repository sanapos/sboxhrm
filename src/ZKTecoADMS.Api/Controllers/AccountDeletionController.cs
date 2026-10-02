using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

public class DeleteMyAccountRequest
{
    public string Password { get; set; } = "";
    public string? Reason { get; set; }
}

/// <summary>
/// Người dùng tự xóa tài khoản trong ứng dụng (App Store 5.1.1(v)).
/// Tài khoản bị vô hiệu hóa ngay và thông tin định danh (email, tên đăng nhập, SĐT, họ tên) được ẩn danh;
/// dữ liệu chứng từ (hóa đơn, chấm công) của cửa hàng được giữ theo quy định pháp luật.
/// Nếu là chủ cửa hàng và không còn quản trị viên nào khác → cửa hàng cũng ngừng hoạt động.
/// </summary>
[ApiController]
[Route("api/account")]
public class AccountDeletionController(
    ZKTecoDbContext db,
    UserManager<ApplicationUser> userManager,
    ILogger<AccountDeletionController> logger) : AuthenticatedControllerBase
{
    [HttpGet("deletion-info")]
    [Authorize]
    public async Task<ActionResult<AppResponse<object>>> DeletionInfo()
    {
        var user = await userManager.FindByIdAsync(CurrentUserId.ToString());
        if (user == null) return Ok(AppResponse<object>.Fail("Không tìm thấy tài khoản"));
        var store = user.StoreId.HasValue ? await db.Stores.AsNoTracking().FirstOrDefaultAsync(s => s.Id == user.StoreId) : null;
        var isOwner = store != null && store.OwnerId == user.Id;
        var otherAdmins = isOwner && await OtherAdminsExistAsync(user);
        return Ok(AppResponse<object>.Success(new
        {
            isOwner,
            storeName = store?.Name,
            storeWillBeClosed = isOwner && !otherAdmins,
        }));
    }

    [HttpPost("delete-me")]
    [Authorize]
    public async Task<ActionResult<AppResponse<bool>>> DeleteMe([FromBody] DeleteMyAccountRequest request)
    {
        var user = await userManager.FindByIdAsync(CurrentUserId.ToString());
        if (user == null) return Ok(AppResponse<bool>.Fail("Không tìm thấy tài khoản"));
        if (string.Equals(user.Role, "SuperAdmin", StringComparison.OrdinalIgnoreCase))
            return Ok(AppResponse<bool>.Fail("Tài khoản quản trị hệ thống không thể tự xóa"));
        if (string.IsNullOrEmpty(request.Password) || !await userManager.CheckPasswordAsync(user, request.Password))
            return Ok(AppResponse<bool>.Fail("Mật khẩu không đúng"));

        var store = user.StoreId.HasValue ? await db.Stores.FirstOrDefaultAsync(s => s.Id == user.StoreId) : null;
        var closeStore = store != null && store.OwnerId == user.Id && !await OtherAdminsExistAsync(user);

        var tag = $"deleted_{user.Id:N}";
        logger.LogWarning("Account self-deletion: user {UserId} store {StoreId} closeStore={Close} reason={Reason}",
            user.Id, user.StoreId, closeStore, request.Reason);

        user.IsActive = false;
        user.Email = $"{tag}@deleted.local";
        user.NormalizedEmail = user.Email.ToUpperInvariant();
        user.UserName = tag;
        user.NormalizedUserName = tag.ToUpperInvariant();
        user.PhoneNumber = null;
        user.FirstName = "Tài khoản";
        user.LastName = "đã xóa";
        user.PlainTextPassword = null;
        user.LockoutEnabled = true;
        user.LockoutEnd = DateTimeOffset.MaxValue;
        user.SecurityStamp = Guid.NewGuid().ToString();
        var res = await userManager.UpdateAsync(user);
        if (!res.Succeeded)
            return Ok(AppResponse<bool>.Fail(string.Join("; ", res.Errors.Select(e => e.Description))));

        await db.UserRefreshTokens.IgnoreQueryFilters().Where(t => t.ApplicationUserId == user.Id).ExecuteDeleteAsync();
        await db.UserDeviceTokens.IgnoreQueryFilters().Where(t => t.UserId == user.Id).ExecuteDeleteAsync();

        if (closeStore)
        {
            store!.IsActive = false;
            await db.SaveChangesAsync();
        }
        return Ok(AppResponse<bool>.Success(true));
    }

    private async Task<bool> OtherAdminsExistAsync(ApplicationUser user) =>
        user.StoreId.HasValue && await db.Users.AnyAsync(u => u.StoreId == user.StoreId && u.Id != user.Id && u.IsActive
            && (u.Role == "Admin" || u.Role == "StoreOwner" || u.Role == "Director"));
}
