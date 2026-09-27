using Xunit;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Chống trùng khi máy gửi lại do lỗi mạng: tạo lệnh in cùng mã → đúng lệnh cũ (kể cả
/// đã in xong); «In lại» (mã mới) vẫn ra lệnh mới; báo bếp gửi lại trả đúng các món.
/// </summary>
public class PosIdempotencyTests
{
    sealed class NullProxy : IClientProxy
    {
        public int Sent;
        public Task SendCoreAsync(string method, object?[] args, CancellationToken ct = default)
        {
            Sent++;
            return Task.CompletedTask;
        }
    }

    sealed class FakeClients : IHubClients
    {
        public readonly NullProxy Proxy = new();
        public IClientProxy All => Proxy;
        public IClientProxy AllExcept(IReadOnlyList<string> excludedConnectionIds) => Proxy;
        public IClientProxy Client(string connectionId) => Proxy;
        public IClientProxy Clients(IReadOnlyList<string> connectionIds) => Proxy;
        public IClientProxy Group(string groupName) => Proxy;
        public IClientProxy GroupExcept(string groupName, IReadOnlyList<string> excludedConnectionIds) => Proxy;
        public IClientProxy Groups(IReadOnlyList<string> groupNames) => Proxy;
        public IClientProxy User(string userId) => Proxy;
        public IClientProxy Users(IReadOnlyList<string> userIds) => Proxy;
    }

    sealed class FakeHub : IHubContext<AttendanceHub>
    {
        public readonly FakeClients FakeClients = new();
        public IHubClients Clients => FakeClients;
        public IGroupManager Groups => throw new NotSupportedException();
    }

    static readonly Guid Store = Guid.NewGuid();

    static (ZKTecoDbContext Db, PosPrintDispatchService Svc, FakeHub Hub, Guid PrinterId) Make()
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
            .Options);
        var printer = new PosStorePrinter
        {
            Id = Guid.NewGuid(),
            StoreId = Store,
            Name = "Bếp",
            IsActive = true,
        };
        db.PosStorePrinters.Add(printer);
        db.SaveChanges();
        db.ChangeTracker.Clear();
        var hub = new FakeHub();
        var svc = new PosPrintDispatchService(db, hub, NullLogger<PosPrintDispatchService>.Instance);
        return (db, svc, hub, printer.Id);
    }

    static EnqueuePrintJobRequest Req(Guid printerId, string? key, string payload = "AAAA") => new(
        Store, PosPrintDocumentType.KitchenSlip, PosPrintPayloadFormat.EscPosBase64, payload, 1,
        "HD001", null, "u1", "Thu ngân", printerId, key);

    [Theory]
    [InlineData(null, null)]
    [InlineData("abc", null)]
    [InlineData("0123456789abcdef0123456789abcdef", "0123456789abcdef0123456789abcdef")]
    [InlineData("  ks:0123456789abcdef  ", "ks:0123456789abcdef")]
    [InlineData("bad key with spaces!!", null)]
    public void Normalize_key(string? raw, string? expected) =>
        Assert.Equal(expected, PosIdempotency.Normalize(raw));

    [Fact]
    public void Detects_unique_violation_by_index_name()
    {
        var inner = new Exception(
            "23505: duplicate key value violates unique constraint \"IX_PosSaleOrders_Store_ClientRequestId\"");
        var ex = new DbUpdateException("save failed", inner);
        Assert.True(PosIdempotency.IsUniqueViolation(ex, PosIdempotency.SaleOrderIndex));
        Assert.False(PosIdempotency.IsUniqueViolation(ex, PosIdempotency.PrintJobIndex));
    }

    [Fact]
    public async Task Same_request_id_returns_same_job_even_after_printed()
    {
        var (db, svc, _, printerId) = Make();
        const string key = "0123456789abcdef0123456789abcdef";

        var first = await svc.EnqueueJobAsync(Req(printerId, key));
        // Agent đã in xong lệnh đầu, nhưng máy gửi mất phản hồi → gửi lại cùng mã.
        var tracked = await db.PosPrintJobs.AsTracking().FirstAsync(j => j.Id == first.Id);
        tracked.Status = PosPrintJobStatus.Completed;
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();

        var retry = await svc.EnqueueJobAsync(Req(printerId, key));

        Assert.Equal(first.Id, retry.Id);
        Assert.Equal(1, await db.PosPrintJobs.CountAsync());
    }

    [Fact]
    public async Task New_request_id_after_printed_creates_reprint()
    {
        var (db, svc, _, printerId) = Make();
        var first = await svc.EnqueueJobAsync(Req(printerId, "11111111111111111111111111111111"));
        var tracked = await db.PosPrintJobs.AsTracking().FirstAsync(j => j.Id == first.Id);
        tracked.Status = PosPrintJobStatus.Completed;
        await db.SaveChangesAsync();
        db.ChangeTracker.Clear();

        // Thu ngân chủ động «In lại» → mã mới → phải ra lệnh mới.
        var reprint = await svc.EnqueueJobAsync(Req(printerId, "22222222222222222222222222222222"));

        Assert.NotEqual(first.Id, reprint.Id);
        Assert.Equal(2, await db.PosPrintJobs.CountAsync());
    }

    [Fact]
    public async Task Retry_while_queued_rebroadcasts_to_agents()
    {
        var (db, svc, hub, printerId) = Make();
        const string key = "33333333333333333333333333333333";
        await svc.EnqueueJobAsync(Req(printerId, key));
        var sentBefore = hub.FakeClients.Proxy.Sent;

        var retry = await svc.EnqueueJobAsync(Req(printerId, key));

        Assert.Equal(PosPrintJobStatus.Queued, retry.Status);
        Assert.True(hub.FakeClients.Proxy.Sent > sentBefore);
        Assert.Equal(1, await db.PosPrintJobs.CountAsync());
    }

    [Fact]
    public void Kitchen_send_replay_round_trip()
    {
        var at = new DateTime(2026, 9, 27, 7, 30, 0, DateTimeKind.Utc);
        var items = new[] { new { productName = "Phở bò", qty = 2m, lineId = Guid.NewGuid() } };
        var json = PosKitchenSendReplay.Serialize(1, 2m, items, at);

        var snap = PosKitchenSendReplay.TryRead(json);

        Assert.NotNull(snap);
        Assert.Equal(1, snap!.SentLines);
        Assert.Equal(2m, snap.SentQty);
        Assert.Equal(at, snap.KitchenSentAt.ToUniversalTime());
        Assert.Equal("Phở bò", snap.SentItems!.Value[0].GetProperty("productName").GetString());
        Assert.Null(PosKitchenSendReplay.TryRead("không phải json"));
        Assert.Null(PosKitchenSendReplay.TryRead(null));
    }
}
