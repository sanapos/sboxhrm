namespace ZKTecoADMS.Application.Constants;

/// <summary>
/// Cấu hình PUSH gửi cho máy (GET /iclock/cdata hoặc nhúng trong getrequest).
/// Mirrored from agap.top SenseFace 2A handshake so the device polls /iclock/getrequest
/// (required for AC_UNLOCK — that firmware ignores C: lines glued onto options=all alone).
/// </summary>
public static class PushDeviceConfigBuilder
{
    public static string BuildGetOptionResponse(
        string serialNumber,
        string attLogStamp,
        string operLogStamp = "9999",
        string bioDataStamp = "9999")
    {
        // Keep SBOX stamp names for sync, plus agap aliases (Stamp/OpStamp) + registry/ping flags.
        return $"GET OPTION FROM: {serialNumber}\r\n" +
               $"PushProtVer=2.4.1\r\n" +
               $"PushOptionsFlag=1\r\n" +
               $"ServerVer=2.4.1\r\n" +
               $"ServerVersion=2.4.1\r\n" +
               $"PushVersion=2.4.1\r\n" +
               $"ATTLOGStamp={attLogStamp}\r\n" +
               $"OPERLOGStamp={operLogStamp}\r\n" +
               $"BIODATAStamp={bioDataStamp}\r\n" +
               $"FINGERTMPStamp={bioDataStamp}\r\n" +
               $"Stamp={attLogStamp}\r\n" +
               $"OpStamp={operLogStamp}\r\n" +
               $"ErrorDelay=5\r\n" +
               $"Delay=5\r\n" +
               $"registry=ok\r\n" +
               $"RegistryCode={serialNumber}\r\n" +
               $"ServerName=ADMS\r\n" +
               $"RequestDelay=5\r\n" +
               $"TransTimes=00:00;14:05\r\n" +
               $"TransInterval=1\r\n" +
               $"TransFlag=1111111010\r\n" +
               $"Realtime=1\r\n" +
               $"SessionID={serialNumber}\r\n" +
               $"TimeZone=7\r\n" +
               $"Encrypt=0\r\n" +
               $"EncryptFlag=0000000000\r\n" +
               $"SupportPing=1\r\n" +
               $"Timeout=20\r\n" +
               $"SyncTime=1";
    }
}
