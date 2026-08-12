namespace SboxPrintAgent;

/// <summary>
/// Print Agent Windows — parity Flutter: heartbeat 12s, claim 3s, SignalR nudge, health.
/// </summary>
public sealed class AgentService : IAsyncDisposable
{
    public const string AppVersion = "win-1.3.4";

    readonly SboxApiClient _api;
    readonly AppSettings _settings;
    readonly Action<string> _log;
    readonly PrintHubClient _hub;
    readonly Dictionary<Guid, PrinterItem> _printers = new();
    readonly HashSet<Guid> _settled = new();
    readonly object _gate = new();

    CancellationTokenSource? _cts;
    Task? _claimLoop;
    Task? _heartbeatLoop;
    Guid _agentId;
    string _deviceId = "";
    List<Guid> _assigned = new();
    bool _claimInFlight;

    public bool IsRunning { get; private set; }
    public Guid AgentId => _agentId;
    public string DeviceId => _deviceId;
    public bool HubConnected => _hub.IsConnected;

    public event Action? StateChanged;
    public event Action? ForceStoppedRemotely;

    public AgentService(SboxApiClient api, AppSettings settings, Action<string> log)
    {
        _api = api;
        _settings = settings;
        _log = log;
        _hub = new PrintHubClient(log);
        _hub.PrintJobNew += OnPrintJobNew;
        _hub.ForceStop += OnForceStop;
        foreach (var id in settings.SettledJobIds)
            if (Guid.TryParse(id, out var g)) _settled.Add(g);
    }

    public void SetPrinterCache(IEnumerable<PrinterItem> printers)
    {
        lock (_gate)
        {
            _printers.Clear();
            foreach (var p in printers) _printers[p.Id] = p;
        }
    }

    public async Task StartAsync(IEnumerable<Guid> assignedPrinterIds, CancellationToken ct = default)
    {
        if (_api.StoreId == null || string.IsNullOrWhiteSpace(_api.AccessToken))
            throw new InvalidOperationException("Chưa đăng nhập");

        var assigned = assignedPrinterIds.Distinct().ToList();
        if (assigned.Count == 0)
            throw new InvalidOperationException("Chọn ít nhất 1 máy in để Agent phục vụ");

        await StopAsync(markOffline: false);

        _deviceId = _settings.EnsureDeviceId();
        _assigned = assigned;
        _settings.AssignedPrinterIds = assigned.Select(x => x.ToString()).ToList();
        _settings.AutoStartAgent = true;
        _settings.Save();

        IsRunning = true;
        _cts = new CancellationTokenSource();
        var token = _cts.Token;

        try
        {
            await _hub.ConnectAsync(_api.BaseUrl, _api.AccessToken!, _api.StoreId.Value, token);
        }
        catch (Exception ex)
        {
            _log("SignalR không kết nối (vẫn poll claim): " + ex.Message);
        }

        await RegisterAsync(refreshPrinters: true, token);
        _claimLoop = Task.Run(() => ClaimLoopAsync(token), token);
        _heartbeatLoop = Task.Run(() => HeartbeatLoopAsync(token), token);
        StateChanged?.Invoke();
        _log($"Agent online · device={_deviceId} · printers={_assigned.Count}");
    }

    public async Task StopAsync(bool markOffline = true)
    {
        var was = IsRunning;
        IsRunning = false;
        try { _cts?.Cancel(); } catch { /* ignore */ }

        if (_api.StoreId != null)
            await _hub.LeaveAsync(_api.StoreId.Value);
        await _hub.DisposeAsync();

        if (markOffline && was && !string.IsNullOrWhiteSpace(_deviceId))
            await _api.MarkOfflineAsync(_deviceId, CancellationToken.None);

        _cts = null;
        _claimLoop = null;
        _heartbeatLoop = null;
        _agentId = Guid.Empty;
        StateChanged?.Invoke();
        if (was) _log("Agent đã dừng");
    }

