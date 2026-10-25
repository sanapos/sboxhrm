namespace SboxFlashGui;

internal sealed class ToolLaunch
{
    public required string FileName { get; init; }
    public required string PrefixArgs { get; init; }
    public string? WorkingDirectory { get; init; }
    public string Display { get; init; } = "";
}

internal static class EspToolLocator
{
    public static ToolLaunch? Find()
    {
        // 1) python -m esptool (portable neu da pip install)
        var py = FindPython();
        if (py != null && CanRunPythonModule(py, "esptool"))
        {
            return new ToolLaunch
            {
                FileName = py,
                PrefixArgs = "-m esptool",
                WorkingDirectory = null,
                Display = $"{py} -m esptool",
            };
        }

        // 2) esptool.exe (IDF venv / PATH / cạnh exe)
        foreach (var exe in CandidateEspToolExes())
        {
            if (!File.Exists(exe)) continue;
            return new ToolLaunch
            {
                FileName = exe,
                PrefixArgs = "",
                WorkingDirectory = Path.GetDirectoryName(exe),
                Display = exe,
            };
        }

        return null;
    }

    public static ToolLaunch FromUserPath(string path)
    {
        path = path.Trim().Trim('"');
        if (path.Contains("-m esptool", StringComparison.OrdinalIgnoreCase))
        {
            var py = FindPython() ?? "python";
            return new ToolLaunch
            {
                FileName = py,
                PrefixArgs = "-m esptool",
                Display = $"{py} -m esptool",
            };
        }

        if (!File.Exists(path))
            throw new FileNotFoundException("Khong tim thay esptool", path);

        return new ToolLaunch
        {
            FileName = path,
            PrefixArgs = "",
            WorkingDirectory = Path.GetDirectoryName(path),
            Display = path,
        };
    }

    private static IEnumerable<string> CandidateEspToolExes()
    {
        var exeDir = AppContext.BaseDirectory;
        yield return Path.Combine(exeDir, "esptool.exe");

        yield return @"E:\esp\tools\python_env\idf5.5_py3.14_env\Scripts\esptool.exe";

        var idfTools = Environment.GetEnvironmentVariable("IDF_TOOLS_PATH");
        if (!string.IsNullOrWhiteSpace(idfTools))
        {
            var envRoot = Path.Combine(idfTools, "python_env");
            if (Directory.Exists(envRoot))
            {
                foreach (var envDir in Directory.GetDirectories(envRoot))
                    yield return Path.Combine(envDir, "Scripts", "esptool.exe");
            }
        }

        var pathEnv = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var part in pathEnv.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
            yield return Path.Combine(part.Trim('"'), "esptool.exe");
    }

    private static string? FindPython()
    {
        var idfPy = @"E:\esp\tools\python_env\idf5.5_py3.14_env\Scripts\python.exe";
        if (File.Exists(idfPy)) return idfPy;

        foreach (var name in new[] { "python.exe", "python3.exe" })
        {
            var pathEnv = Environment.GetEnvironmentVariable("PATH") ?? "";
            foreach (var part in pathEnv.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
            {
                var c = Path.Combine(part.Trim('"'), name);
                if (File.Exists(c)) return c;
            }
        }
        return null;
    }

    private static bool CanRunPythonModule(string python, string module)
    {
        try
        {
            var psi = new System.Diagnostics.ProcessStartInfo
            {
                FileName = python,
                Arguments = $"-c \"import {module}\"",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            };
            using var p = System.Diagnostics.Process.Start(psi);
            if (p == null) return false;
            p.WaitForExit(5000);
            return p.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }
}
