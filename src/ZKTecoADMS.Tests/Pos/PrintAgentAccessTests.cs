using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Middlewares;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Helpers;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Thiết lập máy in / Print Agent: nhân viên order không bật Agent trên máy mới; gói không có «Máy in cloud»
/// thì máy nhân viên không gửi lệnh in cloud (Agent vẫn chạy cho QR order); cửa hàng đang dùng Agent được giữ.
/// </summary>
[Collection("pos-pg")]
public class PrintAgentAccessTests(PosPgFixture fx)
{
    /// <summary>Chỉ trả lời quyền Sửa «Máy in» — đủ cho kiểm tra đăng ký Agent.</summary>
    sealed class PrinterEditPerm(bool canEdit) : IModulePermissionService
    {
        public Task<IReadOnlyDictionary<string, ModulePermissionDto>> GetEffectivePermissionsAsync(
            Guid userId, string role, Guid? storeId, CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyDictionary<string, ModulePermissionDto>>(
                new Dictionary<string, ModulePermissionDto>());

        public Task<bool> HasPermissionAsync(Guid userId, string role, Guid? storeId, string module,
            ModulePermissionAction action, CancellationToken cancellationToken = default) =>
            Task.FromResult(canEdit && module == "PosPrinters" && action == ModulePermissionAction.Edit);
    }

    PosPrintJobsController Jobs(Infrastructure.ZKTecoDbContext db, Guid store, bool canEditPrinters, string role) =>
        PosPgFixture.As(new PosPrintJobsController(db,
            new PosPrintDispatchService(db, new PosPrintDispatchTests.NullHub(),
                NullLogger<PosPrintDispatchService>.Instance),
            new PrinterEditPerm(canEditPrinters)), store, role);

    async Task<(Guid Store, Guid Printer)> StoreWithPrinterAsync()
    {
        var store = await fx.NewStoreAsync();
        var printer = Guid.NewGuid();
        await using var db = fx.NewDb();
        db.PosStorePrinters.Add(new PosStorePrinter
        {
            Id = printer, StoreId = store, Name = "Bếp", ConnectionType = PosPrinterConnectionType.Lan,
            LanHost = "192.168.1.50", IsActive = true,
        });
        await db.SaveChangesAsync();
        return (store, printer);
    }

    static int? StatusOf<T>(ActionResult<T> r) => r.Result switch
    {
        ObjectResult o => o.StatusCode ?? 200,
        _ => null,
    };

    [Fact]
    public async Task Order_khong_bat_duoc_Agent_tren_may_moi()
    {
        if (fx.ConnectionString == null) return;
        var (store, printer) = await StoreWithPrinterAsync();
        await using var db = fx.NewDb();
        var res = await Jobs(db, store, canEditPrinters: false, role: "Waiter")
            .RegisterAgent(new PosPrintJobsController.AgentRegisterDto("phone-order", "Điện thoại", null, [printer], "1.0"));
        Assert.Equal(StatusCodes.Status403Forbidden, StatusOf(res));
        Assert.False(await db.PosPrintAgents.AnyAsync(a => a.StoreId == store));
    }

    [Fact]
    public async Task Quan_ly_bat_Agent_roi_thu_ngan_van_heartbeat_duoc()
    {
        if (fx.ConnectionString == null) return;
        var (store, printer) = await StoreWithPrinterAsync();
        await using var db = fx.NewDb();
        var dto = new PosPrintJobsController.AgentRegisterDto("may-quay", "Máy quầy", null, [printer], "1.0");

        var byManager = await Jobs(db, store, canEditPrinters: true, role: "Manager").RegisterAgent(dto);
        Assert.Equal(StatusCodes.Status200OK, StatusOf(byManager));

        // Máy quầy đã là Agent (QR order / Tingee in qua đây) — thu ngân / order đăng nhập vẫn chạy tiếp.
        var byCashier = await Jobs(db, store, canEditPrinters: false, role: "Cashier").RegisterAgent(dto);
        Assert.Equal(StatusCodes.Status200OK, StatusOf(byCashier));
    }

    async Task<Guid> StoreWithPackageAsync(IEnumerable<string> modules, string? extra = null, string? blocked = null)
    {
        var store = await fx.NewStoreAsync();
        await using var db = fx.NewDb();
        var pkg = new ServicePackage
        {
            Id = Guid.NewGuid(), Name = "Gói " + store.ToString("N")[..6], IsActive = true,
            AllowedModules = JsonSerializer.Serialize(modules),
        };
        db.ServicePackages.Add(pkg);
        await db.SaveChangesAsync();
        await db.Stores.Where(s => s.Id == store).ExecuteUpdateAsync(s => s
            .SetProperty(x => x.ServicePackageId, pkg.Id)
            .SetProperty(x => x.ExtraModules, extra)
            .SetProperty(x => x.BlockedModules, blocked));
        return store;
    }

