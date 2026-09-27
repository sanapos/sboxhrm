using Xunit;
using ZKTecoADMS.Api.Services.Shipping;

namespace ZKTecoADMS.Tests;

/// <summary>Trạng thái vận đơn chuẩn, chuyển trạng thái, xếp hạng cước, báo cáo vận chuyển.</summary>
public class ShippingLifecycleTests
{
    [Theory]
    // GHN
    [InlineData("Ghn", "delivery_fail", null, ShipmentStatus.DeliveryFailed)]
    [InlineData("Ghn", "returning", null, ShipmentStatus.Returning)]
    [InlineData("Ghn", "returned", null, ShipmentStatus.Returned)]
    [InlineData("Ghn", "delivered", null, ShipmentStatus.Delivered)]
    [InlineData("Ghn", "cancel", null, ShipmentStatus.Cancelled)]
    [InlineData("Ghn", "lost", null, ShipmentStatus.Issue)]
    // GHTK: 9 không giao được ≠ hủy; 20 đang trả ≠ đã trả
    [InlineData("Ghtk", null, 9, ShipmentStatus.DeliveryFailed)]
    [InlineData("Ghtk", null, 49, ShipmentStatus.DeliveryFailed)]
    [InlineData("Ghtk", null, 20, ShipmentStatus.Returning)]
    [InlineData("Ghtk", null, 21, ShipmentStatus.Returned)]
    [InlineData("Ghtk", null, 5, ShipmentStatus.Delivered)]
    [InlineData("Ghtk", null, -1, ShipmentStatus.Cancelled)]
    // Viettel Post: 504 = đã trả người gửi (trước đây bị coi là «Đã giao»)
    [InlineData("ViettelPost", null, 501, ShipmentStatus.Delivered)]
    [InlineData("ViettelPost", null, 504, ShipmentStatus.Returned)]
    [InlineData("ViettelPost", null, 505, ShipmentStatus.Returning)]
    [InlineData("ViettelPost", null, 506, ShipmentStatus.DeliveryFailed)]
    [InlineData("ViettelPost", null, 503, ShipmentStatus.Cancelled)]
    // SPX / AhaMove: thất bại ≠ hủy
    [InlineData("Spx", "delivery_failed", null, ShipmentStatus.DeliveryFailed)]
    [InlineData("Spx", "returning", null, ShipmentStatus.Returning)]
    [InlineData("Spx", "returned", null, ShipmentStatus.Returned)]
    [InlineData("Ahamove", "FAILED", null, ShipmentStatus.DeliveryFailed)]
    [InlineData("Ahamove", "IN_PROCESS", null, ShipmentStatus.Delivering)]
    [InlineData("Ahamove", "COMPLETED", null, ShipmentStatus.Delivered)]
    public void Maps_carrier_status(string carrier, string? text, int? number, string expected) =>
        Assert.Equal(expected, ShipmentStatus.FromCarrier(carrier, text, number));

    [Fact]
    public void Failed_delivery_is_not_terminal_and_can_still_be_delivered()
    {
        Assert.False(ShipmentStatus.IsTerminal(ShipmentStatus.DeliveryFailed));
        Assert.True(ShipmentStatus.CanTransition(ShipmentStatus.DeliveryFailed, ShipmentStatus.Delivered));
        Assert.True(ShipmentStatus.CanTransition(ShipmentStatus.Returning, ShipmentStatus.Delivered));
        Assert.True(ShipmentStatus.CanTransition(ShipmentStatus.Delivered, ShipmentStatus.Returned));
        Assert.False(ShipmentStatus.CanTransition(ShipmentStatus.Cancelled, ShipmentStatus.Delivered));
        Assert.False(ShipmentStatus.CanTransition(ShipmentStatus.Returned, ShipmentStatus.Delivering));
        Assert.False(ShipmentStatus.CanTransition(ShipmentStatus.Delivered, ShipmentStatus.Delivering));
    }

