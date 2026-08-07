namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Gán ca cho punch — khớp tab Flutter "Tổng hợp theo ca" (<c>findBestMatchingShift</c>):
/// trong nhiều ca được gán, ưu tiên ca <b>không bị trễ/về sớm</b> (sau grace),
/// rồi mới xét khoảng cách giờ vào. Không ép chọn ca ngoài cửa sổ cho phép.
/// </summary>
public static class ShiftMatchHelper
{
    public const int DefaultMaxDistanceMinutes = 180;

    /// <summary>
    /// Ca qua đêm theo đồng hồ: giờ vào &gt; giờ ra (vd. 22:00–06:00).
    /// Vào = ra (vd. 06:00–06:00) <b>không</b> phải qua đêm — không ghép ca 24h.
    /// </summary>
    public static bool IsOvernight(TimeSpan start, TimeSpan end) => start > end;

    public sealed record Candidate(
        Guid Id,
        TimeSpan StartTime,
        TimeSpan EndTime,
        int LateGraceMinutes = 5,
        int EarlyLeaveGraceMinutes = 5,
        int MaximumAllowedLateMinutes = 30,
        int EarlyCheckInMinutes = 30,
        int MaximumAllowedEarlyLeaveMinutes = 120,
        string? ShiftType = null,
        string? Name = null,
        int OvertimeMinutesThreshold = 30,
        int EarlyOvertimeMinutesThreshold = 30);

    public sealed record Fit(
        Candidate Shift,
        int EffectiveLateIn,
        int EffectiveEarlyOut,
        int DistanceToStart)
    {
        public int PenaltyScore => EffectiveLateIn + EffectiveEarlyOut;
    }

    /// <summary>
    /// Chọn ca tốt nhất cho cặp chấm (hoặc chỉ giờ vào). Trả null nếu không ca nào
    /// nằm trong cửa sổ / vượt maxAllowedLate / cách &gt; 180 phút.
    /// </summary>
    public static Fit? FindBest(
        IEnumerable<Candidate> candidates,
        TimeSpan punchIn,
        TimeSpan? punchOut = null,
        int pairIndex = 0,
        int maxDistanceMinutes = DefaultMaxDistanceMinutes)
    {
        var list = candidates?.ToList() ?? [];
        if (list.Count == 0) return null;

        var ordered = list
            .OrderBy(c => c.StartTime)
            .ToList();
        var scoped = pairIndex > 0 && pairIndex < ordered.Count
            ? ordered.Skip(pairIndex).ToList()
            : ordered;

        var best = PickBest(scoped, punchIn, punchOut);
        if (best == null || best.DistanceToStart > maxDistanceMinutes)
            return null;
        return best;
    }

    /// <summary>Chỉ giờ vào (phạt đi trễ).</summary>
    public static Fit? FindBestForCheckIn(
        IEnumerable<Candidate> candidates,
        TimeSpan punchIn,
        int maxDistanceMinutes = DefaultMaxDistanceMinutes)
        => FindBest(candidates, punchIn, punchOut: null, pairIndex: 0, maxDistanceMinutes);

