using System.Text.Json;
using Xunit;
using ZKTecoADMS.Api.Controllers;

namespace ZKTecoADMS.Tests;

/// <summary>Tên/địa chỉ/SĐT trên hóa đơn mặc định theo thông tin cửa hàng khi chủ chưa đặt.</summary>
public class ReceiptStoreDefaultTests
{
    static JsonElement Rs(string? json) => JsonDocument.Parse(json!).RootElement.GetProperty("receiptStore");

    [Fact]
    public void Cua_hang_moi_chua_co_ExtraJson_lay_ten_cua_hang()
    {
        var json = PosSellIndustryController.WithReceiptStoreDefault(null, "Quán Mây", "12 Bạch Đằng, Đà Nẵng", "0905123456");
        var rs = Rs(json);
        Assert.Equal("Quán Mây", rs.GetProperty("name").GetString());
        Assert.Equal("12 Bạch Đằng, Đà Nẵng", rs.GetProperty("address").GetString());
        Assert.Equal("0905123456", rs.GetProperty("phone").GetString());
    }

    [Fact]
    public void Gia_tri_chu_da_dat_giu_nguyen_chi_dien_cho_trong()
    {
        var extra = """{"sellTax":{"mode":"added"},"receiptStore":{"name":"Mây Coffee - CN1","address":"","phone":null}}""";
        var json = PosSellIndustryController.WithReceiptStoreDefault(extra, "Quán Mây", "12 Bạch Đằng", "0905123456");
        var rs = Rs(json);
        Assert.Equal("Mây Coffee - CN1", rs.GetProperty("name").GetString());
        Assert.Equal("12 Bạch Đằng", rs.GetProperty("address").GetString());
        Assert.Equal("0905123456", rs.GetProperty("phone").GetString());
        Assert.Equal("added", JsonDocument.Parse(json!).RootElement.GetProperty("sellTax").GetProperty("mode").GetString());
    }

    [Fact]
    public void ExtraJson_hong_tra_nguyen_van()
    {
        Assert.Equal("{not json", PosSellIndustryController.WithReceiptStoreDefault("{not json", "A", null, null));
    }
}
