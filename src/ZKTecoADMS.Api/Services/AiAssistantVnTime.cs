namespace ZKTecoADMS.Api.Services;

internal static class AiAssistantVnTime
{
    public const int OffsetHours = 7;

    public static DateTime NowVn() => DateTime.UtcNow.AddHours(OffsetHours);

    public static DateTime ToVn(DateTime utc) => utc.AddHours(OffsetHours);

    public static (DateTime dateLocal, DateTime utcStart, DateTime utcEnd) DayRange(DateTime? date)
    {
        var local = (date ?? NowVn()).Date;
        var utcStart = local.AddHours(-OffsetHours);
        return (local, utcStart, utcStart.AddDays(1));
    }
}
