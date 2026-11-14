using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Xunit;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Bộ lọc cửa hàng chung của EF phải có hiệu lực với request đã đăng nhập, kể cả khi DbContext được tạo lúc
/// xác thực JWT (request chưa có User) — trước đây lúc đó chốt luôn «thấy mọi cửa hàng» cho cả request.
/// </summary>
[Collection("pos-pg")]
public class TenantIsolationTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    /// <summary>Mỗi request giả một accessor riêng (HttpContextAccessor thật dùng chung một biến AsyncLocal tĩnh).</summary>
    sealed class Accessor(HttpContext? context) : IHttpContextAccessor
    {
        public HttpContext? HttpContext { get; set; } = context;
    }

    static ClaimsPrincipal UserOf(Guid storeId, string role) => new(new ClaimsIdentity(
    [
        new Claim(ClaimTypeNames.StoreId, storeId.ToString()),
        new Claim(ClaimTypes.Role, role),
    ], "test"));

    ZKTecoDbContext DbFor(TenantProvider tenant) => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseNpgsql(Fx.ConnectionString!)
        .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
        .Options, tenant);

    static IConfiguration Config(bool enforce) => new ConfigurationBuilder()
        .AddInMemoryCollection(new Dictionary<string, string?> { ["Tenancy:EnforceRequestFilter"] = enforce ? "true" : "false" })
        .Build();

    async Task<(Guid A, Guid B, Guid ProductA, Guid ProductB, Guid Shared)> SeedAsync()
    {
        var a = await Fx.NewStoreAsync();
        var b = await Fx.NewStoreAsync();
        var pa = (await Fx.AddProductAsync(a, "Hàng A", PosProductType.Goods, 1, 1, 1)).Id;
        var pb = (await Fx.AddProductAsync(b, "Hàng B", PosProductType.Goods, 1, 1, 1)).Id;
        var shared = Guid.NewGuid();
        await using var db = Fx.NewDb();
        db.Holidays.AddRange(
            new Holiday { Id = shared, StoreId = null, Name = "Dùng chung", Date = DateTime.UtcNow.Date },
            new Holiday { Id = Guid.NewGuid(), StoreId = a, Name = "Lễ riêng A", Date = DateTime.UtcNow.Date },
            new Holiday { Id = Guid.NewGuid(), StoreId = b, Name = "Lễ riêng B", Date = DateTime.UtcNow.Date });
        await db.SaveChangesAsync();
        return (a, b, pa, pb, shared);
    }

    [Fact]
    public async Task DbContext_tao_luc_chua_dang_nhap_van_loc_cua_hang_sau_khi_co_nguoi_dung()
    {
        if (NoDb) return;
        var (a, b, pa, pb, shared) = await SeedAsync();
        var http = new DefaultHttpContext();
        var tenant = new TenantProvider(new Accessor(http), Config(enforce: true));
        // DbContext + tenant provider được tạo trước khi request có User (như lúc OnTokenValidated).
        await using var db = DbFor(tenant);
        Assert.True(tenant.IsSuperAccess);
        Assert.NotNull(await db.Users.FirstOrDefaultAsync(u => u.StoreId == b));

        http.User = UserOf(a, nameof(Roles.Admin));

        Assert.False(tenant.IsSuperAccess);
        Assert.Equal(a, tenant.StoreId);
        // Dòng của cửa hàng khác: không thấy, kể cả tra theo khóa chính / cập nhật hàng loạt.
        Assert.NotNull(await db.PosProducts.FirstOrDefaultAsync(p => p.Id == pa));
        Assert.Null(await db.PosProducts.FirstOrDefaultAsync(p => p.Id == pb));
        Assert.Null(await db.PosProducts.FindAsync(pb));
        Assert.False(await db.Users.AnyAsync(u => u.StoreId == b));
        Assert.Equal(0, await db.PosProducts.Where(p => p.Id == pb)
            .ExecuteUpdateAsync(s => s.SetProperty(p => p.Name, "bị sửa từ cửa hàng khác")));
        // Dòng dùng chung (StoreId null) và dòng của chính mình vẫn thấy.
        var holidays = await db.Holidays.Where(h => h.Name.StartsWith("Lễ riêng") || h.Id == shared)
            .Select(h => h.Name).ToListAsync();
        Assert.Contains("Dùng chung", holidays);
        Assert.Contains("Lễ riêng A", holidays);
        Assert.DoesNotContain("Lễ riêng B", holidays);
        // Chủ động bỏ lọc vẫn dùng được cho các tra cứu xuyên cửa hàng hợp lệ.
        Assert.NotNull(await db.PosProducts.IgnoreQueryFilters().FirstOrDefaultAsync(p => p.Id == pb));

        await using var check = Fx.NewDb();
        Assert.Equal("Hàng B", (await check.PosProducts.FirstAsync(p => p.Id == pb)).Name);
    }

    [Fact]
    public async Task Hai_request_khac_cua_hang_khong_lan_bo_loc_cua_nhau()
    {
        if (NoDb) return;
        var (a, b, pa, pb, _) = await SeedAsync();
        var tenantA = new TenantProvider(new Accessor(new DefaultHttpContext { User = UserOf(a, "Cashier") }), Config(true));
        var tenantB = new TenantProvider(new Accessor(new DefaultHttpContext { User = UserOf(b, "Cashier") }), Config(true));
        await using var dbA = DbFor(tenantA);
        await using var dbB = DbFor(tenantB);

        Assert.True(await dbA.PosProducts.AnyAsync(p => p.Id == pa));
        Assert.False(await dbA.PosProducts.AnyAsync(p => p.Id == pb));
        Assert.True(await dbB.PosProducts.AnyAsync(p => p.Id == pb));
        Assert.False(await dbB.PosProducts.AnyAsync(p => p.Id == pa));
    }

    [Theory]
    [InlineData(nameof(Roles.SuperAdmin))]
    [InlineData(nameof(Roles.Agent))]
    public async Task Quan_tri_he_thong_va_dai_ly_van_thay_moi_cua_hang(string role)
    {
        if (NoDb) return;
        var (a, _, pa, pb, _) = await SeedAsync();
        var tenant = new TenantProvider(
            new Accessor(new DefaultHttpContext { User = UserOf(a, role) }), Config(true));
        await using var db = DbFor(tenant);

        Assert.True(tenant.IsSuperAccess);
        Assert.Equal(2, await db.PosProducts.CountAsync(p => p.Id == pa || p.Id == pb));
    }

    [Fact]
    public async Task Endpoint_cong_khai_goi_kem_token_van_thay_moi_cua_hang_nhu_truoc()
    {
        if (NoDb) return;
        var (a, _, _, pb, _) = await SeedAsync();
        var http = new DefaultHttpContext { User = UserOf(a, "Cashier") };
        http.SetEndpoint(new Endpoint(null, new EndpointMetadataCollection(new AllowAnonymousAttribute()), "public"));
        var tenant = new TenantProvider(new Accessor(http), Config(true));
        await using var db = DbFor(tenant);

        Assert.True(tenant.IsSuperAccess);
        Assert.True(await db.PosProducts.AnyAsync(p => p.Id == pb));
    }

    [Fact]
    public async Task Endpoint_doi_dang_nhap_thi_loc_theo_cua_hang()
    {
        if (NoDb) return;
        var (a, _, _, pb, _) = await SeedAsync();
        var http = new DefaultHttpContext { User = UserOf(a, "Cashier") };
        http.SetEndpoint(new Endpoint(null, new EndpointMetadataCollection(new AuthorizeAttribute()), "private"));
        var tenant = new TenantProvider(new Accessor(http), Config(true));
        await using var db = DbFor(tenant);

        Assert.False(tenant.IsSuperAccess);
        Assert.False(await db.PosProducts.AnyAsync(p => p.Id == pb));
    }

    [Fact]
    public async Task Cong_tac_tat_dua_ve_cach_cu()
    {
        if (NoDb) return;
        var (a, _, _, pb, _) = await SeedAsync();
        var http = new DefaultHttpContext();
        var tenant = new TenantProvider(new Accessor(http), Config(enforce: false));
        await using var db = DbFor(tenant);
        http.User = UserOf(a, nameof(Roles.Admin));

        // Cách cũ: chốt theo lúc tạo (chưa có User) → không lọc.
        Assert.True(tenant.IsSuperAccess);
        Assert.True(await db.PosProducts.AnyAsync(p => p.Id == pb));
    }

    [Fact]
    public void Dich_vu_nen_khong_co_request_thi_thay_moi_cua_hang()
    {
        var tenant = new TenantProvider(new Accessor(null));
        Assert.True(tenant.IsSuperAccess);
        Assert.Null(tenant.StoreId);
    }
}
