using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace SboxPrintAgent;

public sealed class SboxApiClient
{
    readonly HttpClient _http;
    readonly JsonSerializerOptions _json = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public SboxApiClient(string baseUrl)
    {
        BaseUrl = baseUrl.TrimEnd('/');
        _http = new HttpClient
        {
            BaseAddress = new Uri(BaseUrl + "/"),
            Timeout = TimeSpan.FromSeconds(30),
        };
        _http.DefaultRequestHeaders.Accept.Add(
            new MediaTypeWithQualityHeaderValue("application/json"));
    }

    public string BaseUrl { get; }
    public string? AccessToken { get; private set; }
    public Guid? StoreId { get; private set; }
    public string? DisplayName { get; private set; }

    public void SetToken(string token, Guid? storeId = null)
    {
        AccessToken = token;
        StoreId = storeId ?? JwtStoreId.TryParse(token);
        _http.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", token);
    }

    public async Task LoginAsync(string storeCode, string userName, string password, CancellationToken ct)
    {
        var res = await _http.PostAsJsonAsync("api/Auth/Login", new
        {
            storeCode,
            userName,
            password,
        }, _json, ct);
        var body = await res.Content.ReadAsStringAsync(ct);
        using var doc = JsonDocument.Parse(body);
        var root = doc.RootElement;
        if (!root.TryGetProperty("isSuccess", out var ok) || !ok.GetBoolean())
        {
            var msg = root.TryGetProperty("message", out var m) ? m.GetString() : body;
            throw new InvalidOperationException(msg ?? "Đăng nhập thất bại");
        }
        var data = root.GetProperty("data");
        var token = data.GetProperty("accessToken").GetString()
            ?? throw new InvalidOperationException("Thiếu accessToken");
        DisplayName = data.TryGetProperty("userName", out var un) ? un.GetString()
            : data.TryGetProperty("email", out var em) ? em.GetString() : userName;
        SetToken(token);
    }

    public async Task<List<PrinterItem>> ListPrintersAsync(CancellationToken ct)
    {
        using var doc = await GetDataAsync("api/pos/printers", ct);
        var list = new List<PrinterItem>();
        if (doc.RootElement.ValueKind != JsonValueKind.Array) return list;
        foreach (var e in doc.RootElement.EnumerateArray())
            list.Add(ParsePrinter(e));
        return list;
    }

    public async Task<PrinterItem> GetPrinterAsync(Guid id, CancellationToken ct)
    {
        using var doc = await GetDataAsync($"api/pos/printers/{id}", ct);
        return ParsePrinter(doc.RootElement);
    }

    public async Task<Guid> CreateLanPrinterAsync(
        string name, string host, int port, string paperSize, bool isDefault, CancellationToken ct)
    {
        var payload = BuildPrinterSave(name, host, port, paperSize, isDefault, sortOrder: 0, isActive: true);
        using var doc = await PostDataAsync("api/pos/printers", payload, ct);
        return Guid.Parse(doc.RootElement.GetProperty("id").GetString()!);
    }

    public async Task UpdateLanPrinterAsync(
        Guid id, string name, string host, int port, string paperSize,
        bool isDefault, bool isActive, int sortOrder, CancellationToken ct)
    {
        var payload = BuildPrinterSave(name, host, port, paperSize, isDefault, sortOrder, isActive);
        await PutOkAsync($"api/pos/printers/{id}", payload, ct);
    }

    public async Task<Guid> CreateUsbPrinterAsync(
        string name, string windowsPrinterName, string paperSize, bool isDefault, CancellationToken ct)
    {
        var payload = new
        {
            name,
            connectionType = 3, // Usb
            // Xprinter + auto → app in ảnh (tiếng Việt). Utf8 làm XP-80C lỗi font.
            printerBrand = "xprinter",
            paperSize,
            textMode = "auto",
            lanHost = (string?)null,
            lanPort = 9100,
            usbDeviceName = windowsPrinterName,
            feedBeforeCut = paperSize.StartsWith("Label", StringComparison.OrdinalIgnoreCase) ? 2 : 3,
            partialCut = true,
            openCashDrawer = false,
            openDrawerCashOnly = true,
            beepOnPrint = false,
            isDefault,
            sortOrder = 0,
            isActive = true,
        };
        using var doc = await PostDataAsync("api/pos/printers", payload, ct);
        return Guid.Parse(doc.RootElement.GetProperty("id").GetString()!);
    }

