using System.Text.Json;
using Xunit;
using ZKTecoADMS.Api.Services.Shipping;

namespace ZKTecoADMS.Tests;

/// <summary>AhaMove v3 theo tài liệu developers.ahamove.com (order-status-flow, webhook).</summary>
public class AhamoveIntegrationTests
{
    static JsonElement J(string json) => JsonDocument.Parse(json).RootElement.Clone();

    [Theory]
    // Giao thành công.
    [InlineData("""{"status":"COMPLETED","path":[{"status":""},{"status":"COMPLETED"}]}""", "COMPLETED", ShipmentStatus.Delivered)]
    // Giao thất bại: status vẫn COMPLETED, điểm giao FAILED (trước đây bị ghi «Đã giao»).
    [InlineData("""{"status":"COMPLETED","path":[{},{"status":"FAILED"}]}""", "FAILED", ShipmentStatus.DeliveryFailed)]
    // Đang hoàn / đã hoàn về shop.
    [InlineData("""{"status":"COMPLETED","sub_status":"IN_RETURN","path":[{},{"status":"FAILED"}]}""", "IN RETURN", ShipmentStatus.Returning)]
    [InlineData("""{"status":"COMPLETED","sub_status":"RETURNED","path":[{},{"status":"FAILED"}]}""", "RETURNED", ShipmentStatus.Returned)]
    // Các trạng thái khác giữ nguyên.
    [InlineData("""{"status":"ACCEPTED","sub_status":"BOARDED"}""", "ACCEPTED", ShipmentStatus.Picking)]
    [InlineData("""{"status":"IN PROCESS","sub_status":"COMPLETING"}""", "IN PROCESS", ShipmentStatus.Delivering)]
    [InlineData("""{"status":"CANCELLED"}""", "CANCELLED", ShipmentStatus.Cancelled)]
    public void Trang_thai_that_cua_don(string json, string expected, string mapped)
    {
        var status = AhamoveWebhookHelper.EffectiveStatus(J(json));
        Assert.Equal(expected, status);
        Assert.Equal(mapped, ShipmentStatus.FromAhamove(status));
    }

    [Theory]
    [InlineData("24ABCD-1", "24ABCD")]
    [InlineData("24ABCD-12", "24ABCD")]
    [InlineData("24ABCD", null)]
    [InlineData("AB-CD", null)]
    public void Ma_diem_giao_ve_ma_don_goc(string id, string? expected) =>
        Assert.Equal(expected, AhamoveWebhookHelper.BaseOrderId(id));

    [Fact]
    public void Nhan_tieng_viet_cho_hoan_hang()
    {
        Assert.Equal("Đang hoàn hàng về shop", AhamoveWebhookHelper.DisplayName("IN_RETURN"));
        Assert.Equal("Đã hoàn hàng về shop", AhamoveWebhookHelper.DisplayName("RETURNED"));
    }
}
