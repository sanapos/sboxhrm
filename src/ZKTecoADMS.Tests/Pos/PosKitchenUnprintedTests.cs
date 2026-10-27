using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Phiếu bếp server tự gửi (QR / online / Tingee): lệnh in chắc chắn không ra giấy → món trả về «chưa báo bếp»
/// (trước đây món vẫn «đã báo bếp», không ai báo lại, bếp không làm). Lệnh có thể đã in → không trả.
/// </summary>
[Collection("pos-pg")]
public class PosKitchenUnprintedTests(PosPgFixture fx)
{
    sealed class NullHub : IHubContext<AttendanceHub>
    {
        public IHubClients Clients { get; } = new NullClients();
        public IGroupManager Groups { get; } = new NullGroups();
    }

    sealed class NullClients : IHubClients
    {
        static readonly IClientProxy P = new NullProxy();
        public IClientProxy All => P;
        public IClientProxy AllExcept(IReadOnlyList<string> excludedConnectionIds) => P;
        public IClientProxy Client(string connectionId) => P;
        public IClientProxy Clients(IReadOnlyList<string> connectionIds) => P;
        public IClientProxy Group(string groupName) => P;
        public IClientProxy GroupExcept(string groupName, IReadOnlyList<string> excludedConnectionIds) => P;
        public IClientProxy Groups(IReadOnlyList<string> groupNames) => P;
        public IClientProxy User(string userId) => P;
        public IClientProxy Users(IReadOnlyList<string> userIds) => P;
    }

    sealed class NullProxy : IClientProxy
    {
        public Task SendCoreAsync(string method, object?[] args, CancellationToken ct = default) => Task.CompletedTask;
    }

    sealed class NullGroups : IGroupManager
    {
        public Task AddToGroupAsync(string connectionId, string groupName, CancellationToken ct = default) => Task.CompletedTask;
        public Task RemoveFromGroupAsync(string connectionId, string groupName, CancellationToken ct = default) => Task.CompletedTask;
    }

    static PosPrintDispatchService Svc(ZKTecoDbContext db) =>
        new(db, new NullHub(), NullLogger<PosPrintDispatchService>.Instance);

    bool NoDb => fx.ConnectionString == null;

    record Seed(Guid Store, Guid Printer, Guid Agent, Guid Order, Guid Line);

    /// <summary>Đơn QR có 1 dòng (qty) đã đánh dấu «đã báo bếp» toàn bộ, 1 Agent gắn máy in bếp.</summary>
    async Task<Seed> SeedAsync(decimal qty = 2)
    {
        var store = await fx.NewStoreAsync();
        var product = (await fx.AddProductAsync(store, "Phở", PosProductType.Goods, 100, 20000, 50000)).Id;
        var printer = Guid.NewGuid();
        var agent = Guid.NewGuid();
        var order = Guid.NewGuid();
        var line = Guid.NewGuid();
        await using var db = fx.NewDb();
        db.PosStorePrinters.Add(new PosStorePrinter
        {
            Id = printer, StoreId = store, Name = "Bếp", ConnectionType = PosPrinterConnectionType.Lan,
            LanHost = "192.168.1.50", IsActive = true,
        });
        db.PosPrintAgents.Add(new PosPrintAgent
        {
            Id = agent, StoreId = store, DeviceId = "dev-a", AssignedPrinterIdsJson = $"[\"{printer}\"]",
            IsOnline = true, LastHeartbeatAt = DateTime.UtcNow, IsActive = true,
        });
        db.PosSaleOrders.Add(new PosSaleOrder
        {
            Id = order, StoreId = store, OrderNo = "HDQR" + order.ToString("N")[..6], Status = PosSaleOrderStatus.Draft,
            CustomerName = "QR", SubTotal = qty * 50000, Total = qty * 50000, LockVersion = 3, IsActive = true,
        });
        db.PosSaleOrderLines.Add(new PosSaleOrderLine
        {
            Id = line, StoreId = store, SaleOrderId = order, ProductId = product, ProductName = "Phở",
            Qty = qty, UnitPrice = 50000, LineTotal = qty * 50000,
            KitchenSentQty = qty, KitchenSentAt = DateTime.UtcNow, KitchenPrepStatus = "queued",
        });
        await db.SaveChangesAsync();
        return new Seed(store, printer, agent, order, line);
    }