    public async Task UpdateUsbPrinterAsync(
        Guid id, string name, string windowsPrinterName, string paperSize,
        bool isDefault, bool isActive, CancellationToken ct)
    {
        var payload = new
        {
            name,
            connectionType = 3,
            printerBrand = "xprinter",
            paperSize,
            textMode = "auto",
            lanHost = (string?)null,
            lanPort = 9100,
            usbDeviceName = windowsPrinterName,
            feedBeforeCut = paperSize.StartsWith("Label", StringComparison.OrdinalIgnoreCase) ? 2 : 3,
            partialCut = true,
            openCashDrawer = false,
            openDrawerCashOnly = true,
            beepOnPrint = false,
            isDefault,
            sortOrder = 0,
            isActive,
        };
        await PutOkAsync($"api/pos/printers/{id}", payload, ct);
    }

    public async Task DeletePrinterAsync(Guid id, CancellationToken ct)
    {
        var res = await _http.DeleteAsync($"api/pos/printers/{id}", ct);
        var body = await res.Content.ReadAsStringAsync(ct);
        Unpack(body, res.IsSuccessStatusCode).Dispose();
    }

    public async Task ReportHealthAsync(Guid printerId, string status, string? errorMessage, CancellationToken ct)
    {
        try
        {
            await PostDataAsync($"api/pos/printers/{printerId}/health",
                new { status, errorMessage }, ct);
        }
        catch { /* ignore */ }
    }

    public async Task<List<RouteItem>> GetRoutesAsync(CancellationToken ct)
    {
        using var doc = await GetDataAsync("api/pos/printers/routes", ct);
        var list = new List<RouteItem>();
        if (doc.RootElement.ValueKind != JsonValueKind.Array) return list;
        foreach (var e in doc.RootElement.EnumerateArray())
        {
            var docType = e.TryGetProperty("documentType", out var dt) ? dt.GetString() ?? "" : "";
            if (string.IsNullOrWhiteSpace(docType)) continue;
            var printerId = Guid.Parse(e.GetProperty("printerId").GetString()!);
            var copies = e.TryGetProperty("defaultCopies", out var c) && c.ValueKind == JsonValueKind.Number
                ? c.GetInt32() : 1;
            list.Add(new RouteItem(docType, printerId, copies));
        }
        return list;
    }

    public async Task SaveRoutesAsync(IEnumerable<RouteItem> routes, CancellationToken ct)
    {
        var payload = new
        {
            routes = routes.Select(r => new
            {
                documentType = r.DocumentType,
                printerId = r.PrinterId,
                defaultCopies = r.Copies,
            }).ToList(),
        };
        await PutOkAsync("api/pos/printers/routes", payload, ct);
    }

    public async Task<(Guid AgentId, List<Guid> PrinterIds)> RegisterAgentAsync(
        string deviceId,
        string deviceName,
        string? employeeName,
        IEnumerable<Guid> printerIds,
        string appVersion,
        CancellationToken ct)
    {
        var payload = new
        {
            deviceId,
            deviceName,
            employeeName = employeeName ?? "SboxPrintAgent-Win",
            printerIds = printerIds.ToList(),
            appVersion,
        };
        using var doc = await PostDataAsync("api/pos/print-jobs/agents/register", payload, ct);
        var agentId = Guid.Parse(doc.RootElement.GetProperty("agentId").GetString()!);
        var ids = new List<Guid>();
        if (doc.RootElement.TryGetProperty("printerIds", out var arr) &&
            arr.ValueKind == JsonValueKind.Array)
        {
            foreach (var e in arr.EnumerateArray())
                ids.Add(Guid.Parse(e.GetString()!));
        }
        return (agentId, ids);
    }

