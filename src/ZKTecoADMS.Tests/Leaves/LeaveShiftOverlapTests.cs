using Xunit;
using ZKTecoADMS.Application.Leaves;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Leaves;

public class LeaveShiftOverlapTests
{
    private static readonly Guid Office = Guid.NewGuid();
    private static readonly Guid Night = Guid.NewGuid();

    private static Leave Existing(DateTime start, DateTime end, params Guid[] shifts) => new()
    {
        StartDate = start,
        EndDate = end,
        Status = LeaveStatus.Approved,
        ShiftIds = shifts.ToList(),
    };

    [Fact]
    public void Same_day_with_different_clock_times_conflicts()
    {
        // Đơn cũ lưu 19:31, đơn mới 22:04 cùng ngày, cùng ca → trùng.
        var old = Existing(new DateTime(2026, 10, 29, 19, 31, 39), new DateTime(2026, 10, 29, 19, 31, 39), Office);
        Assert.True(LeaveShiftOverlap.ConflictsWith(old,
            new DateTime(2026, 10, 29, 22, 4, 42), new DateTime(2026, 10, 29, 22, 4, 42), [Office]));
    }

    [Fact]
    public void Different_shift_same_day_is_allowed() =>
        Assert.False(LeaveShiftOverlap.ConflictsWith(
            Existing(new DateTime(2026, 10, 29), new DateTime(2026, 10, 29), Office),
            new DateTime(2026, 10, 29, 9, 0, 0), new DateTime(2026, 10, 29, 9, 0, 0), [Night]));

    [Fact]
    public void Next_day_does_not_conflict() =>
        Assert.False(LeaveShiftOverlap.ConflictsWith(
            Existing(new DateTime(2026, 10, 29, 23, 0, 0), new DateTime(2026, 10, 29, 23, 0, 0), Office),
            new DateTime(2026, 10, 30), new DateTime(2026, 10, 30), [Office]));

    [Fact]
    public void Rejected_never_conflicts()
    {
        var old = Existing(new DateTime(2026, 10, 29), new DateTime(2026, 10, 29), Office);
        old.Status = LeaveStatus.Rejected;
        Assert.False(LeaveShiftOverlap.ConflictsWith(old, new DateTime(2026, 10, 29), new DateTime(2026, 10, 29), [Office]));
    }
}
