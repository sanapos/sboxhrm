using System.Reflection;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Thiết bị chấm công Mobile: hộp cần duyệt gộp, NV tự hủy yêu cầu, chỉnh hàng loạt, chưa đăng ký.</summary>
public class MobileDeviceHubTests
{
    /// <summary>Thông báo giả: mọi hàm trả Task hoàn tất.</summary>
    public class NoopProxy : DispatchProxy
    {
        protected override object? Invoke(MethodInfo? m, object?[]? args)
        {
            var t = m!.ReturnType;
            if (t == typeof(Task)) return Task.CompletedTask;
            if (t.IsGenericType && t.GetGenericTypeDefinition() == typeof(Task<>))
            {
                var inner = t.GetGenericArguments()[0];
                var def = inner.IsValueType ? Activator.CreateInstance(inner) : null;
                return typeof(Task).GetMethod(nameof(Task.FromResult))!.MakeGenericMethod(inner).Invoke(null, [def]);
            }
            return t.IsValueType ? Activator.CreateInstance(t) : null;
        }
    }

    readonly Guid _store = Guid.NewGuid();
    readonly ZKTecoDbContext _db;
    readonly IServiceProvider _sp;

    public MobileDeviceHubTests()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        _sp = services.BuildServiceProvider();
        _db = _sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
    }

    MobileDeviceHubController Ctl(Guid userId)
    {
        var c = new MobileDeviceHubController(_db, DispatchProxy.Create<ISystemNotificationService, NoopProxy>());
        var http = new DefaultHttpContext
        {
            RequestServices = _sp,
            User = new ClaimsPrincipal(new ClaimsIdentity([
                new Claim("id", userId.ToString()),
                new Claim(ClaimTypeNames.StoreId, _store.ToString()),
                new Claim(ClaimTypes.Email, "ql@test.vn"),
            ], "test")),
        };
        c.ControllerContext = new ControllerContext { HttpContext = http };
        return c;
    }

    Employee Emp(string code, string first, Guid? userId = null) => new()
    {
        Id = Guid.NewGuid(), StoreId = _store, EmployeeCode = code, FirstName = first, LastName = "Nguyễn",
        ApplicationUserId = userId,
    };

    static JsonElement Data(object? result)
    {
        var ok = Assert.IsType<OkObjectResult>(result);
        var json = JsonSerializer.Serialize(ok.Value, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
        var root = JsonDocument.Parse(json).RootElement;
        Assert.True(root.GetProperty("isSuccess").GetBoolean(), json);
        return root.GetProperty("data");
    }

    [Fact]
    public async Task Inbox_merges_new_registrations_and_device_changes()
    {
        var a = Emp("NV01", "An", Guid.NewGuid());
        var b = Emp("NV02", "Bình");
        _db.AddRange(a, b);
        var loc = new MobileWorkLocation { Id = Guid.NewGuid(), StoreId = _store, Name = "Kho Q7" };
        _db.Add(loc);
        // Đăng ký mới (lưu mã user) + ảnh mặt
        _db.Add(new AuthorizedMobileDevice
        {
            Id = Guid.NewGuid(), StoreId = _store, DeviceId = "hw-a", DeviceName = "iPhone 15", EmployeeId = a.ApplicationUserId.ToString(),
            IsAuthorized = false, SelectedLocationIdsJson = $"[\"{loc.Id}\"]",
        });
        _db.Add(new MobileFaceRegistration { Id = Guid.NewGuid(), StoreId = _store, OdooEmployeeId = a.ApplicationUserId.ToString()!, FaceImagesJson = "[\"wwwroot\\\\uploads\\\\f1.jpg\"]" });
        // Máy đã duyệt + yêu cầu đổi máy
        var old = new AuthorizedMobileDevice { Id = Guid.NewGuid(), StoreId = _store, DeviceId = "hw-b", DeviceName = "Galaxy A5", EmployeeId = b.Id.ToString(), IsAuthorized = true };
        _db.Add(old);
        _db.Add(new DeviceChangeRequest
        {
            Id = Guid.NewGuid(), StoreId = _store, EmployeeId = b.Id.ToString(), EmployeeName = "Bình", OldDeviceRecordId = old.Id,
            OldDeviceName = "Galaxy A5", NewDeviceId = "hw-c", NewDeviceName = "Galaxy S24", Reason = "Máy cũ hỏng", Status = 0,
        });
        await _db.SaveChangesAsync();

        var data = Data((await Ctl(Guid.NewGuid()).Inbox()).Result);
        Assert.Equal(2, data.GetProperty("counts").GetProperty("total").GetInt32());
        var items = data.GetProperty("items").EnumerateArray().ToList();
        var reg = items.Single(i => i.GetProperty("kind").GetString() == "register");
        Assert.Equal("Nguyễn An", reg.GetProperty("employee").GetProperty("employeeName").GetString());
        Assert.Equal("/uploads/f1.jpg", reg.GetProperty("faceImages")[0].GetString());
        Assert.Equal("Kho Q7", reg.GetProperty("locations")[0].GetString());
        var chg = items.Single(i => i.GetProperty("kind").GetString() == "change");
        Assert.Equal("Galaxy A5", chg.GetProperty("oldDeviceName").GetString());
        Assert.Equal("Máy cũ hỏng", chg.GetProperty("reason").GetString());

        // Nhân viên chưa đăng ký: chỉ ra người chưa có máy được duyệt
        var unreg = Data((await Ctl(Guid.NewGuid()).Unregistered()).Result).EnumerateArray().ToList();
        Assert.Single(unreg);
        Assert.Equal("NV01", unreg[0].GetProperty("employeeCode").GetString());
        Assert.True(unreg[0].GetProperty("pending").GetBoolean());
    }

    [Fact]
    public async Task Employee_cancels_only_own_pending_request()
    {
        var me = Guid.NewGuid();
        var mine = Emp("NV10", "Châu", me);
        var other = Emp("NV11", "Dũng", Guid.NewGuid());
        _db.AddRange(mine, other);
        var myDev = new AuthorizedMobileDevice { Id = Guid.NewGuid(), StoreId = _store, DeviceId = "x", EmployeeId = mine.Id.ToString(), IsAuthorized = false };
        var otherDev = new AuthorizedMobileDevice { Id = Guid.NewGuid(), StoreId = _store, DeviceId = "y", EmployeeId = other.Id.ToString(), IsAuthorized = false };
        _db.AddRange(myDev, otherDev);
        await _db.SaveChangesAsync();

        var refused = (await Ctl(me).CancelMine(new() { EmployeeId = other.Id.ToString() })).Result;
        Assert.Contains("người khác", JsonSerializer.Serialize(((OkObjectResult)refused!).Value, new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));

        var data = Data((await Ctl(me).CancelMine(new() { EmployeeId = mine.Id.ToString() })).Result);
        Assert.Equal(1, data.GetProperty("cancelled").GetInt32());
        Assert.False(await _db.AuthorizedMobileDevices.AnyAsync(d => d.Id == myDev.Id));   // đã xóa mềm
        Assert.True(await _db.AuthorizedMobileDevices.AnyAsync(d => d.Id == otherDev.Id));
    }

    [Fact]
    public async Task Bulk_updates_only_given_flags()
    {
        var d1 = new AuthorizedMobileDevice { Id = Guid.NewGuid(), StoreId = _store, DeviceId = "1", IsAuthorized = true, CanUseGps = true, AllowOutsideCheckIn = false };
        var d2 = new AuthorizedMobileDevice { Id = Guid.NewGuid(), StoreId = _store, DeviceId = "2", IsAuthorized = true, CanUseGps = false, AllowOutsideCheckIn = false };
        _db.AddRange(d1, d2);
        await _db.SaveChangesAsync();

        Data((await Ctl(Guid.NewGuid()).Bulk(new() { Ids = [d1.Id, d2.Id], AllowOutsideCheckIn = true, RequireOutsideReason = true })).Result);
        var after = await _db.AuthorizedMobileDevices.ToDictionaryAsync(d => d.Id);
        Assert.True(after[d1.Id].AllowOutsideCheckIn && after[d2.Id].AllowOutsideCheckIn);
        Assert.True(after[d1.Id].RequireOutsideReason);
        Assert.True(after[d1.Id].CanUseGps);    // không gửi → giữ nguyên
        Assert.False(after[d2.Id].CanUseGps);
    }

    [Fact]
    public void Image_paths_are_relative()
    {
        Assert.Equal("/uploads/a.jpg", MobileDeviceHubController.NormalizeImagePath("wwwroot/uploads/a.jpg"));
        Assert.Equal("/uploads/a.jpg", MobileDeviceHubController.NormalizeImagePath("https://x.vn/uploads/a.jpg"));
        Assert.Equal("/uploads/a.jpg", MobileDeviceHubController.NormalizeImagePath("uploads\\a.jpg"));
    }
}
