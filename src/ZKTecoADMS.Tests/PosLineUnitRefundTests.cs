using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests;

public class PosLineUnitRefundTests
{
    private static PosSaleOrderLine Line(decimal qty, decimal unitPrice, decimal discount, decimal lineTotal) =>
        new() { Qty = qty, UnitPrice = unitPrice, DiscountAmount = discount, LineTotal = lineTotal };

    [Fact]
    public void Paid_line_refunds_net_unit_amount() =>
        Assert.Equal(45_000m, PosSaleStockHelper.LineUnitRefund(Line(2, 50_000, 10_000, 90_000)));

    [Fact]
    public void Fully_discounted_gift_line_refunds_nothing() =>
        // Món tặng / giảm 100%: trước đây hoàn theo đơn giá gốc.
        Assert.Equal(0m, PosSaleStockHelper.LineUnitRefund(Line(1, 50_000, 50_000, 0)));

    [Fact]
    public void Legacy_line_without_stored_total_falls_back_to_unit_price() =>
        Assert.Equal(50_000m, PosSaleStockHelper.LineUnitRefund(Line(1, 50_000, 0, 0)));

    [Fact]
    public void Negative_unit_price_never_refunds_negative() =>
        Assert.Equal(0m, PosSaleStockHelper.LineUnitRefund(Line(1, -5_000, 0, 0)));
}
