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
