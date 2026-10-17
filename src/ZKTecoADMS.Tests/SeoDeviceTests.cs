using ZKTecoADMS.Api.Seo;
using Xunit;

namespace ZKTecoADMS.Tests;

/// <summary>Trang sản phẩm máy chấm công: liên kết, ảnh và nội dung nằm trên SBOX, không trỏ sang website khác.</summary>
public class SeoDeviceTests
{
    static readonly SeoPages.DeviceOffer Face = new("ZKTeco SenseFace 2A", "Nhận diện khuôn mặt", "3.200.000 d", "3.500.000", "Khuôn mặt – Vân tay – Thẻ – WiFi", "ZKTeco");
    static readonly SeoPages.DeviceOffer Finger = new("Ronald Jack 8300Pro", "Máy chấm công vân tay ADMS", "2.200.000 d", null, "Vân tay – Thẻ – TCP/IP – ADMS", "Ronald Jack");

    [Fact]
    public void Slug_matches_home_page_javascript()
    {
        Assert.Equal("zkteco-senseface-2a", SeoPages.DeviceSlug("ZKTeco SenseFace 2A"));
        Assert.Equal("ronald-jack-8300pro", SeoPages.DeviceSlug("Ronald Jack 8300Pro"));
        Assert.Equal("zkteco-mb10vl", SeoPages.DeviceSlug("ZKTeco MB10VL"));
    }

    [Fact]
    public void Device_page_is_self_contained_with_product_schema()
    {
        var html = SeoPages.DevicePage(Face, [Face, Finger]);
        Assert.Contains("https://sboxhrm.com/lap-dat-may-cham-cong/san-pham/zkteco-senseface-2a", html);
        Assert.Contains("\"@type\":\"Product\"", html);
        Assert.Contains("\"price\":\"3200000\"", html);
        Assert.Contains("/images/devices/device-face.svg", html);
        Assert.Contains("FAQPage", html);
        Assert.Contains("lap-dat-may-cham-cong/san-pham/ronald-jack-8300pro", html); // liên kết sang máy khác
        Assert.DoesNotContain("maychamcong24h", html);
        Assert.Contains("1.500 (bản Entry)", html); // thông số chính hãng của SenseFace 2A
    }

    [Fact]
    public void Unknown_model_shows_only_admin_entered_specs()
    {
        var html = SeoPages.DevicePage(Finger, [Face, Finger]);
        Assert.Contains("/images/devices/device-fingerprint.svg", html);
        Assert.DoesNotContain("Bộ xử lý", html);
        Assert.Contains("Vân tay – Thẻ – TCP/IP – ADMS", html);
    }

    [Fact]
    public void Sitemap_lists_device_pages_for_hrm_only()
    {
        var hrm = SeoPages.Sitemap(SeoPages.Hrm, [], [Face, Finger]);
        Assert.Contains("/lap-dat-may-cham-cong/san-pham/zkteco-senseface-2a", hrm);
        var pos = SeoPages.Sitemap(SeoPages.Pos, [], [Face, Finger]);
        Assert.DoesNotContain("san-pham", pos);
    }
}
