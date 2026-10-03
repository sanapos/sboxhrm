using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Nhật ký hệ thống Super Admin: lọc tại server theo cửa hàng / tài khoản / nhóm thao tác, nội dung tiếng Việt.</summary>
public class SystemAdminAuditTests
{
    static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    readonly ZKTecoDbContext _db = new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
    readonly Guid _storeA = Guid.NewGuid();
    readonly Guid _storeB = Guid.NewGuid();
    readonly Guid _userA = Guid.NewGuid();

    SystemAdminAuditController Ctl() => new(_db)
    {
        ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                User = new ClaimsPrincipal(new ClaimsIdentity([
                    new Claim("id", Guid.NewGuid().ToString()),
                    new Claim(ClaimTypes.Role, "SuperAdmin"),
                ], "test")),
            },
        },
    };

    static JsonElement Data(object? result)
    {
        var ok = Assert.IsType<OkObjectResult>(result);
        return JsonDocument.Parse(JsonSerializer.Serialize(ok.Value, Json)).RootElement.GetProperty("data");
    }

    void Seed()
    {
        _db.Stores.AddRange(
            new Store { Id = _storeA, Name = "Cửa hàng A", Code = "cha" },
            new Store { Id = _storeB, Name = "Cửa hàng B", Code = "chb" });
        var now = DateTime.UtcNow;
        _db.AuditLogs.AddRange(
            new AuditLog
            {
                Id = Guid.NewGuid(), Action = "Create", EntityType = "Employee", EntityName = "Nhân viên «87»",
                Details = "{\"source\":\"StoreActivity\",\"endpoint\":\"POST /api/Employees\",\"changes\":[{\"type\":\"Employee\",\"op\":\"Create\",\"label\":\"87\",\"fields\":[{\"field\":\"FirstName\",\"new\":\"An\"}]}]}",
                UserId = _userA, UserEmail = "ql@a.vn", UserName = "Quản lý A", UserRole = "Manager",
                StoreId = _storeA, StoreName = "Cửa hàng A", Timestamp = now.AddMinutes(-3), UserAgent = "Dart/3.5 (dart:io) android",
            },
            new AuditLog
            {
                Id = Guid.NewGuid(), Action = "Login", EntityType = "User", EntityName = "ql@a.vn",
                Details = "Đăng nhập cửa hàng «cha»", UserId = _userA, UserEmail = "ql@a.vn",
                StoreId = _storeA, StoreName = "Cửa hàng A", Timestamp = now.AddMinutes(-2),
            },
            new AuditLog
            {
                Id = Guid.NewGuid(), Action = "LoginFailed", EntityType = "User", EntityName = "x@b.vn",
                Details = "Đăng nhập thất bại", UserEmail = "x@b.vn", StoreId = _storeB, StoreName = "Cửa hàng B",
                Timestamp = now.AddMinutes(-1), Status = "Failed", ErrorMessage = "Tên đăng nhập hoặc mật khẩu không đúng.",
            });
        _db.SaveChanges();
    }

    [Fact]
    public async Task Filters_by_store_user_and_kind_on_server()
    {
        Seed();
        var ctl = Ctl();

        var all = Data((await ctl.List(null, null, null, null, null, null, null, null, null)).Result);
        Assert.Equal(3, all.GetProperty("total").GetInt32());
        Assert.Equal(1, all.GetProperty("failed").GetInt32());

        var storeA = Data((await ctl.List(_storeA, null, null, null, null, null, null, null, null)).Result);
        Assert.Equal(2, storeA.GetProperty("total").GetInt32());

        var auth = Data((await ctl.List(null, null, null, "auth", null, null, null, null, null)).Result);
        Assert.Equal(2, auth.GetProperty("total").GetInt32());

        var byUser = Data((await ctl.List(null, _userA, null, "data", null, null, null, null, null)).Result);
        var row = Assert.Single(byUser.GetProperty("items").EnumerateArray());
        Assert.Equal("Thêm", row.GetProperty("actionName").GetString());
        Assert.Contains("87", row.GetProperty("summary").GetString());
        Assert.Equal("App Android", row.GetProperty("device").GetString());

        var failed = Data((await ctl.List(null, null, null, null, null, "Failed", null, null, "x@b")).Result);
        var f = Assert.Single(failed.GetProperty("items").EnumerateArray());
        Assert.Equal("Đăng nhập sai", f.GetProperty("actionName").GetString());
        Assert.Equal("Cửa hàng B", f.GetProperty("storeName").GetString());
    }

    [Fact]
    public async Task Filter_options_list_stores_users_and_vietnamese_actions()
    {
        Seed();
        var data = Data((await Ctl().Filters(null, null, null)).Result);
        Assert.Equal(2, data.GetProperty("stores").GetArrayLength());
        Assert.Contains(data.GetProperty("actions").EnumerateArray(), a => a.GetProperty("name").GetString() == "Đăng nhập sai");
        // Chọn cửa hàng A → chỉ còn tài khoản của A
        var scoped = Data((await Ctl().Filters(_storeA, null, null)).Result);
        var u = Assert.Single(scoped.GetProperty("users").EnumerateArray());
        Assert.Equal("Quản lý A", u.GetProperty("name").GetString());
    }
}
