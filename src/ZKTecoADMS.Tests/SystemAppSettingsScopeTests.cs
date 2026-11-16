using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Controllers;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Thiết lập cấp hệ thống (StoreId = null) và thiết lập riêng của cửa hàng dùng chung bảng AppSettings,
/// khóa duy nhất là (StoreId, Key). Các màn hệ thống phải làm việc đúng trên dòng StoreId = null:
/// không đọc, không ghi đè và không vỡ vì dòng trùng khóa của cửa hàng.
/// </summary>
public class SystemAppSettingsScopeTests
{
    sealed class PassThroughCache : ICacheService
    {
        public async Task<T?> GetOrCreateAsync<T>(string key, Func<Task<T>> factory, TimeSpan? expiration = null)
            => await factory();
        public void Remove(string key) { }
        public void RemoveByPrefix(string prefix) { }
    }

    static ZKTecoDbContext Db() => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString())
        .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
        .Options);

    /// <summary>Tài khoản hệ thống: có claim id nhưng KHÔNG có storeId.</summary>
    static ControllerContext SystemUser() => new()
    {
        HttpContext = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(
            [
                new Claim("id", Guid.NewGuid().ToString()),
                new Claim(ClaimTypes.Role, nameof(Roles.SuperAdmin)),
            ], "t")),
        },
        ActionDescriptor = new ControllerActionDescriptor(),
    };

    static AppSettings StoreRow(string key, string? value, Guid storeId) => new()
    {
        Id = Guid.NewGuid(),
        Key = key,
        Value = value,
        Group = "Salary",
        StoreId = storeId,
        CreatedAt = new DateTime(2026, 2, 1),
    };

    [Fact]
    public async Task Tai_khoan_he_thong_luu_thiet_lap_khong_ghi_de_dong_cua_cua_hang()
    {
        using var db = Db();
        var store = Guid.NewGuid();
        db.AppSettings.Add(StoreRow("overtime_rate", "1.5", store));
        await db.SaveChangesAsync();

        var ctl = new SettingsController(null!, db) { ControllerContext = SystemUser() };
        var result = await ctl.UpsertAppSetting(new UpsertAppSettingRequest(
            "overtime_rate", "9.9", null, "General", "string", 0, false));

        Assert.IsType<OkObjectResult>(result.Result);

        // Dòng của cửa hàng giữ nguyên giá trị cũ, dòng cấp hệ thống được tạo mới.
        var rows = await db.AppSettings.AsNoTracking().Where(s => s.Key == "overtime_rate").ToListAsync();
        Assert.Equal(2, rows.Count);
        Assert.Equal("1.5", Assert.Single(rows, r => r.StoreId == store).Value);
        Assert.Equal("9.9", Assert.Single(rows, r => r.StoreId == null).Value);
    }

    [Fact]
    public async Task Tai_khoan_he_thong_doc_setting_khong_thay_dong_cua_cua_hang()
    {
        using var db = Db();
        db.AppSettings.Add(StoreRow("overtime_rate", "1.5", Guid.NewGuid()));
        await db.SaveChangesAsync();

        var ctl = new SettingsController(null!, db) { ControllerContext = SystemUser() };
        var result = await ctl.GetAppSetting("overtime_rate", new AllowAllPermissions());

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        var body = Assert.IsType<AppResponse<AppSettingsDto>>(ok.Value);
        // Không có dòng cấp hệ thống ⇒ trả giá trị rỗng, KHÔNG trả 1.5 của cửa hàng.
        Assert.Equal(string.Empty, body.Data!.Value);
        Assert.Equal(Guid.Empty, body.Data.Id);
    }

    [Fact]
    public async Task Luu_hang_loat_thiet_lap_he_thong_khong_vo_khi_nhieu_cua_hang_cung_khoa()
    {
        using var db = Db();
        db.AppSettings.AddRange(
            StoreRow("overtime_rate", "1.5", Guid.NewGuid()),
            StoreRow("overtime_rate", "2.0", Guid.NewGuid()));
        await db.SaveChangesAsync();

        var ctl = Admin(db);
        var result = await ctl.UpdateSettingsBatch(new UpdateAppSettingsRequest(
            [new AppSettingItem("overtime_rate", "3.0")]));

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        Assert.True(Assert.IsType<AppResponse<bool>>(ok.Value).IsSuccess);

        var rows = await db.AppSettings.AsNoTracking().Where(s => s.Key == "overtime_rate").ToListAsync();
        Assert.Equal(3, rows.Count);
        Assert.Equal("3.0", Assert.Single(rows, r => r.StoreId == null).Value);
        // Hai dòng của cửa hàng không bị sửa.
        Assert.Equal(["1.5", "2.0"], rows.Where(r => r.StoreId != null).Select(r => r.Value).Order().ToArray());
    }

    [Fact]
    public async Task Danh_sach_thiet_lap_he_thong_khong_lan_dong_cua_cua_hang()
    {
        using var db = Db();
        db.AppSettings.AddRange(
            StoreRow("overtime_rate", "1.5", Guid.NewGuid()),
            new AppSettings
            {
                Id = Guid.NewGuid(), Key = AppSettingKeys.CompanyName, Value = "SBOX",
                Group = "General", StoreId = null, CreatedAt = new DateTime(2026, 1, 1),
            });
        await db.SaveChangesAsync();

        var result = await Admin(db).GetAllSettings();

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        var items = Assert.IsType<AppResponse<List<AppSettingsDto>>>(ok.Value).Data!;
        Assert.Equal(AppSettingKeys.CompanyName, Assert.Single(items).Key);
    }

    static SystemAdminController Admin(ZKTecoDbContext db) =>
        new(db, null!, null!, NullLogger<SystemAdminController>.Instance, null!,
            new PassThroughCache(), null!, null!, null!)
        {
            ControllerContext = SystemUser(),
        };

    /// <summary>Cho qua kiểm quyền module — test này chỉ xét phạm vi StoreId của truy vấn.</summary>
    sealed class AllowAllPermissions : IModulePermissionService
    {
        public Task<IReadOnlyDictionary<string, ModulePermissionDto>> GetEffectivePermissionsAsync(
            Guid userId, string role, Guid? storeId, CancellationToken cancellationToken = default)
            => Task.FromResult<IReadOnlyDictionary<string, ModulePermissionDto>>(
                new Dictionary<string, ModulePermissionDto>());

        public Task<bool> HasPermissionAsync(Guid userId, string role, Guid? storeId, string module,
            ModulePermissionAction action, CancellationToken cancellationToken = default)
            => Task.FromResult(true);
    }
}
