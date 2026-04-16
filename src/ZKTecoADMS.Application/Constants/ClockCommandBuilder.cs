using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Constants;

public static class ClockCommandBuilder
{
    public static string BuildAddOrUpdateEmployeeCommand(DeviceUser user)
    {
        return $"DATA UPDATE USERINFO PIN={user.Pin}\tName={user.Name}\tPri={user.Privilege}\tPasswd={user.Password}\tCard={user.CardNumber}\tGrp={user.GroupId}\tTZ=0000\tVerify={user.VerifyMode}";
    }

    public static string BuildDeleteEmployeeCommand(string pin)
    {
        return $"DATA DELETE USERINFO PIN={pin}";
    }

    public static string BuildGetAllUsersCommand()
    {
        // CHECK USERINFO - yêu cầu máy gửi lại toàn bộ danh sách user
        // Máy sẽ trả về qua POST /iclock/cdata?table=OPERLOG
        return "CHECK USERINFO";
    }

    /// <summary>
    /// Builds command to start fingerprint enrollment on device
    /// PIN: User PIN, FID: Finger index (0-9)
    /// </summary>
    public static string BuildEnrollFingerprintCommand(string pin, int fingerIndex = 0)
    {
        // ENROLL_FP: Lệnh bắt đầu đăng ký vân tay trên máy chấm công
        // Máy sẽ hiển thị giao diện đăng ký vân tay
        return $"ENROLL_FP PIN={pin}\tFID={fingerIndex}";
    }

    /// <summary>
    /// Builds command to delete fingerprint(s) from device
    /// PIN: User PIN, FID: Finger index (0-9), -1 to delete all
    /// </summary>
    public static string BuildDeleteFingerprintCommand(string pin, int fingerIndex = -1)
    {
        if (fingerIndex < 0)
        {
            // Xóa tất cả vân tay của user
            return $"DATA DELETE FINGERTMP PIN={pin}";
        }
        // Xóa vân tay cụ thể
        return $"DATA DELETE FINGERTMP PIN={pin}\tFID={fingerIndex}";
    }

    /// <summary>
    /// Builds command to query fingerprint templates for sync
    /// </summary>
    public static string BuildGetFingerprintsCommand()
    {
        return "DATA QUERY FINGERTMP";
    }

    /// <summary>
    /// Builds command to start face enrollment on device
    /// PIN: User PIN, FID=50 (visible light face), BIODATAFLAG=1 (biometric)
    /// </summary>
    public static string BuildEnrollFaceCommand(string pin)
    {
        return $"ENROLL_FP PIN={pin}\tFID=50\tBIODATAFLAG=8";
    }

    /// <summary>
    /// Builds command to delete face from device
    /// PIN: User PIN, FID=50 (visible light face index)
    /// </summary>
    public static string BuildDeleteFaceCommand(string pin)
    {
        return $"DATA DELETE FINGERTMP PIN={pin}\tFID=50";
    }

    /// <summary>
    /// Builds a command to query attendance logs within a time period.
    /// Default: Last 2 years up to today.
    /// Time format: YYYY-MM-DDThh:mm:ss
    /// </summary>
    public static string BuildGetAttendanceCommand(DateTime? startTime = null, DateTime? endTime = null)
    {
        var end = endTime ?? DateTime.Now;
        var start = startTime ?? end.AddYears(-2);

        // Format: YYYY-MM-DDThh:mm:ss (ISO 8601)
        var startTimeStr = start.ToString("yyyy-MM-ddTHH:mm:ss");
        var endTimeStr = end.ToString("yyyy-MM-ddTHH:mm:ss");

        return $"DATA QUERY ATTLOG StartTime={startTimeStr}\tEndTime={endTimeStr}";
    }
}