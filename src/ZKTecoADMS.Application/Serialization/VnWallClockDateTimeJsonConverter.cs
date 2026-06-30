using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using ZKTecoADMS.Application.Helpers;

namespace ZKTecoADMS.Application.Serialization;

/// <summary>
/// Serialize chấm công: giờ tường VN, không gắn Z.
/// Deserialize: chuỗi có Z (legacy) → lấy mặt số giờ, không cộng thêm 7h.
/// </summary>
public sealed class VnWallClockDateTimeJsonConverter : JsonConverter<DateTime>
{
    private const string Format = "yyyy-MM-dd'T'HH:mm:ss.fff";

    public override DateTime Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var s = reader.GetString();
        if (string.IsNullOrEmpty(s)) return default;
        return ParseAttendanceJson(s);
    }

    internal static DateTime ParseAttendanceJson(string s)
    {
        var hasTz = s.EndsWith("Z", StringComparison.OrdinalIgnoreCase)
            || s.Contains('+', StringComparison.Ordinal)
            || System.Text.RegularExpressions.Regex.IsMatch(s, @"-\d{2}:\d{2}$");

        if (!hasTz)
        {
            return DateTime.Parse(s, CultureInfo.InvariantCulture, DateTimeStyles.None);
        }

        var dt = DateTime.Parse(s, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);
        // Legacy API gắn Z nhầm lên giờ VN — giữ mặt số, bỏ qua offset.
        return new DateTime(dt.Year, dt.Month, dt.Day, dt.Hour, dt.Minute, dt.Second, dt.Millisecond);
    }

    public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions options)
    {
        var wall = VnTimeHelper.AttendanceWallClock(value);
        writer.WriteStringValue(wall.ToString(Format, CultureInfo.InvariantCulture));
    }
}

public sealed class NullableVnWallClockDateTimeJsonConverter : JsonConverter<DateTime?>
{
    public override DateTime? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Null) return null;
        var s = reader.GetString();
        if (string.IsNullOrEmpty(s)) return null;
        return VnWallClockDateTimeJsonConverter.ParseAttendanceJson(s);
    }

    public override void Write(Utf8JsonWriter writer, DateTime? value, JsonSerializerOptions options)
    {
        if (!value.HasValue)
        {
            writer.WriteNullValue();
            return;
        }

        new VnWallClockDateTimeJsonConverter().Write(writer, value.Value, options);
    }
}
