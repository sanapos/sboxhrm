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
}
