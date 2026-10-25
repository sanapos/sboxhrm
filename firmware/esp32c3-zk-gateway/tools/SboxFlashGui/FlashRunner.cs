using System.Diagnostics;
using System.Text;

namespace SboxFlashGui;

internal sealed class FlashRunner
{
    public event Action<string>? LineReceived;

    public async Task<(bool Ok, string Message)> RunUsbAsync(
        ToolLaunch tool,
        string port,
        int baud,
        IReadOnlyList<(string Offset, string Path)> images,
        bool eraseFlash,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(tool.FileName) || !File.Exists(tool.FileName))
            return (false, $"Khong tim thay tool nap: {tool.Display}");
        if (string.IsNullOrWhiteSpace(port))
            return (false, "Chua chon cong COM.");
        if (images.Count == 0)
            return (false, "Chua chon file ROM.");

        foreach (var img in images)
        {
            if (!File.Exists(img.Path))
                return (false, $"Thieu file: {img.Path}");
        }

        var args = new StringBuilder();
        if (!string.IsNullOrWhiteSpace(tool.PrefixArgs))
            args.Append(tool.PrefixArgs).Append(' ');
        args.Append("--chip esp32c3 ");
        args.Append($"--port \"{port}\" ");
        args.Append($"--baud {baud} ");
        args.Append("--before default_reset --after hard_reset write_flash ");
        if (eraseFlash)
            args.Append("--erase-all ");
        args.Append("-z --flash_mode dio --flash_freq 80m --flash_size detect ");
        foreach (var img in images)
            args.Append($"{img.Offset} \"{img.Path}\" ");

        return await RunProcessAsync(tool.FileName, args.ToString().Trim(), tool.WorkingDirectory, ct);
    }

    public async Task<(bool Ok, string Message)> RunOtaAsync(
        string gatewayIp,
        string password,
        string binPath,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(gatewayIp))
            return (false, "Chua nhap IP gateway.");
        if (!File.Exists(binPath))
            return (false, $"Khong thay ROM: {binPath}");

        using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(3) };
        if (!string.IsNullOrEmpty(password))
        {
            var token = Convert.ToBase64String(Encoding.ASCII.GetBytes($"admin:{password}"));
            client.DefaultRequestHeaders.Authorization =
                new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", token);
        }

        try
        {
            LineReceived?.Invoke($"GET http://{gatewayIp}/api/info ...");
            try
            {
                var info = await client.GetStringAsync($"http://{gatewayIp}/api/info", ct);
                LineReceived?.Invoke(info);
            }
            catch (Exception ex)
            {
                LineReceived?.Invoke($"[canh bao] /api/info: {ex.Message}");
            }

            LineReceived?.Invoke($"POST http://{gatewayIp}/api/ota ({new FileInfo(binPath).Length} bytes)...");
            await using var fs = File.OpenRead(binPath);
            using var content = new StreamContent(fs);
            content.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/octet-stream");
            using var resp = await client.PostAsync($"http://{gatewayIp}/api/ota", content, ct);
            var body = await resp.Content.ReadAsStringAsync(ct);
            LineReceived?.Invoke($"HTTP {(int)resp.StatusCode} {resp.StatusCode}: {body}");
            if (!resp.IsSuccessStatusCode)
                return (false, $"OTA that bai: HTTP {(int)resp.StatusCode}");

            LineReceived?.Invoke("Cho gateway reboot (~40s)...");
            var deadline = DateTime.UtcNow.AddSeconds(45);
            while (DateTime.UtcNow < deadline)
            {
                ct.ThrowIfCancellationRequested();
                await Task.Delay(3000, ct);
                try
                {
                    var after = await client.GetStringAsync($"http://{gatewayIp}/api/info", ct);
                    LineReceived?.Invoke("Gateway da len lai:");
                    LineReceived?.Invoke(after);
                    return (true, "OTA thanh cong.");
                }
                catch
                {
                    LineReceived?.Invoke(".");
                }
            }

            return (false, "OTA da gui, nhung gateway chua len lai trong 45s.");
        }
        catch (OperationCanceledException)
        {
            return (false, "Da huy.");
        }
        catch (Exception ex)
        {
            return (false, $"OTA loi: {ex.Message}");
        }
    }

    private async Task<(bool Ok, string Message)> RunProcessAsync(
        string fileName,
        string args,
        string? workingDirectory,
        CancellationToken ct)
    {
        LineReceived?.Invoke($"> {fileName} {args}");

        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = args,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
        };
        if (!string.IsNullOrWhiteSpace(workingDirectory) && Directory.Exists(workingDirectory))
            psi.WorkingDirectory = workingDirectory;

        using var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
        var tcs = new TaskCompletionSource<int>();

        proc.OutputDataReceived += (_, e) =>
        {
            if (e.Data != null) LineReceived?.Invoke(e.Data);
        };
        proc.ErrorDataReceived += (_, e) =>
        {
            if (e.Data != null) LineReceived?.Invoke(e.Data);
        };
        proc.Exited += (_, _) => tcs.TrySetResult(proc.ExitCode);

        if (!proc.Start())
            return (false, "Khong khoi dong duoc esptool.");

        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();

        await using var reg = ct.Register(() =>
        {
            try
            {
                if (!proc.HasExited) proc.Kill(entireProcessTree: true);
            }
            catch { /* ignore */ }
        });

        var code = await tcs.Task;
        if (ct.IsCancellationRequested)
            return (false, "Da huy.");
        if (code != 0)
            return (false, $"esptool thoat ma {code}. Xem log phia tren.");
        return (true, "Nap USB thanh cong.");
    }
}
