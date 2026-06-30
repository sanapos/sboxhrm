using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ZKTecoADMS.Api.Serialization;

/// <summary>
/// UTC thật (Kind=Utc/Local) → JSON kèm Z.
/// Unspecified (Npgsql legacy / chấm công VN) → JSON không Z — client parse theo loại field.
/// </summary>
public sealed class UtcDateTimeJsonConverter : JsonConverter<DateTime>
{
    public override DateTime Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var s = reader.GetString();
        if (string.IsNullOrEmpty(s)) return default;
        return DateTime.Parse(s, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);
    }

    public override void Write(Utf8JsonWriter writer, DateTime value, JsonSerializerOptions options)
    {
        switch (value.Kind)
        {
            case DateTimeKind.Utc:
                writer.WriteStringValue(
                    value.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture));
                break;
            case DateTimeKind.Local:
                writer.WriteStringValue(
                    value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture));
                break;
            default:
                writer.WriteStringValue(
                    value.ToString("yyyy-MM-dd'T'HH:mm:ss.fff", CultureInfo.InvariantCulture));
                break;
        }
    }
}

public sealed class NullableUtcDateTimeJsonConverter : JsonConverter<DateTime?>
{
    public override DateTime? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Null) return null;
        var s = reader.GetString();
        if (string.IsNullOrEmpty(s)) return null;
        return DateTime.Parse(s, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);
    }

    public override void Write(Utf8JsonWriter writer, DateTime? value, JsonSerializerOptions options)
    {
        if (!value.HasValue)
        {
            writer.WriteNullValue();
            return;
        }
        new UtcDateTimeJsonConverter().Write(writer, value.Value, options);
    }
}
