using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Kích hoạt / cấp license key trên PostgreSQL thật (transaction, ExecuteUpdate, kích đồng thời).</summary>
[Collection("pos-pg")]
public class LicenseKeyActivationTests(PosPgFixture fx)
{
    private bool NoDb => fx.ConnectionString == null;

    private async Task<Guid> NewAgentAsync()
    {
        var id = Guid.NewGuid();
        await using var db = fx.NewDb();
        db.Agents.Add(new Agent { Id = id, Name = "ĐL " + id.ToString("N")[..6], Code = "DL" + id.ToString("N")[..8] });
        await db.SaveChangesAsync();
        return id;
    }

    private async Task<Guid> NewStoreAsync(Guid? agentId, Action<Store>? configure = null)
    {
        var id = await fx.NewStoreAsync();
        await using var db = fx.NewDb();
        var s = await db.Stores.AsTracking().FirstAsync(x => x.Id == id);
        s.AgentId = agentId;
        configure?.Invoke(s);
        await db.SaveChangesAsync();
        return id;
    }

    private async Task<LicenseKey> NewKeyAsync(Guid? agentId, int days = 30, bool active = true)
    {
        var k = new LicenseKey
        {
            Id = Guid.NewGuid(),
            Key = "BAS-" + Guid.NewGuid().ToString("N")[..12].ToUpperInvariant(),
            DurationDays = days,
            MaxUsers = 10,
            MaxDevices = 2,
            AgentId = agentId,
            IsActive = active,
        };
        await using var db = fx.NewDb();
        db.LicenseKeys.Add(k);
        await db.SaveChangesAsync();
        return k;
    }

    private async Task<LicenseKeyActivator.Outcome> ActivateAsync(Guid storeId, Guid? actingAgentId, params string[] keys)
    {
        await using var db = fx.NewDb();
        var store = await db.Stores.AsTracking().FirstAsync(s => s.Id == storeId);
        return await LicenseKeyActivator.ActivateAsync(db, store, keys, actingAgentId, Guid.NewGuid().ToString());
    }

    private async Task<LicenseKey> KeyAsync(Guid id)
    {
        await using var db = fx.NewDb();
        return await db.LicenseKeys.FirstAsync(k => k.Id == id);
    }

    private async Task<Store> StoreAsync(Guid id)
    {
        await using var db = fx.NewDb();
        return await db.Stores.FirstAsync(s => s.Id == id);
    }

    [Fact]
    public async Task Agent_cannot_use_unassigned_pool_key_nor_see_it()
    {
        if (NoDb) return;
        var agent = await NewAgentAsync();
        var store = await NewStoreAsync(agent);
        var pool = await NewKeyAsync(agentId: null);
        var own = await NewKeyAsync(agent);

        var r = await ActivateAsync(store, agent, pool.Key);

        Assert.False(r.Ok);
        Assert.Contains("đã được cấp cho đại lý", r.Error);
        Assert.False((await KeyAsync(pool.Id)).IsUsed);

        await using var db = fx.NewDb();
        var s = await db.Stores.FirstAsync(x => x.Id == store);
        var visible = await LicenseKeyActivationHelper
            .FilterActivatableForStore(db.LicenseKeys, s, agent)
            .Select(k => k.Id).ToListAsync();
        Assert.Contains(own.Id, visible);
        Assert.DoesNotContain(pool.Id, visible);
    }

    [Fact]
    public async Task Key_activation_adds_days_to_remaining_and_ignores_trial_renewal_limit()
    {
        if (NoDb) return;
        var agent = await NewAgentAsync();
        var today = DateTime.UtcNow.Date;
        // Đã kích key trước đó và đã gia hạn dùng thử 3 lần — kích key vẫn phải được.
        var store = await NewStoreAsync(agent, s =>
        {
            s.LicenseKey = "BAS-OLD";
            s.RenewalCount = 3;
            s.ExpiryDate = today.AddDays(10);
            s.IsLocked = true;
        });
        var key = await NewKeyAsync(agent, days: 30);

        var r = await ActivateAsync(store, agent, key.Key.ToLowerInvariant()); // nhập chữ thường vẫn nhận

        Assert.True(r.Ok, r.Error);
        var s = await StoreAsync(store);
        Assert.Equal(today.AddDays(40), s.ExpiryDate!.Value.Date);
        Assert.Equal(3, s.RenewalCount);
        Assert.False(s.IsLocked);
        var k = await KeyAsync(key.Id);
        Assert.True(k.IsUsed);
        Assert.Equal(store, k.StoreId);

        await using var db = fx.NewDb();
        Assert.True(await db.AuditLogs.AnyAsync(a =>
            a.StoreId == store && a.Action == AuditActions.LicenseActivated));
    }