    /// <summary>
    /// Chỉ giờ ra (phạt về sớm): ưu tiên ca không về sớm sau grace, rồi gần EndTime.
    /// </summary>
    public static Fit? FindBestForCheckOut(
        IEnumerable<Candidate> candidates,
        TimeSpan punchOut,
        int maxDistanceMinutes = DefaultMaxDistanceMinutes)
    {
        var list = candidates?.ToList() ?? [];
        if (list.Count == 0) return null;

        Fit? best = null;
        foreach (var c in list)
        {
            if (!IsPunchOutInWindow(punchOut, c.StartTime, c.EndTime,
                    c.MaximumAllowedEarlyLeaveMinutes > 0
                        ? c.MaximumAllowedEarlyLeaveMinutes
                        : 120))
                continue;

            var early = RawEarlyOutMinutes(punchOut, c.StartTime, c.EndTime);
            if (early > 0 && early <= Math.Max(c.EarlyLeaveGraceMinutes, 0))
                early = 0;

            var distEnd = CircularMinutes(punchOut, c.EndTime);
            // Dùng DistanceToStart slot để mangiar tới end (so sánh dưới).
            var fit = new Fit(c, EffectiveLateIn: 0, EffectiveEarlyOut: early, DistanceToStart: distEnd);

            if (best == null
                || fit.EffectiveEarlyOut < best.EffectiveEarlyOut
                || (fit.EffectiveEarlyOut == best.EffectiveEarlyOut
                    && fit.DistanceToStart < best.DistanceToStart))
            {
                best = fit;
            }
        }

        if (best == null || best.DistanceToStart > maxDistanceMinutes)
            return null;
        return best;
    }

    public static int CircularMinutes(TimeSpan a, TimeSpan b)
    {
        var d = (int)Math.Abs((a - b).TotalMinutes);
        return d > 720 ? 1440 - d : d;
    }

    public static int MinutesLateAfterStart(TimeSpan punch, TimeSpan start, TimeSpan end)
    {
        var overnight = IsOvernight(start, end);
        if (!overnight)
            return punch > start ? (int)(punch - start).TotalMinutes : 0;

        if (punch >= start)
            return (int)(punch - start).TotalMinutes;
        if (punch <= end)
            return (int)((TimeSpan.FromDays(1) - start) + punch).TotalMinutes;
        return 0;
    }

    public static int MinutesEarlyBeforeEnd(TimeSpan punch, TimeSpan start, TimeSpan end)
        => RawEarlyOutMinutes(punch, start, end);

    /// <summary>Độ dài ca (phút) — ưu tiên ca dài hơn khi điểm phạt bằng nhau (tránh Ca sáng 4h thắng ca hành chính 9.5h).</summary>
    public static int ShiftDurationMinutes(Candidate c)
    {
        var start = (int)c.StartTime.TotalMinutes;
        var end = (int)c.EndTime.TotalMinutes;
        if (IsOvernight(c.StartTime, c.EndTime))
            return Math.Max(1, (1440 - start) + end);
        return Math.Max(1, end - start);
    }

    private static Fit? PickBest(
        IReadOnlyList<Candidate> ids,
        TimeSpan punchIn,
        TimeSpan? punchOut)
    {
        Fit? best = null;
        foreach (var c in ids)
        {
            var fit = Evaluate(c, punchIn, punchOut);
            if (fit == null) continue;
            if (best == null
                || fit.PenaltyScore < best.PenaltyScore
                || (fit.PenaltyScore == best.PenaltyScore
                    && fit.EffectiveLateIn < best.EffectiveLateIn)
                || (fit.PenaltyScore == best.PenaltyScore
                    && fit.EffectiveLateIn == best.EffectiveLateIn
                    && fit.DistanceToStart < best.DistanceToStart)
                // Hòa điểm: chọn ca dài hơn (Ca hành chính > Ca sáng cùng giờ vào).
                || (fit.PenaltyScore == best.PenaltyScore
                    && fit.EffectiveLateIn == best.EffectiveLateIn
                    && fit.DistanceToStart == best.DistanceToStart
                    && ShiftDurationMinutes(fit.Shift) > ShiftDurationMinutes(best.Shift)))
            {
                best = fit;
            }
        }
        return best;
    }

