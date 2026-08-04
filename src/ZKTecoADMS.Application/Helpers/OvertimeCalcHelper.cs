namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Tính phút/giờ tăng ca + ước lượng tiền — khớp Flutter
/// <c>shift_records_calculator</c> + <c>payroll_summary_tab</c>:
/// early/late sau ngưỡng, ca type Tăng ca, free2=0, bucket weekday/weekend/holiday.
/// Hệ số: Benefit.otRate* ?? store rates ?? 1.5/2/3.
/// </summary>
public static class OvertimeCalcHelper
{
    public const string FreeTwoPunchMode = "free2";

    public enum OtBucket { Weekday, Weekend, Holiday }

    public sealed record OtRates(decimal Weekday, decimal Weekend, decimal Holiday)
    {
        public static OtRates Defaults { get; } = new(1.5m, 2.0m, 3.0m);

        public static OtRates Resolve(
            decimal? benefitWeekday,
            decimal? benefitWeekend,
            decimal? benefitHoliday,
            decimal? storeWeekday,
            decimal? storeWeekend,
            decimal? storeHoliday)
        {
            static decimal Pick(decimal? a, decimal? b, decimal fallback) =>
                a is > 0 ? a.Value : b is > 0 ? b.Value : fallback;

            return new OtRates(
                Pick(benefitWeekday, storeWeekday, 1.5m),
                Pick(benefitWeekend, storeWeekend, 2.0m),
                Pick(benefitHoliday, storeHoliday, 3.0m));
        }
    }

    public sealed record Punch(DateTime Time, bool IsCheckIn, bool IsCheckOut);

    public sealed record DayOtResult(
        DateTime Date,
        OtBucket Bucket,
        int OvertimeMinutes,
        int WorkedMinutes,
        DateTime? FirstIn,
        DateTime? LastOut,
        string Source);

    public sealed record EmployeeOtResult(
        int WeekdayMinutes,
        int WeekendMinutes,
        int HolidayMinutes,
        int TotalMinutes,
        int OvertimeDays,
        IReadOnlyList<DayOtResult> Days)
    {
        public double WeekdayHours => Math.Round(WeekdayMinutes / 60.0, 2);
        public double WeekendHours => Math.Round(WeekendMinutes / 60.0, 2);
        public double HolidayHours => Math.Round(HolidayMinutes / 60.0, 2);
        public double TotalHours => Math.Round(TotalMinutes / 60.0, 2);
    }

    public static bool IsOvertimeShiftType(string? shiftType)
    {
        if (string.IsNullOrWhiteSpace(shiftType)) return false;
        var raw = shiftType.Trim().ToLowerInvariant();
        return raw.Contains("tăng ca")
            || raw.Contains("tang ca")
            || raw.Contains("tangca")
            || raw == "tangca"
            || raw.Contains("overtime");
    }

