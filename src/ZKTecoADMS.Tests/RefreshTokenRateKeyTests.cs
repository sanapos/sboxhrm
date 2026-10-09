using System.Text;
using Microsoft.AspNetCore.Http;
using Xunit;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests;

/// <summary>Giới hạn làm mới token theo từng refresh token (không theo IP, không chung với đăng nhập).</summary>
public class RefreshTokenRateKeyTests
{
    static DefaultHttpContext Ctx(string path, string body)
    {
        var bytes = Encoding.UTF8.GetBytes(body);
        var ctx = new DefaultHttpContext();
        ctx.Request.Method = "POST";
        ctx.Request.Path = path;
        ctx.Request.ContentType = "application/json";
        ctx.Request.ContentLength = bytes.Length;
        ctx.Request.Body = new MemoryStream(bytes);
        return ctx;
    }

    static async Task<(DefaultHttpContext Ctx, string BodySeenByAction)> RunAsync(string path, string body)
    {
        var ctx = Ctx(path, body);
        string seen = "";
        await RefreshTokenRateKey.CaptureAsync(ctx, async () =>
        {
            using var r = new StreamReader(ctx.Request.Body, leaveOpen: true);
            seen = await r.ReadToEndAsync();
        });
        return (ctx, seen);
    }

    [Fact]
    public async Task Lay_khoa_theo_refresh_token_va_action_van_doc_duoc_body()
    {
        const string body = """{"refreshToken":"abc123","deviceKey":"pos-1"}""";
        var (ctx, seen) = await RunAsync("/api/auth/refresh", body);
        Assert.Equal(RefreshTokenRateKey.Key("abc123"), ctx.Items[RefreshTokenRateKey.ItemKey]);
        Assert.StartsWith("rt:", (string)ctx.Items[RefreshTokenRateKey.ItemKey]!);
        Assert.Equal(body, seen); // model binding của action vẫn đọc được body
    }

    [Fact]
    public async Task Hai_phien_khac_nhau_khong_chung_luot()
    {
        var (a, _) = await RunAsync("/api/Auth/Refresh", """{"RefreshToken":"phien-A"}""");
        var (b, _) = await RunAsync("/api/auth/refresh", """{"refreshToken":"phien-B"}""");
        Assert.NotNull(a.Items[RefreshTokenRateKey.ItemKey]);
        Assert.NotEqual(a.Items[RefreshTokenRateKey.ItemKey], b.Items[RefreshTokenRateKey.ItemKey]);
        Assert.DoesNotContain("phien-A", (string)a.Items[RefreshTokenRateKey.ItemKey]!); // không giữ mã gốc
    }

    [Fact]
    public async Task Duong_dan_khac_hoac_body_la_khong_dat_khoa()
    {
        var (login, seen) = await RunAsync("/api/auth/login", """{"refreshToken":"x"}""");
        Assert.False(login.Items.ContainsKey(RefreshTokenRateKey.ItemKey));
        Assert.Contains("refreshToken", seen);
        var (bad, seenBad) = await RunAsync("/api/auth/refresh", "khong-phai-json");
        Assert.False(bad.Items.ContainsKey(RefreshTokenRateKey.ItemKey)); // rơi về giới hạn theo IP
        Assert.Equal("khong-phai-json", seenBad);
    }
}
