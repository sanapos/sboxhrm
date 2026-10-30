using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Zalo bot: liên kết bằng mã 6 số qua webhook (bí mật, hết hạn, hủy), chọn tin đưa vào hàng đợi (cửa hàng bật bot,
/// nhóm thông báo, người đã liên kết, ẩn số tiền), gửi hàng đợi + thử lại / token hỏng.
/// </summary>
public class ZaloBotTests
{
    static readonly DateTime Now = new(2026, 10, 30, 3, 0, 0, DateTimeKind.Utc);
    static readonly Guid StoreId = Guid.NewGuid();
    static readonly Guid UserA = Guid.NewGuid();
    static readonly Guid UserB = Guid.NewGuid();

    static ZKTecoDbContext NewDb(string name) => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(name)
        .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
        .Options);

    static readonly ZaloBotSecrets Secrets = new(new ConfigurationBuilder()
        .AddInMemoryCollection(new Dictionary<string, string?> { ["JwtSettings:AccessTokenSecret"] = "test-secret-123" })
        .Build());

    sealed class FakeClient : IZaloBotClient
    {
        public readonly List<(string Token, string ChatId, string Text)> Sent = [];
        public Func<string, ZaloBotResult> SendResult = _ => new ZaloBotResult(true, null, null, null);

        public Task<ZaloBotResult> GetMeAsync(string token, CancellationToken ct = default) =>
            Task.FromResult(token == "good"
                ? new ZaloBotResult(true, null, null, JsonDocument.Parse("""{"id":"b1","account_name":"Bot Cafe"}""").RootElement)
                : new ZaloBotResult(false, 401, "Unauthorized", null));

        public Task<ZaloBotResult> SetWebhookAsync(string token, string url, string secret, CancellationToken ct = default) =>
            Task.FromResult(new ZaloBotResult(true, null, null, null));

        public Task<ZaloBotResult> SendMessageAsync(string token, string chatId, string text, CancellationToken ct = default)
        {
            Sent.Add((token, chatId, text));
            return Task.FromResult(SendResult(chatId));
        }
    }

    static async Task<ZaloBotSetting> SeedAsync(ZKTecoDbContext db, bool enabled = true, string categories = ZaloBotText.DefaultCategories, bool hideMoney = false)
    {
        db.Stores.Add(new Store { Id = StoreId, Name = "Cafe An" });
        db.Users.Add(new ApplicationUser { Id = UserA, UserName = "a", FirstName = "Nguyễn", LastName = "An", StoreId = StoreId });
        db.Users.Add(new ApplicationUser { Id = UserB, UserName = "b", FirstName = "Trần", LastName = "Bình", StoreId = StoreId });
        var s = new ZaloBotSetting
        {
            Id = Guid.NewGuid(),
            StoreId = StoreId,
            Enabled = enabled,
            BotTokenEnc = Secrets.Protect("good"),
            WebhookSecret = "s3cret-value",
            Categories = categories,
            HideMoney = hideMoney,
        };
        db.ZaloBotSettings.Add(s);
        await db.SaveChangesAsync();
        return s;
    }

    static JsonElement Msg(string text, string chatId = "chat-1", string name = "An Zalo") =>
        JsonDocument.Parse(JsonSerializer.Serialize(new
        {
            event_name = "message.text.received",
            message = new
            {
                message_id = "m1",
                from = new { id = chatId, display_name = name, is_bot = false },
                chat = new { id = chatId, chat_type = "PRIVATE" },
                text,
            },
        })).RootElement;

    static ZaloBotService Svc(ZKTecoDbContext db, FakeClient c) =>
        new(db, c, Secrets, NullLogger<ZaloBotService>.Instance);

    // ─── Văn bản ─────────────────────────────────────────────────

    [Theory]
    [InlineData("Thực lĩnh: 6.000.000 VND.", "Thực lĩnh: ***đ.")]
    [InlineData("Phạt 20.000đ (trừ lương)", "Phạt ***đ (trừ lương)")]
    [InlineData("Ca 2 bắt đầu 13:00", "Ca 2 bắt đầu 13:00")]
    public void MaskMoney_hides_amounts_only(string input, string expected) =>
        Assert.Equal(expected, ZaloBotText.MaskMoney(input));

    [Theory]
    [InlineData("123456", "123456")]
    [InlineData(" 123 456 ", "123456")]
    [InlineData("#123-456", "123456")]
    [InlineData("12345", null)]
    [InlineData("xin chào", null)]
    public void ExtractLinkCode(string text, string? expected) =>
        Assert.Equal(expected, ZaloBotText.ExtractLinkCode(text));

    [Fact]
    public void Categories_keep_canonical_order_and_drop_unknown()
    {
        Assert.Equal("payroll,leave,system", ZaloBotText.JoinCategories(["system", "LEAVE", "bogus", "payroll", "leave"]));
        Assert.Equal(["payroll", "shift"], ZaloBotText.ParseCategories("payroll, x ,shift"));
    }

    [Fact]
    public void FormatNotification_respects_2000_char_limit()
    {
        var text = ZaloBotText.FormatNotification("Tiêu đề", new string('a', 3000), false, "https://sboxhrm.com");
        Assert.Equal(ZaloBotClient.MaxTextLength, text.Length);
        Assert.StartsWith("🔔 Tiêu đề\n", text);
    }

    [Fact]
    public void Parse_api_envelope()
    {
        Assert.True(ZaloBotClient.Parse("""{"ok":true,"result":{"message_id":"x"}}""", 200).Ok);
        var err = ZaloBotClient.Parse("""{"ok":false,"error_code":401,"description":"Unauthorized"}""", 200);
        Assert.True(err.TokenInvalid);
        Assert.True(ZaloBotClient.Parse("<html>bad gateway</html>", 429).RateLimited);
    }

    [Fact]
    public void Secrets_roundtrip_and_reject_garbage()
    {
        var enc = Secrets.Protect("123:abc");
        Assert.NotEqual("123:abc", enc);
        Assert.Equal("123:abc", Secrets.Unprotect(enc));
        Assert.Null(Secrets.Unprotect("not-base64!"));
    }

    // ─── Kết nối + liên kết ──────────────────────────────────────

    [Fact]
    public async Task Connect_rejects_bad_token_and_stores_encrypted_good_token()
    {
        using var db = NewDb(nameof(Connect_rejects_bad_token_and_stores_encrypted_good_token));
        var svc = Svc(db, new FakeClient());
        var s = new ZaloBotSetting { Id = Guid.NewGuid(), StoreId = StoreId };

        Assert.NotNull(await svc.ConnectAsync(s, "bad", "https://sboxhrm.com", default));
        Assert.Null(s.BotTokenEnc);

        Assert.Null(await svc.ConnectAsync(s, " good ", "https://sboxhrm.com", default));
        Assert.Equal("good", svc.Token(s));
        Assert.Equal("Bot Cafe", s.BotName);
        Assert.True(s.WebhookOk);
        Assert.True(s.WebhookSecret.Length >= 8);
    }

    [Fact]
    public async Task Webhook_links_with_valid_code_then_unlinks()
    {
        using var db = NewDb(nameof(Webhook_links_with_valid_code_then_unlinks));
        var s = await SeedAsync(db);
        var client = new FakeClient();
        var svc = Svc(db, client);

        var link = await svc.CreateLinkCodeAsync(StoreId, UserA, Now, default);
        Assert.Matches("^[0-9]{6}$", link.PendingCode!);

        Assert.Equal(403, await svc.HandleWebhookAsync(s.Id, "wrong", Msg(link.PendingCode!), Now, default));
        Assert.Equal(404, await svc.HandleWebhookAsync(Guid.NewGuid(), "s3cret-value", Msg(link.PendingCode!), Now, default));
        Assert.Empty(client.Sent);

        Assert.Equal(200, await svc.HandleWebhookAsync(s.Id, "s3cret-value", Msg(link.PendingCode!), Now.AddMinutes(5), default));
        var saved = await db.ZaloBotLinks.SingleAsync(l => l.UserId == UserA);
        Assert.Equal("chat-1", saved.ChatId);
        Assert.Equal("An Zalo", saved.ZaloName);
        Assert.Null(saved.PendingCode);
        Assert.Contains("Nguyễn An", client.Sent[^1].Text);
        Assert.Contains("Cafe An", client.Sent[^1].Text);

        await svc.HandleWebhookAsync(s.Id, "s3cret-value", Msg("HUY"), Now, default);
        Assert.Null((await db.ZaloBotLinks.SingleAsync(l => l.UserId == UserA)).ChatId);
        Assert.Contains("hủy liên kết", client.Sent[^1].Text);
    }

    [Fact]
    public async Task Webhook_rejects_expired_code()
    {
        using var db = NewDb(nameof(Webhook_rejects_expired_code));
        var s = await SeedAsync(db);
        var client = new FakeClient();
        var svc = Svc(db, client);
        var link = await svc.CreateLinkCodeAsync(StoreId, UserA, Now, default);

        await svc.HandleWebhookAsync(s.Id, "s3cret-value", Msg(link.PendingCode!), Now.AddMinutes(16), default);

        Assert.Null((await db.ZaloBotLinks.SingleAsync()).ChatId);
        Assert.Contains("hết hạn", client.Sent.Single().Text);
    }

    // ─── Hàng đợi ────────────────────────────────────────────────

    static Notification Notif(Guid user, string category, string title = "Phiếu lương đã chốt",
        string message = "Thực lĩnh: 6.000.000 VND.") => new()
    {
        Id = Guid.NewGuid(),
        TargetUserId = user,
        StoreId = StoreId,
        Title = title,
        Message = message,
        CategoryCode = category,
    };

    static async Task LinkAsync(ZKTecoDbContext db, Guid user, string chatId)
    {
        db.ZaloBotLinks.Add(new ZaloBotLink { Id = Guid.NewGuid(), StoreId = StoreId, UserId = user, ChatId = chatId, LinkedAt = Now });
        await db.SaveChangesAsync();
    }

    [Fact]
    public async Task Enqueue_only_linked_users_and_enabled_categories()
    {
        using var db = NewDb(nameof(Enqueue_only_linked_users_and_enabled_categories));
        await SeedAsync(db, categories: "payroll");
        await LinkAsync(db, UserA, "chat-a");

        var n = await ZaloBotService.EnqueueAsync(db,
            [Notif(UserA, "salary"), Notif(UserA, "task"), Notif(UserB, "payroll")], "https://sboxhrm.com");

        Assert.Equal(1, n);
        var m = await db.ZaloBotMessages.SingleAsync();
        Assert.Equal("chat-a", m.ChatId);
        Assert.Equal("payroll", m.CategoryCode);
        Assert.Contains("6.000.000 VND", m.Text);
        Assert.Contains("https://sboxhrm.com", m.Text);
    }

    [Fact]
    public async Task Enqueue_masks_money_and_skips_disabled_store()
    {
        using var db = NewDb(nameof(Enqueue_masks_money_and_skips_disabled_store));
        var s = await SeedAsync(db, hideMoney: true);
        await LinkAsync(db, UserA, "chat-a");

        await ZaloBotService.EnqueueAsync(db, [Notif(UserA, "payroll")], null);
        Assert.Contains("***đ", (await db.ZaloBotMessages.SingleAsync()).Text);

        var tracked = await db.ZaloBotSettings.AsTracking().SingleAsync();
        tracked.Enabled = false;
        await db.SaveChangesAsync();
        Assert.Equal(0, await ZaloBotService.EnqueueAsync(db, [Notif(UserA, "payroll")], null));
    }

    // ─── Gửi ─────────────────────────────────────────────────────

    static ZaloBotMessage Queued(string chatId) => new()
    {
        Id = Guid.NewGuid(),
        StoreId = StoreId,
        UserId = UserA,
        ChatId = chatId,
        Text = "hello",
        NextAttemptAt = Now.AddMinutes(-1),
    };

    [Fact]
    public async Task Process_sends_and_retries_with_backoff()
    {
        using var db = NewDb(nameof(Process_sends_and_retries_with_backoff));
        await SeedAsync(db);
        db.ZaloBotMessages.AddRange(Queued("ok"), Queued("fail"));
        await db.SaveChangesAsync();
        var client = new FakeClient { SendResult = c => c == "ok" ? new(true, null, null, null) : new(false, 408, "timeout", null) };

        Assert.Equal(1, await Svc(db, client).ProcessBatchAsync(Now, 50, default));

        var ok = await db.ZaloBotMessages.SingleAsync(m => m.ChatId == "ok");
        Assert.Equal(ZaloBotService.Sent, ok.Status);
        var fail = await db.ZaloBotMessages.SingleAsync(m => m.ChatId == "fail");
        Assert.Equal(ZaloBotService.Pending, fail.Status);
        Assert.Equal(1, fail.Attempts);
        Assert.Equal(Now.AddMinutes(1), fail.NextAttemptAt);

        // Chưa đến hạn → không gửi lại
        Assert.Equal(0, await Svc(db, client).ProcessBatchAsync(Now.AddSeconds(30), 50, default));
        Assert.Equal(2, client.Sent.Count);
    }

    [Fact]
    public async Task Process_fails_after_max_attempts_and_flags_dead_token()
    {
        using var db = NewDb(nameof(Process_fails_after_max_attempts_and_flags_dead_token));
        await SeedAsync(db);
        var m = Queued("x");
        m.Attempts = ZaloBotService.MaxAttempts - 1;
        db.ZaloBotMessages.AddRange(m, Queued("y"));
        await db.SaveChangesAsync();
        var client = new FakeClient { SendResult = _ => new(false, 401, "Unauthorized", null) };

        await Svc(db, client).ProcessBatchAsync(Now, 50, default);

        Assert.Single(client.Sent); // token hỏng → không gọi tiếp cho tin sau
        Assert.Equal(ZaloBotService.Failed, (await db.ZaloBotMessages.SingleAsync(x => x.Id == m.Id)).Status);
        Assert.Equal(ZaloBotService.Pending, (await db.ZaloBotMessages.SingleAsync(x => x.ChatId == "y")).Status);
        Assert.Contains("Token", (await db.ZaloBotSettings.SingleAsync()).LastError);
    }

    [Fact]
    public async Task Process_drops_messages_when_bot_disabled()
    {
        using var db = NewDb(nameof(Process_drops_messages_when_bot_disabled));
        await SeedAsync(db, enabled: false);
        db.ZaloBotMessages.Add(Queued("x"));
        await db.SaveChangesAsync();
        var client = new FakeClient();

        await Svc(db, client).ProcessBatchAsync(Now, 50, default);

        Assert.Empty(client.Sent);
        Assert.Equal(ZaloBotService.Failed, (await db.ZaloBotMessages.SingleAsync()).Status);
    }
}