    async Task<Guid> QueueKitchenAsync(Seed s, decimal qty, DateTime? createdAt = null)
    {
        await using var db = fx.NewDb();
        var job = await Svc(db).EnqueueJobAsync(new EnqueuePrintJobRequest(
            s.Store, PosPrintDocumentType.KitchenSlip, PosPrintPayloadFormat.KitchenSlipJson,
            "{\"lines\":[" + Guid.NewGuid().ToString("N") + "]}", 1, "QR|" + Guid.NewGuid().ToString("N")[..8],
            s.Order, null, "QR khách", s.Printer,
            KitchenLinesJson: PosPrintDispatchService.SerializeKitchenLines([new KitchenLineRef(s.Line, qty)])));
        if (createdAt != null)
            await db.PosPrintJobs.Where(j => j.Id == job.Id)
                .ExecuteUpdateAsync(x => x
                    .SetProperty(j => j.CreatedAt, createdAt.Value)
                    .SetProperty(j => j.ExpiresAt, createdAt.Value.AddHours(24)));
        return job.Id;
    }

    async Task<(decimal Sent, string Prep, int Version)> LineAsync(Seed s)
    {
        await using var db = fx.NewDb();
        var l = await db.PosSaleOrderLines.AsNoTracking().FirstAsync(x => x.Id == s.Line);
        var o = await db.PosSaleOrders.AsNoTracking().FirstAsync(x => x.Id == s.Order);
        return (l.KitchenSentQty, l.KitchenPrepStatus, o.LockVersion);
    }

    async Task<PosPrintJob> JobAsync(Guid id)
    {
        await using var db = fx.NewDb();
        return await db.PosPrintJobs.AsNoTracking().FirstAsync(j => j.Id == id);
    }

    async Task ForceStateAsync(Guid job, PosPrintJobStatus status, Guid agent, DateTime claimedAt)
    {
        await using var db = fx.NewDb();
        await db.PosPrintJobs.Where(j => j.Id == job).ExecuteUpdateAsync(x => x
            .SetProperty(j => j.Status, status)
            .SetProperty(j => j.AgentId, agent)
            .SetProperty(j => j.ClaimedAt, claimedAt));
    }

    [Fact]
    public async Task Agent_offline_too_long_returns_items_to_not_sent()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueKitchenAsync(s, 2, createdAt: DateTime.UtcNow.AddMinutes(-10));
        await using (var db = fx.NewDb())
            await Svc(db).SweepStuckJobsAsync(s.Store);

        Assert.Equal("STALE_QUEUED", (await JobAsync(job)).ErrorCode);
        Assert.True((await JobAsync(job)).KitchenLinesReverted);
        var (sent, prep, version) = await LineAsync(s);
        Assert.Equal(0, sent);
        Assert.Equal(PosKitchenKdsHelper.None, prep);
        Assert.Equal(4, version);   // máy đang mở bàn tải lại

