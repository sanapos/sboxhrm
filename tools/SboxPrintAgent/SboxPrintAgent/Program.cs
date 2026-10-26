using SboxPrintAgent.Ui;

namespace SboxPrintAgent;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        // Kiểm tra in A4/A5 không cần đăng nhập / không đụng cấu hình:
        //   SboxPrintAgent.exe --print-pdf hoadon.pdf "Tên máy in Windows" [file-ra.pdf]
        // Kết quả ghi vào <pdf>.result.txt (bản WinExe không có cửa sổ console).
        if (args.Length >= 3 && args[0] == "--guess-paper")
        {
            File.WriteAllText(args[2], WindowsSpooler.GuessPaperSize(args[1]));
            return 0;
        }
        if (args.Length >= 3 && args[0] == "--print-pdf")
            return PrintPdfFromCli(args[1], args[2], args.Length > 3 ? args[3] : null);

        ApplicationConfiguration.Initialize();
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException += (_, e) =>
            UiMsg.Error(e.Exception.Message, "Lỗi giao diện");
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            var ex = e.ExceptionObject as Exception;
            UiMsg.Error(ex?.Message ?? e.ExceptionObject?.ToString() ?? "Lỗi không xác định", "Lỗi nghiêm trọng");
        };

        try
        {
            Application.Run(new MainForm());
        }
        catch (Exception ex)
        {
            UiMsg.Error(ex.Message + "\n\n" + ex.StackTrace, "Không mở được SBOX Print Agent");
        }
        return 0;
    }

    static int PrintPdfFromCli(string pdfPath, string printer, string? toFile)
    {
        var result = pdfPath + ".result.txt";
        try
        {
            var pdf = File.ReadAllBytes(pdfPath);
            PdfPagePrinter.PrintAsync(printer, pdf, 1, "SBOX test A4", toFile)
                .GetAwaiter().GetResult();
            File.WriteAllText(result, "OK");
            return 0;
        }
        catch (Exception ex)
        {
            File.WriteAllText(result, "FAIL: " + ex);
            return 1;
        }
    }
}