    private static Fit? Evaluate(Candidate st, TimeSpan punchIn, TimeSpan? punchOut)
    {
        var start = st.StartTime;
        var end = st.EndTime;
        var overnight = IsOvernight(start, end);
        var lateGrace = Math.Max(st.LateGraceMinutes, 0);
        var earlyGrace = Math.Max(st.EarlyLeaveGraceMinutes, 0);
        var earlyCheckIn = st.EarlyCheckInMinutes > 0 ? st.EarlyCheckInMinutes : 30;
        var maxAllowedLate = st.MaximumAllowedLateMinutes;

        int rawEarlyIn = 0;
        int rawLateIn = 0;
        if (overnight)
        {
            // Cửa sổ vào sớm [start − earlyCheckIn, start) — hỗ trợ ca gần 24h
            // (06:00–05:59) khi khoảng (end, start) chỉ còn ~1 phút.
            var earlyFrom = start - TimeSpan.FromMinutes(earlyCheckIn);
            if (earlyFrom < TimeSpan.Zero)
                earlyFrom += TimeSpan.FromDays(1);

            var inEarlyWindow = earlyFrom < start
                ? punchIn >= earlyFrom && punchIn < start
                : punchIn >= earlyFrom || punchIn < start;

            if (inEarlyWindow)
            {
                rawEarlyIn = punchIn <= start
                    ? (int)(start - punchIn).TotalMinutes
                    : (int)(start + TimeSpan.FromDays(1) - punchIn).TotalMinutes;
            }
            else if (punchIn >= start)
                rawLateIn = (int)(punchIn - start).TotalMinutes;
            else if (punchIn <= end)
                rawLateIn = (int)((TimeSpan.FromDays(1) - start) + punchIn).TotalMinutes;
            else
            {
                rawEarlyIn = (int)(start - punchIn).TotalMinutes;
                if (rawEarlyIn < 0)
                    rawEarlyIn += 1440;
            }
        }
        else
        {
            if (punchIn < start)
                rawEarlyIn = (int)(start - punchIn).TotalMinutes;
            else if (punchIn > start)
                rawLateIn = (int)(punchIn - start).TotalMinutes;
        }

        if (rawEarlyIn > earlyCheckIn) return null;
        if (maxAllowedLate > 0 && rawLateIn > maxAllowedLate) return null;
        // Không chấm VÀO sau giờ tan ca (ca thường).
        if (!overnight && punchIn > end) return null;

        var effectiveLateIn = rawLateIn;
        if (effectiveLateIn > 0 && effectiveLateIn <= lateGrace)
            effectiveLateIn = 0;

        var effectiveEarlyOut = 0;
        if (punchOut.HasValue)
        {
            var rawEarlyOut = RawEarlyOutMinutes(punchOut.Value, start, end);
            effectiveEarlyOut = rawEarlyOut;
            if (effectiveEarlyOut > 0 && effectiveEarlyOut <= earlyGrace)
                effectiveEarlyOut = 0;
        }

        return new Fit(st, effectiveLateIn, effectiveEarlyOut, CircularMinutes(punchIn, start));
    }

    private static int RawEarlyOutMinutes(TimeSpan punchOut, TimeSpan start, TimeSpan end)
    {
        var overnight = IsOvernight(start, end);
        if (!overnight)
            return punchOut < end ? (int)(end - punchOut).TotalMinutes : 0;

        if (punchOut <= end)
            return (int)(end - punchOut).TotalMinutes;
        if (punchOut >= start)
            return (int)((TimeSpan.FromDays(1) - punchOut) + end).TotalMinutes;
        return 0;
    }

    private static bool IsPunchOutInWindow(
        TimeSpan punch, TimeSpan start, TimeSpan end, int maxEarlyMinutes)
    {
        var overnight = IsOvernight(start, end);
        var fallbackWindow = TimeSpan.FromHours(2);
        var earlyLimit = TimeSpan.FromMinutes(Math.Max(maxEarlyMinutes, (int)fallbackWindow.TotalMinutes));

        if (!overnight)
        {
            if (punch < start) return false;
            if (punch > end + fallbackWindow) return false;
            // Cho phép ra sớm trong maxEarly — penalty tính sau; từ chối nếu trước start.
            _ = earlyLimit;
            return true;
        }

        if (punch <= end + fallbackWindow)
            return true;
        if (punch >= start) return true;
        return false;
    }
}
