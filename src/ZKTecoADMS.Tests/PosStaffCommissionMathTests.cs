using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Enums;
using Xunit;

namespace ZKTecoADMS.Tests;

public class PosStaffCommissionMathTests
{
    [Fact]
    public void Combo_salon_allocates_by_catalog_price()
    {
        // Combo 500k: cắt 200k + gội 80k + massage 150k + dầu gội 70k
        var shares = PosStaffCommissionMath.AllocateComboRevenue(
            500_000m, 1,
            [
                (Guid.Parse("11111111-1111-1111-1111-111111111001"), 1, 200_000m),
                (Guid.Parse("11111111-1111-1111-1111-111111111002"), 1, 80_000m),
                (Guid.Parse("11111111-1111-1111-1111-111111111003"), 1, 150_000m),
                (Guid.Parse("11111111-1111-1111-1111-111111111004"), 1, 70_000m),
            ]);
        Assert.Equal(4, shares.Count);
        Assert.Equal(500_000m, shares.Sum(s => s.Revenue));
        Assert.Equal(200_000m, shares[0].Revenue);
        Assert.Equal(80_000m, shares[1].Revenue);
        Assert.Equal(150_000m, shares[2].Revenue);
        Assert.Equal(70_000m, shares[3].Revenue);
    }

    [Fact]
    public void Combo_zero_catalog_splits_equally()
    {
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        var shares = PosStaffCommissionMath.AllocateComboRevenue(
            300_000m, 1, [(a, 1, 0), (b, 1, 0)]);
        Assert.Equal(150_000m, shares[0].Revenue);
        Assert.Equal(150_000m, shares[1].Revenue);
    }

    [Fact]
    public void Commission_modes_salon_examples()
    {
        Assert.Equal(0, PosStaffCommissionMath.CalcCommission(
            PosCommissionMode.None, 20, 0, 200_000m, 1, 200_000m));
        Assert.Equal(40_000m, PosStaffCommissionMath.CalcCommission(
            PosCommissionMode.PercentOfLine, 20, 0, 200_000m, 1, 200_000m));
        Assert.Equal(15_000m, PosStaffCommissionMath.CalcCommission(
            PosCommissionMode.FixedPerUnit, 0, 15_000m, 200_000m, 1, 200_000m));
        Assert.Equal(16_000m, PosStaffCommissionMath.CalcCommission(
            PosCommissionMode.PercentOfCatalog, 20, 0, 80_000m, 1, 80_000m));
        Assert.Equal(30_000m, PosStaffCommissionMath.CalcCommission(
            PosCommissionMode.FixedPerUnit, 0, 15_000m, 200_000m, 2, 200_000m));
    }
}
