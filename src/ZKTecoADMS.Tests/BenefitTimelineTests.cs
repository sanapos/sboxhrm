using Xunit;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests;

/// <summary>Hồ sơ lương theo ngày hiệu lực: tách kỳ lương đúng đoạn, không chồng ngày.</summary>
public class BenefitTimelineTests
{
    static EmployeeBenefit V(string from, string? end = null) => new()
    {
        Id = Guid.NewGuid(),
        EmployeeId = Guid.Empty,
        BenefitId = Guid.NewGuid(),
        EffectiveDate = DateTime.Parse(from),
        EndDate = end == null ? null : DateTime.Parse(end),
    };

    [Fact]
    public void First_version_covers_whole_period_even_if_assigned_mid_month()
    {
        var v = V("2026-05-14 10:30");
        var segs = BenefitTimeline.Segments([v], new DateTime(2026, 5, 1), new DateTime(2026, 5, 31));
        Assert.Single(segs);
        Assert.Equal(new DateTime(2026, 5, 1), segs[0].From);
        Assert.Equal(new DateTime(2026, 5, 31), segs[0].To);
    }

    [Fact]
    public void Raise_mid_month_splits_into_two_segments()
    {
        var a = V("2026-01-01");
        var b = V("2026-05-16");
        a.EndDate = BenefitTimeline.EndBefore(b.EffectiveDate);
        var segs = BenefitTimeline.Segments([b, a], new DateTime(2026, 5, 1), new DateTime(2026, 5, 31));
        Assert.Equal(2, segs.Count);
        Assert.Equal(new DateTime(2026, 5, 15), segs[0].To);
        Assert.Equal(new DateTime(2026, 5, 16), segs[1].From);
        Assert.Same(b, segs[1].Version);
    }

    [Fact]
    public void Legacy_same_day_end_does_not_double_count()
    {
        var a = V("2026-01-01", "2026-05-14 10:30");
        var b = V("2026-05-14 10:30");
        var segs = BenefitTimeline.Segments([a, b], new DateTime(2026, 5, 1), new DateTime(2026, 5, 31));
        Assert.Equal(new DateTime(2026, 5, 13), segs[0].To);
        Assert.Equal(new DateTime(2026, 5, 14), segs[1].From);
    }

    [Fact]
    public void Plan_ends_running_version_and_replaces_later_ones()
    {
        var a = V("2026-01-01");
        var future = V("2026-07-01");
        a.EndDate = BenefitTimeline.EndBefore(future.EffectiveDate);
        var plan = BenefitTimeline.PlanNewVersion([a, future], new DateTime(2026, 6, 1));
        Assert.Contains(future, plan.Replaced);
        Assert.Contains(a, plan.Ended);
        Assert.Same(a, plan.Previous);
    }

    [Fact]
    public void Same_day_change_replaces_instead_of_overlapping()
    {
        var a = V("2026-06-01");
        var plan = BenefitTimeline.PlanNewVersion([a], new DateTime(2026, 6, 1));
        Assert.Contains(a, plan.Replaced);
        Assert.Empty(plan.Ended);
        Assert.Null(plan.Previous);
    }

    [Fact]
    public void Current_and_upcoming()
    {
        var a = V("2026-01-01");
        var b = V("2026-12-01");
        a.EndDate = BenefitTimeline.EndBefore(b.EffectiveDate);
        var day = new DateTime(2026, 10, 2);
        Assert.Same(a, BenefitTimeline.PickCurrent([a, b], day));
        Assert.Same(b, BenefitTimeline.PickUpcoming([a, b], day));
        // Chỉ có bản tương lai: vẫn coi là hồ sơ hiện tại (bản đầu tiên tính từ trước).
        Assert.Same(b, BenefitTimeline.PickCurrent([b], day));
    }
}
