using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests;

/// <summary>Thiết lập bán hàng: mỗi nhóm trường cần quyền riêng.</summary>
public class SellSettingsAccessTests
{
    static PosStoreSellSettings Base() => new()
    {
        ExtraJson = """{"sellTax":{"mode":"per_item","vatRate":10},"customerDisplay":{"viewerCode":"abc"},"qrOrder":{"requireGeofence":false}}""",
    };

    static string[] Keys(PosStoreSellSettings before, PosStoreSellSettings after) =>
        SellSettingsAccess.ChangedSections(before, after).Select(s => s.Key).ToArray();

    [Fact]
    public void Unchanged_or_reformatted_json_needs_nothing()
    {
        var a = Base();
        var b = SellSettingsAccess.Snapshot(a);
        b.ExtraJson = """{ "qrOrder": {"requireGeofence": false}, "customerDisplay": {"viewerCode": "abc"}, "sellTax": {"vatRate": 10, "mode": "per_item"} }""";
        Assert.Empty(Keys(a, b));
    }

    [Fact]
    public void Customer_display_change_only_needs_customer_display()
    {
        var a = Base();
        var b = SellSettingsAccess.Snapshot(a);
        b.ExtraJson = a.ExtraJson!.Replace("\"abc\"", "\"xyz1234567\"");
        Assert.Equal(["customerDisplay"], Keys(a, b));
    }

    [Fact]
    public void Tax_change_needs_store_settings()
    {
        var a = Base();
        var b = SellSettingsAccess.Snapshot(a);
        b.ExtraJson = a.ExtraJson!.Replace("\"vatRate\":10", "\"vatRate\":8");
        Assert.Equal(["store"], Keys(a, b));
    }

    [Fact]
    public void Flags_map_to_their_sections()
    {
        var a = Base();
        var b = SellSettingsAccess.Snapshot(a);
        b.EnableQrTableOrder = true;
        b.ReportDayStartHour = 6;
        b.AllowNegativeStock = true;
        b.LoyaltyEnabled = !a.LoyaltyEnabled;
        Assert.Equal(new[] { "endOfDay", "qrOrder", "stock", "store" }, Keys(a, b).OrderBy(x => x));
    }

    [Fact]
    public void Broken_json_counts_as_store_change()
    {
        var a = Base();
        var b = SellSettingsAccess.Snapshot(a);
        b.ExtraJson = "{not json";
        Assert.Equal(["store"], Keys(a, b));
    }
}