    async Task HeartbeatLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && IsRunning)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(12), ct);
                if (!IsRunning) break;
                await RegisterAsync(refreshPrinters: false, ct);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { break; }
            catch (Exception ex) { _log("Heartbeat lỗi: " + ex.Message); }
        }
    }

    async Task ClaimLoopAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && IsRunning)
        {
            try
            {
                await TryClaimOnceAsync();
                await Task.Delay(3000, ct);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { break; }
            catch (Exception ex)
            {
                _log("Claim loop: " + ex.Message);
                await Task.Delay(3000, ct);
            }
        }
    }

    async Task RegisterAsync(bool refreshPrinters, CancellationToken ct)
    {
        if (!IsRunning || _api.StoreId == null) return;

        if (refreshPrinters || _printers.Count == 0)
        {
            try
            {
                var list = await _api.ListPrintersAsync(ct);
                SetPrinterCache(list);
                // drop deleted assigned
                var alive = list.Select(p => p.Id).ToHashSet();
                _assigned = _assigned.Where(alive.Contains).ToList();
                _settings.AssignedPrinterIds = _assigned.Select(x => x.ToString()).ToList();
                _settings.Save();
            }
            catch (Exception ex)
            {
                _log("Refresh printers: " + ex.Message);
            }
        }

        if (_assigned.Count == 0)
            throw new InvalidOperationException("Không còn máy in được gán");

        var (agentId, _) = await _api.RegisterAgentAsync(
            _deviceId,
            $"Win/{Environment.MachineName}",
            _api.DisplayName ?? "SboxPrintAgent-Win",
            _assigned,
            AppVersion,
            ct);

        _agentId = agentId;
        _settings.AgentId = agentId;
        _settings.Save();
        StateChanged?.Invoke();
    }

    DateTime _lastNudgeUtc = DateTime.MinValue;

    void OnPrintJobNew()
    {
        // SignalR đôi khi bắn trùng 2 lần trong cùng tick → tránh claim/in song song.
        var now = DateTime.UtcNow;
        if ((now - _lastNudgeUtc).TotalMilliseconds < 800) return;
        _lastNudgeUtc = now;
        _ = TryClaimOnceAsync();
    }

    async Task TryClaimOnceAsync()
    {
        if (!IsRunning || _agentId == Guid.Empty) return;
        lock (_gate)
        {
            if (_claimInFlight) return;
            _claimInFlight = true;
        }
        try
        {
            var job = await _api.ClaimAsync(_agentId, CancellationToken.None);
            if (job == null) return;
            await ProcessJobAsync(job, CancellationToken.None);
        }
        catch (Exception ex)
        {
            _log("Claim: " + ex.Message);
        }
        finally
        {
            lock (_gate) _claimInFlight = false;
        }
    }

    async Task ProcessJobAsync(ClaimJob job, CancellationToken ct)
    {
        // Chống treo vô hạn (TCP/HTTP) — quá 25s thì Fail để job không thành STUCK_NO_REQUEUE.
        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeoutCts.CancelAfter(TimeSpan.FromSeconds(25));
        try
        {
            await ProcessJobCoreAsync(job, timeoutCts.Token);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            _log($"✗ Timeout 25s khi in job {Short(job.JobId)}");
            await FailSafe(job.JobId, "PRINT_TIMEOUT",
                "In quá 25 giây (máy in/mạng không phản hồi).", CancellationToken.None);
        }
    }

    async Task ProcessJobCoreAsync(ClaimJob job, CancellationToken ct)
    {
        if (_settled.Contains(job.JobId))
        {
            try { await _api.CompleteAsync(job.JobId, _agentId, ct); } catch { /* ignore */ }
            return;
        }

        if (!_assigned.Contains(job.PrinterId))
        {
            await FailSafe(job.JobId, "PRINTER_MISMATCH", "Agent không phục vụ máy in này", ct);
            return;
        }

        _log($"Nhận lệnh in {Short(job.JobId)} · {DocTypes.LabelOf(job.DocumentType)}");

        PrinterItem? printer;
        lock (_gate) _printers.TryGetValue(job.PrinterId, out printer);

        if (printer == null || !ConnLabel.CanPrintOnWindows(printer))
        {
            try
            {
                printer = await _api.GetPrinterAsync(job.PrinterId, ct);
                lock (_gate) _printers[printer.Id] = printer;
            }
            catch (Exception ex) { _log("GetPrinter: " + ex.Message); }
        }

        if (printer == null || !ConnLabel.CanPrintOnWindows(printer))
        {
            await FailSafe(job.JobId, "NO_PRINTER",
                "Máy in chưa cấu hình mạng/USB trên máy Windows này.", ct);
            return;
        }

        try
        {
            try { await _api.MarkPrintingAsync(job.JobId, _agentId, ct); }
            catch (Exception ex) { _log("MarkPrinting: " + ex.Message); }

            var bytes = EscPosBuilder.BuildFromJob(job);
            if (bytes.Length == 0)
                throw new InvalidOperationException("Payload in rỗng / không đọc được");

            _log($"Gửi {bytes.Length} byte → {printer.Name} ({(ConnLabel.IsUsb(printer) ? printer.UsbDeviceName : printer.LanHost + ":" + printer.LanPort)})");

            var copies = Math.Clamp(job.Copies, 1, 10);
            for (var i = 0; i < copies; i++)
            {
                await SendToPrinterAsync(printer, bytes, ct);
                if (i + 1 < copies) await Task.Delay(200, ct);
            }

            Exception? completeEx = null;
            for (var attempt = 0; attempt < 3; attempt++)
            {
                try
                {
                    await _api.CompleteAsync(job.JobId, _agentId, ct);
                    completeEx = null;
                    break;
                }
                catch (Exception ex)
                {
                    completeEx = ex;
                    _log($"Complete lần {attempt + 1} lỗi: {ex.Message}");
                    await Task.Delay(500 * (attempt + 1), ct);
                }
            }
            if (completeEx != null) throw completeEx;

            await _api.ReportHealthAsync(printer.Id, "Online", null, ct);
            MarkSettled(job.JobId);
            _log($"✓ Đã in xong → {printer.Name}");
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex)
        {
            _log($"✗ Lỗi in: {ex.Message}");
            await _api.ReportHealthAsync(printer.Id, "Offline", ex.Message, CancellationToken.None);
            await FailSafe(job.JobId, "PRINT_FAILED", ex.Message, CancellationToken.None);
        }
    }

    static async Task SendToPrinterAsync(PrinterItem printer, byte[] bytes, CancellationToken ct)
    {
        if (ConnLabel.IsUsb(printer))
        {
            // Gửi theo tên queue Windows (ResolvePrinterName chống lệch khi USB đổi cổng).
            await Task.Run(() => WindowsSpooler.SendRaw(printer.UsbDeviceName!, bytes), ct);
            return;
        }

        var host = printer.LanHost!;
        var port = printer.LanPort > 0 ? printer.LanPort : 9100;
        await LanScanner.SendRawAsync(host, port, bytes, ct);
    }

    async Task FailSafe(Guid jobId, string code, string msg, CancellationToken ct)
    {
        try { await _api.FailAsync(jobId, _agentId, code, msg, ct); }
        catch { /* ignore */ }
        MarkSettled(jobId);
    }

    void MarkSettled(Guid jobId)
    {
        _settled.Add(jobId);
        if (_settled.Count > 120)
        {
            foreach (var id in _settled.Take(_settled.Count - 80).ToList())
                _settled.Remove(id);
        }
        _settings.SettledJobIds = _settled.Select(x => x.ToString("D")).Take(100).ToList();
        _settings.Save();
    }

    void OnForceStop(string deviceId)
    {
        if (!string.Equals(deviceId, _deviceId, StringComparison.OrdinalIgnoreCase)) return;
        _log("Agent bị tắt từ máy khác (forceStop)");
        _ = StopAsync(markOffline: false);
        _settings.AutoStartAgent = false;
        _settings.Save();
        ForceStoppedRemotely?.Invoke();
    }

    static string Short(Guid id) => id.ToString("N")[..8];

    public async ValueTask DisposeAsync() => await StopAsync(markOffline: true);
}
