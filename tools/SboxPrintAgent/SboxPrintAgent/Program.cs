using SboxPrintAgent.Ui;

namespace SboxPrintAgent;

static class Program
{
    [STAThread]
    static void Main()
    {
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
    }
}
