namespace ZKTecoADMS.Application.Constants;

/// <summary>
/// Cấu hình PUSH gửi cho máy (GET /iclock/cdata hoặc nhúng trong getrequest khi máy không gọi cdata GET).
/// </summary>
public static class PushDeviceConfigBuilder
{
    public static string BuildGetOptionResponse(
        string serialNumber,
        string attLogStamp,
        string operLogStamp = "9999",
        string bioDataStamp = "9999")
    {
        return $"GET OPTION FROM: {serialNumber}\r\n" +
               $"ATTLOGStamp={attLogStamp}\r\n" +
               $"OPERLOGStamp={operLogStamp}\r\n" +
               $"BIODATAStamp={bioDataStamp}\r\n" +
               $"FINGERTMPStamp={bioDataStamp}\r\n" +
               "ErrorDelay=30\r\n" +
               "Delay=3\r\n" +
               "TransTimes=00:00;14:05\r\n" +
               "TransInterval=10\r\n" +
               "TransFlag=1111111100\r\n" +
               "Realtime=1\r\n" +
               "TimeZone=+07:00\r\n" +
               "Timeout=20\r\n" +
               "SyncTime=1\r\n" +
               "ServerVer=2.0.4\r\n" +
               "Encrypt=0";
    }
}
