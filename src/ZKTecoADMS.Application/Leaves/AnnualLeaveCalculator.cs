using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Leaves;

/// <summary>Kết quả phép năm của một nhân viên trong một năm.</summary>
public sealed class AnnualLeaveYear
{
    public int Year { get; init; }
    public bool Eligible { get; init; }
    /// <summary>Phép chuẩn (hồ sơ lương hoặc chính sách) + thâm niên, trước khi tính theo tháng.</summary>
    public decimal BaseDays { get; init; }
    public decimal SeniorityDays { get; init; }
    public int Months { get; init; }
    /// <summary>Được hưởng trong năm (đã tính theo tháng, làm tròn).</summary>
    public decimal Entitled { get; init; }
    public decimal Carry { get; init; }
    public decimal CarryExpired { get; init; }
    public DateTime? CarryExpiresOn { get; init; }
    public decimal Adjust { get; init; }
    public decimal Used { get; init; }
    public decimal Pending { get; init; }
    public decimal PaidOutDays { get; init; }
    public decimal PaidOutAmount { get; init; }
    public decimal DailyRate { get; init; }
    public decimal Remaining => Entitled + Carry + Adjust - CarryExpired - Used - PaidOutDays;
    /// <summary>Còn có thể xin (đã trừ đơn đang chờ duyệt).</summary>
    public decimal Available => Remaining - Pending;
}

/// <summary>
/// Tính phép năm theo Bộ luật Lao động 2019 (Điều 113, 114) và Nghị định 145/2020 (Điều 66):
/// 12 ngày/năm, cứ đủ 5 năm làm việc +1 ngày; làm chưa đủ năm thì
/// (phép năm + thâm niên) ÷ 12 × số tháng làm việc, phần lẻ từ 0,5 làm tròn lên.
/// </summary>
public static class AnnualLeaveCalculator
{
    public sealed record LeaveUse(DateTime StartDate, decimal Days, bool Approved);

    public static AnnualLeaveYear Compute(
        AnnualLeavePolicy policy,
        Employee employee,
        Benefit? benefit,
        int year,
        IEnumerable<LeaveUse> leaves,
        IEnumerable<AnnualLeaveEntry> entries,
        DateTime today)
    {
        var eligible = benefit != null
            && (policy.ApplyTo == "all" || benefit.RateType == SalaryRateType.Monthly);

        var baseDays = benefit != null && benefit.RateType == SalaryRateType.Monthly && (benefit.PaidLeaveDays ?? 0) > 0
            ? benefit.PaidLeaveDays!.Value
            : policy.DefaultDays;

        var seniority = 0m;
        if (policy.SeniorityEveryYears > 0 && employee.JoinDate.HasValue)
        {
            var asOf = new DateTime(year, 12, 31);
            if (employee.ResignationDate.HasValue && employee.ResignationDate.Value.Date < asOf) asOf = employee.ResignationDate.Value.Date;
            var years = FullYears(employee.JoinDate.Value.Date, asOf);
            seniority = Math.Floor((decimal)years / policy.SeniorityEveryYears) * policy.SeniorityDays;
        }

        var months = MonthsWorked(employee.JoinDate, employee.ResignationDate, year, policy.ProrateCutoffDay);
        var total = baseDays + seniority;
        var entitled = !eligible || months <= 0
            ? 0
            : !policy.ProrateByMonths || months >= 12
                ? total
                : Math.Round(total / 12m * months, 0, MidpointRounding.AwayFromZero);

        var yearEntries = entries.Where(e => e.Year == year).ToList();
        var carry = yearEntries.Where(e => e.Kind == "carry").Sum(e => e.Days);
        var adjust = yearEntries.Where(e => e.Kind is "adjust" or "opening").Sum(e => e.Days);
        var payouts = yearEntries.Where(e => e.Kind == "payout").ToList();
        var paidDays = payouts.Sum(e => Math.Abs(e.Days));
        var paidAmount = payouts.Sum(e => e.Amount ?? 0);

        var yearLeaves = leaves.Where(l => l.StartDate.Year == year).ToList();
        var used = yearLeaves.Where(l => l.Approved).Sum(l => l.Days);
        var pending = yearLeaves.Where(l => !l.Approved).Sum(l => l.Days);

        // Phép chuyển sang phải dùng trước cuối tháng hết hạn; quá hạn phần chưa dùng bị hủy.
        DateTime? expiresOn = null;
        var expired = 0m;
        if (carry > 0 && policy.CarryExpireMonth is >= 1 and <= 12)
        {
            expiresOn = new DateTime(year, policy.CarryExpireMonth, DateTime.DaysInMonth(year, policy.CarryExpireMonth));
            if (today.Date > expiresOn.Value)
            {
                var usedBefore = yearLeaves.Where(l => l.Approved && l.StartDate.Date <= expiresOn.Value).Sum(l => l.Days);
                expired = Math.Max(0, carry - usedBefore);
            }
        }

        return new AnnualLeaveYear
        {
            Year = year,
            Eligible = eligible,
            BaseDays = eligible ? baseDays : 0,
            SeniorityDays = eligible ? seniority : 0,
            Months = months,
            Entitled = entitled,
            Carry = carry,
            CarryExpired = expired,
            CarryExpiresOn = expiresOn,
            Adjust = adjust,
            Used = used,
            Pending = pending,
            PaidOutDays = paidDays,
            PaidOutAmount = paidAmount,
            DailyRate = DailyRate(policy, benefit),
        };
    }

    static int FullYears(DateTime from, DateTime to)
    {
        var y = to.Year - from.Year;
        if (to.Month < from.Month || (to.Month == from.Month && to.Day < from.Day)) y--;
        return Math.Max(0, y);
    }

