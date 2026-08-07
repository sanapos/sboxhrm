namespace ZKTecoADMS.Application.Constants;

/// <summary>ADMS engine profiles — classify by Platform/FW, not marketing model name.</summary>
public static class AdmsEngineProfiles
{
    public const string Default = "Default";
    public const string PullDeny = "PullDeny";
    public const string Linux = "Linux";
    public const string AndroidVisibleLight = "AndroidVisibleLight";
    public const string TftLegacy = "TftLegacy";

    /// <summary>
    /// Server-only stamp sync marker — MUST NOT be delivered to the device.
    /// CDataGet uses pending Sync* commands to set OPERLOG/ATTLOG Stamp=0.
    /// </summary>
    public const string StampSyncCommand = "__STAMP_SYNC__";

    public static bool IsStampSyncMarker(string? command) =>
        string.Equals(command?.Trim(), StampSyncCommand, StringComparison.OrdinalIgnoreCase);

    /// <summary>Legacy CHECK marker used before __STAMP_SYNC__ — only for Sync* command types.</summary>
    public static bool IsLegacyStampCheck(DeviceCommandTypes commandType, string? command) =>
        (commandType is DeviceCommandTypes.SyncDeviceUsers or DeviceCommandTypes.SyncAttendances)
        && string.Equals(command?.Trim(), "CHECK", StringComparison.OrdinalIgnoreCase);

    public static bool ShouldSkipDeviceDelivery(DeviceCommandTypes commandType, string? command) =>
        IsStampSyncMarker(command) || IsLegacyStampCheck(commandType, command);

    public static string ResolveProfile(string? platform, string? firmware, string? serialNumber)
    {
        // Options/DeviceInfo đôi khi ghi Ver_6.60_Apr... thay vì "Ver 6.60 Apr..."
        static string Norm(string? s) =>
            (s ?? string.Empty).Replace('_', ' ');

        var p = Norm(platform);
        var fw = Norm(firmware);

        // Android / visible-light face terminals (e.g. ZAM70 2FA) — check before SN OEM heuristics.
        if (p.Contains("Android", StringComparison.OrdinalIgnoreCase)
            || p.Contains("ZAM", StringComparison.OrdinalIgnoreCase)
            || fw.Contains("Android", StringComparison.OrdinalIgnoreCase)
            || fw.Contains("ZAM", StringComparison.OrdinalIgnoreCase)
            || fw.Contains("NF24", StringComparison.OrdinalIgnoreCase)
            || fw.Contains("OCM", StringComparison.OrdinalIgnoreCase))
        {
            return AndroidVisibleLight;
        }

        // OEM fingerprint series (demo 131* ZLM31) often deny QUERY/ENROLL_FP.
        // Không áp cho máy TFT/ZLM60 Ver 6.x/8.x (vd. K30/8300) — vẫn đăng ký vân tay được.
        // SN 131* chỉ là heuristic OEM demo cũ; platform/firmware mới hơn phải thắng.
        var isLegacyTftOrZlm60 =
            p.Contains("ZLM60", StringComparison.OrdinalIgnoreCase)
            || p.Contains("ZEM5", StringComparison.OrdinalIgnoreCase)
            || p.Contains("ZEM6", StringComparison.OrdinalIgnoreCase)
            || fw.StartsWith("Ver 6.", StringComparison.OrdinalIgnoreCase)
            || fw.Contains("ZLM60", StringComparison.OrdinalIgnoreCase);

        if (!string.IsNullOrWhiteSpace(serialNumber)
            && serialNumber.StartsWith("131", StringComparison.Ordinal)
            && !fw.Contains("ZAM", StringComparison.OrdinalIgnoreCase)
            && !isLegacyTftOrZlm60)
        {
            return PullDeny;
        }

        if (p.Contains("ZEM5", StringComparison.OrdinalIgnoreCase)
            || p.Contains("ZEM6", StringComparison.OrdinalIgnoreCase)
            || fw.StartsWith("Ver 6.", StringComparison.OrdinalIgnoreCase)
            || p.Contains("ZLM60", StringComparison.OrdinalIgnoreCase))
        {
            return TftLegacy;
        }

        if (p.Contains("Linux", StringComparison.OrdinalIgnoreCase)
            || p.Contains("ZLM", StringComparison.OrdinalIgnoreCase)
            || p.Contains("ZMM", StringComparison.OrdinalIgnoreCase))
        {
            return Linux;
        }

        return Default;
    }

    public static void ApplyProfileDefaults(Domain.Entities.DeviceInfo info, string profile)
    {
        var previous = info.EngineProfile;
        info.EngineProfile = profile;
        switch (profile)
        {
            case PullDeny:
                // USERINFO query thường -1002; ATTLOG query vẫn chạy được trên nhiều máy
                // (vd. ZLM60_TFT Long Bình 3) — không seed SupportsAttendanceQuery=false.
                info.SupportsUserQuery ??= false;
                info.SupportsEnrollFingerprint ??= false;
                // Chỉ tắt cửa với PullDeny thuần (OEM demo không ZAM). Không ghi đè nếu đã học true.
                info.SupportsDoorControl ??= false;
                info.PreferStampSync = true;
                break;
            case AndroidVisibleLight:
                info.SupportsFaceUpdate ??= true;
                info.SupportsUserQuery ??= true;
                info.SupportsAttendanceQuery ??= true;
                // ZAM70 / 2FA thường có relay cửa — cho phép thử CONTROL DEVICE
                if (info.SupportsDoorControl == false)
                {
                    // Có thể bị seed nhầm từ SN 131*; reset để thử lại
                    var fw = info.FirmwareVersion ?? string.Empty;
                    if (fw.Contains("ZAM", StringComparison.OrdinalIgnoreCase)
                        || fw.Contains("NF24", StringComparison.OrdinalIgnoreCase)
                        || fw.Contains("OCM", StringComparison.OrdinalIgnoreCase))
                    {
                        info.SupportsDoorControl = null;
                    }
                }
                info.SupportsDoorControl ??= true;
                break;
            case TftLegacy:
                // TFT cũ: USER ADD hay lỗi; DATA UPDATE thường OK; QUERY tùy máy
                info.SupportsFaceUpdate ??= false;
                // Thoát PullDeny nhầm (SN 131* + ZLM60/8300): mở lại enroll FP trừ khi đã học false từ lệnh thật.
                if (string.Equals(previous, PullDeny, StringComparison.OrdinalIgnoreCase)
                    && info.SupportsEnrollFingerprint == false)
                {
                    info.SupportsEnrollFingerprint = null;
                }
                // Mặc định cho phép thử đăng ký vân tay từ xa trên TFT/ZLM60.
                info.SupportsEnrollFingerprint ??= true;
                break;
            case Linux:
                info.SupportsUserQuery ??= true;
                info.SupportsAttendanceQuery ??= true;
                break;
        }

        info.CapabilityUpdatedAt = DateTime.UtcNow;
    }
}
