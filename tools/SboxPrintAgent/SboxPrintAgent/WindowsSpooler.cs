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

    /// <summary>
    /// Đoán khổ khi thêm máy in Windows: máy văn phòng (driver có khổ A4, tên không giống máy nhiệt/tem)
    /// → «A4» (chỉ nhận chứng từ khổ trang qua PDF); còn lại → «K80».
    /// </summary>
    public static string GuessPaperSize(string printerName)
    {
        var name = (printerName ?? "").Trim();
        if (System.Text.RegularExpressions.Regex.IsMatch(name,
                @"\bpos|receipt|thermal|\bbill|tm-|xp-|k58|k80|\b(57|58|72|80)\b|\brp\d|tsp|gp-|label|\btem\b|zebra|godex|\btsc|sunmi",
                System.Text.RegularExpressions.RegexOptions.IgnoreCase))
            return "K80";
        try
        {
            var ps = new PrinterSettings { PrinterName = ResolvePrinterName(name) };
            if (!ps.IsValid) return "K80";
            foreach (PaperSize p in ps.PaperSizes)
            {
                if (p.Kind == PaperKind.A4) return "A4";
            }
        }
        catch { /* driver lỗi → coi như máy nhiệt */ }
        return "K80";
    }

    public static bool IsPagePaper(string? paperSize) =>
        string.Equals(paperSize, "A4", StringComparison.OrdinalIgnoreCase) ||
        string.Equals(paperSize, "A5", StringComparison.OrdinalIgnoreCase);

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
