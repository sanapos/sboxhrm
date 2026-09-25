using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Abstractions;
using Microsoft.AspNetCore.Mvc.Controllers;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.Mvc.Routing;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers.Filters;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Agent chỉ được gọi API cổng đại lý và thiết bị của cửa hàng mình quản lý.</summary>
public class AgentApiScopeFilterTests
{
    static readonly Guid AgentUserId = Guid.NewGuid();

    static ZKTecoDbContext NewDb()
    {
        var options = new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        return new ZKTecoDbContext(options);
    }

    static ClaimsPrincipal Principal(string role, Guid userId) =>
        new(new ClaimsIdentity(
            [new Claim(ClaimTypes.Role, role), new Claim("id", userId.ToString())], "test"));

    static async Task<IActionResult?> Run(
        ZKTecoDbContext db,
        string role,
        string controller,
        string template = "",
        IDictionary<string, object?>? route = null,
        IDictionary<string, object?>? args = null,
        bool allowAnonymous = false)
    {
        var http = new DefaultHttpContext { User = Principal(role, AgentUserId) };
        var routeData = new RouteData();
        foreach (var (k, v) in route ?? new Dictionary<string, object?>()) routeData.Values[k] = v;
        var descriptor = new ControllerActionDescriptor
        {
            ControllerName = controller,
            ActionName = "Act",
            AttributeRouteInfo = new AttributeRouteInfo { Template = template },
            EndpointMetadata = allowAnonymous ? [new AllowAnonymousAttribute()] : [],
        };
        var ctx = new ActionExecutingContext(
            new ActionContext(http, routeData, descriptor),
            new List<IFilterMetadata>(),
            args ?? new Dictionary<string, object?>(),
            controller: new object());

        var nextCalled = false;
        await new AgentApiScopeFilter(db).OnActionExecutionAsync(ctx, () =>
        {
            nextCalled = true;
            return Task.FromResult(new ActionExecutedContext(ctx, new List<IFilterMetadata>(), new object()));
        });
        return nextCalled ? null : ctx.Result;
    }

    static void AssertForbidden(IActionResult? result) =>
        Assert.Equal(StatusCodes.Status403Forbidden, Assert.IsType<ObjectResult>(result).StatusCode);

    [Theory]
    [InlineData("Kpi")]
    [InlineData("Employees")]
    [InlineData("Branch")]
    [InlineData("SystemAdmin")]
    [InlineData("PosSales")]
    public async Task Agent_is_blocked_from_store_and_system_admin_apis(string controller)
    {
        using var db = NewDb();
        AssertForbidden(await Run(db, nameof(Roles.Agent), controller));
    }

    [Theory]
    [InlineData("Agent", "")]
    [InlineData("Notifications", "")]
    [InlineData("Auth", "")]
    [InlineData("Accounts", "api/[controller]/profile/password")]
    public async Task Agent_can_use_portal_apis(string controller, string template)
    {
        using var db = NewDb();
        Assert.Null(await Run(db, nameof(Roles.Agent), controller, template));
    }

    [Fact]
    public async Task Agent_cannot_manage_store_accounts()
    {
        using var db = NewDb();
        AssertForbidden(await Run(db, nameof(Roles.Agent), "Accounts", "api/[controller]/{id}/password"));
    }

    [Fact]
    public async Task Non_agent_roles_and_anonymous_endpoints_are_untouched()
    {
        using var db = NewDb();
        Assert.Null(await Run(db, nameof(Roles.Admin), "Kpi"));
        Assert.Null(await Run(db, nameof(Roles.Agent), "PublicSettings", allowAnonymous: true));
    }

    [Fact]
    public async Task Agent_device_access_is_limited_to_own_stores()
    {
        using var db = NewDb();
        var agent = new Agent { Id = Guid.NewGuid(), UserId = AgentUserId };
        var ownStore = new Store { Id = Guid.NewGuid(), AgentId = agent.Id };
        var otherStore = new Store { Id = Guid.NewGuid(), AgentId = Guid.NewGuid() };
        var ownDevice = new Device { Id = Guid.NewGuid(), StoreId = ownStore.Id };
        var otherDevice = new Device { Id = Guid.NewGuid(), StoreId = otherStore.Id };
        db.AddRange(agent, ownStore, otherStore, ownDevice, otherDevice);
        await db.SaveChangesAsync();

        Assert.Null(await Run(db, nameof(Roles.Agent), "DeviceCommands",
            route: new Dictionary<string, object?> { ["deviceId"] = ownDevice.Id }));
        AssertForbidden(await Run(db, nameof(Roles.Agent), "DeviceCommands",
            route: new Dictionary<string, object?> { ["deviceId"] = otherDevice.Id }));
        AssertForbidden(await Run(db, nameof(Roles.Agent), "Devices",
            route: new Dictionary<string, object?> { ["id"] = otherDevice.Id }));
        Assert.Null(await Run(db, nameof(Roles.Agent), "DeviceUsers",
            args: new Dictionary<string, object?> { ["request"] = new { DeviceId = ownDevice.Id } }));
        // Không xác định được thiết bị (vd. danh sách tất cả) → chặn.
        AssertForbidden(await Run(db, nameof(Roles.Agent), "Devices"));
    }
}
