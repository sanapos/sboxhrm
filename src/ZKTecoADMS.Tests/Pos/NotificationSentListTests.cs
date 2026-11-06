using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Danh sách đợt thông báo đã gửi chạy trên PostgreSQL thật: cột uuid không có hàm max().</summary>
[Collection("pos-pg")]
public class NotificationSentListTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    async Task<Guid> OwnerOfAsync(Guid store)
    {
        await using var db = Fx.NewDb();
        return await db.Users.Where(u => u.StoreId == store).Select(u => u.Id).FirstAsync();
    }

    async Task<Guid> AddUserAsync(Guid store, string lastName, string firstName)
    {
        var id = Guid.NewGuid();
        var email = $"u{id:N}@sbox.vn";
        await using var db = Fx.NewDb();
        db.Users.Add(new ApplicationUser
        {
            Id = id, StoreId = store, UserName = email, NormalizedUserName = email.ToUpperInvariant(),
            Email = email, NormalizedEmail = email.ToUpperInvariant(), SecurityStamp = Guid.NewGuid().ToString(),
            FirstName = firstName, LastName = lastName,
        });
        await db.SaveChangesAsync();
        return id;
    }

    async Task<Guid> AddBatchAsync(Guid store, Guid? sender, string title, DateTime at, int recipients, int read)
    {
        var batch = Guid.NewGuid();
        await using var db = Fx.NewDb();
        for (var i = 0; i < recipients; i++)
        {
            db.Notifications.Add(new Notification
            {
                Id = Guid.NewGuid(), StoreId = store, BatchId = batch, FromUserId = sender,
                Title = title, Message = "Nội dung " + title, Timestamp = at, IsRead = i < read,
            });
        }
        await db.SaveChangesAsync();
        return batch;
    }

    async Task<JsonElement> GetSentAsync(Guid store, string role = "Admin", int page = 1, int pageSize = 20)
    {
        await using var db = Fx.NewDb();
        var controller = PosPgFixture.As(
            new NotificationCenterController(db, null!, null!, null!, NullLogger<NotificationCenterController>.Instance),
            store, role);
        var data = Data(await controller.GetSent(page, pageSize));
        return JsonSerializer.SerializeToElement(data, data.GetType());
    }

    [Fact]
    public async Task Sent_list_shows_sender_counts_and_newest_first()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var owner = await OwnerOfAsync(store);
        var now = DateTime.UtcNow;
        await AddBatchAsync(store, owner, "Cũ", now.AddHours(-2), recipients: 3, read: 1);
        var newest = await AddBatchAsync(store, owner, "Mới", now, recipients: 2, read: 2);

        var r = await GetSentAsync(store);

        Assert.Equal(2, r.GetProperty("total").GetInt32());
        var items = r.GetProperty("items").EnumerateArray().ToList();
        Assert.Equal(2, items.Count);
        Assert.Equal(newest, items[0].GetProperty("BatchId").GetGuid());
        Assert.Equal("Mới", items[0].GetProperty("Title").GetString());
        Assert.Equal("Nội dung Mới", items[0].GetProperty("Body").GetString());
        Assert.Equal(2, items[0].GetProperty("Total").GetInt32());
        Assert.Equal(2, items[0].GetProperty("Read").GetInt32());
        Assert.Equal("Admin Test", items[0].GetProperty("SenderName").GetString());
        Assert.Equal(3, items[1].GetProperty("Total").GetInt32());
        Assert.Equal(1, items[1].GetProperty("Read").GetInt32());
    }

    [Fact]
    public async Task Sent_list_batch_without_sender_has_no_name()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        await AddBatchAsync(store, null, "Hệ thống", DateTime.UtcNow, recipients: 1, read: 0);

        var item = (await GetSentAsync(store)).GetProperty("items").EnumerateArray().Single();

        Assert.Equal(JsonValueKind.Null, item.GetProperty("SenderName").ValueKind);
    }

    [Fact]
    public async Task Sent_list_admin_sees_each_batch_sender_manager_sees_only_own()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var owner = await OwnerOfAsync(store);
        var other = await AddUserAsync(store, "Nguyễn", "Lan");
        var now = DateTime.UtcNow;
        await AddBatchAsync(store, owner, "Của chủ", now, recipients: 1, read: 0);
        await AddBatchAsync(store, other, "Của Lan", now.AddMinutes(-1), recipients: 1, read: 0);

        var admin = (await GetSentAsync(store)).GetProperty("items").EnumerateArray().ToList();
        Assert.Equal(2, admin.Count);
        Assert.Equal("Admin Test", admin[0].GetProperty("SenderName").GetString());
        Assert.Equal("Nguyễn Lan", admin[1].GetProperty("SenderName").GetString());

        var manager = await GetSentAsync(store, role: "Manager");
        Assert.Equal(1, manager.GetProperty("total").GetInt32());
        Assert.Equal("Của chủ", manager.GetProperty("items").EnumerateArray().Single().GetProperty("Title").GetString());
    }

    [Fact]
    public async Task Sent_list_pages_keep_order_and_other_stores_stay_out()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        var otherStore = await Fx.NewStoreAsync();
        var owner = await OwnerOfAsync(store);
        var now = DateTime.UtcNow;
        for (var i = 0; i < 7; i++)
            await AddBatchAsync(store, owner, "Đợt " + i, now.AddMinutes(-i), recipients: 1, read: 0);
        await AddBatchAsync(otherStore, await OwnerOfAsync(otherStore), "Cửa hàng khác", now, recipients: 1, read: 0);

        var second = await GetSentAsync(store, page: 2, pageSize: 5);

        Assert.Equal(7, second.GetProperty("total").GetInt32());
        var titles = second.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("Title").GetString()).ToList();
        Assert.Equal(["Đợt 5", "Đợt 6"], titles);
    }
}
