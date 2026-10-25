// zkemkeeper face enroll — đủ chuỗi Connect_Net → Disconnect.
// 111 một mình (Flag=0, không RegEvent) thường không mở UI.
//
// Cần: Windows, zkemkeeper.dll đã đăng ký (Standalone SDK).
//   csc /nologo /r:Interop.zkemkeeper.dll /r:System.Windows.Forms.dll ZkEnrollFace.cs
// hoặc ProgID nếu đã regsvr32:
//   csc /nologo /r:System.dll ZkEnrollFace.cs
//
// Chạy (STA bắt buộc để nhận OnEnrollFingerEx):
//   ZkEnrollFace.exe 192.168.1.201 968315

using System;
using System.Threading;
using System.Windows.Forms;
using zkemkeeper;

internal static class ZkEnrollFace
{
    const int Machine = 1;
    static CZKEM Ax;
    static volatile bool Done;
    static volatile bool Ok;
    static string LastErr = "";

    [STAThread]
    static int Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.WriteLine("Usage: ZkEnrollFace <ip> <PIN> [port=4370]");
            return 2;
        }

        string ip = args[0];
        string pin = args[1];
        int port = args.Length > 2 ? int.Parse(args[2]) : 4370;

        Ax = new CZKEM();
        Ax.OnEnrollFinger += OnEnrollFinger;
        Ax.OnEnrollFingerEx += OnEnrollFingerEx;

        Console.WriteLine("Connect_Net {0}:{1}", ip, port);
        if (!Ax.Connect_Net(ip, port))
        {
            int code = 0;
            Ax.GetLastError(ref code);
            Console.WriteLine("Connect_Net FAIL GetLastError={0}", code);
            return 1;
        }

        try
        {
            // Giữ máy online trong lúc SDK thao tác (handbook: EnableDevice sau connect).
            Ax.EnableDevice(Machine, true);

            // 65535 = mọi realtime event, gồm OnEnrollFinger / OnEnrollFingerEx.
            if (!Ax.RegEvent(Machine, 65535))
            {
                Console.WriteLine("RegEvent FAIL");
                return 1;
            }

            // SSR_SetUserInfo: tạo user + bật (bEnabled=true). Privilege 0 = user thường.
            if (!Ax.SSR_SetUserInfo(Machine, pin, pin, "", 0, true))
            {
                int code = 0;
                Ax.GetLastError(ref code);
                Console.WriteLine("SSR_SetUserInfo warn GetLastError={0} (user co the da ton tai)", code);
            }

            Ax.CancelOperation();

            // Handbook iFace: DelUserFace index CHỈ 50 (không phải 111).
            Ax.DelUserFace(Machine, pin, 50);
            Ax.RefreshData(Machine);

            // StartEnrollEx(UserID, FingerIndex, Flag)
            // 111 = mở enroll mặt (công văn ZKTeco). Flag=1 = valid — Flag=0 hay bị máy bỏ.
            // Nếu 111 từ chối, thử 50 (index template mặt trên máy NIR/iFace).
            bool started = Ax.StartEnrollEx(pin, 111, 1)
                           || Ax.StartEnrollEx(pin, 50, 1);
            if (!started)
            {
                int code = 0;
                Ax.GetLastError(ref code);
                Console.WriteLine("StartEnrollEx FAIL GetLastError={0}", code);
                return 1;
            }

            Console.WriteLine("StartEnrollEx OK — dung truoc may, nhin camera (60s)");
            DateTime until = DateTime.UtcNow.AddSeconds(60);
            while (!Done && DateTime.UtcNow < until)
            {
                Application.DoEvents();
                Thread.Sleep(50);
            }

            // Handbook: sau enroll máy có thể đứng im — StartIdentify bắt về 1:N.
            Ax.StartIdentify();
            Ax.RefreshData(Machine);
            Ax.EnableDevice(Machine, true);

            Console.WriteLine(Ok ? "ENROLL FACE OK" : "ENROLL FACE timeout/fail " + LastErr);
            return Ok ? 0 : 1;
        }
        finally
        {
            Ax.Disconnect();
            Console.WriteLine("Disconnect");
        }
    }

    static void OnEnrollFinger(int enrollNumber, int fingerIndex, int actionResult, int templateLength)
    {
        HandleEnroll("OnEnrollFinger", enrollNumber.ToString(), fingerIndex, actionResult, templateLength);
    }

    static void OnEnrollFingerEx(string enrollNumber, int fingerIndex, int actionResult, int templateLength)
    {
        HandleEnroll("OnEnrollFingerEx", enrollNumber, fingerIndex, actionResult, templateLength);
    }

    static void HandleEnroll(string ev, string pin, int fingerIndex, int actionResult, int templateLength)
    {
        Console.WriteLine("{0} PIN={1} Index={2} ActionResult={3} TmpLen={4}",
            ev, pin, fingerIndex, actionResult, templateLength);
        // ActionResult=0 thành công (handbook). Index enroll mặt thường 111 hoặc 50.
        LastErr = "ActionResult=" + actionResult;
        Ok = actionResult == 0;
        Done = true;
    }
}