    public static bool IsFreeTwoPunch(string? attendanceMode) =>
        string.Equals(attendanceMode, FreeTwoPunchMode, StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// Tính OT theo ngày trong khoảng. punches đã là wall-clock VN (hoặc cùng timezone nhất quán).
    /// </summary>
    public static EmployeeOtResult ComputeEmployeeOvertime(
        IReadOnlyList<Punch> punches,
        IReadOnlyList<ShiftMatchHelper.Candidate> assignedShifts,
        string? attendanceMode,
        Func<DateTime, bool> isWeeklyOff,
        Func<DateTime, bool> isHoliday,
        DateTime rangeStart,
        DateTime rangeEnd)
    {
        if (IsFreeTwoPunch(attendanceMode) || punches.Count == 0)
            return Empty();

        var candidates = assignedShifts?.ToList() ?? [];
        if (candidates.Count == 0)
            return Empty();

        var byDate = punches
            .Where(p => p.Time.Date >= rangeStart.Date && p.Time.Date <= rangeEnd.Date)
            .GroupBy(p => p.Time.Date)
            .OrderBy(g => g.Key);

        var days = new List<DayOtResult>();
        var wd = 0;
        var we = 0;
        var hol = 0;
        var otDays = 0;

        foreach (var dayGroup in byDate)
        {
            var date = dayGroup.Key;
            var dayPunches = dayGroup.OrderBy(p => p.Time).ToList();
            var pairs = BuildPairs(dayPunches);
            if (pairs.Count == 0) continue;

            var holiday = isHoliday(date);
            var rest = isWeeklyOff(date);
            var bucket = holiday ? OtBucket.Holiday : rest ? OtBucket.Weekend : OtBucket.Weekday;

            var dayOt = 0;
            var dayWorked = 0;
            DateTime? firstIn = null;
            DateTime? lastOut = null;
            var source = "shift";

            var pairIndex = 0;
            foreach (var (pin, pout) in pairs)
            {
                if (pin == null || pout == null) continue;
                firstIn ??= pin.Value;
                lastOut = pout.Value;

                var inTs = pin.Value.TimeOfDay;
                var outTs = pout.Value.TimeOfDay;
                var worked = WorkedMinutes(pin.Value, pout.Value);
                dayWorked += worked;

                var fit = ShiftMatchHelper.FindBest(candidates, inTs, outTs, pairIndex);
                if (fit == null)
                {
                    pairIndex++;
                    continue;
                }

                var shift = fit.Shift;
                var isOt = IsOvertimeShiftType(shift.ShiftType);
                int pairOt;
                if (isOt)
                {
                    pairOt = worked;
                    source = "ot_shift";
                }
                else
                {
                    pairOt = PairOvertimeBeyondShift(shift, inTs, outTs, pin.Value, pout.Value);
                }

                dayOt += Math.Max(0, pairOt);
                pairIndex++;
            }

            // Ngày lễ / ngày nghỉ có làm: toàn bộ giờ làm → OT bucket (giờ thực, không × hệ số).
            if ((holiday || rest) && dayWorked > 0)
            {
                dayOt = dayWorked;
                source = holiday ? "holiday" : "rest_day";
            }

            if (dayOt <= 0) continue;

            otDays++;
            switch (bucket)
            {
                case OtBucket.Holiday: hol += dayOt; break;
                case OtBucket.Weekend: we += dayOt; break;
                default: wd += dayOt; break;
            }

            days.Add(new DayOtResult(date, bucket, dayOt, dayWorked, firstIn, lastOut, source));
        }

        return new EmployeeOtResult(wd, we, hol, wd + we + hol, otDays, days);
    }

    public static decimal EstimatePay(
        EmployeeOtResult ot,
        OtRates rates,
        decimal hourlyRate,
        int hourlyOvertimeType,
        decimal hourlyOvertimeFixedRate)
    {
        if (hourlyOvertimeType == 2) return 0; // không tính TC theo giờ
        if (hourlyRate < 0) hourlyRate = 0;

        if (hourlyOvertimeType == 0)
        {
            var hours = (decimal)ot.TotalHours;
            return Math.Round(hours * hourlyOvertimeFixedRate, 0);
        }

        // Type 1 — hệ số (từ Benefit/store, không hardcode cứng trong payroll)
        var pay = (decimal)ot.WeekdayHours * hourlyRate * rates.Weekday
                + (decimal)ot.WeekendHours * hourlyRate * rates.Weekend
                + (decimal)ot.HolidayHours * hourlyRate * rates.Holiday;
        return Math.Round(pay, 0);
    }

    private static EmployeeOtResult Empty() =>
        new(0, 0, 0, 0, 0, Array.Empty<DayOtResult>());

    private static List<(DateTime? In, DateTime? Out)> BuildPairs(List<Punch> dayPunches)
    {
        var pairs = new List<(DateTime? In, DateTime? Out)>();
        var ins = dayPunches.Where(p => p.IsCheckIn && !p.IsCheckOut).ToList();
        var outs = dayPunches.Where(p => p.IsCheckOut).ToList();

        if (ins.Count > 0 && outs.Count > 0 && ins.Count + outs.Count == dayPunches.Count)
        {
            var remaining = outs.Select(o => o.Time).ToList();
            foreach (var inP in ins)
            {
                var idx = remaining.FindIndex(o => o >= inP.Time);
                if (idx >= 0)
                {
                    pairs.Add((inP.Time, remaining[idx]));
                    remaining.RemoveAt(idx);
                }
                else pairs.Add((inP.Time, null));
            }
            foreach (var o in remaining) pairs.Add((null, o));
            return pairs;
        }

        // Chronological pairs (máy không phân biệt In/Out)
        for (var i = 0; i < dayPunches.Count; i += 2)
        {
            var a = dayPunches[i].Time;
            DateTime? b = i + 1 < dayPunches.Count ? dayPunches[i + 1].Time : null;
            pairs.Add((a, b));
        }
        return pairs;
    }

    private static int WorkedMinutes(DateTime punchIn, DateTime punchOut)
    {
        var end = punchOut;
        if (end < punchIn) end = end.AddDays(1);
        return Math.Max(0, (int)(end - punchIn).TotalMinutes);
    }

    private static int PairOvertimeBeyondShift(
        ShiftMatchHelper.Candidate shift,
        TimeSpan punchIn,
        TimeSpan punchOut,
        DateTime punchInDt,
        DateTime punchOutDt)
    {
        var start = shift.StartTime;
        var end = shift.EndTime;
        var overnight = ShiftMatchHelper.IsOvernight(start, end);
        var otThresh = shift.OvertimeMinutesThreshold > 0 ? shift.OvertimeMinutesThreshold : 30;
        var earlyThresh = shift.EarlyOvertimeMinutesThreshold > 0
            ? shift.EarlyOvertimeMinutesThreshold
            : 30;

        // Resolve out on timeline relative to in
        var outMin = (int)punchOut.TotalMinutes;
        var inMin = (int)punchIn.TotalMinutes;
        var startMin = (int)start.TotalMinutes;
        var endMin = (int)end.TotalMinutes;

        var ot = 0;

        // After shift end
        int extraMin = 0;
        if (overnight)
        {
            if (outMin > endMin && outMin < startMin)
                extraMin = outMin - endMin;
        }
        else if (outMin > endMin)
        {
            extraMin = outMin - endMin;
        }
        // Cross-midnight checkout next calendar day handled via DateTime span when out < in on clock
        if (!overnight && punchOutDt.Date > punchInDt.Date)
        {
            var endDt = punchInDt.Date.Add(end);
            if (punchOutDt > endDt)
                extraMin = (int)(punchOutDt - endDt).TotalMinutes;
        }

        if (extraMin > otThresh) ot += extraMin;

        // Before shift start
        int before = 0;
        if (overnight)
        {
            if (inMin >= endMin && inMin < startMin)
                before = startMin - inMin;
        }
        else if (inMin < startMin)
        {
            before = startMin - inMin;
        }

        if (before > earlyThresh) ot += before;

        return ot;
    }
}
