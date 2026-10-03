using System.Security.Claims;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using Xunit;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// CSDL PostgreSQL tạm cho test nghiệp vụ POS (transaction, ExecuteUpdate, khóa đồng thời — InMemory không có).
/// Kết nối: biến môi trường SBOX_TEST_PG, nếu không có thì lấy từ ZKTecoADMS.Api/appsettings.Development.json.
/// Tạo database sbox_test_xxx, EnsureCreated theo model, xóa khi xong. Không có PostgreSQL → test bỏ qua.
/// </summary>
public sealed class PosPgFixture : IAsyncLifetime
{
    public string? ConnectionString { get; private set; }
    public string? SkipReason { get; private set; }
    string? _adminConn;
    string? _dbName;

    static PosPgFixture() => AppContext.SetSwitch("Npgsql.EnableLegacyTimestampBehavior", true);

    static string? BaseConnection()
    {
        var env = Environment.GetEnvironmentVariable("SBOX_TEST_PG");
        if (!string.IsNullOrWhiteSpace(env)) return env;
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null && !File.Exists(Path.Combine(dir.FullName, "ZKTecoADMS.Api", "appsettings.Development.json")))
            dir = dir.Parent;
        if (dir == null) return null;
        using var doc = JsonDocument.Parse(File.ReadAllText(
            Path.Combine(dir.FullName, "ZKTecoADMS.Api", "appsettings.Development.json")));
        return doc.RootElement.TryGetProperty("ConnectionStrings", out var cs) &&
               cs.TryGetProperty("DefaultConnection", out var d) ? d.GetString() : null;
    }

    public async Task InitializeAsync()
    {
        var baseConn = BaseConnection();
        if (string.IsNullOrWhiteSpace(baseConn)) { SkipReason = "Không có chuỗi kết nối PostgreSQL"; return; }
        try
        {
            var b = new NpgsqlConnectionStringBuilder(baseConn) { Database = "postgres", Timeout = 3 };
            _adminConn = b.ConnectionString;
            _dbName = "sbox_test_" + Guid.NewGuid().ToString("N")[..12];
            await using (var c = new NpgsqlConnection(_adminConn))
            {
                await c.OpenAsync();
                await using var cmd = new NpgsqlCommand($"CREATE DATABASE \"{_dbName}\"", c);
                await cmd.ExecuteNonQueryAsync();
            }
            ConnectionString = new NpgsqlConnectionStringBuilder(baseConn) { Database = _dbName, IncludeErrorDetail = true }.ConnectionString;
            await using var db = NewDb();
            await db.Database.EnsureCreatedAsync();
        }
        catch (Exception ex)
        {
            SkipReason = "PostgreSQL không dùng được: " + ex.Message;
            ConnectionString = null;
        }
    }

    public async Task DisposeAsync()
    {
        if (_adminConn == null || _dbName == null) return;
        try
        {
            NpgsqlConnection.ClearAllPools();
            await using var c = new NpgsqlConnection(_adminConn);
            await c.OpenAsync();
            await using var cmd = new NpgsqlCommand($"DROP DATABASE IF EXISTS \"{_dbName}\" WITH (FORCE)", c);
            await cmd.ExecuteNonQueryAsync();
        }
        catch { /* dọn dẹp không được không làm hỏng test */ }
    }

    public ZKTecoDbContext NewDb() => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseNpgsql(ConnectionString!)
        .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
        .Options);

    /// <summary>Gắn người dùng quản lý của cửa hàng vào controller (bỏ qua attribute phân quyền khi gọi trực tiếp).</summary>
    public static T As<T>(T controller, Guid storeId, string role = "Admin") where T : ControllerBase
    {
        controller.ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                RequestServices = Microsoft.Extensions.DependencyInjection.ServiceCollectionContainerBuilderExtensions.BuildServiceProvider(new Microsoft.Extensions.DependencyInjection.ServiceCollection()),
                User = new ClaimsPrincipal(new ClaimsIdentity(
                [
                    new Claim(ClaimTypeNames.StoreId, storeId.ToString()),
                    new Claim("id", (UserOf.TryGetValue(storeId, out var uid) ? uid : Guid.NewGuid()).ToString()),
                    new Claim(ClaimTypes.Email, "test@sbox.vn"),
                    new Claim(ClaimTypes.Role, role),
                ], "test")),
            },
        };
        return controller;
    }

    /// <summary>Tài khoản quản lý của từng cửa hàng test (phiếu thu / chi cần người tạo có thật).</summary>
    static readonly System.Collections.Concurrent.ConcurrentDictionary<Guid, Guid> UserOf = new();

    /// <summary>Cửa hàng mới (mỗi test một cửa hàng để không lẫn dữ liệu) + tài khoản Admin.</summary>
    public async Task<Guid> NewStoreAsync()
    {
        var id = Guid.NewGuid();
        var userId = Guid.NewGuid();
        await using var db = NewDb();
        db.Stores.Add(new Store { Id = id, Name = "Test " + id.ToString("N")[..6], Code = "t" + id.ToString("N")[..10], IsActive = true });
        var email = $"u{userId:N}@sbox.vn";
        db.Users.Add(new ApplicationUser
        {
            Id = userId, StoreId = id, UserName = email, NormalizedUserName = email.ToUpperInvariant(),
            Email = email, NormalizedEmail = email.ToUpperInvariant(), SecurityStamp = Guid.NewGuid().ToString(),
            FirstName = "Test", LastName = "Admin",
        });
        await db.SaveChangesAsync();
        UserOf[id] = userId;
        return id;
    }

    public async Task<PosProduct> AddProductAsync(Guid storeId, string name, PosProductType type, decimal onHand,
        decimal cost, decimal price, Action<PosProduct>? configure = null)
    {
        var p = new PosProduct
        {
            Id = Guid.NewGuid(), StoreId = storeId, ProductCode = "SP" + Guid.NewGuid().ToString("N")[..6], Name = name,
            ProductType = type, OnHandQty = onHand, CostPrice = cost, BasePrice = price, IsActive = true,
        };
        configure?.Invoke(p);
        await using var db = NewDb();
        db.PosProducts.Add(p);
        await db.SaveChangesAsync();
        return p;
    }
}

[CollectionDefinition("pos-pg")]
public class PosPgCollection : ICollectionFixture<PosPgFixture>;
