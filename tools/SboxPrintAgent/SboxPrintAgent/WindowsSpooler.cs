using System.Drawing.Printing;
using System.Linq;
using System.Runtime.InteropServices;

namespace SboxPrintAgent;

/// <summary>In RAW ESC/POS qua driver Windows đã cài (USB / Share).</summary>
public static class WindowsSpooler
{
    public static List<string> ListInstalledPrinters()
    {
        var list = new List<string>();
        foreach (string name in PrinterSettings.InstalledPrinters)
        {
            if (!string.IsNullOrWhiteSpace(name))
                list.Add(name);
        }
        return list.OrderBy(x => x, StringComparer.CurrentCultureIgnoreCase).ToList();
    }

    /// Resolve tên máy in Windows ổn định theo tên queue (không theo cổng USB001…).
    /// Khi cổng USB đổi, tên máy in thường giữ nguyên; nếu lệch nhẹ thì khớp chứa tên.
    public static string ResolvePrinterName(string preferredName)
    {
        var want = (preferredName ?? "").Trim();
        if (want.Length == 0) return want;
        var installed = ListInstalledPrinters();
        var exact = installed.FirstOrDefault(n =>
            string.Equals(n, want, StringComparison.OrdinalIgnoreCase));
        if (exact != null) return exact;

        // Khớp chứa: "EPSON TM-T82" ↔ "EPSON TM-T82 Receipt"
        var partial = installed
            .Where(n =>
                n.Contains(want, StringComparison.OrdinalIgnoreCase) ||
                want.Contains(n, StringComparison.OrdinalIgnoreCase))
            .OrderBy(n => Math.Abs(n.Length - want.Length))
            .FirstOrDefault();
        return partial ?? want;
    }

    public static void SendRaw(string printerName, byte[] data)
    {
        if (string.IsNullOrWhiteSpace(printerName))
            throw new InvalidOperationException("Chưa chọn máy in Windows.");
        if (data.Length == 0)
            throw new InvalidOperationException("Không có dữ liệu để in.");

        var resolved = ResolvePrinterName(printerName);
        if (!OpenPrinter(resolved, out var handle, IntPtr.Zero))
            throw new InvalidOperationException(
                $"Không mở được máy in «{printerName}»" +
                (string.Equals(resolved, printerName.Trim(), StringComparison.OrdinalIgnoreCase)
                    ? ""
                    : $" (đã thử «{resolved}»)") +
                ". Kiểm tra máy đã cài driver và đang sẵn sàng. " +
                "Gán theo tên máy in Windows — không dùng tên cổng USB001/COM.");

        try
        {
            var di = new DOCINFOA
            {
                pDocName = "SBOX Print",
                pDataType = "RAW",
            };
            if (!StartDocPrinter(handle, 1, di))
                throw new InvalidOperationException("Không bắt đầu được lệnh in (StartDoc).");

            try
            {
                if (!StartPagePrinter(handle))
                    throw new InvalidOperationException("Không bắt đầu được trang in.");
                try
                {
                    var pinned = GCHandle.Alloc(data, GCHandleType.Pinned);
                    try
                    {
                        if (!WritePrinter(handle, pinned.AddrOfPinnedObject(), data.Length, out var written) ||
                            written != data.Length)
                            throw new InvalidOperationException("Gửi dữ liệu tới máy in thất bại.");
                    }
                    finally { pinned.Free(); }
                }
                finally { EndPagePrinter(handle); }
            }
            finally { EndDocPrinter(handle); }
        }
        finally { ClosePrinter(handle); }
    }

    public static void SendTest(string printerName)
        => SendRaw(printerName, EscPosBuilder.TestSlip(printerName));

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    sealed class DOCINFOA
    {
        [MarshalAs(UnmanagedType.LPStr)] public string? pDocName;
        [MarshalAs(UnmanagedType.LPStr)] public string? pOutputFile;
        [MarshalAs(UnmanagedType.LPStr)] public string? pDataType;
    }

    [DllImport("winspool.drv", EntryPoint = "OpenPrinterA", SetLastError = true, CharSet = CharSet.Ansi)]
    static extern bool OpenPrinter(string pPrinterName, out IntPtr phPrinter, IntPtr pDefault);

    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", EntryPoint = "StartDocPrinterA", SetLastError = true, CharSet = CharSet.Ansi)]
    static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In] DOCINFOA di);

    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.drv", SetLastError = true)]
    static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);
}
