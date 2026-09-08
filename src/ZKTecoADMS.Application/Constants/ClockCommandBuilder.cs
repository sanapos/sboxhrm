using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Constants;

/// <summary>
/// ZKTeco PUSH / ADMS command strings (PUSH SDK ~3.2).
/// Wire format on poll response: C:{commandId}:{command}
/// Fields are TAB-separated (\t). Prefix "DATA" required for UPDATE/DELETE/QUERY data ops.
/// </summary>
public static class ClockCommandBuilder
{
    public const int DefaultEnrollRetry = 3;
    public const int EnrollOverwrite = 1;
    public const int EnrollNoOverwrite = 2;

    public static string BuildAddOrUpdateEmployeeCommand(DeviceUser user)
    {
        var passwd = user.Password ?? string.Empty;
        var card = user.CardNumber ?? string.Empty;
        return $"DATA UPDATE USERINFO PIN={user.Pin}\tName={user.Name}\tPri={user.Privilege}\tPasswd={passwd}\tCard={card}\tGrp={user.GroupId}\tTZ=0000\tVerify={user.VerifyMode}";
    }

    public static string BuildDeleteEmployeeCommand(string pin)
    {
        return $"DATA DELETE USERINFO PIN={pin}";
    }

    /// <summary>Pull all users from device (POST table=USERINFO/OPERLOG).</summary>
    public static string BuildGetAllUsersCommand()
    {
        return "DATA QUERY USERINFO";
    }

    /// <summary>Pull one user by PIN (some firmware prefers this over full dump).</summary>
    public static string BuildGetUserCommand(string pin)
    {
        return $"DATA QUERY USERINFO PIN={pin}";
    }

    /// <summary>
    /// Remote fingerprint enrollment (PUSH SDK §12.1).
    /// RETRY/OVERWRITE are required on many firmware builds — omitting them may return -1002.
    /// </summary>
    public static string BuildEnrollFingerprintCommand(
        string pin,
        int fingerIndex = 0,
        int retry = DefaultEnrollRetry,
        int overwrite = EnrollOverwrite)
    {
        return $"ENROLL_FP PIN={pin}\tFID={fingerIndex}\tRETRY={retry}\tOVERWRITE={overwrite}";
    }

    public static string BuildDeleteFingerprintCommand(string pin, int fingerIndex = -1)
    {
        if (fingerIndex < 0)
        {
            return $"DATA DELETE FINGERTMP PIN={pin}";
        }

        return $"DATA DELETE FINGERTMP PIN={pin}\tFID={fingerIndex}";
    }

    public static string BuildGetFingerprintsCommand()
    {
        return "DATA QUERY FINGERTMP";
    }

    public static string BuildGetFingerprintsForUserCommand(string pin, int? fingerIndex = null)
    {
        if (fingerIndex is >= 0)
        {
            return $"DATA QUERY FINGERTMP PIN={pin}\tFID={fingerIndex.Value}";
        }

        return $"DATA QUERY FINGERTMP PIN={pin}";
    }

    /// <summary>Pull VL / SenseFace templates (BIODATA Type=1 fingerprint, Type=9 face).</summary>
    public static string BuildGetBiodataCommand() => "DATA QUERY BIODATA";

    public static string BuildGetBiodataForUserCommand(string pin) =>
        $"DATA QUERY BIODATA Pin={pin}";

    /// <summary>Pull legacy NIR face templates (FACE table).</summary>
    public static string BuildGetFacesCommand() => "DATA QUERY FACE";

    /// <summary>
    /// Remote VL-face enroll — captured from sana.zkbiotimecloud.com for SenseFace 2A:
    /// <c>C:1854446:ENROLL_BIO TYPE=9\tPIN=123\tCardNo=\tRETRY=3\tOVERWRITE=1</c>
    /// </summary>
    public static string BuildEnrollFaceCommand(string pin)
    {
        return $"ENROLL_BIO TYPE=9\tPIN={pin}\tCardNo=\tRETRY={DefaultEnrollRetry}\tOVERWRITE={EnrollOverwrite}";
    }

    /// <summary>PUSH SDK §7.8 — delete face template (not FINGERTMP FID=50).</summary>
    public static string BuildDeleteFaceCommand(string pin)
    {
        return $"DATA DELETE FACE PIN={pin}";
    }

    /// <summary>
    /// Push fingerprint to device. Captured from BioTime ADMS:
    /// <c>DATA UPDATE FINGERTMP PIN=…	FID=…	Size=…	Valid=1	TMP=…</c>
    /// </summary>
    public static string BuildUpdateFingerprintCommand(
        string pin,
        int fingerIndex,
        string template,
        int? size = null,
        int valid = 1)
    {
        var sz = size is > 0 ? size.Value : template.Length;
        return $"DATA UPDATE FINGERTMP PIN={pin}\tFID={fingerIndex}\tSize={sz}\tValid={valid}\tTMP={template}";
    }

