using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Endpoint thiết lập công khai không được vỡ khi nhiều cửa hàng có cùng một khóa
/// (vd «overtime_rate» trong thiết lập lương) — lỗi thật trên máy chủ:
/// "An item with the same key has already been added. Key: overtime_rate".
/// </summary>
public class PublicSettingsDuplicateKeyTests
{
    /// <summary>Cache đi thẳng xuống DB để test kiểm tra đúng truy vấn.</summary>
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

    static PublicSettingsController Controller(ZKTecoDbContext db) => new(
        db, NullLogger<PublicSettingsController>.Instance, new PassThroughCache());

    static AppSettings Row(string key, string? value, Guid? storeId, DateTime createdAt, DateTime? lastModified = null)
        => new()
        {
            Id = Guid.NewGuid(),
            Key = key,
            Value = value,
            Group = storeId == null ? "General" : "Salary",
            IsPublic = true,
            StoreId = storeId,
            CreatedAt = createdAt,
            LastModified = lastModified,
        };

    [Fact]
    public async Task Nhieu_cua_hang_cung_khoa_overtime_rate_khong_lam_vo_endpoint()
    {
        using var db = Db();
        db.AppSettings.AddRange(
            Row(AppSettingKeys.CompanyName, "SBOX", null, new DateTime(2026, 1, 1)),
            // Hai cửa hàng đều lưu thiết lập lương với cùng khóa — nguyên nhân lỗi cũ.
            Row("overtime_rate", "1.5", Guid.NewGuid(), new DateTime(2026, 2, 1)),
            Row("overtime_rate", "2.0", Guid.NewGuid(), new DateTime(2026, 3, 1)));
        await db.SaveChangesAsync();

        var result = await Controller(db).GetPublicSettings();

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        var body = Assert.IsType<AppResponse<PublicAppSettingsResponse>>(ok.Value);
        Assert.True(body.IsSuccess);
        Assert.Equal("SBOX", body.Data!.CompanyName);
    }

    [Fact]
    public async Task Trung_khoa_cap_he_thong_thi_lay_dong_cap_nhat_gan_nhat()
    {
        using var db = Db();
        // Dữ liệu cũ (trước khi có chỉ mục duy nhất) có thể còn 2 dòng cùng khóa, StoreId null.
        db.AppSettings.AddRange(
            Row(AppSettingKeys.CompanyName, "Tên cũ", null, new DateTime(2026, 1, 1)),
            Row(AppSettingKeys.CompanyName, "Tên mới", null, new DateTime(2026, 1, 1),
                lastModified: new DateTime(2026, 5, 1)));
        await db.SaveChangesAsync();

        var result = await Controller(db).GetPublicSettings();

        var ok = Assert.IsType<OkObjectResult>(result.Result);
        var body = Assert.IsType<AppResponse<PublicAppSettingsResponse>>(ok.Value);
        Assert.Equal("Tên mới", body.Data!.CompanyName);
    }

    [Fact]
    public async Task Lay_setting_theo_khoa_khong_tra_du_lieu_cua_cua_hang()
    {
        using var db = Db();
        db.AppSettings.Add(Row("company_address", "Địa chỉ cửa hàng A", Guid.NewGuid(), new DateTime(2026, 2, 1)));
        await db.SaveChangesAsync();

        var result = await Controller(db).GetSetting("company_address");

        Assert.IsType<NotFoundObjectResult>(result.Result);
    }
}
