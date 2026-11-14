namespace SboxPrintAgent;

/// <summary>
/// Print Agent Windows — parity Flutter: heartbeat 12s (debounce 8s),
/// claim 3s, SignalR nudge, release khi không in được, timeout 75s, re-login 401.
/// </summary>
public sealed class AgentService : IAsyncDisposable
{
    public const string AppVersion = "win-1.4.6";

    readonly SboxApiClient _api;
    readonly AppSettings _settings;
    readonly Action<string> _log;
    readonly PrintHubClient _hub;
    readonly Dictionary<Guid, PrinterItem> _printers = new();
    readonly HashSet<Guid> _settled = new();
    /// <summary>Mốc lần gửi in (dispatchKey) của lần Agent đã xử lý xong từng lệnh.</summary>
    readonly Dictionary<Guid, string> _settledDispatch = new();
    /// <summary>Lệnh Agent đã báo lỗi khi CHƯA gửi được ra máy in — «In lại» phải in thật.</summary>
    readonly HashSet<Guid> _notPrinted = new();
    readonly object _gate = new();

    CancellationTokenSource? _cts;
    Task? _claimLoop;
    Task? _heartbeatLoop;
    Guid _agentId;
    string _deviceId = "";
    List<Guid> _assigned = new();
    bool _claimInFlight;
    DateTime _lastRegisterUtc = DateTime.MinValue;
    DateTime _lastAuthRetryUtc = DateTime.MinValue;
    Func<CancellationToken, Task>? _relogin;

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
        _hub.Reconnected += OnHubReconnected;
        foreach (var raw in settings.SettledJobIds)
        {
            // «mã lệnh» hoặc «mã lệnh|mốc lần gửi in».
            var cut = raw.IndexOf('|');
            if (!Guid.TryParse(cut > 0 ? raw[..cut] : raw, out var g)) continue;
            _settled.Add(g);
            if (cut > 0 && cut + 1 < raw.Length) _settledDispatch[g] = raw[(cut + 1)..];
        }
    }

    /// <summary>Cho phép tự đăng nhập lại khi token hết hạn (401).</summary>
    public void SetReloginHandler(Func<CancellationToken, Task>? handler) => _relogin = handler;

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
            _log("SignalR không kết nối (vẫn poll claim): " + SboxApiClient.FormatError(ex));
        }

        await RegisterAsync(refreshPrinters: true, force: true, token);
        _claimLoop = Task.Run(() => ClaimLoopAsync(token), token);
        _heartbeatLoop = Task.Run(() => HeartbeatLoopAsync(token), token);
        StateChanged?.Invoke();
        _log($"Agent online · {AppVersion} · device={_deviceId} · printers={_assigned.Count}");
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
                await RegisterAsync(refreshPrinters: false, force: false, ct);
            }
            catch (OperationCanceledException) when (ct.IsCancellationRequested) { break; }
            catch (Exception ex)
            {
                _log("Heartbeat lỗi: " + SboxApiClient.FormatError(ex));
                await TryReloginIfNeededAsync(ex, ct);
            }
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
                _log("Claim loop: " + SboxApiClient.FormatError(ex));
                await TryReloginIfNeededAsync(ex, ct);
                await Task.Delay(3000, ct);
            }
        }
    }

    async Task RegisterAsync(bool refreshPrinters, bool force, CancellationToken ct)
    {
        if (!IsRunning || _api.StoreId == null) return;

        // Debounce giống Flutter — tránh spam register làm API/heartbeat loạn.
        var now = DateTime.UtcNow;
        if (!force && !refreshPrinters && (now - _lastRegisterUtc).TotalSeconds < 8)
            return;

        if (refreshPrinters || _printers.Count == 0)
        {
            try
            {
                var list = await _api.ListPrintersAsync(ct);
                SetPrinterCache(list);
                var alive = list.Select(p => p.Id).ToHashSet();
                _assigned = _assigned.Where(alive.Contains).ToList();
                _settings.AssignedPrinterIds = _assigned.Select(x => x.ToString()).ToList();
                _settings.Save();
            }
            catch (Exception ex)
            {
                _log("Refresh printers: " + SboxApiClient.FormatError(ex));
                await TryReloginIfNeededAsync(ex, ct);
                if (_assigned.Count == 0) return;
            }
        }

        if (_assigned.Count == 0)
        {
            _log("Không còn máy in được gán — dừng Agent.");
            _ = StopAsync(markOffline: true);
            return;
        }

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
        _lastRegisterUtc = DateTime.UtcNow;
        StateChanged?.Invoke();
    }

    DateTime _lastNudgeUtc = DateTime.MinValue;

    void OnPrintJobNew()
    {
        var now = DateTime.UtcNow;
        if ((now - _lastNudgeUtc).TotalMilliseconds < 800) return;
        _lastNudgeUtc = now;
        _ = TryClaimOnceAsync();
    }

    void OnHubReconnected()
    {
        _ = Task.Run(async () =>
        {
            try
            {
                if (!IsRunning) return;
                await RegisterAsync(refreshPrinters: false, force: true, CancellationToken.None);
                await TryClaimOnceAsync();
            }
            catch (Exception ex)
            {
                _log("Sau reconnect: " + SboxApiClient.FormatError(ex));
            }
        });
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
            _log("Claim: " + SboxApiClient.FormatError(ex));
            await TryReloginIfNeededAsync(ex, CancellationToken.None);
        }
        finally
        {
            lock (_gate) _claimInFlight = false;
        }
    }

    async Task TryReloginIfNeededAsync(Exception ex, CancellationToken ct)
    {
        var auth = ex is ApiException { IsAuth: true } ||
                   SboxApiClient.FormatError(ex).Contains("401", StringComparison.Ordinal) ||
                   SboxApiClient.FormatError(ex).Contains("Unauthorized", StringComparison.OrdinalIgnoreCase);
        if (!auth || _relogin == null || !IsRunning) return;

        var now = DateTime.UtcNow;
        if ((now - _lastAuthRetryUtc).TotalSeconds < 20) return;
        _lastAuthRetryUtc = now;

        try
        {
            _log("Token hết hạn / 401 — đang đăng nhập lại…");
            await _relogin(ct);
            if (_api.StoreId != null && !string.IsNullOrWhiteSpace(_api.AccessToken))
            {
                try
                {
                    await _hub.ConnectAsync(_api.BaseUrl, _api.AccessToken!, _api.StoreId.Value, ct);
                }
                catch (Exception hubEx)
                {
                    _log("SignalR sau re-login: " + SboxApiClient.FormatError(hubEx));
                }
                await RegisterAsync(refreshPrinters: true, force: true, ct);
                _log("Đã đăng nhập lại và đăng ký Agent.");
            }
        }
        catch (Exception relogEx)
        {
            _log("Re-login thất bại: " + SboxApiClient.FormatError(relogEx));
        }
    }

    async Task ProcessJobAsync(ClaimJob job, CancellationToken ct)
    {
        // Parity Flutter 75s — tem/USB/LAN chậm không nên Fail sớm.
        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeoutCts.CancelAfter(TimeSpan.FromSeconds(75));
        try
        {
            await ProcessJobCoreAsync(job, timeoutCts.Token);
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            _log($"✗ Timeout 75s khi in job {Short(job.JobId)}");
            await FailSafe(job.JobId, "PRINT_TIMEOUT",
                "In quá 75 giây (máy in/mạng không phản hồi).", CancellationToken.None, job.DispatchKey);
        }
    }

    /// <summary>
    /// Lệnh đã xử lý quay lại do người dùng bấm «In lại» (không phải máy chủ giao lại lệnh kẹt):
    /// lần trước chưa ra giấy, hoặc mốc lần gửi in đã đổi.
    /// </summary>
    bool IsUserReprint(ClaimJob job) =>
        _notPrinted.Contains(job.JobId)
        || (!string.IsNullOrEmpty(job.DispatchKey)
            && _settledDispatch.TryGetValue(job.JobId, out var done)
            && done != job.DispatchKey);

    async Task ProcessJobCoreAsync(ClaimJob job, CancellationToken ct)
    {
        // Giữ mốc lần gửi in: bản nạp lại payload (EnsurePayloadAsync) không có trường này.
        var dispatchKey = job.DispatchKey;
        if (_settled.Contains(job.JobId))
        {
            if (!IsUserReprint(job))
            {
                try { await _api.CompleteAsync(job.JobId, _agentId, ct); } catch { /* ignore */ }
                return;
            }
            // «In lại» dùng lại đúng mã lệnh cũ. Trước đây Agent thấy mã đã xử lý nên chỉ báo «in xong»
            // mà không in — máy bếp hết giấy, thay giấy rồi bấm «In lại» vẫn không ra phiếu.
            _settled.Remove(job.JobId);
            _settledDispatch.Remove(job.JobId);
            _notPrinted.Remove(job.JobId);
        }

        if (!_assigned.Contains(job.PrinterId))
        {
            // Nhả cho Agent khác (A6/Flutter) — đừng Fail cứng.
            await ReleaseSafe(job.JobId, "PRINTER_MISMATCH",
                "Agent Windows không phục vụ máy in này — nhả cho Agent khác", ct);
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
            catch (Exception ex) { _log("GetPrinter: " + SboxApiClient.FormatError(ex)); }
        }

        if (printer == null || !ConnLabel.CanPrintOnWindows(printer))
        {
            await ReleaseSafe(job.JobId, "NOT_LOCAL_PORT",
                "Máy Windows này không kết nối được cổng in — nhả cho Agent khác", ct);
            return;
        }

        var sent = false;
        try
        {
            job = await EnsurePayloadAsync(job, ct);

            // Chỉ in khi máy chủ xác nhận «đang in». Không xác nhận được mà vẫn in thì máy chủ còn coi lệnh là
            // «chưa in» → giao Agent khác hoặc báo «chưa in» → ra hai phiếu. Thử lại một lần rồi nhả lệnh.
            var marked = false;
            for (var attempt = 0; attempt < 2 && !marked; attempt++)
            {
                try
                {
                    if (attempt > 0) await Task.Delay(600, ct);
                    await _api.MarkPrintingAsync(job.JobId, _agentId, ct);
                    marked = true;
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex) { _log("MarkPrinting: " + SboxApiClient.FormatError(ex)); }
            }
            if (!marked)
            {
                await ReleaseSafe(job.JobId, "MARK_PRINTING_FAILED",
                    "Agent không xác nhận được bắt đầu in — xếp lại hàng đợi", ct);
                return;
            }

            if (string.Equals(job.PayloadFormat, "PdfBase64", StringComparison.OrdinalIgnoreCase))
            {
                // Chứng từ A4/A5: in qua driver Windows (máy in văn phòng), không gửi RAW.
                if (!ConnLabel.IsUsb(printer))
                    throw new InvalidOperationException(
                        "Chứng từ A4/A5 cần máy in đã cài trên Windows — máy in mạng hãy cài driver rồi chọn máy in Windows.");
                var pdf = Convert.FromBase64String((job.Payload ?? "").Trim());
                _log($"In PDF {pdf.Length / 1024} KB → {printer.Name} ({printer.UsbDeviceName})");
                await PdfPagePrinter.PrintAsync(
                    printer.UsbDeviceName!, pdf, job.Copies,
                    "SBOX " + DocTypes.LabelOf(job.DocumentType), ct: ct);
                sent = true;
                await CompleteJobAsync(job, printer, ct, dispatchKey);
                return;
            }

            if (WindowsSpooler.IsPagePaper(printer.PaperSize))
                throw new InvalidOperationException(
                    $"Máy in {printer.PaperSize} «{printer.Name}» chỉ in chứng từ khổ trang — phiếu nhiệt hãy gán cho máy in nhiệt.");

            var bytes = EscPosBuilder.BuildFromJob(job, printer);
            if (bytes.Length == 0)
                throw new InvalidOperationException("Payload in rỗng / không đọc được");

            _log($"Gửi {bytes.Length} byte → {printer.Name} ({(ConnLabel.IsUsb(printer) ? printer.UsbDeviceName : printer.LanHost + ":" + printer.LanPort)})");

            var copies = Math.Clamp(job.Copies, 1, 10);
            for (var i = 0; i < copies; i++)
            {
                await SendToPrinterAsync(printer, bytes, ct);
                if (i + 1 < copies) await Task.Delay(200, ct);
            }

            sent = true;
            await CompleteJobAsync(job, printer, ct, dispatchKey);
        }
        catch (OperationCanceledException) { throw; }
        catch (Exception ex) when (sent)
        {
            // Giấy đã ra, chỉ không báo được «in xong» lên máy chủ. Trước đây báo PRINT_FAILED + máy in
            // Offline cho phiếu đã in: máy bán báo lại bếp, bếp làm hai lần. Ghi nhận đã in, báo lại ở nền.
            _log($"Đã in nhưng chưa báo được «in xong»: {SboxApiClient.FormatError(ex)} — sẽ báo lại");
            MarkSettled(job.JobId, dispatchKey);
            _ = ReportCompleteLaterAsync(job.JobId);
        }
        catch (Exception ex)
        {
            _log($"✗ Lỗi in: {SboxApiClient.FormatError(ex)}");
            await _api.ReportHealthAsync(printer.Id, "Offline", SboxApiClient.FormatError(ex), CancellationToken.None);
            await FailSafe(job.JobId, "PRINT_FAILED", SboxApiClient.FormatError(ex), CancellationToken.None,
                dispatchKey, printed: false);
        }
    }

    /// <summary>Báo lại «in xong» cho phiếu đã ra giấy (máy chủ nhận cả khi báo muộn).</summary>
    async Task ReportCompleteLaterAsync(Guid jobId)
    {
        for (var i = 1; i <= 6; i++)
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(10 * i));
                await _api.CompleteAsync(jobId, _agentId, CancellationToken.None);
                return;
            }
            catch { /* thử lại */ }
        }
    }

    async Task CompleteJobAsync(ClaimJob job, PrinterItem printer, CancellationToken ct, string? dispatchKey)
    {
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
                _log($"Complete lần {attempt + 1} lỗi: {SboxApiClient.FormatError(ex)}");
                await Task.Delay(500 * (attempt + 1), ct);
            }
        }
        if (completeEx != null) throw completeEx;

        await _api.ReportHealthAsync(printer.Id, "Online", null, ct);
        MarkSettled(job.JobId, dispatchKey);
        _log($"✓ Đã in xong → {printer.Name}");
    }

    async Task<ClaimJob> EnsurePayloadAsync(ClaimJob job, CancellationToken ct)
    {
        var payload = job.Payload ?? "";
        if (payload.Trim().Length >= 32) return job;
        try
        {
            var full = await _api.GetJobAsync(job.JobId, ct);
            if (full != null && !string.IsNullOrWhiteSpace(full.Payload) && full.Payload.Trim().Length > payload.Trim().Length)
            {
                _log($"Nạp lại payload job {Short(job.JobId)} ({full.Payload!.Length} ký tự)");
                return full;
            }
        }
        catch (Exception ex)
        {
            _log("Refill payload: " + SboxApiClient.FormatError(ex));
        }
        return job;
    }

    static async Task SendToPrinterAsync(PrinterItem printer, byte[] bytes, CancellationToken ct)
    {
        if (ConnLabel.IsUsb(printer))
        {
            await Task.Run(() => WindowsSpooler.SendRaw(printer.UsbDeviceName!, bytes), ct);
            return;
        }

        var host = printer.LanHost!;
        var port = printer.LanPort > 0 ? printer.LanPort : 9100;
        await LanScanner.SendRawAsync(host, port, bytes, ct);
    }

    /// <param name="printed">false = chắc chắn chưa gửi được ra máy in; mặc định coi như có thể đã in.</param>
    async Task FailSafe(Guid jobId, string code, string msg, CancellationToken ct,
        string? dispatchKey = null, bool printed = true)
    {
        try { await _api.FailAsync(jobId, _agentId, code, msg, ct); }
        catch { /* ignore */ }
        MarkSettled(jobId, dispatchKey, printed);
    }

    async Task ReleaseSafe(Guid jobId, string code, string msg, CancellationToken ct)
    {
        try
        {
            await _api.ReleaseAsync(jobId, _agentId, code, msg, ct);
            _log($"Nhả job {Short(jobId)} ({code})");
        }
        catch (Exception ex)
        {
            _log("Release lỗi → fail: " + SboxApiClient.FormatError(ex));
            await FailSafe(jobId, code, msg, ct, printed: false);
            return;
        }
        // Không MarkSettled — job có thể quay lại Agent này sau khi reclaim.
    }

    void MarkSettled(Guid jobId, string? dispatchKey = null, bool printed = true)
    {
        _settled.Add(jobId);
        if (printed) _notPrinted.Remove(jobId);
        else _notPrinted.Add(jobId);
        if (!string.IsNullOrEmpty(dispatchKey)) _settledDispatch[jobId] = dispatchKey;
        if (_settled.Count > 120)
        {
            foreach (var id in _settled.Take(_settled.Count - 80).ToList())
            {
                _settled.Remove(id);
                _settledDispatch.Remove(id);
                _notPrinted.Remove(id);
            }
        }
        // Lệnh chưa ra giấy không lưu xuống đĩa: mở lại Agent rồi «In lại» vẫn phải in thật.
        _settings.SettledJobIds = _settled
            .Where(x => !_notPrinted.Contains(x))
            .Select(x => _settledDispatch.TryGetValue(x, out var k) ? $"{x:D}|{k}" : x.ToString("D"))
            .Take(100).ToList();
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
