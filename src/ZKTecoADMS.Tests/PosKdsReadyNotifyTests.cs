using System.Reflection;
using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Bếp «Ra món» / «Xong» → người gọi món (phục vụ) nhận thông báo «Món đã xong».</summary>
public class PosKdsReadyNotifyTests
{
    public class CaptureProxy : DispatchProxy
    {
        public static readonly List<(List<Guid> To, string Title, string Message)> Sent = [];

        protected override object? Invoke(MethodInfo? m, object?[]? args)
        {
            if (m?.Name == nameof(ISystemNotificationService.CreateAndSendToUsersAsync) && args != null)
                lock (Sent)
                    Sent.Add((((IEnumerable<Guid>)args[0]!).ToList(), (string)args[2]!, (string)args[3]!));
            return Task.CompletedTask;
        }
    }

    readonly Guid _store = Guid.NewGuid();
    readonly Guid _kitchenUser = Guid.NewGuid();
    readonly Guid _waiter = Guid.NewGuid();
    readonly ServiceProvider _sp;
    readonly ZKTecoDbContext _db;

    public PosKdsReadyNotifyTests()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        _sp = services.BuildServiceProvider();
        _db = _sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        _db.Users.Add(new ApplicationUser
        {
            Id = _waiter, Email = "phucvu@test", UserName = "phucvu@test", StoreId = _store, IsActive = true,
            Role = nameof(Roles.Waiter), FirstName = "Vụ", LastName = "Phục",
        });
        _db.Users.Add(new ApplicationUser
        {
            Id = _kitchenUser, Email = "bep@test", UserName = "bep@test", StoreId = _store, IsActive = true,
            Role = nameof(Roles.Cashier), FirstName = "Bếp", LastName = "Trưởng",
        });
        _db.SaveChanges();
    }

    PosKdsController Ctl(ISystemNotificationService n) => new(_db, null!, n)
    {
        ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                RequestServices = _sp,
                User = new ClaimsPrincipal(new ClaimsIdentity([
                    new Claim("id", _kitchenUser.ToString()),
                    new Claim(ClaimTypes.Role, "Cashier"),
                    new Claim(ClaimTypes.Email, "bep@test"),
                    new Claim(ClaimTypeNames.StoreId, _store.ToString()),
                ], "test")),
            },
        },
    };

    (Guid OrderId, Guid LineId) AddSentLine(string orderedBy)
    {
        var table = new PosServiceResource { Id = Guid.NewGuid(), StoreId = _store, Name = "Bàn 5", IsActive = true };
        var order = new PosSaleOrder
        {
            Id = Guid.NewGuid(), StoreId = _store, OrderNo = "D1", Status = PosSaleOrderStatus.Draft,
            ServiceResourceId = table.Id, IsActive = true,
        };
        var line = new PosSaleOrderLine
        {
            Id = Guid.NewGuid(), StoreId = _store, SaleOrderId = order.Id, ProductId = Guid.NewGuid(),
            ProductName = "Bún chả", Qty = 2, KitchenSentQty = 2, KitchenPrepStatus = "queued",
            KitchenSentAt = DateTime.UtcNow, CreatedAt = DateTime.UtcNow, CreatedBy = orderedBy, IsActive = true,
        };
        _db.PosServiceResources.Add(table);
        _db.PosSaleOrders.Add(order);
        _db.PosSaleOrderLines.Add(line);
        _db.SaveChanges();
        return (order.Id, line.Id);
    }

    [Fact]
    public async Task ReadyLine_NotifiesWaiterOnce()
    {
        var notifications = DispatchProxy.Create<ISystemNotificationService, CaptureProxy>();
        var (_, lineId) = AddSentLine("PhucVu@test");
        lock (CaptureProxy.Sent) CaptureProxy.Sent.RemoveAll(s => s.To.Contains(_waiter));

        await Ctl(notifications).PrepLine(lineId, new PosKdsController.PrepDto { Status = "ready" });
        // Bấm «Xong» sau «Ra món» — món đã báo rồi, không gửi lại.
        await Ctl(notifications).PrepLine(lineId, new PosKdsController.PrepDto { Status = "done" });

        List<(List<Guid> To, string Title, string Message)> mine;
        lock (CaptureProxy.Sent) mine = CaptureProxy.Sent.Where(s => s.To.Contains(_waiter)).ToList();
        var sent = Assert.Single(mine);
        Assert.Equal([_waiter], sent.To);
        Assert.Equal("Món đã xong", sent.Title);
        Assert.Contains("Bàn 5", sent.Message);
        Assert.Contains("Bún chả ×2", sent.Message);
    }

    [Fact]
    public async Task Bump_DoesNotNotifyKitchenUserThemselves()
    {
        var notifications = DispatchProxy.Create<ISystemNotificationService, CaptureProxy>();
        var (orderId, _) = AddSentLine("bep@test");

        await Ctl(notifications).Bump(orderId);

        lock (CaptureProxy.Sent)
            Assert.DoesNotContain(CaptureProxy.Sent, s => s.To.Contains(_kitchenUser));
    }
}
