using Xunit;
using ZKTecoADMS.Application.Leaves;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests;

/// <summary>Phép năm: được hưởng, thâm niên, tính theo tháng, chuyển phép, đếm ngày làm việc, tiền phép.</summary>
public class AnnualLeaveCalculatorTests
{
    static readonly AnnualLeavePolicy P = new();
    static Benefit Monthly(decimal rate = 13_000_000, decimal? days = 12) =>
        new() { RateType = SalaryRateType.Monthly, Rate = rate, PaidLeaveDays = days, PaidLeaveType = "sunday" };
    static Employee Emp(string? join = null, string? resign = null) => new()
    {
        Id = Guid.NewGuid(),
        JoinDate = join == null ? null : DateTime.Parse(join),
        ResignationDate = resign == null ? null : DateTime.Parse(resign),
    };
    static AnnualLeaveYear Y(Employee e, Benefit? b, int year = 2026, IEnumerable<AnnualLeaveCalculator.LeaveUse>? l = null,
        IEnumerable<AnnualLeaveEntry>? x = null, string today = "2026-10-02", AnnualLeavePolicy? p = null) =>
        AnnualLeaveCalculator.Compute(p ?? P, e, b, year, l ?? [], x ?? [], DateTime.Parse(today));

    [Fact]
    public void Full_year_12_days_plus_seniority_every_5_years()
    {
        Assert.Equal(12, Y(Emp("2024-01-10"), Monthly()).Entitled);
        Assert.Equal(13, Y(Emp("2020-03-01"), Monthly()).Entitled);   // đủ 6 năm
        Assert.Equal(14, Y(Emp("2015-06-01"), Monthly()).Entitled);   // đủ 11 năm
    }

    [Fact]
    public void Joined_mid_year_prorated_and_rounded_half_up()
    {
        // Vào 10/07: tính tháng 7..12 = 6 tháng → 12/12×6 = 6
        Assert.Equal(6, Y(Emp("2026-07-10"), Monthly()).Entitled);
        // Vào 20/07: tháng 7 không tính → 5 tháng → 5
        Assert.Equal(5, Y(Emp("2026-07-20"), Monthly()).Entitled);
        // Nghỉ việc 31/03: 3 tháng → 3
        Assert.Equal(3, Y(Emp("2020-01-01", "2026-03-31"), Monthly(), today: "2026-04-10").Months);
    }

    [Fact]
    public void Non_monthly_not_eligible_by_default()
    {
        var y = Y(Emp("2024-01-01"), new Benefit { RateType = SalaryRateType.Daily, Rate = 300000 });
        Assert.False(y.Eligible);
        Assert.Equal(0, y.Entitled);
        var all = new AnnualLeavePolicy { ApplyTo = "all" };
        Assert.Equal(12, Y(Emp("2024-01-01"), new Benefit { RateType = SalaryRateType.Daily, Rate = 300000 }, p: all).Entitled);
    }

    [Fact]
    public void Remaining_counts_used_pending_carry_adjust_and_payout()
    {
        var e = Emp("2024-01-01");
        var y = Y(e, Monthly(), l: [new(new DateTime(2026, 5, 4), 3, true), new(new DateTime(2026, 11, 2), 2, false)],
            x: [
                new AnnualLeaveEntry { Year = 2026, Kind = "carry", Days = 4 },
                new AnnualLeaveEntry { Year = 2026, Kind = "adjust", Days = 1 },
                new AnnualLeaveEntry { Year = 2026, Kind = "payout", Days = -2, Amount = 1_000_000 },
            ]);
        // carry 4 hết hạn 31/03, chưa dùng trước hạn → mất 4
        Assert.Equal(4, y.CarryExpired);
        Assert.Equal(12 + 4 + 1 - 4 - 3 - 2, y.Remaining);
        Assert.Equal(y.Remaining - 2, y.Available);
    }

    [Fact]
    public void Carry_used_before_expiry_is_kept()
    {
        var y = Y(Emp("2024-01-01"), Monthly(), l: [new(new DateTime(2026, 2, 10), 3, true)],
            x: [new AnnualLeaveEntry { Year = 2026, Kind = "carry", Days = 4 }]);
        Assert.Equal(1, y.CarryExpired);
        Assert.Equal(12 + 4 - 1 - 3, y.Remaining);
    }

    [Fact]
    public void Count_working_days_skips_sundays_and_holidays()
    {
        var hol = new HashSet<DateTime> { new(2026, 9, 2) };
        // 31/08 (T2) .. 06/09 (CN): 7 ngày lịch, bỏ CN 6/9 và lễ 2/9 → 5
        Assert.Equal(5, AnnualLeaveCalculator.CountDays(new DateTime(2026, 8, 31), new DateTime(2026, 9, 6), false, true, "sunday", null, hol));
        // Nghỉ chiều T7 & CN: T7 tính nửa ngày
        Assert.Equal(4.5m, AnnualLeaveCalculator.CountDays(new DateTime(2026, 8, 31), new DateTime(2026, 9, 6), false, true, "sat-afternoon-sun", null, hol));
        Assert.Equal(0.5m, AnnualLeaveCalculator.CountDays(new DateTime(2026, 9, 3), new DateTime(2026, 9, 3), true, true, "sunday", null, hol));
        Assert.Equal(0, AnnualLeaveCalculator.CountDays(new DateTime(2026, 9, 6), new DateTime(2026, 9, 6), false, true, "sunday", null, hol));
    }

    [Fact]
    public void Daily_rate_for_payout()
    {
        Assert.Equal(500_000, AnnualLeaveCalculator.DailyRate(P, Monthly(13_000_000)));
        var withCompletion = new AnnualLeavePolicy { PayoutBasis = "base_completion" };
        var b = Monthly(10_400_000);
        b.CompletionSalary = 2_600_000;
        Assert.Equal(500_000, AnnualLeaveCalculator.DailyRate(withCompletion, b));
        Assert.Equal(320_000, AnnualLeaveCalculator.DailyRate(P, new Benefit { RateType = SalaryRateType.Hourly, Rate = 40_000, Description = "hoursPerWorkDay:8" }));
    }
}
