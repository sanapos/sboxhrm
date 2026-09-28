using Xunit;
using ZKTecoADMS.Api.Services.Kpi;
using ZKTecoADMS.Api.Services.Production;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests;

/// <summary>Lương sản phẩm lũy tiến + lương KPI theo mốc.</summary>
public class PayrollKpiProductionTests
{
    static List<ProductPriceTier> Tiers() =>
    [
        new() { TierLevel = 1, MinQuantity = 1, MaxQuantity = 100, UnitPrice = 5000 },
        new() { TierLevel = 2, MinQuantity = 101, MaxQuantity = 200, UnitPrice = 6000 },
        new() { TierLevel = 3, MinQuantity = 201, MaxQuantity = null, UnitPrice = 7000 },
    ];

    [Theory]
    [InlineData(0, 0)]
    [InlineData(80, 400_000)]
    [InlineData(150, 800_000)]      // 100×5000 + 50×6000
    [InlineData(250, 1_450_000)]    // 500k + 600k + 50×7000
    public void Luy_tien_theo_bac(decimal qty, decimal expected) =>
        Assert.Equal(expected, ProductionPricing.ProgressiveTotal(Tiers(), qty));

    [Fact]
    public void Chia_tien_theo_dong_tong_bang_luy_tien_ca_thang()
    {
        var qtys = new List<decimal> { 60, 70, 90, 30 }; // tổng 250
        var priced = ProductionPricing.Allocate(Tiers(), qtys);
        Assert.Equal(ProductionPricing.ProgressiveTotal(Tiers(), 250), priced.Sum(p => p.Amount));
        Assert.Equal(300_000m, priced[0].Amount);       // 60×5000
        Assert.Equal(40 * 5000m + 30 * 6000m, priced[1].Amount);
    }

    [Fact]
    public void Xoa_mot_dong_tinh_lai_van_dung_tong()
    {
        // Trước đây xóa / sửa dòng đầu tháng không tính lại các dòng sau → tổng tháng sai.
        var after = ProductionPricing.Allocate(Tiers(), [70m, 90m, 30m]);
        Assert.Equal(ProductionPricing.ProgressiveTotal(Tiers(), 190), after.Sum(p => p.Amount));
    }

    static KpiEmployeeTarget Target(decimal target, decimal? actual, decimal cs = 10_000_000,
        string? bonus = null, string? penalty = null) => new()
    {
        TargetValue = target,
        ActualValue = actual,
        CompletionSalary = cs,
        BonusTiersJson = bonus,
        PenaltyTiersJson = penalty,
    };

    [Fact]
    public void Chua_nhap_thuc_te_thi_bang_0()
    {
        Assert.Equal(0m, KpiPayCalculator.Compute(Target(100, null)).Total);
    }

    [Fact]
    public void Chua_dat_luong_ti_le_tru_phat_theo_phan_tram()
    {
        // 70% → lương 7tr; mốc 50–80% phạt 10% lương hoàn thành = −1tr → 6tr
        const string penalty = """[{"fromPct":0,"toPct":50,"rate":-30,"rateType":1},{"fromPct":50,"toPct":80,"rate":-10,"rateType":1}]""";
        var pay = KpiPayCalculator.Compute(Target(100_000_000, 70_000_000, penalty: penalty));
        Assert.Equal(7_000_000m, pay.BasePay);
        Assert.Equal(-1_000_000m, pay.Adjustment);
        Assert.Equal(6_000_000m, pay.Total);
    }

    [Fact]
    public void Vuot_chi_tieu_cong_thuong_theo_moc()
    {
        // 130%: đủ 10tr + 5% phần vượt từ 100% đến 130% (30tr × 5%) = 1.5tr
        const string bonus = """[{"fromPct":100,"toPct":-1,"rate":5,"rateType":1}]""";
        var pay = KpiPayCalculator.Compute(Target(100_000_000, 130_000_000, bonus: bonus));
        Assert.Equal(10_000_000m, pay.BasePay);
        Assert.Equal(1_500_000m, pay.Adjustment);
        Assert.Equal(11_500_000m, pay.Total);
    }

    [Fact]
    public void Tong_luong_khong_am_khi_phat_lon()
    {
        const string penalty = """[{"fromPct":0,"toPct":100,"rate":-5000000,"rateType":0}]""";
        Assert.Equal(0m, KpiPayCalculator.Compute(Target(100, 10, cs: 1_000_000, penalty: penalty)).Total);
    }

    [Theory]
    [InlineData(95, 150)]
    [InlineData(89.5, 120)]   // trước đây rơi vào khoảng hở 89–90 → 0%
    [InlineData(40, 0)]
    public void Ty_le_thuong_theo_diem_khong_ho_moc(decimal score, decimal expected)
    {
        var rules = new List<KpiBonusRule>
        {
            new() { MinScore = 90, MaxScore = 100, BonusRate = 150 },
            new() { MinScore = 80, MaxScore = 89, BonusRate = 120 },
            new() { MinScore = 50, MaxScore = 79, BonusRate = 100 },
        };
        Assert.Equal(expected, KpiPayCalculator.BonusRateForScore(rules, score));
    }
}
