using System.Text.Json.Nodes;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests;

/// <summary>Form hàng hóa lưu chung cả cửa hàng trong ExtraJson.productForm.</summary>
public class ProductFormLayoutTests
{
    [Fact]
    public void Merge_keeps_other_keys_and_replaces_layout()
    {
        const string extra = """{"sellTax":{"vatRate":8},"ProductForm":{"preset":"food","sections":["recipe"]}}""";
        var json = PosSellIndustryController.MergeProductFormLayout(extra, "electronics", ["warranty", "serial"]);
        var root = JsonNode.Parse(json)!.AsObject();

        Assert.Equal(8, root["sellTax"]!["vatRate"]!.GetValue<int>());
        Assert.False(root.ContainsKey("ProductForm"));
        Assert.Equal("electronics", root["productForm"]!["preset"]!.GetValue<string>());
        Assert.Equal(["warranty", "serial"], root["productForm"]!["sections"]!.AsArray().Select(x => x!.GetValue<string>()));
    }

    [Fact]
    public void Merge_recovers_from_broken_json()
    {
        var json = PosSellIndustryController.MergeProductFormLayout("{oops", "", []);
        Assert.Empty(JsonNode.Parse(json)!["productForm"]!["sections"]!.AsArray());
    }

    [Fact]
    public void Layout_change_needs_product_permission_not_store_settings()
    {
        var a = new PosStoreSellSettings { ExtraJson = """{"sellTax":{"vatRate":8}}""" };
        var b = SellSettingsAccess.Snapshot(a);
        b.ExtraJson = PosSellIndustryController.MergeProductFormLayout(a.ExtraJson, "fashion", ["brand"]);

        var sections = SellSettingsAccess.ChangedSections(a, b);
        Assert.Equal(["productForm"], sections.Select(s => s.Key));
        Assert.Contains("PosProducts", sections[0].Modules);
    }
}
