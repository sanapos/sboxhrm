using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Repositories;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Trang 1 phải là N bản ghi đầu SAU khi sắp xếp. Trước Skip/Take chạy trước OrderBy: danh sách thông báo
/// trang đầu là N dòng bất kỳ, thông báo mới nhất («Món đã xong») không hiện trên đầu.
/// </summary>
public class EfRepositoryPagingOrderTests
{
    sealed class NoTenant : ITenantProvider
    {
        public Guid? StoreId => null;
        public bool IsSuperAccess => true;
    }

    static (ZKTecoDbContext Db, EfRepository<Notification> Repo) Seed()
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var start = new DateTime(2026, 10, 1, 0, 0, 0, DateTimeKind.Utc);
        // Thêm theo thứ tự cũ → mới: không sắp xếp thì Take lấy các dòng cũ nhất.
        for (var i = 0; i < 10; i++)
            db.Add(new Notification { Id = Guid.NewGuid(), Title = $"N{i}", Message = "x", Timestamp = start.AddDays(i) });
        db.SaveChanges();
        return (db, new EfRepository<Notification>(db, NullLogger<EfRepository<Notification>>.Instance, new NoTenant()));
    }

    [Fact]
    public async Task GetAllWithInclude_orders_before_paging()
    {
        var (_, repo) = Seed();
        var page1 = await repo.GetAllWithIncludeAsync(
            orderBy: q => q.OrderByDescending(n => n.Timestamp), skip: 0, take: 3);
        Assert.Equal(["N9", "N8", "N7"], page1.Select(n => n.Title));

        var page2 = await repo.GetAllWithIncludeAsync(
            orderBy: q => q.OrderByDescending(n => n.Timestamp), skip: 3, take: 3);
        Assert.Equal(["N6", "N5", "N4"], page2.Select(n => n.Title));
    }

    [Fact]
    public async Task GetAll_orders_before_paging()
    {
        var (_, repo) = Seed();
        var page1 = await repo.GetAllAsync(orderBy: q => q.OrderByDescending(n => n.Timestamp), take: 2);
        Assert.Equal(["N9", "N8"], page1.Select(n => n.Title));
    }
}
