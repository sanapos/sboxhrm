using System.Runtime.InteropServices;
using System.Drawing.Printing;

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

    public static void SendRaw(string printerName, byte[] data)
    {
        if (string.IsNullOrWhiteSpace(printerName))
            throw new InvalidOperationException("Chưa chọn máy in Windows.");
        if (data.Length == 0)
            throw new InvalidOperationException("Không có dữ liệu để in.");

        if (!OpenPrinter(printerName.Trim(), out var handle, IntPtr.Zero))
            throw new InvalidOperationException(
                $"Không mở được máy in «{printerName}». Kiểm tra máy đã cài driver và đang sẵn sàng.");

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