        // Lượt dọn sau không trả lần hai.
        await using (var db = fx.NewDb())
            await Svc(db).SweepStuckJobsAsync(s.Store);
        Assert.Equal(0, (await LineAsync(s)).Sent);
    }

    [Fact]
    public async Task Only_the_qty_of_that_ticket_is_returned()
    {
        if (NoDb) return;
        var s = await SeedAsync(qty: 3);
        var job = await QueueKitchenAsync(s, 1);
        await using (var db = fx.NewDb())
        {
            var claimed = await Svc(db).ClaimNextJobAsync(s.Store, s.Agent);
            Assert.Equal(job, claimed?.Id);
            await Svc(db).FailJobAsync(job, s.Agent, "AGENT_ERROR", "Lỗi cổng in");
        }
        Assert.Equal(2, (await LineAsync(s)).Sent);
    }

    [Fact]
    public async Task Print_timeout_may_have_printed_so_items_stay_sent()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueKitchenAsync(s, 2);
        await using (var db = fx.NewDb())
        {
            await Svc(db).ClaimNextJobAsync(s.Store, s.Agent);
            await Svc(db).MarkPrintingAsync(job, s.Agent);
            await Svc(db).FailJobAsync(job, s.Agent, "PRINT_TIMEOUT", "Quá 75 giây");
        }
        Assert.Equal(2, (await LineAsync(s)).Sent);
        Assert.False((await JobAsync(job)).KitchenLinesReverted);
    }

    [Fact]
    public async Task Stuck_claimed_is_not_printed_but_stuck_printing_may_be()
    {
        if (NoDb) return;
        var claimed = await SeedAsync();
        var jobClaimed = await QueueKitchenAsync(claimed, 2);
        // Agent nhận rồi mất hẳn (không ai coi là còn sống) quá 3 phút.
        await using (var db = fx.NewDb())
            await db.PosPrintAgents.Where(a => a.Id == claimed.Agent).ExecuteUpdateAsync(x => x
                .SetProperty(a => a.IsOnline, false)
                .SetProperty(a => a.LastHeartbeatAt, DateTime.UtcNow.AddMinutes(-10)));
        await ForceStateAsync(jobClaimed, PosPrintJobStatus.Claimed, claimed.Agent, DateTime.UtcNow.AddMinutes(-5));
        await using (var db = fx.NewDb())
            await Svc(db).SweepStuckJobsAsync(claimed.Store);
        var jc = await JobAsync(jobClaimed);
        // Phiếu bếp Claimed của Agent chết được xếp lại hàng đợi trước (SOFT_REQUEUE) — vẫn chưa in, món giữ «đã báo».
        Assert.True(jc.Status == PosPrintJobStatus.Queued || jc.ErrorCode == PosPrintDispatchService.StuckClaimed);

        var printing = await SeedAsync();
        var jobPrinting = await QueueKitchenAsync(printing, 2);
        await ForceStateAsync(jobPrinting, PosPrintJobStatus.Printing, printing.Agent, DateTime.UtcNow.AddMinutes(-5));
        await using (var db = fx.NewDb())
            await Svc(db).SweepStuckJobsAsync(printing.Store);
        var jp = await JobAsync(jobPrinting);
        Assert.Equal(PosPrintDispatchService.StuckPrinting, jp.ErrorCode);
        Assert.Equal(2, (await LineAsync(printing)).Sent);
    }

    [Fact]
    public async Task Stuck_claimed_invoice_gets_its_own_code()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        Guid job;
        await using (var db = fx.NewDb())
            job = (await Svc(db).EnqueueJobAsync(new EnqueuePrintJobRequest(
                s.Store, PosPrintDocumentType.SaleInvoice, PosPrintPayloadFormat.EscPosBase64,
                "AAAA" + Guid.NewGuid().ToString("N"), 1, "HD1", s.Order, null, "Thu ngân", s.Printer))).Id;
        await ForceStateAsync(job, PosPrintJobStatus.Claimed, s.Agent, DateTime.UtcNow.AddMinutes(-5));
        await using (var db = fx.NewDb())
            await Svc(db).SweepStuckJobsAsync(s.Store);
        Assert.Equal(PosPrintDispatchService.StuckClaimed, (await JobAsync(job)).ErrorCode);
    }

    [Fact]
    public async Task Retrying_a_returned_ticket_marks_items_sent_again()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueKitchenAsync(s, 2, createdAt: DateTime.UtcNow.AddMinutes(-10));
        await using (var db = fx.NewDb())
            await Svc(db).SweepStuckJobsAsync(s.Store);
        Assert.Equal(0, (await LineAsync(s)).Sent);

        await using (var db = fx.NewDb())
            await Svc(db).RetryJobAsync(s.Store, job, null, "admin");
        Assert.Equal(2, (await LineAsync(s)).Sent);
        Assert.False((await JobAsync(job)).KitchenLinesReverted);
    }

    [Fact]
    public async Task Late_complete_after_return_marks_items_sent_again()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueKitchenAsync(s, 2);
        await using (var db = fx.NewDb())
        {
            await Svc(db).ClaimNextJobAsync(s.Store, s.Agent);
            await Svc(db).FailJobAsync(job, s.Agent, "AGENT_ERROR", "lỗi");
        }
        Assert.Equal(0, (await LineAsync(s)).Sent);
        // Agent cũ (bản không chờ «đang in») thật ra đã in rồi báo xong muộn sau STUCK_CLAIMED.
        await using (var db = fx.NewDb())
            await db.PosPrintJobs.Where(j => j.Id == job).ExecuteUpdateAsync(x => x
                .SetProperty(j => j.Status, PosPrintJobStatus.Cancelled)
                .SetProperty(j => j.ErrorCode, PosPrintDispatchService.StuckClaimed));
        await using (var db = fx.NewDb())
            Assert.NotNull(await Svc(db).CompleteJobAsync(job, s.Agent));
        Assert.Equal(2, (await LineAsync(s)).Sent);
    }

    [Fact]
    public async Task Revert_without_any_job_for_unassigned_printer_returns_items()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        await using (var db = fx.NewDb())
            await Svc(db).RevertKitchenLinesAsync(s.Store, s.Order, [new KitchenLineRef(s.Line, 2)], "QR|x");
        Assert.Equal(0, (await LineAsync(s)).Sent);
    }
}
