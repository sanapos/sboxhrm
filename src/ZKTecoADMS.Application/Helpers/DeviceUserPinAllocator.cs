namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Allocates ZKTeco-compatible device PINs (digits, max 8) unique per device.
/// Preference: reuse employee mapping → short code/phone suffix → sequential free number.
/// </summary>
public static class DeviceUserPinAllocator
{
    public const int MaxPinLength = 8;

    public static string DigitsOnly(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return string.Empty;
        return new string(value.Where(char.IsDigit).ToArray());
    }

    /// <summary>
    /// Pick a free PIN for <paramref name="deviceId"/>.
    /// <paramref name="existingPins"/> = all PINs already on that device.
    /// </summary>
    public static string Allocate(IReadOnlyCollection<string> existingPins, string? preferredPin)
    {
        var used = new HashSet<string>(
            existingPins.Where(p => !string.IsNullOrWhiteSpace(p)),
            StringComparer.Ordinal);

        foreach (var candidate in PreferredCandidates(preferredPin))
        {
            if (!used.Contains(candidate))
                return candidate;
        }

        return AllocateSequential(used);
    }

    public static IEnumerable<string> PreferredCandidates(string? preferredPin)
    {
        var digits = DigitsOnly(preferredPin);
        if (string.IsNullOrEmpty(digits))
            yield break;

        if (digits.Length <= MaxPinLength)
        {
            yield return digits;
            yield break;
        }

        // Phone / long employee code: try shorter tails first (easier to enter on device keypad).
        foreach (var len in new[] { 6, 7, 8 })
        {
            if (digits.Length >= len)
                yield return digits[^len..];
        }
    }

    public static string AllocateSequential(HashSet<string> used)
    {
        long next = 1;
        foreach (var p in used)
        {
            if (p.Length <= MaxPinLength && long.TryParse(p, out var n) && n >= next)
                next = n + 1;
        }

        const long max = 99_999_999L; // 8 digits
        for (; next <= max; next++)
        {
            var s = next.ToString();
            if (!used.Contains(s))
                return s;
        }

        throw new InvalidOperationException("Hết PIN trống trên máy (đã dùng hết dải 1–99999999).");
    }
}
