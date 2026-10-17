using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Assets;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Báo cáo tài sản: tổng giá trị chỉ gồm tài sản còn nắm giữ (đã thanh lý / mất không cộng nguyên giá).</summary>
public class AssetReportSummaryTests
{
    readonly Guid _store = Guid.NewGuid();
    readonly ServiceProvider _sp;
    readonly ZKTecoDbContext _db;

    public AssetReportSummaryTests()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        _sp = services.BuildServiceProvider();
        _db = _sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
    }

    AssetReportsController Ctl() => new(_db, NullLogger<AssetReportsController>.Instance)
    {
        ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                RequestServices = _sp,
                User = new ClaimsPrincipal(new ClaimsIdentity([
                    new Claim("id", Guid.NewGuid().ToString()),
                    new Claim(ClaimTypes.Role, "Admin"),
                    new Claim(ClaimTypeNames.StoreId, _store.ToString()),
                ], "test")),
            },
        },
    };

    Asset A(string code, AssetStatus status, decimal price, int qty = 1) => new()
    {
        Id = Guid.NewGuid(), StoreId = _store, AssetCode = code, Name = code, Status = status,
        AssetType = AssetType.Electronics, PurchasePrice = price, Quantity = qty, IsActive = true,
    };

    [Fact]
    public async Task Tong_gia_tri_bo_tai_san_da_thanh_ly_hoac_mat()
    {
        _db.Assets.AddRange(
            A("TS1", AssetStatus.Active, 10_000_000),
            A("TS2", AssetStatus.InStock, 2_000_000, qty: 3),
            A("TS3", AssetStatus.Disposed, 50_000_000),
            A("TS4", AssetStatus.Lost, 7_000_000));
        await _db.SaveChangesAsync();

        var res = Assert.IsType<OkObjectResult>(await Ctl().GetSummary());
        var s = ((AppResponse<AssetStatisticsDto>)res.Value!).Data!;
        Assert.Equal(4, s.TotalAssets);                      // vẫn đếm đủ
        Assert.Equal(1, s.DisposedAssets);
        Assert.Equal(16_000_000m, s.TotalPurchaseValue);     // trước đây 73.000.000
        Assert.Equal(16_000_000m, s.TotalCurrentValue);
        Assert.Equal(16_000_000m, Assert.Single(s.ByType).TotalValue);
    }
}
