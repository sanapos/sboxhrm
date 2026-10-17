using Xunit;
using ZKTecoADMS.Api.Services.Shipping;

namespace ZKTecoADMS.Tests;

public class ShippingReportTests
{
    static ShippingReportRow Row(string status, decimal fee, decimal? carrierFee, string payer, decimal cod = 0,
        int fails = 0, DateTime? settled = null) =>
        new(Guid.NewGuid(), "HD1", null, null, "Ghn", "GHN", "T", null, status, status, fee, carrierFee, payer, cod,
            DateTime.UtcNow, DateTime.UtcNow, null, fails, null, null, null, null, settled, null);

    [Fact]
    public void Ty_le_thanh_cong_bo_don_huy_va_don_dang_di()
    {
        var rows = new[]
        {
            Row(ShipmentStatus.Delivered, 0, 0, ShippingFeePayer.Shop),
            Row(ShipmentStatus.Delivered, 0, 0, ShippingFeePayer.Shop),
            Row(ShipmentStatus.Returned, 0, 0, ShippingFeePayer.Shop),
            Row(ShipmentStatus.Cancelled, 0, 0, ShippingFeePayer.Shop),
            Row(ShipmentStatus.InTransit, 0, 0, ShippingFeePayer.Shop),
        };
        Assert.Equal(66.7, PosShippingService.Summarize("a", "a", rows).SuccessRate);
    }

    [Theory]
    [InlineData(ShipmentStatus.Delivering, ShipmentStatus.Picking, false)]   // trễ: lùi bước
    [InlineData(ShipmentStatus.InTransit, ShipmentStatus.Created, false)]
    [InlineData(ShipmentStatus.Picking, ShipmentStatus.InTransit, true)]
    [InlineData(ShipmentStatus.InTransit, ShipmentStatus.InTransit, true)]
    [InlineData(ShipmentStatus.Delivering, ShipmentStatus.DeliveryFailed, true)]
    [InlineData(ShipmentStatus.DeliveryFailed, ShipmentStatus.Delivering, true)]  // giao lại
    [InlineData(ShipmentStatus.DeliveryFailed, ShipmentStatus.Delivered, true)]
    [InlineData(ShipmentStatus.Delivered, ShipmentStatus.InTransit, false)]
    [InlineData(ShipmentStatus.Delivered, ShipmentStatus.Returned, true)]
    [InlineData(ShipmentStatus.Returned, ShipmentStatus.Delivered, false)]
    [InlineData(ShipmentStatus.Cancelled, ShipmentStatus.Picking, false)]
    [InlineData(null, ShipmentStatus.Delivering, true)]
    public void Chuyen_trang_thai_van_don(string? from, string to, bool expected) =>
        Assert.Equal(expected, ShipmentStatus.CanTransition(from, to));
}