    public async Task MarkOfflineAsync(string deviceId, CancellationToken ct)
    {
        try { await PostDataAsync("api/pos/print-jobs/agents/offline", new { deviceId, forceStop = false }, ct); }
        catch { /* ignore */ }
    }

    public async Task<AgentsSnapshot> ListAgentsAsync(bool onlineOnly, CancellationToken ct)
    {
        using var doc = await GetDataAsync(
            $"api/pos/print-jobs/agents?onlineOnly={onlineOnly.ToString().ToLowerInvariant()}&staleSeconds=90",
            ct);
        var root = doc.RootElement;
        var agents = new List<AgentInfo>();
        if (root.TryGetProperty("agents", out var arr) && arr.ValueKind == JsonValueKind.Array)
        {
            foreach (var e in arr.EnumerateArray())
            {
                var printerIds = new List<Guid>();
                if (e.TryGetProperty("printerIds", out var pids) && pids.ValueKind == JsonValueKind.Array)
                {
                    foreach (var id in pids.EnumerateArray())
                        if (Guid.TryParse(id.GetString(), out var g)) printerIds.Add(g);
                }
                var names = new List<string>();
                if (e.TryGetProperty("printerNames", out var pns) && pns.ValueKind == JsonValueKind.Array)
                {
                    foreach (var n in pns.EnumerateArray())
                        names.Add(n.GetString() ?? "");
                }
                DateTime? hb = null;
                if (e.TryGetProperty("lastHeartbeatAt", out var hbe) && hbe.ValueKind == JsonValueKind.String
                    && DateTime.TryParse(hbe.GetString(), out var hbd))
                    hb = hbd;

                agents.Add(new AgentInfo(
                    Guid.Parse(e.GetProperty("agentId").GetString()!),
                    e.TryGetProperty("deviceId", out var did) ? did.GetString() ?? "" : "",
                    e.TryGetProperty("deviceName", out var dn) ? dn.GetString() : null,
                    e.TryGetProperty("employeeName", out var en) ? en.GetString() : null,
                    e.TryGetProperty("accountLabel", out var al) ? al.GetString() : null,
                    printerIds,
                    names,
                    e.TryGetProperty("isOnline", out var on) && on.GetBoolean(),
                    hb,
                    e.TryGetProperty("appVersion", out var av) ? av.GetString() : null));
            }
        }

        var conflicts = new List<Guid>();
        if (root.TryGetProperty("conflictPrinterIds", out var cids) && cids.ValueKind == JsonValueKind.Array)
        {
            foreach (var id in cids.EnumerateArray())
                if (Guid.TryParse(id.GetString(), out var g)) conflicts.Add(g);
        }

        return new AgentsSnapshot(
            root.TryGetProperty("onlineCount", out var oc) ? oc.GetInt32() : agents.Count(a => a.IsOnline),
            root.TryGetProperty("multiAgent", out var ma) && ma.GetBoolean(),
            root.TryGetProperty("hasPrinterConflict", out var hc) && hc.GetBoolean(),
            conflicts,
            agents);
    }

    public async Task<ClaimJob?> ClaimAsync(Guid agentId, CancellationToken ct)
    {
        using var doc = await PostDataAsync($"api/pos/print-jobs/agents/{agentId}/claim", new { }, ct);
        return ParseClaim(doc.RootElement);
    }

    public async Task MarkPrintingAsync(Guid jobId, Guid agentId, CancellationToken ct)
    {
        await PostDataAsync($"api/pos/print-jobs/{jobId}/printing?agentId={agentId}", new { }, ct);
    }

