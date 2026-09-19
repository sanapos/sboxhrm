using ZKTecoADMS.Application.Services;
using ZKTecoADMS.Domain.Enums;
using Xunit;

namespace ZKTecoADMS.Tests;

/// <summary>Nhiều mức tính giờ karaoke / bi-a / KS.</summary>
public class PosServiceBillingMathTests
{
    static decimal Charge(
        int elapsed,
        PosServiceBillingMode mode,
        decimal price,
        int? min = null,
        int? round = null,
        int? grace = null,
        int? roundAfter = null,
        decimal openingFee = 0,
        int? openingMinutes = null)
    {
        var billable = PosServiceBillingMath.BillableMinutes(
            elapsed, mode, min, round, grace, roundAfter);
        return PosServiceBillingMath.TimedLineCharge(
            mode, billable, price, openingFee, openingMinutes, round);
    }

    static (int billable, decimal qty, decimal total) Row(
        int elapsed,
        PosServiceBillingMode mode,
        decimal price,
        int? min = null,
        int? round = null,
        int? grace = null,
        int? roundAfter = null,
        decimal openingFee = 0,
        int? openingMinutes = null)
    {
        var billable = PosServiceBillingMath.BillableMinutes(
            elapsed, mode, min, round, grace, roundAfter);
        var qty = PosServiceBillingMath.ExtraQty(mode, billable, openingMinutes, round);
        var total = Math.Max(0, openingFee) + qty * price;
        return (billable, qty, total);
    }

    [Fact]
    public void PerHour_min1h_round15_karaokeClassic()
    {
        const decimal price = 200_000m;
        var mode = PosServiceBillingMode.PerHour;

        Assert.Equal(0m, Charge(0, mode, price, min: 60, round: 15));
        // Dưới 1h vẫn tính tối thiểu 1h.
        Assert.Equal(200_000m, Charge(1, mode, price, min: 60, round: 15));
        Assert.Equal(200_000m, Charge(59, mode, price, min: 60, round: 15));
        Assert.Equal(200_000m, Charge(60, mode, price, min: 60, round: 15));
        // 61p → làm tròn 75p = 1.25h
        var r61 = Row(61, mode, price, min: 60, round: 15);
        Assert.Equal(75, r61.billable);
        Assert.Equal(1.25m, r61.qty);
        Assert.Equal(250_000m, r61.total);
        // 90p = 1.5h
        Assert.Equal(300_000m, Charge(90, mode, price, min: 60, round: 15));
        // 3h / 7h
        Assert.Equal(600_000m, Charge(180, mode, price, min: 60, round: 15));
        Assert.Equal(1_400_000m, Charge(420, mode, price, min: 60, round: 15));
        // 8h
        Assert.Equal(1_600_000m, Charge(480, mode, price, min: 60, round: 15));
    }

    [Fact]
    public void PerHour_openingFee_includesMinutes_then_minHour()
    {
        // Phí mở 80k gồm 30p; sau đó 200k/h, min 1h tổng ở lại (kể cả phút mở).
        var r = Row(1, PosServiceBillingMode.PerHour, 200_000m,
            min: 60, round: 15, openingFee: 80_000m, openingMinutes: 30);
        Assert.Equal(60, r.billable);
        Assert.Equal(0.5m, r.qty); // 60 − 30
        Assert.Equal(180_000m, r.total); // 80k + 0.5×200k
    }

    [Fact]
    public void PerHour_prorata_noMin_noRound()
    {
        const decimal price = 120_000m;
        var mode = PosServiceBillingMode.PerHour;
        var r31 = Row(31, mode, price);
        Assert.Equal(31, r31.billable);
        Assert.Equal(0.5167m, r31.qty);
        Assert.Equal(62_004m, r31.total);
    }

    [Fact]
    public void PerBlock_5min_openingFeeIncludes30()
    {
        // Phí mở 50k gồm 30 phút, mỗi block 5p = 10k.
        const decimal price = 10_000m;
        const decimal open = 50_000m;
        var mode = PosServiceBillingMode.PerBlock;

        Assert.Equal(50_000m, Charge(0, mode, price, round: 5, openingFee: open, openingMinutes: 30));
        Assert.Equal(50_000m, Charge(1, mode, price, round: 5, openingFee: open, openingMinutes: 30));
        Assert.Equal(50_000m, Charge(30, mode, price, round: 5, openingFee: open, openingMinutes: 30));
        var r31 = Row(31, mode, price, round: 5, openingFee: open, openingMinutes: 30);
        Assert.Equal(35, r31.billable);
        Assert.Equal(1m, r31.qty);
        Assert.Equal(60_000m, r31.total);
        var r36 = Row(36, mode, price, round: 5, openingFee: open, openingMinutes: 30);
        Assert.Equal(40, r36.billable);
        Assert.Equal(2m, r36.qty);
        Assert.Equal(70_000m, r36.total);
    }