    /// <summary>
    /// Push VL face template blob (SpeedFace / some SenseFace). Captured from older BioTime:
    /// <c>DATA UPDATE BIODATA Pin=…	No=0	Index=0	Valid=1	Duress=0	Type=9	MajorVer=58	MinorVer=12	Tmp=…</c>
    /// ZAM70 NF24 often returns device error -30 on this — use <see cref="BuildUpdateBioPhotoCommand"/> instead.
    /// Note: Pin=/Tmp= (not PIN=/TMP=).
    /// </summary>
    public static string BuildUpdateVisibleFaceCommand(
        string pin,
        string template,
        int index = 0,
        int majorVer = 58,
        int minorVer = 12)
    {
        return $"DATA UPDATE BIODATA Pin={pin}\tNo=0\tIndex={index}\tValid=1\tDuress=0\tType=9\tMajorVer={majorVer}\tMinorVer={minorVer}\tTmp={template}";
    }

    /// <summary>
    /// Push visible-light face as JPEG. Captured from zkbiotime.xmzkteco.com (ZAM70 profile):
    /// <c>DATA UPDATE BIOPHOTO PIN=…	Type=9	Format=1	Url=iclock/doc/biophoto/{id}.jpg</c>
    /// </summary>
    public static string BuildUpdateBioPhotoCommand(string pin, string relativeUrl, int type = 9)
    {
        return $"DATA UPDATE BIOPHOTO PIN={pin}\tType={type}\tFormat=1\tUrl={relativeUrl}";
    }

    /// <summary>
    /// Inline JPEG (same table as BioTime Url form). Use when the device cannot fetch Url.
    /// </summary>
    public static string BuildUpdateBioPhotoContentCommand(string pin, byte[] jpegBytes, int type = 9)
    {
        var b64 = Convert.ToBase64String(jpegBytes);
        return $"DATA UPDATE BIOPHOTO PIN={pin}\tType={type}\tSize={jpegBytes.Length}\tContent={b64}";
    }

    /// <summary>Legacy NIR face (FID ≥ 50) — PUSH SDK FACE table.</summary>
    public static string BuildUpdateFaceTemplateCommand(string pin, int faceIndex, string template, int? size = null)
    {
        var sz = size is > 0 ? size.Value : template.Length;
        return $"DATA UPDATE FACE PIN={pin}\tFID={faceIndex}\tSize={sz}\tValid=1\tTMP={template}";
    }

    /// <summary>
    /// Push user photo. Captured from BioTime:
    /// <c>DATA UPDATE USERPIC PIN=…	Size=…	Content=&lt;jpeg-base64&gt;</c>
    /// </summary>
    public static string BuildUpdateUserPicCommand(string pin, byte[] jpegBytes)
    {
        var b64 = Convert.ToBase64String(jpegBytes);
        return $"DATA UPDATE USERPIC PIN={pin}\tSize={jpegBytes.Length}\tContent={b64}";
    }

    public static DateTime VietnamEndOfToday()
    {
        var vnNow = DateTime.UtcNow.AddHours(7);
        return vnNow.Date.AddDays(1).AddSeconds(-1);
    }

    public static string BuildDefaultSyncAttendancesCommand() =>
        BuildGetAttendanceCommand(DateTime.UtcNow.AddHours(7).AddYears(-5), VietnamEndOfToday());

    /// <summary>PUSH SDK §11.2 — time format YYYY-MM-DDThh:mm:ss.</summary>
    public static string BuildGetAttendanceCommand(DateTime? startTime = null, DateTime? endTime = null)
    {
        var end = endTime ?? VietnamEndOfToday();
        var start = startTime ?? end.AddYears(-2);

        var startTimeStr = start.ToString("yyyy-MM-ddTHH:mm:ss");
        var endTimeStr = end.ToString("yyyy-MM-ddTHH:mm:ss");

        return $"DATA QUERY ATTLOG StartTime={startTimeStr}\tEndTime={endTimeStr}";
    }

    /// <summary>
    /// Remote open door / unlock relay.
    /// Captured from agap.top (SenseFace 2A / ZAM70): wire <c>C:OPENDOOR0:AC_UNLOCK</c>, device ACK Return=0.
    /// <paramref name="useAccessControlProtocol"/> true keeps legacy CONTROL DEVICE hex for older AC panels.
    /// </summary>
    public static string BuildOpenDoorCommand(bool useAccessControlProtocol = false, int doorId = 1, int durationSeconds = 5)
    {
        if (!useAccessControlProtocol)
            return "AC_UNLOCK";

        var door = Math.Clamp(doorId <= 0 ? 1 : doorId, 1, 16);
        var dur = Math.Clamp(durationSeconds, 1, 254);
        return $"CONTROL DEVICE 01{door:X2}01{dur:X2}";
    }

    /// <summary>
    /// ADMS poll response line. OpenDoor uses agap-style id prefix OPENDOOR{n} (device ACKs ID=OPENDOOR{n}).
    /// </summary>
    public static string FormatWireCommand(long commandId, string command, DeviceCommandTypes commandType)
    {
        var id = commandType == DeviceCommandTypes.OpenDoor
            ? $"OPENDOOR{commandId}"
            : commandId.ToString();
        return $"C:{id}:{command}";
    }

    /// <summary>
    /// Remote close lock output (DD=00 Off) — CONTROL DEVICE 01010100.
    /// </summary>
    public static string BuildCloseDoorCommand(bool useAccessControlProtocol = true, int doorId = 1)
    {
        var door = Math.Clamp(doorId <= 0 ? 1 : doorId, 1, 16);
        return $"CONTROL DEVICE 01{door:X2}0100";
    }
}