    [Fact]
    public async Task Trial_store_keeps_remaining_trial_days()
    {
        if (NoDb) return;
        var today = DateTime.UtcNow.Date;
        var store = await NewStoreAsync(null, s =>
        {
            s.TrialStartDate = today.AddDays(-4);
            s.TrialDays = 14; // còn 10 ngày
        });
        var key = await NewKeyAsync(null, days: 30);

        var r = await ActivateAsync(store, null, key.Key);

        Assert.True(r.Ok, r.Error);
        Assert.Equal(today.AddDays(40), (await StoreAsync(store)).ExpiryDate!.Value.Date);
    }

    [Fact]
    public async Task Zero_day_key_is_rejected_and_not_burned()
    {
        if (NoDb) return;
        var store = await NewStoreAsync(null);
        var key = await NewKeyAsync(null, days: 0);

        var r = await ActivateAsync(store, null, key.Key);

        Assert.False(r.Ok);
        Assert.False((await KeyAsync(key.Id)).IsUsed);
        Assert.Null((await StoreAsync(store)).ExpiryDate);
    }

    [Fact]
    public async Task Bulk_is_all_or_nothing()
    {
        if (NoDb) return;
        var store = await NewStoreAsync(null);
        var good = await NewKeyAsync(null);
        var revoked = await NewKeyAsync(null, active: false);

        var r = await ActivateAsync(store, null, good.Key, revoked.Key);

        Assert.False(r.Ok);
        Assert.Contains(revoked.Key, r.Error);
        Assert.False((await KeyAsync(good.Id)).IsUsed);
        Assert.Null((await StoreAsync(store)).ExpiryDate);
    }

    [Fact]
    public async Task Same_key_activated_concurrently_only_once()
    {
        if (NoDb) return;
        var storeA = await NewStoreAsync(null);
        var storeB = await NewStoreAsync(null);
        var key = await NewKeyAsync(null);

        var results = await Task.WhenAll(
            ActivateAsync(storeA, null, key.Key),
            ActivateAsync(storeB, null, key.Key));

        Assert.Single(results, r => r.Ok);
        var winner = (await KeyAsync(key.Id)).StoreId;
        var loser = winner == storeA ? storeB : storeA;
        Assert.NotNull((await StoreAsync(winner!.Value)).ExpiryDate);
        Assert.Null((await StoreAsync(loser)).ExpiryDate); // bên thua không được cộng ngày
    }

    [Fact]
    public async Task Assigning_key_never_moves_it_from_another_agent()
    {
        if (NoDb) return;
        var agentA = await NewAgentAsync();
        var agentB = await NewAgentAsync();
        var key = await NewKeyAsync(agentA);

        await using (var db = fx.NewDb())
        {
            var (ok, err) = await AgentAssignmentPersistHelper.AssignLicenseToAgentAsync(db, key.Id, agentB, "test");
            Assert.False(ok);
            Assert.Equal(AgentAssignmentPersistHelper.LicenseAlreadyAssignedMessage, err);
        }
        Assert.Equal(agentA, (await KeyAsync(key.Id)).AgentId);

        await using (var db = fx.NewDb())
        {
            var (ok, _) = await AgentAssignmentPersistHelper.AssignLicenseToAgentAsync(db, key.Id, agentA, "test");
            Assert.True(ok); // gán lại đúng đại lý cũ: không lỗi
        }
    }
}