    static readonly string[] BasicPos = ["PosSell", "PosProducts", "PosPrinters", "PosPrintTemplates"];

    async Task<int> CallAsync(Guid store, string method, string path)
    {
        var http = new DefaultHttpContext
        {
            User = new ClaimsPrincipal(new ClaimsIdentity(
            [
                new Claim("storeId", store.ToString()),
                new Claim(ClaimTypes.Role, "Waiter"),
            ], "test")),
        };
        http.Request.Method = method;
        http.Request.Path = path;
        var passed = false;
        var mw = new StorePackageModuleMiddleware(_ => { passed = true; return Task.CompletedTask; },
            NullLogger<StorePackageModuleMiddleware>.Instance);
        await using var db = fx.NewDb();
        using var cache = new MemoryCache(new MemoryCacheOptions { SizeLimit = 10000 });
        await mw.InvokeAsync(http, db, cache);
        return passed ? StatusCodes.Status200OK : http.Response.StatusCode;
    }

    [Fact]
    public async Task Goi_khong_co_may_in_cloud_chi_chan_may_nhan_vien_gui_lenh_in()
    {
        if (fx.ConnectionString == null) return;
        var store = await StoreWithPackageAsync(BasicPos);

        Assert.Equal(StatusCodes.Status403Forbidden, await CallAsync(store, "POST", "/api/pos/print-jobs"));
        // Agent vẫn chạy: đăng ký, nhận lệnh QR order; hàng đợi / in lại vẫn mở.
        Assert.Equal(StatusCodes.Status200OK, await CallAsync(store, "POST", "/api/pos/print-jobs/agents/register"));
        Assert.Equal(StatusCodes.Status200OK, await CallAsync(store, "GET", "/api/pos/print-jobs/queue"));
        Assert.Equal(StatusCodes.Status200OK, await CallAsync(store, "POST", $"/api/pos/print-jobs/{Guid.NewGuid()}/retry"));
        // Thiết lập máy in vẫn theo gói cũ (PosPrinters).
        Assert.Equal(StatusCodes.Status200OK, await CallAsync(store, "GET", "/api/pos/printers"));
    }

    [Fact]
    public async Task Goi_co_may_in_cloud_thi_may_nhan_vien_gui_lenh_in_duoc()
    {
        if (fx.ConnectionString == null) return;
        var inPackage = await StoreWithPackageAsync(BasicPos.Append("PosStorePrinters"));
        Assert.Equal(StatusCodes.Status200OK, await CallAsync(inPackage, "POST", "/api/pos/print-jobs"));

        var addedForStore = await StoreWithPackageAsync(BasicPos, extra: "[\"PosStorePrinters\"]");
        Assert.Equal(StatusCodes.Status200OK, await CallAsync(addedForStore, "POST", "/api/pos/print-jobs"));
    }

    [Fact]
    public async Task Cua_hang_dang_dung_Agent_duoc_them_may_in_cloud_mot_lan()
    {
        if (fx.ConnectionString == null) return;
        var usingAgent = await StoreWithPackageAsync(BasicPos, extra: "[\"PosKds\"]");
        var blocked = await StoreWithPackageAsync(BasicPos, blocked: "[\"PosStorePrinters\"]");
        var noAgent = await StoreWithPackageAsync(BasicPos);
        await using (var db = fx.NewDb())
        {
            foreach (var s in new[] { usingAgent, blocked })
                db.PosPrintAgents.Add(new PosPrintAgent
                {
                    Id = Guid.NewGuid(), StoreId = s, DeviceId = "dev-" + s.ToString("N")[..6],
                    AssignedPrinterIdsJson = "[]", IsActive = true,
                });
            await db.SaveChangesAsync();
        }

        await using (var db = fx.NewDb())
        {
            await PrintAgentPackageBackfill.ApplyAsync(db);
            Assert.Equal(0, await PrintAgentPackageBackfill.ApplyAsync(db)); // chạy lại không thêm trùng

            async Task<List<string>> Extra(Guid id) => StorePackageHelper.DeserializeModules(
                await db.Stores.Where(s => s.Id == id).Select(s => s.ExtraModules).FirstAsync());
            Assert.Equal(["PosKds", "PosStorePrinters"], await Extra(usingAgent));
            Assert.Empty(await Extra(blocked));
            Assert.Empty(await Extra(noAgent));
        }
        Assert.Equal(StatusCodes.Status200OK, await CallAsync(usingAgent, "POST", "/api/pos/print-jobs"));
    }
}
