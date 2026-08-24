using Microsoft.AspNetCore.SignalR.Client;

namespace SboxPrintAgent;

/// <summary>SignalR — cùng hub Flutter Agent (`/hubs/attendance`).</summary>
public sealed class PrintHubClient : IAsyncDisposable
{
    HubConnection? _hub;
    readonly Action<string> _log;

    public event Action? PrintJobNew;
    public event Action<string>? ForceStop; // deviceId
    public event Action? Reconnected;

    public bool IsConnected => _hub?.State == HubConnectionState.Connected;

    public PrintHubClient(Action<string> log) => _log = log;

    public async Task ConnectAsync(string apiBaseUrl, string accessToken, Guid storeId, CancellationToken ct)
    {
        await DisposeAsync();

        var hubUrl = apiBaseUrl.TrimEnd('/') + "/hubs/attendance";
        _hub = new HubConnectionBuilder()
            .WithUrl(hubUrl, opts =>
            {
                opts.AccessTokenProvider = () => Task.FromResult<string?>(accessToken);
            })
            .WithAutomaticReconnect()
            .Build();

        _hub.On("PrintJobNew", (object? _) =>
        {
            _log("SignalR: PrintJobNew");
            PrintJobNew?.Invoke();
        });

        _hub.On("PrinterAgentHeartbeat", (object? payload) =>
        {
            try
            {
                var json = System.Text.Json.JsonSerializer.Serialize(payload);
                using var doc = System.Text.Json.JsonDocument.Parse(json);
                var data = doc.RootElement;
                var force = data.TryGetProperty("forceStop", out var fs) &&
                            fs.ValueKind is System.Text.Json.JsonValueKind.True;
                var online = data.TryGetProperty("isOnline", out var on) &&
                             on.ValueKind is System.Text.Json.JsonValueKind.True;
                var deviceId = data.TryGetProperty("deviceId", out var d) ? d.GetString() : null;
                if (force && !online && !string.IsNullOrWhiteSpace(deviceId))
                    ForceStop?.Invoke(deviceId!);
            }
            catch { /* ignore parse */ }
        });

        _hub.Reconnected += async _ =>
        {
            _log("SignalR: reconnected — join lại print group");
            try { await _hub.InvokeAsync("JoinPrintAgentGroup", storeId.ToString(), CancellationToken.None); }
            catch (Exception ex) { _log("Join lại lỗi: " + ex.Message); }
            Reconnected?.Invoke();
        };

        await _hub.StartAsync(ct);
        await _hub.InvokeAsync("JoinPrintAgentGroup", storeId.ToString(), ct);
        _log("SignalR: đã join print agent group");
    }

    public async Task LeaveAsync(Guid storeId)
    {
        if (_hub == null) return;
        try
        {
            if (_hub.State == HubConnectionState.Connected)
                await _hub.InvokeAsync("LeavePrintAgentGroup", storeId.ToString());
        }
        catch { /* ignore */ }
    }

    public async ValueTask DisposeAsync()
    {
        if (_hub == null) return;
        try { await _hub.StopAsync(); } catch { /* ignore */ }
        try { await _hub.DisposeAsync(); } catch { /* ignore */ }
        _hub = null;
    }
}