    [Fact]
    public void PerBlock_15min_fractionalExtra_ceilsToWholeBlock()
    {
        // Mở 20p không khớp block 15 → phần vượt 25p phải thành 2 block, không 1.666.
        var r = Row(45, PosServiceBillingMode.PerBlock, 80_000m, round: 15, openingMinutes: 20);
        Assert.Equal(45, r.billable);
        Assert.Equal(2m, r.qty);
        Assert.Equal(160_000m, r.total);
    }

    [Fact]
    public void Grace_wins_while_inside_free_window()
    {
        const decimal price = 200_000m;
        var mode = PosServiceBillingMode.PerHour;
        // 8p < grace 10 → 0 giờ dù min 60.
        Assert.Equal(0, PosServiceBillingMath.BillableMinutes(8, mode, 60, 15, 10, null));
        Assert.Equal(50_000m, Charge(8, mode, price, min: 60, round: 15, grace: 10, openingFee: 50_000m));
        // Vượt grace 1p → min 1h.
        Assert.Equal(200_000m, Charge(11, mode, price, min: 60, round: 15, grace: 10));
    }

    [Fact]
    public void Grace_subtracts_then_round()
    {
        var mode = PosServiceBillingMode.PerBlock;
        var r = Row(16, mode, 10_000m, round: 5, grace: 10);
        Assert.Equal(10, r.billable); // 16-10=6 → round 10
        Assert.Equal(2m, r.qty);
    }

    [Fact]
    public void RoundAfter_skips_rounding_until_threshold()
    {
        var mode = PosServiceBillingMode.PerHour;
        var under = Row(15, mode, 180_000m, round: 15, roundAfter: 15);
        Assert.Equal(15, under.billable); // raw == 15, chưa "sau"
        var over = Row(16, mode, 180_000m, round: 15, roundAfter: 15);
        Assert.Equal(30, over.billable);
    }

    [Fact]
    public void PerDay_hotel_min_one_night()
    {
        var mode = PosServiceBillingMode.PerDay;
        Assert.Equal(1m, Row(1, mode, 500_000m, min: 1440).qty);
        Assert.Equal(1m, Row(1440, mode, 500_000m).qty);
        Assert.Equal(2m, Row(1441, mode, 500_000m).qty);
        Assert.Equal(1_000_000m, Charge(1500, mode, 500_000m));
        Assert.Equal(0m, Charge(0, mode, 500_000m, min: 1440));
    }

    [Fact]
    public void PerMinute_billiards()
    {
        var r = Row(17, PosServiceBillingMode.PerMinute, 2_000m);
        Assert.Equal(17m, r.qty);
        Assert.Equal(34_000m, r.total);
    }

    [Fact]
    public void Elapsed_ceilings_net_seconds_and_subtracts_open_pause()
    {
        var start = new DateTime(2026, 9, 18, 10, 0, 0, DateTimeKind.Utc);
        var end = start.AddMinutes(60).AddSeconds(1); // 60p1s → 61p nếu không pause
        Assert.Equal(61, PosServiceBillingMath.ElapsedMinutes(start, end));

        var paused = end.AddMinutes(-10).AddSeconds(-30); // pause 10p30s
        var net = PosServiceBillingMath.ElapsedMinutes(start, end, 0, paused);
        // 60p1s - 10p30s = 49p31s → ceil 50
        Assert.Equal(50, net);
    }

    [Fact]
    public void Elapsed_seven_hour_karaoke_unspecified_utc_wall_clock()
    {
        var start = new DateTime(2026, 9, 18, 20, 0, 0, DateTimeKind.Unspecified);
        var end = new DateTime(2026, 9, 19, 3, 0, 0, DateTimeKind.Unspecified);
        Assert.Equal(420, PosServiceBillingMath.ElapsedMinutes(start, end));
    }

    [Fact]
    public void Elapsed_accumulated_pause_plus_open_pause()
    {
        var start = new DateTime(2026, 9, 18, 10, 0, 0, DateTimeKind.Utc);
        var end = start.AddHours(3);
        var paused = end.AddMinutes(-20);
        Assert.Equal(145, PosServiceBillingMath.ElapsedMinutes(start, end, 15, paused));
        // 180 - 15 - 20 = 145
    }

    [Fact]
    public void Preview_karaoke_block_matches_formula_copy()
    {
        var rows = PosServiceBillingMath.Preview(
            PosServiceBillingMode.PerBlock, 10_000m, null, 5, null, null, 50_000m, 30);
        var at31 = rows.Single(r => r.ElapsedMinutes == 31);
        Assert.Equal(35, at31.BillableMinutes);
        Assert.Equal(1m, at31.Qty);
        Assert.Equal(60_000m, at31.Total);
        var at420 = rows.Single(r => r.ElapsedMinutes == 420);
        Assert.Equal(420, at420.BillableMinutes);
        Assert.Equal(78m, at420.Qty); // (420-30)/5
        Assert.Equal(50_000m + 78 * 10_000m, at420.Total);
    }
}
