namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Làm tròn giờ công theo AppSettings key <c>rounding_rule</c>.
/// </summary>
public static class WorkHoursHelper
{
    public const string RoundingNone = "none";

    public static double RoundHours(double hours, string? roundingRule)
    {
        if (hours <= 0) return 0;
        var rule = (roundingRule ?? RoundingNone).Trim().ToLowerInvariant();
        if (rule is "" or RoundingNone) return hours;
        var minutes = (int)Math.Round(hours * 60, MidpointRounding.AwayFromZero);
        return RoundMinutes(minutes, rule) / 60.0;
    }

    public static int RoundMinutes(int minutes, string rule)
    {
        if (minutes <= 0) return 0;
        const int step = 15;
        return rule switch
        {
            "round_up" => ((minutes + step - 1) / step) * step,
            "round_down" => (minutes / step) * step,
            "round_nearest" => ((minutes + step / 2) / step) * step,
            _ => minutes
        };
    }
}
