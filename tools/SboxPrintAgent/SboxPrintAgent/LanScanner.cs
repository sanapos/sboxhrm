using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace SboxPrintAgent;

public static class LanScanner
{
    public sealed record Hit(string Host, int Port, int LatencyMs);

    public static async Task<List<Hit>> ScanAsync(
        string? subnetPrefix,
        int port = 9100,
        int timeoutMs = 350,
        IProgress<string>? log = null,
        CancellationToken ct = default)
    {
        var prefix = string.IsNullOrWhiteSpace(subnetPrefix)
            ? GuessLocalSubnetPrefix()
            : subnetPrefix.Trim().TrimEnd('.');

        if (string.IsNullOrWhiteSpace(prefix))
            throw new InvalidOperationException("Không xác định được subnet LAN. Nhập tay dạng 192.168.1");

        log?.Report($"Quét {prefix}.1–254 :{port} …");

        var hits = new System.Collections.Concurrent.ConcurrentBag<Hit>();
        await Parallel.ForEachAsync(
            Enumerable.Range(1, 254),
            new ParallelOptions { MaxDegreeOfParallelism = 64, CancellationToken = ct },
            async (i, token) =>
            {
                var host = $"{prefix}.{i}";
                var sw = System.Diagnostics.Stopwatch.StartNew();
                try
                {
                    using var client = new TcpClient();
                    var connect = client.ConnectAsync(host, port);
                    var done = await Task.WhenAny(connect, Task.Delay(timeoutMs, token));
                    if (done != connect || !client.Connected) return;
                    sw.Stop();
                    hits.Add(new Hit(host, port, (int)sw.ElapsedMilliseconds));
                    log?.Report($"✓ {host}:{port} ({sw.ElapsedMilliseconds}ms)");
                }
                catch
                {
                    // closed / timeout
                }
            });

        return hits.OrderBy(h => h.Host).ToList();
    }

    public static async Task SendTestAsync(string host, int port, string title, CancellationToken ct = default)
        => await SendRawAsync(host, port, EscPosBuilder.TestSlip(title), ct);

    public static async Task SendRawAsync(string host, int port, byte[] data, CancellationToken ct = default)
    {
        using var client = new TcpClient();
        using var connectCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        connectCts.CancelAfter(TimeSpan.FromSeconds(5));
        try
        {
            await client.ConnectAsync(host, port, connectCts.Token);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            throw new TimeoutException($"Máy in {host}:{port} không phản hồi trong 5 giây (TCP).");
        }

        await using var stream = client.GetStream();
        stream.WriteTimeout = 8000;
        stream.ReadTimeout = 3000;
        using var writeCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        writeCts.CancelAfter(TimeSpan.FromSeconds(8));
        try
        {
            await stream.WriteAsync(data, writeCts.Token);
            await stream.FlushAsync(writeCts.Token);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            throw new TimeoutException($"Gửi dữ liệu tới {host}:{port} quá 8 giây.");
        }
    }

    static string? GuessLocalSubnetPrefix()
    {
        foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (ni.OperationalStatus != OperationalStatus.Up) continue;
            if (ni.NetworkInterfaceType is NetworkInterfaceType.Loopback) continue;
            foreach (var ua in ni.GetIPProperties().UnicastAddresses)
            {
                if (ua.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                var ip = ua.Address.ToString();
                if (ip.StartsWith("127.")) continue;
                var parts = ip.Split('.');
                if (parts.Length == 4)
                    return $"{parts[0]}.{parts[1]}.{parts[2]}";
            }
        }
        foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
        {
            var gw = ni.GetIPProperties().GatewayAddresses
                .FirstOrDefault(g => g.Address.AddressFamily == AddressFamily.InterNetwork);
            if (gw == null) continue;
            var parts = gw.Address.ToString().Split('.');
            if (parts.Length == 4)
                return $"{parts[0]}.{parts[1]}.{parts[2]}";
        }
        return null;
    }
}
