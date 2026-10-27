using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Core.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// DbContext của app mặc định NoTracking: đọc bản ghi rồi sửa phải dùng AsTracking, không thì SaveChanges không ghi gì
/// (trạng thái lệnh máy chấm công, yêu cầu tư vấn… trước đây đều «sửa xong vẫn như cũ»).
/// </summary>
public class UntrackedUpdateTests
{
    // Cùng cấu hình theo dõi như production (Infrastructure/DependencyInjectionExtensions.cs).
    static ZKTecoDbContext NewDb(string name) => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(name)
        .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
        .Options);

    [Fact]
    public async Task Trang_thai_lenh_may_cham_cong_duoc_luu()
    {
        var name = Guid.NewGuid().ToString();
        await using (var db = NewDb(name))
        {
            db.DeviceCommands.Add(new DeviceCommand { Id = Guid.NewGuid(), DeviceId = Guid.NewGuid(), CommandId = 42, Command = "DATA QUERY USERINFO" });
            await db.SaveChangesAsync();
        }
        await using (var db = NewDb(name))
        {
            await new DeviceService(null!, NullLogger<DeviceService>.Instance, db)
                .UpdateCommandStatusAsync(42, CommandStatus.Success, "OK", null);
        }
        await using var check = NewDb(name);
        var cmd = await check.DeviceCommands.SingleAsync(c => c.CommandId == 42);
        // Trước đây lệnh mãi ở «Created» dù máy đã trả kết quả.
        Assert.Equal(CommandStatus.Success, cmd.Status);
        Assert.Equal("OK", cmd.ResponseData);
        Assert.NotNull(cmd.CompletedAt);
    }

    [Fact]
    public async Task Cap_nhat_yeu_cau_tu_van_duoc_luu()
    {
        var name = Guid.NewGuid().ToString();
        var id = Guid.NewGuid();
        await using (var db = NewDb(name))
        {
            db.ConsultationRequests.Add(new ConsultationRequest { Id = id, Name = "Lan", Phone = "0900000000", IsActive = true });
            await db.SaveChangesAsync();
        }
        await using (var db = NewDb(name))
        {
            var controller = new ConsultationRequestsAdminController(db)
            {
                ControllerContext = new ControllerContext
                {
                    HttpContext = new DefaultHttpContext
                    {
                        User = new ClaimsPrincipal(new ClaimsIdentity(
                        [
                            new Claim("id", Guid.NewGuid().ToString()), new Claim(ClaimTypes.Role, "SuperAdmin"),
                            new Claim(ClaimTypes.Email, "admin@test.local"),
                        ], "test")),
                    },
                },
            };
            await controller.Update(id, new ConsultationRequestsAdminController.UpdateConsultationRequestDto("Contacted", "Đã gọi"));
        }
        await using var check = NewDb(name);
        var r = await check.ConsultationRequests.SingleAsync(x => x.Id == id);
        Assert.Equal("Contacted", r.Status);
        Assert.Equal("Đã gọi", r.AdminNote);
    }
}
