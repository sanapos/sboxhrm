using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Infrastructure.Interceptors;

namespace ZKTecoADMS.Tests;

public class ActivityAuditInterceptorTests
{
    sealed class Item
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = "";
        public decimal Price { get; set; }
        public string? Password { get; set; }
        public DateTime? Deleted { get; set; }
        public DateTime? LockExpiresAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
    }

    sealed class Ctx(DbContextOptions<Ctx> o) : DbContext(o)
    {
        public DbSet<Item> Items => Set<Item>();
    }

    static (Ctx Db, ActivityAuditCollector Col) Make()
    {
        var col = new ActivityAuditCollector();
        var opts = new DbContextOptionsBuilder<Ctx>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .AddInterceptors(new ActivityAuditInterceptor(col))
            .Options;
        return (new Ctx(opts), col);
    }

    [Fact]
    public async Task Records_create_update_with_old_new_values_soft_delete_and_masks_secrets()
    {
        var (db, col) = Make();
        var item = new Item { Id = Guid.NewGuid(), Name = "Trà sữa", Price = 25000, Password = "123456" };
        db.Items.Add(item);
        await db.SaveChangesAsync();
        var created = Assert.Single(col.Changes);
        Assert.Equal("Create", created.Op);
        Assert.Equal("Trà sữa", created.Label);
        Assert.Contains(created.Fields, f => f.Field == "Password" && f.New == "••••");

        col.Changes.Clear();
        item.Price = 30000;
        item.UpdatedAt = DateTime.UtcNow; // trường kỹ thuật — không ghi
        await db.SaveChangesAsync();
        var upd = Assert.Single(col.Changes);
        Assert.Equal("Update", upd.Op);
        var f = Assert.Single(upd.Fields);
        Assert.Equal(("Price", "25000", "30000"), (f.Field, f.Old, f.New));

        col.Changes.Clear();
        item.LockExpiresAt = DateTime.UtcNow.AddMinutes(2); // khóa đơn tự động — không ghi
        await db.SaveChangesAsync();
        Assert.Empty(col.Changes);

        item.Deleted = DateTime.UtcNow; // xóa mềm → Xóa
        await db.SaveChangesAsync();
        Assert.Equal("Delete", Assert.Single(col.Changes).Op);
    }

    [Fact]
    public async Task Suspended_collector_records_nothing()
    {
        var (db, col) = Make();
        col.Suspended = true;
        db.Items.Add(new Item { Id = Guid.NewGuid(), Name = "x" });
        await db.SaveChangesAsync();
        Assert.Empty(col.Changes);
    }
}
