using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Bản server của engine khuyến mãi phải ra cùng số với pos_promotion_engine.dart.</summary>
public class PosPromotionEngineTests
{
    static PosPromotion Promo(string type, string config, bool stackable = false, int? from = null, int? to = null) => new()
    {
        Id = Guid.NewGuid(), Name = type, Type = type, ConfigJson = config, Stackable = stackable,
        TimeFromMinutes = from, TimeToMinutes = to, IsActive = true,
    };

    static readonly DateTime Noon = new(2026, 10, 9, 12, 0, 0);

    [Fact]
    public void TimeDiscount_Percent_OnAllLines()
    {
        var p = Guid.NewGuid();
        var r = PosPromotionEngine.Compute(
            PosPromotionEngine.FromEntities([Promo("time_discount", """{"percent":10}""")]),
            [new PosPromotionEngine.Line("0", p, null, false, 2, 50000)], Noon, false);
        Assert.Equal(5000m, r.LineDiscount["0"]);
    }

    [Fact]
    public void TimeWindow_OutsideHours_NoDiscount()
    {
        var r = PosPromotionEngine.Compute(
            PosPromotionEngine.FromEntities([Promo("time_discount", """{"percent":30}""", from: 18 * 60, to: 21 * 60)]),
            [new PosPromotionEngine.Line("0", Guid.NewGuid(), null, false, 1, 100000)], Noon, false);
        Assert.Empty(r.LineDiscount);
    }

    [Fact]
    public void BuyTwoGetOne_SameProduct()
    {
        var p = Guid.NewGuid();
        var r = PosPromotionEngine.Compute(
            PosPromotionEngine.FromEntities([Promo("buy_x_get_y", """{"buyQty":2,"getQty":1}""")]),
            [new PosPromotionEngine.Line("0", p, null, false, 3, 30000)], Noon, false);
        Assert.Equal(10000m, r.LineDiscount["0"]);
    }

    [Fact]
    public void BillDiscount_AfterLineDiscount_WithCap()
    {
        var r = PosPromotionEngine.Compute(
            PosPromotionEngine.FromEntities([
                Promo("time_discount", """{"percent":10}"""),
                Promo("bill_discount", """{"minBill":100000,"billPercent":10,"maxDiscount":15000}"""),
            ]),
            [new PosPromotionEngine.Line("0", Guid.NewGuid(), null, false, 1, 200000)], Noon, false);
        Assert.Equal(20000m, r.LineDiscount["0"]);
        Assert.Equal(15000m, r.BillDiscount); // 10% × 180.000 = 18.000 → trần 15.000
    }

    [Fact]
    public void Exclusive_TakesLargest_StackableAdds()
    {
        var r = PosPromotionEngine.Compute(
            PosPromotionEngine.FromEntities([
                Promo("time_discount", """{"percent":10}"""),
                Promo("time_discount", """{"percent":20}"""),
                Promo("time_discount", """{"amountPerUnit":1000}""", stackable: true),
            ]),
            [new PosPromotionEngine.Line("0", Guid.NewGuid(), null, false, 1, 10000)], Noon, false);
        Assert.Equal(3000m, r.LineDiscount["0"]); // 20% (2.000) + cộng dồn 1.000
    }
}
