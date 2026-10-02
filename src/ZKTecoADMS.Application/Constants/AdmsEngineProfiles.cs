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
    /// Máy push «lite» đời mới giá rẻ (LX35, chip Anyka AK37xx, PushVersion 3.0.x):
    /// ngày giờ dạng «yyyy-MM-dd HH:mm:ss» (không có T), không xử lý khối GET OPTION trong getrequest (luôn gửi Stamp=9999).
    /// Đã thử trên máy thật (FW ZLM31-FXO1-3.1.8, Push 3.0.1, 02–03/10/2026) + đọc ROM LX35.bin:
    /// - lệnh cấp đầu chỉ có CHECK / CLEAR / INFO / REBOOT / DATA / Pause / Resume (không ENROLL_FP, AC_UNLOCK, SET OPTION);
    /// - DATA QUERY USERINFO / ATTLOG trả -1002 với mọi dạng tham số;
    /// - CHECK làm máy bắt tay lại (GET cdata options=all) → đọc ATTLOGStamp/OPERLOGStamp=0 → gửi lại toàn bộ chấm công / user.
    /// Vì vậy tải lại dữ liệu = lệnh đánh dấu __STAMP_SYNC__ + CHECK (xem <see cref="UsesCheckStampSync"/>).
    /// </summary>
    public const string PushLite = "PushLite";

    /// <summary>Firmware chưa biết (máy chưa gửi INFO/options).</summary>
    public static bool IsUnknownFirmware(string? firmware) =>
        string.IsNullOrWhiteSpace(firmware)
        || firmware.Trim().Equals("Unknown", StringComparison.OrdinalIgnoreCase)
        || firmware.StartsWith("PUSH v", StringComparison.OrdinalIgnoreCase);

    /// <summary>Tải lại chấm công / user bằng __STAMP_SYNC__ + CHECK (máy bắt tay lại, nhận Stamp=0) thay cho DATA QUERY.</summary>
    public static bool UsesCheckStampSync(string? profile) =>
        string.Equals(profile, PushLite, StringComparison.OrdinalIgnoreCase);

    /// <summary>Handshake chỉ gửi TransFlag dạng chuỗi số — firmware LX35 đọc bằng strspn (mặc định 1101101100).</summary>
    public static bool UsesDigitTransFlag(string? profile) =>
        string.Equals(profile, PushLite, StringComparison.OrdinalIgnoreCase);

    /// <summary>Lệnh DATA QUERY ATTLOG dùng dấu cách giữa ngày và giờ.</summary>
    public static bool UsesSpaceDateTime(string? profile) =>
        string.Equals(profile, PushLite, StringComparison.OrdinalIgnoreCase);

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

    public static string ResolveProfile(string? platform, string? firmware, string? serialNumber, string? pushVersion = null)
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

        // LX35: Anyka AK37xx; khi chưa có platform thì nhận qua pushver=3.0.x ở handshake
        // (INFO trả «PushVersion=Ver 3.0.1-20230519» — bỏ tiền tố «Ver»).
        var pushVer = (pushVersion ?? string.Empty).Trim();
        if (pushVer.StartsWith("Ver", StringComparison.OrdinalIgnoreCase))
            pushVer = pushVer[3..].TrimStart(' ', '_', '.');
        if (p.Contains("AK37", StringComparison.OrdinalIgnoreCase)
            || p.Contains("AK39", StringComparison.OrdinalIgnoreCase)
            || (string.IsNullOrWhiteSpace(p)
                && IsUnknownFirmware(firmware)
                && pushVer.StartsWith("3.0", StringComparison.Ordinal)))
        {
            return PushLite;
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

        var identityKnown = !string.IsNullOrWhiteSpace(p) || !IsUnknownFirmware(firmware);
        if (identityKnown
            && !string.IsNullOrWhiteSpace(serialNumber)
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

    public static bool IsAndroidVisibleLight(string? platform, string? firmware, string? serialNumber) =>
        ResolveProfile(platform, firmware, serialNumber) == AndroidVisibleLight;

    public static bool IsAndroidVisibleLight(Domain.Entities.DeviceInfo? info, string? serialNumber) =>
        IsAndroidVisibleLight(info?.Platform, info?.FirmwareVersion, serialNumber);

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
            case PushLite:
                // Thoát PullDeny gắn nhầm theo SN: các cờ «false» do seed, không phải do máy từ chối.
                if (string.Equals(previous, PullDeny, StringComparison.OrdinalIgnoreCase))
                {
                    if (info.SupportsUserQuery == false) info.SupportsUserQuery = null;
                    if (info.SupportsEnrollFingerprint == false) info.SupportsEnrollFingerprint = null;
                    if (info.SupportsDoorControl == false) info.SupportsDoorControl = null;
                    // -1002 học được khi còn PullDeny là do gửi ngày dạng «T» — PushLite gửi dạng có dấu cách.
                    if (info.SupportsAttendanceQuery == false) info.SupportsAttendanceQuery = null;
                }
                info.SupportsUserQuery ??= true;
                info.SupportsAttendanceQuery ??= true;
                // ROM không có ENROLL_FP / AC_UNLOCK; máy không có camera (FaceFunOn=0).
                info.SupportsEnrollFingerprint = false;
                info.SupportsFaceUpdate = false;
                info.SupportsDoorControl = false;
                // Stamp=0 chỉ có tác dụng khi máy bắt tay lại — server gửi kèm CHECK (UsesCheckStampSync).
                info.PreferStampSync = true;
                break;
        }

        info.CapabilityUpdatedAt = DateTime.UtcNow;
    }
}