    [Fact]
    public void Online_order_only_cancelled_when_returned_or_cancelled()
    {
        Assert.Equal("shipping", ShipmentStatus.ToOnlineStatus(ShipmentStatus.DeliveryFailed));
        Assert.Equal("shipping", ShipmentStatus.ToOnlineStatus(ShipmentStatus.Returning));
        Assert.Equal("cancelled", ShipmentStatus.ToOnlineStatus(ShipmentStatus.Returned));
        Assert.Equal("delivered", ShipmentStatus.ToOnlineStatus(ShipmentStatus.Delivered));
    }

    static ShippingCompareQuoteItem Q(string carrier, decimal fee, int? eta, bool ok = true) =>
        new(carrier, carrier, ok, fee, $"{carrier} gói", "x", null, null, eta);

    [Fact]
    public void Ranks_cheapest_fastest_and_recommends_cheapest_when_not_much_slower()
    {
        var ranked = ShippingQuoteRanker.Rank(
        [
            Q("A", 30000, 48 * 60),
            Q("B", 45000, 24 * 60),
            Q("C", 20000, null, ok: false),
        ]);
        Assert.Contains(ShippingQuoteRanker.Cheapest, ranked[0].Badges!);
        Assert.Contains(ShippingQuoteRanker.Recommended, ranked[0].Badges!);
        Assert.Contains(ShippingQuoteRanker.Fastest, ranked[1].Badges!);
        Assert.Null(ranked[2].Badges);
    }

    [Fact]
    public void Recommends_fastest_when_cheapest_is_more_than_a_day_slower()
    {
        var ranked = ShippingQuoteRanker.Rank(
        [
            Q("A", 25000, 5 * 24 * 60),
            Q("B", 32000, 24 * 60),
        ]);
        Assert.DoesNotContain(ShippingQuoteRanker.Recommended, ranked[0].Badges!);
        Assert.Contains(ShippingQuoteRanker.Recommended, ranked[1].Badges!);
    }

    [Theory]
    [InlineData("12 giờ", 720)]
    [InlineData("24h", 1440)]
    [InlineData("2 ngày", 2880)]
    [InlineData("3-4 ngày", 5760)]
    [InlineData("", null)]
    public void Parses_viettel_post_duration(string raw, int? minutes) =>
        Assert.Equal(minutes, ViettelPostShippingClient.ParseVtpDurationMinutes(raw));

    static ShippingReportRow R(string status, decimal fee = 30000, decimal carrierFee = 25000,
        string payer = "shop", decimal cod = 0, int fails = 0, double? hours = null, DateTime? codSettled = null) =>
        new(Guid.NewGuid(), "HD", "Khách", "09", "Ghn", "GHN", "T1", "GHN", status, status, fee, carrierFee,
            payer, cod, DateTime.UtcNow, null, null, fails, null, null, null, null, codSettled, hours);

    [Fact]
    public void Summarizes_success_rate_cost_and_cod()
    {
        var s = PosShippingService.Summarize("Ghn", "GHN",
        [
            R(ShipmentStatus.Delivered, cod: 200000, hours: 20),
            R(ShipmentStatus.Delivered, cod: 100000, hours: 40, codSettled: DateTime.UtcNow, fails: 1),
            R(ShipmentStatus.Returned, fails: 2),
            R(ShipmentStatus.Cancelled),
            R(ShipmentStatus.Delivering, payer: "customer"),
        ]);
        Assert.Equal(5, s.Shipments);
        Assert.Equal(2, s.Delivered);
        Assert.Equal(1, s.Returned);
        Assert.Equal(1, s.Cancelled);
        Assert.Equal(1, s.InProgress);
        Assert.Equal(2, s.FailedOrders);
        Assert.Equal(3, s.FailedAttempts);
        Assert.Equal(66.7, s.SuccessRate);          // 2 giao / (2 giao + 1 hoàn)
        Assert.Equal(30.0, s.AvgDeliveryHours);
        Assert.Equal(75000m, s.CarrierCost);         // 3 đơn shop trả cước (bỏ đơn hủy + đơn khách trả)
        Assert.Equal(90000m, s.FeeCharged);          // bỏ đơn hủy + đơn hoàn
        Assert.Equal(15000m, s.ShipProfit);
        Assert.Equal(300000m, s.CodDelivered);
        Assert.Equal(200000m, s.CodPending);
    }
}