    public async Task CompleteAsync(Guid jobId, Guid agentId, CancellationToken ct)
    {
        var res = await _http.PostAsJsonAsync(
            $"api/pos/print-jobs/{jobId}/complete?agentId={agentId:D}", new { }, _json, ct);
        var body = await res.Content.ReadAsStringAsync(ct);
        if (!res.IsSuccessStatusCode)
            throw new InvalidOperationException($"Complete HTTP {(int)res.StatusCode}: {body}");
        using var doc = Unpack(body, true);
        // Xác nhận server đã chuyển Completed — tránh coi là xong khi data null.
        if (doc.RootElement.ValueKind == JsonValueKind.Object &&
            doc.RootElement.TryGetProperty("status", out var st) &&
            !string.Equals(st.GetString(), "Completed", StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidOperationException("Server chưa đánh dấu Completed: " + st.GetString());
        }
    }

    public async Task FailAsync(Guid jobId, Guid agentId, string errorCode, string errorMessage, CancellationToken ct)
    {
        await PostDataAsync($"api/pos/print-jobs/{jobId}/fail?agentId={agentId}",
            new { errorCode, errorMessage }, ct);
    }

    /// <summary>Nhả job về Queued để Agent khác claim (parity Flutter).</summary>
    public async Task ReleaseAsync(Guid jobId, Guid agentId, string errorCode, string errorMessage, CancellationToken ct)
    {
        await PostDataAsync($"api/pos/print-jobs/{jobId}/release?agentId={agentId}",
            new { errorCode, errorMessage }, ct);
    }

    public async Task<ClaimJob?> GetJobAsync(Guid jobId, CancellationToken ct)
    {
        using var doc = await GetDataAsync($"api/pos/print-jobs/{jobId}", ct);
        return ParseClaim(doc.RootElement);
    }

    public async Task<Guid> CreateTestJobAsync(Guid printerId, CancellationToken ct)
    {
        var bytes = EscPosBuilder.TestSlip("Cloud test");
        var payload = Convert.ToBase64String(bytes);
        using var doc = await PostDataAsync("api/pos/print-jobs", new
        {
            documentType = "SaleInvoice",
            payloadFormat = "EscPosBase64",
            payload,
            copies = 1,
            referenceNo = "TEST-WIN",
            printerId,
        }, ct);
        return Guid.Parse(doc.RootElement.GetProperty("jobId").GetString()!);
    }

    static object BuildPrinterSave(
        string name, string host, int port, string paperSize,
        bool isDefault, int sortOrder, bool isActive) => new
    {
        name,
        connectionType = 1,
        printerBrand = "xprinter",
        paperSize,
        textMode = "auto",
        lanHost = host,
        lanPort = port,
        feedBeforeCut = paperSize.StartsWith("Label", StringComparison.OrdinalIgnoreCase) ? 2 : 3,
        partialCut = true,
        openCashDrawer = false,
        openDrawerCashOnly = true,
        beepOnPrint = false,
        isDefault,
        sortOrder,
        isActive,
    };

    static PrinterItem ParsePrinter(JsonElement e)
    {
        var docs = new List<string>();
        if (e.TryGetProperty("documentTypes", out var dts) && dts.ValueKind == JsonValueKind.Array)
        {
            foreach (var d in dts.EnumerateArray())
                docs.Add(ReadString(d) ?? "");
        }
        return new PrinterItem(
            Guid.Parse(ReadString(e.GetProperty("id"))!),
            ReadString(e.GetProperty("name")) ?? "",
            e.TryGetProperty("lanHost", out var h) ? ReadString(h) : null,
            e.TryGetProperty("lanPort", out var p) ? ReadInt(p, 9100) : 9100,
            e.TryGetProperty("connectionType", out var c) ? ReadConnType(c) : "Lan",
            e.TryGetProperty("paperSize", out var ps) ? ReadString(ps) ?? "K80" : "K80",
            e.TryGetProperty("isDefault", out var idf) && ReadBool(idf),
            !e.TryGetProperty("isActive", out var ia) || ReadBool(ia, defaultIfMissing: true),
            e.TryGetProperty("requiresAgent", out var ra) && ReadBool(ra),
            e.TryGetProperty("isDeviceLocal", out var idl) && ReadBool(idl),
            e.TryGetProperty("ownerDeviceId", out var od) ? ReadString(od) : null,
            e.TryGetProperty("healthStatus", out var hs) ? ReadString(hs) ?? "Unknown" : "Unknown",
            docs,
            e.TryGetProperty("defaultCopies", out var dc) ? ReadInt(dc, 1) : 1,
            e.TryGetProperty("feedBeforeCut", out var fb) ? ReadInt(fb, 3) : 3,
            e.TryGetProperty("partialCut", out var pc) && ReadBool(pc),
            e.TryGetProperty("printerBrand", out var pb) ? ReadString(pb) : null,
            e.TryGetProperty("textMode", out var tm) ? ReadString(tm) : null,
            e.TryGetProperty("usbDeviceName", out var usb) ? ReadString(usb) : null);
    }

    static string ReadConnType(JsonElement c) => c.ValueKind switch
    {
        JsonValueKind.String => c.GetString() ?? "Lan",
        JsonValueKind.Number => c.GetInt32() switch
        {
            1 => "Lan",
            2 => "Bluetooth",
            3 => "Usb",
            4 => "Sunmi",
            _ => "Lan",
        },
        _ => "Lan",
    };

    static string? ReadString(JsonElement e) => e.ValueKind switch
    {
        JsonValueKind.String => e.GetString(),
        JsonValueKind.Number => e.GetRawText(),
        JsonValueKind.True => "true",
        JsonValueKind.False => "false",
        JsonValueKind.Null or JsonValueKind.Undefined => null,
        _ => e.ToString(),
    };

    static int ReadInt(JsonElement e, int fallback) => e.ValueKind switch
    {
        JsonValueKind.Number => e.TryGetInt32(out var n) ? n : fallback,
        JsonValueKind.String when int.TryParse(e.GetString(), out var n) => n,
        _ => fallback,
    };

    static bool ReadBool(JsonElement e, bool defaultIfMissing = false) => e.ValueKind switch
    {
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        JsonValueKind.String when bool.TryParse(e.GetString(), out var b) => b,
        JsonValueKind.Number => e.GetInt32() != 0,
        _ => defaultIfMissing,
    };

    static ClaimJob? ParseClaim(JsonElement root)
    {
        if (root.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return null;
        if (root.ValueKind != JsonValueKind.Object) return null;
        JsonElement jid;
        if (root.TryGetProperty("jobId", out jid) || root.TryGetProperty("id", out jid) ||
            root.TryGetProperty("Id", out jid))
        {
            // ok
        }
        else return null;

        var jobIdStr = ReadString(jid);
        if (!Guid.TryParse(jobIdStr, out var jobId)) return null;
        if (!root.TryGetProperty("printerId", out var pidEl) &&
            !root.TryGetProperty("PrinterId", out pidEl))
            return null;
        if (!Guid.TryParse(ReadString(pidEl), out var printerId)) return null;

        return new ClaimJob(
            jobId,
            printerId,
            root.TryGetProperty("documentType", out var dt) ? ReadString(dt) ?? "" : "",
            root.TryGetProperty("payloadFormat", out var pf) ? ReadString(pf) ?? "" : "",
            root.TryGetProperty("payload", out var p) ? ReadString(p) : null,
            root.TryGetProperty("copies", out var c) ? ReadInt(c, 1) : 1,
            root.TryGetProperty("referenceNo", out var rn) ? ReadString(rn) : null);
    }

    async Task<JsonDocument> GetDataAsync(string path, CancellationToken ct)
    {
        var res = await _http.GetAsync(path, ct);
        var body = await res.Content.ReadAsStringAsync(ct);
        if (res.StatusCode == System.Net.HttpStatusCode.Unauthorized)
            throw new ApiException(Trunc(body, 240).Length > 0 ? Trunc(body, 240) : "HTTP 401 Unauthorized", isAuth: true);
        return Unpack(body, res.IsSuccessStatusCode);
    }

    async Task<JsonDocument> PostDataAsync(string path, object payload, CancellationToken ct)
    {
        var res = await _http.PostAsJsonAsync(path, payload, _json, ct);
        var body = await res.Content.ReadAsStringAsync(ct);
        if (res.StatusCode == System.Net.HttpStatusCode.Unauthorized)
            throw new ApiException(Trunc(body, 240).Length > 0 ? Trunc(body, 240) : "HTTP 401 Unauthorized", isAuth: true);
        return Unpack(body, res.IsSuccessStatusCode);
    }

    async Task PutOkAsync(string path, object payload, CancellationToken ct)
    {
        var json = JsonSerializer.Serialize(payload, _json);
        var res = await _http.PutAsync(path,
            new StringContent(json, Encoding.UTF8, "application/json"), ct);
        var body = await res.Content.ReadAsStringAsync(ct);
        Unpack(body, res.IsSuccessStatusCode).Dispose();
    }

    static JsonDocument Unpack(string body, bool httpOk)
    {
        using var probe = JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body);
        var root = probe.RootElement.Clone();
        if (root.TryGetProperty("isSuccess", out var ok))
        {
            if (!ok.GetBoolean())
            {
                var msg = root.TryGetProperty("message", out var m) ? m.GetString() : null;
                if (string.IsNullOrWhiteSpace(msg))
                    msg = Trunc(body, 240);
                if (string.IsNullOrWhiteSpace(msg))
                    msg = "API trả isSuccess=false (không có message)";
                throw new ApiException(msg, isAuth: LooksLikeAuth(msg, body));
            }
            if (root.TryGetProperty("data", out var data))
                return JsonDocument.Parse(data.GetRawText());
            return JsonDocument.Parse("null");
        }
        if (!httpOk)
        {
            var snippet = Trunc(body, 240);
            var auth = LooksLikeAuth(snippet, body) ||
                       snippet.Contains("401", StringComparison.Ordinal) ||
                       snippet.Contains("Unauthorized", StringComparison.OrdinalIgnoreCase);
            throw new ApiException(
                string.IsNullOrWhiteSpace(snippet) ? "HTTP lỗi (body trống)" : snippet,
                isAuth: auth);
        }
        return JsonDocument.Parse(root.GetRawText());
    }

    static bool LooksLikeAuth(string? msg, string? body)
    {
        var s = (msg ?? "") + " " + (body ?? "");
        return s.Contains("401", StringComparison.Ordinal) ||
               s.Contains("Unauthorized", StringComparison.OrdinalIgnoreCase) ||
               s.Contains("đăng nhập", StringComparison.OrdinalIgnoreCase) ||
               (s.Contains("token", StringComparison.OrdinalIgnoreCase) &&
                (s.Contains("hết hạn", StringComparison.OrdinalIgnoreCase) ||
                 s.Contains("expired", StringComparison.OrdinalIgnoreCase) ||
                 s.Contains("invalid", StringComparison.OrdinalIgnoreCase)));
    }

    static string Trunc(string? s, int max)
    {
        if (string.IsNullOrWhiteSpace(s)) return "";
        s = s.Replace('\r', ' ').Replace('\n', ' ').Trim();
        return s.Length <= max ? s : s[..max] + "…";
    }

    public static string FormatError(Exception ex)
    {
        var parts = new List<string>();
        for (Exception? e = ex; e != null; e = e.InnerException)
        {
            if (!string.IsNullOrWhiteSpace(e.Message))
                parts.Add(e.Message.Trim());
            else
                parts.Add(e.GetType().Name);
        }
        return parts.Count == 0 ? ex.GetType().Name : string.Join(" → ", parts.Distinct());
    }
}

public sealed class ApiException : InvalidOperationException
{
    public bool IsAuth { get; }
    public ApiException(string message, bool isAuth = false) : base(message) => IsAuth = isAuth;
}

static class JwtStoreId
{
    public static Guid? TryParse(string jwt)
    {
        try
        {
            var handler = new System.IdentityModel.Tokens.Jwt.JwtSecurityTokenHandler();
            var token = handler.ReadJwtToken(jwt);
            foreach (var c in token.Claims)
            {
                if (c.Type is "storeId" or "StoreId" && Guid.TryParse(c.Value, out var g))
                    return g;
            }
        }
        catch { /* ignore */ }
        return null;
    }
}
