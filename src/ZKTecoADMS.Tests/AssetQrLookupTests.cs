using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Assets;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Tem QR tài sản: nội dung QR in trên tem = QrCode (trống thì AssetCode). Quét tem → API tra cứu phải mở đúng tài sản,
/// kể cả khi máy quét kèm khoảng trắng / xuống dòng, và không lộ tài sản cửa hàng khác.
/// </summary>
public class AssetQrLookupTests
{
    readonly Guid _store = Guid.NewGuid();
    readonly ServiceProvider _sp;
    readonly ZKTecoDbContext _db;

    public AssetQrLookupTests()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        _sp = services.BuildServiceProvider();
        _db = _sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
    }

    AssetsController Ctl() => new(_db)
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

    Asset A(string code, string? qr, Guid? store = null) => new()
    {
        Id = Guid.NewGuid(), StoreId = store ?? _store, AssetCode = code, QrCode = qr, Name = "Laptop " + code,
        Status = AssetStatus.Active, AssetType = AssetType.Electronics, PurchasePrice = 1, Quantity = 1, IsActive = true,
    };

    async Task<string?> Lookup(string code)
    {
        var res = await Ctl().LookupAsset(code);
        if (res is not OkObjectResult ok) return null;
        return ((AppResponse<AssetDetailDto>)ok.Value!).Data!.AssetCode;
    }

    [Fact]
    public async Task Quet_tem_mo_dung_tai_san()
    {
        _db.Assets.AddRange(
            A("TS-0001", "TS-0001"),          // mặc định QrCode = AssetCode
            A("TS-0002", "QR-PHONG-KE-TOAN-7"), // QR riêng
            A("TS-0003", null),               // dữ liệu cũ chưa có QrCode → tem in AssetCode
            A("TS-9999", "TS-9999", store: Guid.NewGuid()));
        await _db.SaveChangesAsync();

        Assert.Equal("TS-0001", await Lookup("TS-0001"));
        Assert.Equal("TS-0002", await Lookup("QR-PHONG-KE-TOAN-7"));
        Assert.Equal("TS-0002", await Lookup("TS-0002"));
        Assert.Equal("TS-0003", await Lookup("TS-0003"));
        Assert.Equal("TS-0001", await Lookup(" TS-0001\r\n")); // máy quét kèm xuống dòng
        Assert.Null(await Lookup("TS-9999"));                  // cửa hàng khác
    }
}
