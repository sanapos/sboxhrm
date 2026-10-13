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
/// Hàng đợi in cloud (Agent): nhận / nhả / in xong / dọn treo — chạy trên PostgreSQL thật
/// (ExecuteUpdate, advisory lock, tranh chấp 2 Agent).
/// </summary>
[Collection("pos-pg")]
public class PosPrintDispatchTests(PosPgFixture fx)
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

    PosPrintDispatchService Svc(ZKTecoDbContext db) =>
        new(db, new NullHub(), NullLogger<PosPrintDispatchService>.Instance);

    record Setup(Guid Store, Guid Printer, Guid AgentA, Guid AgentB);

    async Task<Setup> SeedAsync(bool twoAgents = true)
    {
        var store = await fx.NewStoreAsync();
        var printer = Guid.NewGuid();
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        await using var db = fx.NewDb();
        db.PosStorePrinters.Add(new PosStorePrinter
        {
            Id = printer, StoreId = store, Name = "Bếp", ConnectionType = PosPrinterConnectionType.Lan,
            LanHost = "192.168.1.50", IsActive = true,
        });
        var json = $"[\"{printer}\"]";
        db.PosPrintAgents.Add(new PosPrintAgent
        {
            Id = a, StoreId = store, DeviceId = "dev-a", AssignedPrinterIdsJson = json,
            IsOnline = true, LastHeartbeatAt = DateTime.UtcNow, IsActive = true,
        });
        if (twoAgents)
            db.PosPrintAgents.Add(new PosPrintAgent
            {
                Id = b, StoreId = store, DeviceId = "dev-b", AssignedPrinterIdsJson = json,
                IsOnline = true, LastHeartbeatAt = DateTime.UtcNow, IsActive = true,
            });
        await db.SaveChangesAsync();
        return new Setup(store, printer, a, b);
    }

    async Task<Guid> QueueAsync(Setup s, PosPrintDocumentType type = PosPrintDocumentType.KitchenSlip,
        DateTime? createdAt = null)
    {
        var id = Guid.NewGuid();
        await using var db = fx.NewDb();
        db.PosPrintJobs.Add(new PosPrintJob
        {
            Id = id, StoreId = s.Store, PrinterId = s.Printer, DocumentType = type,
            PayloadFormat = PosPrintPayloadFormat.EscPosBase64, Payload = "AAAA" + id.ToString("N"),
            Copies = 1, Status = PosPrintJobStatus.Queued, ExpiresAt = DateTime.UtcNow.AddHours(1),
            CreatedAt = createdAt ?? DateTime.UtcNow, IsActive = true,
        });
        await db.SaveChangesAsync();
        return id;
    }

    async Task<PosPrintJob> JobAsync(Guid id)
    {
        await using var db = fx.NewDb();
        return await db.PosPrintJobs.AsNoTracking().FirstAsync(j => j.Id == id);
    }

    async Task<PosPrintJob?> ClaimAsync(Setup s, Guid agent, IReadOnlyCollection<Guid>? exclude = null)
    {
        await using var db = fx.NewDb();
        return await Svc(db).ClaimNextJobAsync(s.Store, agent, excludePrinterIds: exclude);
    }

    bool NoDb => fx.ConnectionString == null;

    [Fact]
    public async Task Claim_Print_Complete_HappyPath()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueAsync(s);
        var claimed = await ClaimAsync(s, s.AgentA);
        Assert.Equal(job, claimed?.Id);
        await using (var db = fx.NewDb())
        {
            Assert.NotNull(await Svc(db).MarkPrintingAsync(job, s.AgentA));
            Assert.NotNull(await Svc(db).CompleteJobAsync(job, s.AgentA));
        }
        Assert.Equal(PosPrintJobStatus.Completed, (await JobAsync(job)).Status);
    }

    [Fact]
    public async Task Release_NotLocalPort_OtherAgentGetsIt_ReleaserCooldown()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueAsync(s);
        Assert.Equal(job, (await ClaimAsync(s, s.AgentA))?.Id);
        await using (var db = fx.NewDb())
            await Svc(db).ReleaseClaimAsync(job, s.AgentA, "Máy này không kết nối được cổng in", "NOT_LOCAL_PORT");

        var j = await JobAsync(job);
        Assert.Equal(PosPrintJobStatus.Queued, j.Status);
        Assert.Equal(s.AgentA, j.ReleasedByAgentId);
        Assert.Equal("RELEASED_PORT", j.ErrorCode);

        // Agent vừa nhả không nhận lại (trước đây: nhả → nhận → nhả liên tục).
        Assert.Null(await ClaimAsync(s, s.AgentA));
        // Agent khác nhận được.
        Assert.Equal(job, (await ClaimAsync(s, s.AgentB))?.Id);
    }

    [Fact]
    public async Task Release_BothAgentsCannotOpenPort_FailsFast()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueAsync(s);
        Assert.Equal(job, (await ClaimAsync(s, s.AgentA))?.Id);
        await using (var db = fx.NewDb())
            await Svc(db).ReleaseClaimAsync(job, s.AgentA, "x", "NOT_LOCAL_PORT");
        Assert.Equal(job, (await ClaimAsync(s, s.AgentB))?.Id);
        await using (var db = fx.NewDb())
            await Svc(db).ReleaseClaimAsync(job, s.AgentB, "x", "NOT_LOCAL_PORT");

        var j = await JobAsync(job);
        Assert.Equal(PosPrintJobStatus.Failed, j.Status);
        Assert.Equal("NO_AGENT_PORT", j.ErrorCode);
    }

    [Fact]
    public async Task Release_OnlyAgent_FailsFast()
    {
        if (NoDb) return;
        var s = await SeedAsync(twoAgents: false);
        var job = await QueueAsync(s);
        Assert.Equal(job, (await ClaimAsync(s, s.AgentA))?.Id);
        await using (var db = fx.NewDb())
            await Svc(db).ReleaseClaimAsync(job, s.AgentA, "x", "NOT_LOCAL_PORT");
        Assert.Equal(PosPrintJobStatus.Failed, (await JobAsync(job)).Status);
    }

    [Fact]
    public async Task OutboundRelease_KeepsAttemptCount_AndCooldown()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueAsync(s);
        Assert.Equal(job, (await ClaimAsync(s, s.AgentA))?.Id);
        await using (var db = fx.NewDb())
            await Svc(db).ReleaseClaimAsync(job, s.AgentA, "Máy gửi lệnh — nhả cho Print Agent", "OUTBOUND_SKIP");
        var j = await JobAsync(job);
        Assert.Equal(PosPrintJobStatus.Queued, j.Status);
        Assert.Equal("RELEASED", j.ErrorCode);
        Assert.Equal(0, j.AttemptCount);
        Assert.Null(await ClaimAsync(s, s.AgentA));
        Assert.Equal(job, (await ClaimAsync(s, s.AgentB))?.Id);
    }

    [Fact]
    public async Task SamePrinter_NotGivenToSecondAgent_WhileFirstPrinting()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var j1 = await QueueAsync(s, createdAt: DateTime.UtcNow.AddSeconds(-2));
        var j2 = await QueueAsync(s);
        Assert.Equal(j1, (await ClaimAsync(s, s.AgentA))?.Id);
        // Agent B không được in đồng thời vào cùng máy in.
        Assert.Null(await ClaimAsync(s, s.AgentB));
        // Chính Agent A nhận tiếp được (tự xếp hàng trên máy nó)…
        // …trừ khi A báo máy đó đang bận (chạy song song theo máy in).
        Assert.Null(await ClaimAsync(s, s.AgentA, [s.Printer]));
        await using (var db = fx.NewDb())
        {
            await Svc(db).MarkPrintingAsync(j1, s.AgentA);
            await Svc(db).CompleteJobAsync(j1, s.AgentA);
        }
        Assert.Equal(j2, (await ClaimAsync(s, s.AgentB))?.Id);
    }

    [Fact]
    public async Task SamePrinter_HolderAgentDead_OtherAgentCanClaimNext()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var j1 = await QueueAsync(s, createdAt: DateTime.UtcNow.AddSeconds(-2));
        var j2 = await QueueAsync(s);
        Assert.Equal(j1, (await ClaimAsync(s, s.AgentA))?.Id);
        // Agent A mất heartbeat (tắt máy giữa chừng) → máy in không bị khóa theo nó.
        await using (var db = fx.NewDb())
            await db.PosPrintAgents.Where(a => a.Id == s.AgentA).ExecuteUpdateAsync(x => x
                .SetProperty(a => a.LastHeartbeatAt, DateTime.UtcNow.AddMinutes(-5)));
        Assert.Equal(j2, (await ClaimAsync(s, s.AgentB))?.Id);
    }

    [Fact]
    public async Task ConcurrentClaims_SamePrinter_OnlyOneAgentWins()
    {
        if (NoDb) return;
        for (var round = 0; round < 5; round++)
        {
            var s = await SeedAsync();
            await QueueAsync(s, createdAt: DateTime.UtcNow.AddSeconds(-2));
            await QueueAsync(s);
            var results = await Task.WhenAll(ClaimAsync(s, s.AgentA), ClaimAsync(s, s.AgentB));
            var winners = results.Where(r => r != null).ToList();
            Assert.Single(winners);

            await using var db = fx.NewDb();
            var active = await db.PosPrintJobs.AsNoTracking()
                .Where(j => j.StoreId == s.Store && j.Status == PosPrintJobStatus.Claimed)
                .Select(j => j.AgentId).Distinct().ToListAsync();
            Assert.Single(active);
        }
    }

    [Fact]
    public async Task ConcurrentClaims_DifferentJobs_NeverDuplicate()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueAsync(s);
        var results = await Task.WhenAll(Enumerable.Range(0, 6)
            .Select(i => ClaimAsync(s, i % 2 == 0 ? s.AgentA : s.AgentB)));
        Assert.Single(results, r => r?.Id == job);
        Assert.Equal(1, (await JobAsync(job)).AttemptCount);
    }

    [Fact]
    public async Task LateComplete_AfterStuckCancel_ByOwningAgent_MarksCompleted()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueAsync(s, PosPrintDocumentType.SaleInvoice);
        Assert.Equal(job, (await ClaimAsync(s, s.AgentA))?.Id);
        await using (var db = fx.NewDb())
        {
            await Svc(db).MarkPrintingAsync(job, s.AgentA);
            // Server hủy STUCK vì không nhận được «in xong» (mất mạng)…
            await db.PosPrintJobs.Where(j => j.Id == job).ExecuteUpdateAsync(x => x
                .SetProperty(j => j.Status, PosPrintJobStatus.Cancelled)
                .SetProperty(j => j.ErrorCode, "STUCK_NO_REQUEUE"));
            // …Agent khác báo xong: không nhận.
            Assert.Null(await Svc(db).CompleteJobAsync(job, s.AgentB));
            // Đúng Agent báo muộn: ghi «đã in».
            Assert.NotNull(await Svc(db).CompleteJobAsync(job, s.AgentA));
        }
        Assert.Equal(PosPrintJobStatus.Completed, (await JobAsync(job)).Status);
    }

    [Fact]
    public async Task LateComplete_AfterPrintTimeout_MarksCompleted()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueAsync(s);
        Assert.Equal(job, (await ClaimAsync(s, s.AgentA))?.Id);
        await using (var db = fx.NewDb())
        {
            await Svc(db).MarkPrintingAsync(job, s.AgentA);
            await Svc(db).FailJobAsync(job, s.AgentA, "PRINT_TIMEOUT", "Quá 75 giây");
            Assert.NotNull(await Svc(db).CompleteJobAsync(job, s.AgentA));
        }
        Assert.Equal(PosPrintJobStatus.Completed, (await JobAsync(job)).Status);
    }

    [Fact]
    public async Task Complete_RejectedForUserRetriedJob()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueAsync(s);
        Assert.Equal(job, (await ClaimAsync(s, s.AgentA))?.Id);
        await using (var db = fx.NewDb())
        {
            await Svc(db).FailJobAsync(job, s.AgentA, "PRINT_FAILED", "lỗi");
            await Svc(db).RetryJobAsync(s.Store, job, null, "thu ngân");
            // Lệnh «In lại» (có thể đã đổi máy in) không được đánh xong bởi báo cáo cũ.
            Assert.Null(await Svc(db).CompleteJobAsync(job, s.AgentA));
        }
        Assert.Equal(PosPrintJobStatus.Queued, (await JobAsync(job)).Status);
    }

    [Fact]
    public async Task Complete_IsIdempotent()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueAsync(s);
        await ClaimAsync(s, s.AgentA);
        await using var db = fx.NewDb();
        await Svc(db).MarkPrintingAsync(job, s.AgentA);
        Assert.NotNull(await Svc(db).CompleteJobAsync(job, s.AgentA));
        Assert.NotNull(await Svc(db).CompleteJobAsync(job, s.AgentA));
        Assert.Equal(PosPrintJobStatus.Completed, (await JobAsync(job)).Status);
    }

    [Fact]
    public async Task Sweep_CancelsStuckInvoice_WithoutAnyAgentClaiming()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueAsync(s, PosPrintDocumentType.SaleInvoice);
        await using (var db = fx.NewDb())
        {
            await db.PosPrintJobs.Where(j => j.Id == job).ExecuteUpdateAsync(x => x
                .SetProperty(j => j.Status, PosPrintJobStatus.Printing)
                .SetProperty(j => j.AgentId, s.AgentA)
                .SetProperty(j => j.ClaimedAt, DateTime.UtcNow.AddMinutes(-10)));
            await Svc(db).SweepStuckJobsAsync(s.Store);
        }
        var j = await JobAsync(job);
        Assert.Equal(PosPrintJobStatus.Cancelled, j.Status);
        Assert.Equal("STUCK_NO_REQUEUE", j.ErrorCode);
    }

    [Fact]
    public async Task Sweep_CancelsStaleQueued()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueAsync(s, createdAt: DateTime.UtcNow.AddMinutes(-10));
        await using (var db = fx.NewDb())
            await Svc(db).SweepStuckJobsAsync(s.Store);
        Assert.Equal("STALE_QUEUED", (await JobAsync(job)).ErrorCode);
    }

    [Fact]
    public async Task Sweep_KeepsOldJobJustRetried()
    {
        if (NoDb) return;
        var s = await SeedAsync();
        var job = await QueueAsync(s, createdAt: DateTime.UtcNow.AddMinutes(-30));
        await using (var db = fx.NewDb())
        {
            await db.PosPrintJobs.Where(j => j.Id == job).ExecuteUpdateAsync(x => x
                .SetProperty(j => j.Status, PosPrintJobStatus.Failed)
                .SetProperty(j => j.ErrorCode, "NO_AGENT_PORT"));
            await Svc(db).RetryJobAsync(s.Store, job, null, "test");
        }
        await using (var db = fx.NewDb())
            await Svc(db).SweepStuckJobsAsync(s.Store);
        var j = await JobAsync(job);
        Assert.Equal(PosPrintJobStatus.Queued, j.Status);
        Assert.Null(j.ErrorCode);
    }

    [Theory]
    [InlineData(PosPrintJobStatus.Printing, true, null, true)]
    [InlineData(PosPrintJobStatus.Printing, false, null, false)]
    [InlineData(PosPrintJobStatus.Claimed, true, null, true)]
    [InlineData(PosPrintJobStatus.Queued, null, "SOFT_REQUEUE", true)]
    [InlineData(PosPrintJobStatus.Queued, null, null, false)]
    [InlineData(PosPrintJobStatus.Queued, null, "RELEASED", false)]
    [InlineData(PosPrintJobStatus.Cancelled, true, "STUCK_NO_REQUEUE", true)]
    [InlineData(PosPrintJobStatus.Cancelled, true, "USER_CANCELLED", false)]
    [InlineData(PosPrintJobStatus.Cancelled, false, "STUCK_NO_REQUEUE", false)]
    [InlineData(PosPrintJobStatus.Failed, true, "PRINT_TIMEOUT", true)]
    [InlineData(PosPrintJobStatus.Failed, true, "PRINT_FAILED", false)]
    public void CanAcceptComplete_Rules(PosPrintJobStatus status, bool? sameAgent, string? code, bool expected)
    {
        var me = Guid.NewGuid();
        Guid? jobAgent = sameAgent switch { true => me, false => Guid.NewGuid(), null => null };
        Assert.Equal(expected, PosPrintDispatchService.CanAcceptComplete(status, jobAgent, code, me));
    }

    // ── Chốt tạo lệnh: máy đã tắt / máy không Agent nào nhận ────────────────────────────
    record RouteSetup(Guid Store, Guid Kitchen, Guid Inactive, Guid Orphan, Guid OfflineAgentPrinter);

    async Task<RouteSetup> SeedRoutingAsync()
    {
        var store = await fx.NewStoreAsync();
        var kitchen = Guid.NewGuid();
        var inactive = Guid.NewGuid();
        var orphan = Guid.NewGuid();
        var offline = Guid.NewGuid();
        await using var db = fx.NewDb();
        PosStorePrinter P(Guid id, string name, string host, bool active = true) => new()
        {
            Id = id, StoreId = store, Name = name, ConnectionType = PosPrinterConnectionType.Lan,
            LanHost = host, IsActive = active,
        };
        db.PosStorePrinters.AddRange(
            P(kitchen, "Bếp chính", "10.0.0.1"),
            P(inactive, "Bếp cũ", "10.0.0.2", active: false),
            P(orphan, "USB máy cũ", "10.0.0.3"),
            P(offline, "Bếp quầy 2", "10.0.0.4"));
        db.PosPrinterDocumentRoutes.Add(new PosPrinterDocumentRoute
        {
            Id = Guid.NewGuid(), StoreId = store, PrinterId = kitchen,
            DocumentType = PosPrintDocumentType.KitchenSlip, IsActive = true,
        });
        db.PosPrintAgents.Add(new PosPrintAgent
        {
            Id = Guid.NewGuid(), StoreId = store, DeviceId = "t1", AssignedPrinterIdsJson = $"[\"{kitchen}\"]",
            IsOnline = true, LastHeartbeatAt = DateTime.UtcNow, IsActive = true,
        });
        // Agent quầy 2 đang tắt máy 1 tiếng — máy của nó vẫn «có chủ».
        db.PosPrintAgents.Add(new PosPrintAgent
        {
            Id = Guid.NewGuid(), StoreId = store, DeviceId = "a7", AssignedPrinterIdsJson = $"[\"{offline}\"]",
            IsOnline = false, LastHeartbeatAt = DateTime.UtcNow.AddHours(-1), IsActive = true,
        });
        await db.SaveChangesAsync();
        return new RouteSetup(store, kitchen, inactive, orphan, offline);
    }

    async Task<PosPrintJob> EnqueueToAsync(Guid store, Guid printer)
    {
        await using var db = fx.NewDb();
        return await Svc(db).EnqueueJobAsync(new EnqueuePrintJobRequest(
            store, PosPrintDocumentType.KitchenSlip, PosPrintPayloadFormat.EscPosBase64,
            "AAAA" + Guid.NewGuid().ToString("N"), 1, "T-" + Guid.NewGuid().ToString("N")[..6], null,
            null, "test", PrinterIdOverride: printer));
    }

    [Fact]
    public async Task Enqueue_to_inactive_printer_goes_to_default_kitchen()
    {
        if (NoDb) return;
        var s = await SeedRoutingAsync();
        Assert.Equal(s.Kitchen, (await EnqueueToAsync(s.Store, s.Inactive)).PrinterId);
    }

    [Fact]
    public async Task Enqueue_to_printer_no_agent_serves_goes_to_default_kitchen()
    {
        if (NoDb) return;
        var s = await SeedRoutingAsync();
        Assert.Equal(s.Kitchen, (await EnqueueToAsync(s.Store, s.Orphan)).PrinterId);
    }

    [Fact]
    public async Task Enqueue_to_printer_of_offline_agent_stays_put()
    {
        if (NoDb) return;
        var s = await SeedRoutingAsync();
        // Agent tạm tắt → giữ đúng quầy, bật lại sẽ in; không đổ sang bếp chính.
        Assert.Equal(s.OfflineAgentPrinter, (await EnqueueToAsync(s.Store, s.OfflineAgentPrinter)).PrinterId);
    }

    [Fact]
    public async Task Enqueue_to_served_printer_unchanged()
    {
        if (NoDb) return;
        var s = await SeedRoutingAsync();
        Assert.Equal(s.Kitchen, (await EnqueueToAsync(s.Store, s.Kitchen)).PrinterId);
    }

    // ── Chống trùng theo đơn: phiếu bếp thêm món cùng đơn KHÔNG được coi là trùng ─────────────────
    async Task<PosPrintJob> EnqueueDocAsync(Guid store, Guid printer, PosPrintDocumentType type, Guid orderId,
        string payload)
    {
        await using var db = fx.NewDb();
        return await Svc(db).EnqueueJobAsync(new EnqueuePrintJobRequest(
            store, type, PosPrintPayloadFormat.KitchenSlipJson, payload, 1,
            "R-" + Guid.NewGuid().ToString("N")[..8], orderId, null, "test", PrinterIdOverride: printer));
    }

    [Fact]
    public async Task Kitchen_slips_same_order_different_items_are_not_deduped()
    {
        if (NoDb) return;
        var s = await SeedRoutingAsync();
        var order = Guid.NewGuid();
        var a = await EnqueueDocAsync(s.Store, s.Kitchen, PosPrintDocumentType.KitchenSlip, order, "{\"lines\":[\"Gỏi\"]}");
        var b = await EnqueueDocAsync(s.Store, s.Kitchen, PosPrintDocumentType.KitchenSlip, order, "{\"lines\":[\"Nem\"]}");
        Assert.NotEqual(a.Id, b.Id);
        // Nội dung giống hệt (gửi lặp) vẫn chặn.
        var c = await EnqueueDocAsync(s.Store, s.Kitchen, PosPrintDocumentType.KitchenSlip, order, "{\"lines\":[\"Nem\"]}");
        Assert.Equal(b.Id, c.Id);
    }

    [Fact]
    public async Task Invoice_same_order_still_deduped_while_queued()
    {
        if (NoDb) return;
        var s = await SeedRoutingAsync();
        var order = Guid.NewGuid();
        var a = await EnqueueDocAsync(s.Store, s.Kitchen, PosPrintDocumentType.SaleInvoice, order, "{\"v\":1}");
        var b = await EnqueueDocAsync(s.Store, s.Kitchen, PosPrintDocumentType.SaleInvoice, order, "{\"v\":2}");
        Assert.Equal(a.Id, b.Id);
    }

    [Fact]
    public async Task Kitchen_default_prefers_healthy_external_over_sunmi()
    {
        if (NoDb) return;
        var store = await fx.NewStoreAsync();
        Guid sunmi = Guid.NewGuid(), lan = Guid.NewGuid(), lanBroken = Guid.NewGuid();
        await using (var db = fx.NewDb())
        {
            db.PosStorePrinters.AddRange(
                new PosStorePrinter { Id = sunmi, StoreId = store, Name = "Sunmi", ConnectionType = PosPrinterConnectionType.Sunmi, IsActive = true, CreatedAt = DateTime.UtcNow.AddMinutes(-3) },
                new PosStorePrinter { Id = lanBroken, StoreId = store, Name = "LAN hỏng", ConnectionType = PosPrinterConnectionType.Lan, LanHost = "10.0.0.9", IsActive = true, HealthStatus = PosPrinterHealthStatus.Error, CreatedAt = DateTime.UtcNow.AddMinutes(-2) },
                new PosStorePrinter { Id = lan, StoreId = store, Name = "LAN bếp", ConnectionType = PosPrinterConnectionType.Lan, LanHost = "10.0.0.8", IsActive = true, CreatedAt = DateTime.UtcNow.AddMinutes(-1) });
            var t = DateTime.UtcNow.AddMinutes(-10);
            foreach (var (id, i) in new[] { (sunmi, 0), (lanBroken, 1), (lan, 2) })
                db.PosPrinterDocumentRoutes.Add(new PosPrinterDocumentRoute
                {
                    Id = Guid.NewGuid(), StoreId = store, PrinterId = id, IsActive = true,
                    DocumentType = PosPrintDocumentType.KitchenSlip, CreatedAt = t.AddSeconds(i),
                });
            await db.SaveChangesAsync();
        }
        await using (var db = fx.NewDb())
        {
            var list = await Svc(db).ResolvePrintersAsync(store, PosPrintDocumentType.KitchenSlip);
            Assert.Equal(new[] { lan, sunmi, lanBroken }, list.Select(p => p.Id).ToArray());
        }
    }

    // ── Mạng chập chờn: gửi lại / in lại không ra phiếu đôi, không nuốt phiếu ───────────────
    async Task<PosPrintJob> EnqueueRawAsync(Guid store, Guid printer, string payload, string refNo,
        string? clientRequestId = null, string? retryOf = null)
    {
        await using var db = fx.NewDb();
        return await Svc(db).EnqueueJobAsync(new EnqueuePrintJobRequest(
            store, PosPrintDocumentType.KitchenSlip, PosPrintPayloadFormat.KitchenSlipJson, payload, 1,
            refNo, null, null, "test", PrinterIdOverride: printer, ClientRequestId: clientRequestId,
            RetryOfReference: retryOf));
    }

    async Task SetStatusAsync(Guid jobId, PosPrintJobStatus status, string? code = null)
    {
        await using var db = fx.NewDb();
        DateTime? done = status == PosPrintJobStatus.Completed ? DateTime.UtcNow : null;
        await db.PosPrintJobs.Where(j => j.Id == jobId).ExecuteUpdateAsync(x => x
            .SetProperty(j => j.Status, status)
            .SetProperty(j => j.ErrorCode, code)
            .SetProperty(j => j.CompletedAt, done));
    }

    [Fact]
    public async Task Same_client_request_after_failure_requeues_old_job()
    {
        if (NoDb) return;
        var s = await SeedRoutingAsync();
        var a = await EnqueueRawAsync(s.Store, s.Kitchen, "{\"x\":1}", "R1", clientRequestId: "cr-1-abcdefgh");
        await SetStatusAsync(a.Id, PosPrintJobStatus.Failed, "NO_AGENT_PORT");
        var b = await EnqueueRawAsync(s.Store, s.Kitchen, "{\"x\":1}", "R1", clientRequestId: "cr-1-abcdefgh");
        Assert.Equal(a.Id, b.Id);
        Assert.Equal(PosPrintJobStatus.Queued, (await JobAsync(a.Id)).Status);
    }

    [Fact]
    public async Task Same_client_request_after_completed_does_not_print_again()
    {
        if (NoDb) return;
        var s = await SeedRoutingAsync();
        var a = await EnqueueRawAsync(s.Store, s.Kitchen, "{\"x\":2}", "R2", clientRequestId: "cr-2-abcdefgh");
        await SetStatusAsync(a.Id, PosPrintJobStatus.Completed);
        var b = await EnqueueRawAsync(s.Store, s.Kitchen, "{\"x\":2}", "R2", clientRequestId: "cr-2-abcdefgh");
        Assert.Equal(a.Id, b.Id);
        Assert.Equal(PosPrintJobStatus.Completed, (await JobAsync(a.Id)).Status);
    }

    [Fact]
    public async Task Retry_of_printed_reference_returns_original_same_printer_only()
    {
        if (NoDb) return;
        var s = await SeedRoutingAsync();
        var a = await EnqueueRawAsync(s.Store, s.Kitchen, "{\"x\":3}", "ksend|HD1|abc");
        await SetStatusAsync(a.Id, PosPrintJobStatus.Completed);
        // In lại từ «In treo» (mã mới + khóa gốc) → lần đầu đã in → không ra phiếu thứ hai.
        var b = await EnqueueRawAsync(s.Store, s.Kitchen, "{\"x\":3,\"r\":1}", "ksend|HD1|abc|r|1",
            retryOf: "ksend|HD1|abc");
        Assert.Equal(a.Id, b.Id);
        // Chuyển sang máy khác → in thật.
        var c = await EnqueueRawAsync(s.Store, s.OfflineAgentPrinter, "{\"x\":3,\"r\":2}", "ksend|HD1|abc|r|2",
            retryOf: "ksend|HD1|abc");
        Assert.NotEqual(a.Id, c.Id);
    }

    [Fact]
    public async Task Retry_of_failed_reference_prints_new_job()
    {
        if (NoDb) return;
        var s = await SeedRoutingAsync();
        var a = await EnqueueRawAsync(s.Store, s.Kitchen, "{\"x\":4}", "ksend|HD2|abc");
        await SetStatusAsync(a.Id, PosPrintJobStatus.Failed, "NO_AGENT_PORT");
        var b = await EnqueueRawAsync(s.Store, s.Kitchen, "{\"x\":4,\"r\":1}", "ksend|HD2|abc|r|1",
            retryOf: "ksend|HD2|abc");
        Assert.NotEqual(a.Id, b.Id);
    }
}
