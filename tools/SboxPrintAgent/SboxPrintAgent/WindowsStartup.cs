using Microsoft.Win32;

namespace SboxPrintAgent;

/// <summary>Tự chạy khi mở Windows (HKCU Run).</summary>
public static class WindowsStartup
{
    const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    const string ValueName = "SboxPrintAgent";

    public static bool IsEnabled()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: false);
            var v = key?.GetValue(ValueName) as string;
            return !string.IsNullOrWhiteSpace(v);
        }
        catch
        {
            return false;
        }
    }

    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true)
            ?? Registry.CurrentUser.CreateSubKey(RunKeyPath);
        if (key == null)
            throw new InvalidOperationException("Không ghi được cấu hình khởi động Windows.");

        if (enabled)
        {
            var exe = Environment.ProcessPath
                ?? Application.ExecutablePath;
            if (string.IsNullOrWhiteSpace(exe) || !File.Exists(exe))
                throw new InvalidOperationException("Không xác định được đường dẫn file chương trình.");
            key.SetValue(ValueName, $"\"{exe}\"");
        }
        else
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }
}