    /// <summary>
    /// Số tháng làm việc trong năm. Tháng vào làm chỉ tính nếu vào trước/đúng ngày <paramref name="cutoff"/>;
    /// tháng nghỉ việc chỉ tính nếu làm tới ít nhất ngày <paramref name="cutoff"/>.
    /// </summary>
    public static int MonthsWorked(DateTime? join, DateTime? resign, int year, int cutoff)
    {
        var start = 1;
        var end = 12;
        if (join.HasValue)
        {
            if (join.Value.Year > year) return 0;
            if (join.Value.Year == year) start = join.Value.Month + (join.Value.Day > cutoff ? 1 : 0);
        }
        if (resign.HasValue)
        {
            if (resign.Value.Year < year) return 0;
            if (resign.Value.Year == year) end = resign.Value.Month - (resign.Value.Day < cutoff ? 1 : 0);
        }
        return Math.Max(0, end - start + 1);
    }

    /// <summary>Tiền một ngày phép theo hồ sơ lương.</summary>
    public static decimal DailyRate(AnnualLeavePolicy policy, Benefit? b)
    {
        if (b == null) return 0;
        var std = policy.PayoutStandardDays > 0 ? policy.PayoutStandardDays : 26;
        decimal v = b.RateType switch
        {
            SalaryRateType.Monthly => (b.Rate + (policy.PayoutBasis == "base_completion" ? b.CompletionSalary ?? 0 : 0)) / std,
            SalaryRateType.Daily => (b.DailyFixedRate ?? 0) > 0 ? b.DailyFixedRate!.Value : b.Rate,
            SalaryRateType.Hourly => b.Rate * HoursPerDay(b),
            SalaryRateType.Shift => (b.FixedShiftRate ?? 0) * Math.Max(1, b.ShiftsPerDay ?? 1),
            _ => 0,
        };
        return Math.Round(v, 0, MidpointRounding.AwayFromZero);
    }

    static decimal HoursPerDay(Benefit b)
    {
        foreach (var part in (b.Description ?? "").Split('|'))
        {
            var i = part.IndexOf(':');
            if (i > 0 && part[..i].Trim() == "hoursPerWorkDay"
                && decimal.TryParse(part[(i + 1)..].Trim(), System.Globalization.NumberStyles.Number, System.Globalization.CultureInfo.InvariantCulture, out var h) && h > 0)
                return h;
        }
        return b.StandardHoursPerDay is > 0 ? b.StandardHoursPerDay.Value : 8;
    }

    // ─── Đếm ngày nghỉ ─────────────────────────────────────────────

    /// <summary>
    /// Số ngày phép của một đơn: bỏ ngày lễ và ngày nghỉ hằng tuần của nhân viên
    /// («chiều thứ 7 &amp; CN»: thứ 7 tính nửa ngày). Nửa ca = 0,5.
    /// </summary>
    public static decimal CountDays(
        DateTime start, DateTime end, bool halfShift, bool workingDaysOnly,
        string? paidLeaveType, string? weeklyOffDays, ISet<DateTime> holidays)
    {
        var s = start.Date;
        var e = end.Date < s ? s : end.Date;
        var total = 0m;
        for (var d = s; d <= e; d = d.AddDays(1))
            total += workingDaysOnly ? DayWeight(d, paidLeaveType, weeklyOffDays, holidays) : 1;
        if (halfShift) return total > 0 ? 0.5m : 0;
        return total;
    }

    static decimal DayWeight(DateTime d, string? paidLeaveType, string? weeklyOffDays, ISet<DateTime> holidays)
    {
        if (holidays.Contains(d.Date)) return 0;
        var sat = d.DayOfWeek == DayOfWeek.Saturday;
        var sun = d.DayOfWeek == DayOfWeek.Sunday;
        switch ((paidLeaveType ?? "").Trim().ToLowerInvariant())
        {
            case "sunday": return sun ? 0 : 1;
            case "saturday": return sat ? 0 : 1;
            case "sat-sun": return sat || sun ? 0 : 1;
            case "sat-afternoon-sun": return sun ? 0 : sat ? 0.5m : 1;
            case "schedule":
            case "off-1":
            case "off-2":
            case "off-3":
            case "off-4":
                return 1;
        }
        var w = weeklyOffDays ?? "";
        if (sun && w.Contains("Sunday", StringComparison.OrdinalIgnoreCase)) return 0;
        if (sat && w.Contains("Saturday", StringComparison.OrdinalIgnoreCase)) return 0;
        return 1;
    }

    /// <summary>Ngày lễ của các năm cần xét (bản ghi đúng năm + lặp hằng năm), áp dụng cho nhân viên.</summary>
    public static HashSet<DateTime> HolidaySet(IEnumerable<Holiday> holidays, IEnumerable<int> years, Guid employeeId)
    {
        var list = holidays.Where(h => string.IsNullOrWhiteSpace(h.EmployeeIds) || h.EmployeeIds.Contains(employeeId.ToString(), StringComparison.OrdinalIgnoreCase)).ToList();
        var set = new HashSet<DateTime>();
        foreach (var y in years.Distinct())
        {
            foreach (var h in list)
            {
                if (h.Date.Year == y) set.Add(h.Date.Date);
                else if (h.IsRecurring && h.Date.Year < y && !(h.Date.Month == 2 && h.Date.Day == 29 && !DateTime.IsLeapYear(y)))
                    set.Add(new DateTime(y, h.Date.Month, h.Date.Day));
            }
        }
        return set;
    }
}
