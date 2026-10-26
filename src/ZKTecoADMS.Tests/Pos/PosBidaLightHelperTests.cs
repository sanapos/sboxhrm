using Xunit;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests.Pos;

public class PosBidaLightHelperTests
{
    [Fact]
    public void Chua_bat_thi_khong_co_khoa_va_mac_dinh_tam_dung_van_sang()
    {
        var cfg = PosBidaLightHelper.Read("""{"qrOrder":{"requireGeofence":false}}""");
        Assert.Null(cfg.Secret);
        Assert.True(cfg.PausedOn);
    }

    [Fact]
    public void Ghi_roi_doc_lai_va_giu_cac_nut_khac()
    {
        var json = PosBidaLightHelper.Write("""{"sellTax":{"vatRate":10}}""", new("abc123", false));
        var cfg = PosBidaLightHelper.Read(json);
        Assert.Equal("abc123", cfg.Secret);
        Assert.False(cfg.PausedOn);
        Assert.Contains("vatRate", json);

        var off = PosBidaLightHelper.Write(json, new(null, true));
        Assert.Null(PosBidaLightHelper.Read(off).Secret);
        Assert.Contains("vatRate", off);
    }

    [Fact]
    public void App_luu_ExtraJson_cu_khong_lam_mat_hay_doi_khoa()
    {
        var server = """{"bidaLight":{"secret":"new","pausedOn":true},"a":1}""";
        var stale = """{"bidaLight":{"secret":"old","pausedOn":true},"a":2}""";
        var merged = PosBidaLightHelper.KeepServerNode(stale, server);
        Assert.Equal("new", PosBidaLightHelper.Read(merged).Secret);
        Assert.Contains("\"a\":2", merged);

        var withoutNode = PosBidaLightHelper.KeepServerNode("""{"a":3}""", server);
        Assert.Equal("new", PosBidaLightHelper.Read(withoutNode).Secret);

        // Server chưa bật mà app gửi khóa tự chế → bỏ.
        var forged = PosBidaLightHelper.KeepServerNode(stale, """{"a":1}""");
        Assert.Null(PosBidaLightHelper.Read(forged).Secret);
    }

    [Fact]
    public void Khoa_thiet_bi_tach_dung_cua_hang_va_bi_mat()
    {
        var store = Guid.NewGuid();
        var key = PosBidaLightHelper.DeviceKey(store, "deadbeef");
        Assert.True(PosBidaLightHelper.TryParseDeviceKey(key, out var s, out var secret));
        Assert.Equal(store, s);
        Assert.True(PosBidaLightHelper.SecretMatches("deadbeef", secret));
        Assert.False(PosBidaLightHelper.SecretMatches("deadbeee", secret));
        Assert.False(PosBidaLightHelper.SecretMatches(null, secret));

        Assert.False(PosBidaLightHelper.TryParseDeviceKey("", out _, out _));
        Assert.False(PosBidaLightHelper.TryParseDeviceKey(store.ToString() + "-x", out _, out _));
        Assert.False(PosBidaLightHelper.TryParseDeviceKey($"{store:N}-", out _, out _));
    }
}
