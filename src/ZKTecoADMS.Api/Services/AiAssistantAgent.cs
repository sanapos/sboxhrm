using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Trợ lý ảo phân tích: Gemini tự chọn báo cáo POS / HRM cần xem (function calling), server chạy đúng API báo cáo
/// của app bằng phiên đăng nhập của người hỏi (cùng số liệu, cùng quyền + gói, đúng cửa hàng / chi nhánh),
/// rồi Gemini phân tích và trả lời.
/// </summary>
public sealed class AiAssistantAgent(
    ZKTecoDbContext db,
    IGeminiAiService gemini,
    IHttpContextAccessor http,
    AiAssistantActions actions,
    ILogger<AiAssistantAgent> logger)
{
    const int MaxRounds = 6;
    const int MaxToolCalls = 10;
    /// <summary>Ký tự tối đa mỗi kết quả báo cáo gửi lại Gemini (mỗi vòng sau gửi lại toàn bộ — giữ gọn để đỡ token).</summary>
    const int MaxResultChars = 10000;
    /// <summary>
    /// Giới hạn token «suy nghĩ» mỗi vòng: chọn công cụ / đọc số liệu không cần suy nghĩ dài, mà token suy nghĩ tính vào
    /// hạn mức như token trả lời. Model không nhận tham số này (400) → tự bỏ và gọi lại.
    /// </summary>
    const int ThinkingBudget = 1024;

    /// <param name="Scope">Phạm vi nhân sự của người hỏi.</param>
    /// <param name="Prompt">Câu hỏi gốc (nhật ký thao tác).</param>
    /// <param name="WithActions">Câu cần thêm / sửa / xóa / duyệt — false = chỉ phân tích, không gửi khai báo thao tác.</param>
    /// <param name="Groups">Nhóm thao tác cần gửi (null = mọi nhóm) — xem <see cref="AiAssistantIntent"/>.</param>
    /// <param name="OnEvent">Có = trả lời dần (stream): trạng thái đang làm gì + từng đoạn chữ (xem <see cref="AgentEvent"/>).</param>
    public sealed record Options(AiAssistantScope Scope, string Prompt, bool WithActions, IReadOnlySet<string>? Groups,
        Func<AgentEvent, Task>? OnEvent = null);

    /// <summary>
    /// Sự kiện gửi dần cho app: <c>status</c> (đang xem báo cáo…), <c>delta</c> (đoạn chữ mới), <c>reset</c> (bỏ chữ tạm —
    /// model chuyển sang gọi công cụ). Câu trả lời chính thức (đã lọc thẻ, định dạng) vẫn là kết quả cuối.
    /// </summary>
    public sealed record AgentEvent(string Type, string Text);

    static readonly HttpClient Loopback = new(new SocketsHttpHandler
    {
        PooledConnectionLifetime = TimeSpan.FromMinutes(5),
    })
    { Timeout = TimeSpan.FromSeconds(60) };

    public sealed record Result(string Reply, List<string> ReportsUsed, List<AiAssistantActions.Pending> Proposed);

    /// <summary>Câu muốn thêm / sửa / xóa / duyệt — đi qua agent (có công cụ đề xuất phiếu).</summary>
    public static bool LooksLikeWrite(string query) => AiAssistantIntent.LooksLikeAction(query);

    /// <summary>Câu hỏi phân tích / số liệu tổng hợp — đi thẳng qua agent thay vì bot rule.</summary>
    public static bool LooksAnalytical(string query)
    {
        var q = (query ?? "").ToLowerInvariant();
        string[] keys =
        [
            "phân tích", "phan tich", "so sánh", "so sanh", "xu hướng", "tăng trưởng", "tăng hay giảm", "giảm bao nhiêu",
            "tăng bao nhiêu", "báo cáo", "bao cao", "doanh thu", "doanh số", "lợi nhuận", "lãi", "lỗ", "giá vốn",
            "biên lợi", "bán chạy", "bán chậm", "top ", "nhiều nhất", "ít nhất", "cao nhất", "thấp nhất", "trung bình",
            "tỷ lệ", "ti le", "tồn kho", "tồn lâu", "hết hàng", "sắp hết", "nhập hàng", "công nợ", "khách hàng nào",
            "nhân viên nào", "ai bán", "món nào", "mặt hàng", "nhóm hàng", "chi phí", "thu chi", "sổ quỹ", "quỹ",
            "tháng này", "tháng trước", "tuần này", "tuần trước", "quý", "năm nay", "năm ngoái", "hôm qua", "7 ngày",
            "30 ngày", "đi trễ nhiều", "đi muộn", "vắng nhiều", "bảng công", "ngày công", "tăng ca", "quỹ lương",
            "tổng lương", "chi lương", "nghỉ phép nhiều", "đánh giá", "đề xuất", "gợi ý", "cải thiện", "dự báo",
            "tình hình kinh doanh", "kinh doanh", "hiệu quả",
        ];
        return keys.Any(q.Contains);
    }

    public async Task<Result> RunAsync(
        string systemPrompt,
        IReadOnlyList<(string Role, string Content)> turns,
        Guid storeId,
        IReadOnlyDictionary<string, ModulePermissionDto> perms,
        bool isSuperUser,
        CancellationToken ct,
        Guid? userId = null,
        string userRole = "",
        Options? options = null)
    {
        var scope = options?.Scope ?? AiAssistantScope.Of(null, [], selfOnly: true);
        var packageModules = await Infrastructure.Helpers.StorePackageHelper.ResolveAllowedModulesAsync(db, storeId, ct);
        var reports = AiAssistantReportCatalog.Allowed(perms, isSuperUser, packageModules);
        var actx = userId is Guid uid
            ? new AiAssistantActions.Ctx(storeId, uid, userRole, perms, isSuperUser, packageModules, scope, options?.Prompt ?? "")
            : null;
        var actionDecls = actx == null || options is { WithActions: false } ? [] : actions.ToolDeclarations(actx, options?.Groups);
        var tools = BuildTools(reports, actionDecls);
        // Phần ổn định (quy tắc, danh mục báo cáo, quy tắc thao tác) đứng TRƯỚC phần đổi theo người / giờ: Gemini tự
        // lưu đệm tiền tố trùng giữa các lượt gọi (implicit caching) → token lặp lại được tính rẻ hơn.
        var system = AnalystInstructions(reports) + "\n" + AiAssistantActions.Instructions(actionDecls.Count > 0)
                     + "\n" + systemPrompt + "\n\n" + NowLine();
        var proposed = new List<AiAssistantActions.Pending>();

        var contents = new List<object>();
        foreach (var (role, content) in turns)
        {
            if (string.IsNullOrWhiteSpace(content)) continue;
            contents.Add(new { role = role == "assistant" ? "model" : "user", parts = new[] { new { text = content } } });
        }

        var used = new List<string>();
        var calls = 0;
        string? model = null;
        var nudged = false;
        var thinkingOk = true;
        var onEvent = options?.OnEvent;
        var streamed = false;
        // Một vòng gọi: có người nghe → stream (gửi dần chữ), không → gọi thường.
        Task<JsonElement> Generate(object b, string? m) =>
            onEvent == null ? gemini.GenerateContentRawAsync(b, ct, m) : StreamRoundAsync(b, m, onEvent, s => streamed |= s, ct);
        async Task Reset()
        {
            if (onEvent != null && streamed) await onEvent(new AgentEvent("reset", ""));
            streamed = false;
        }
        for (var round = 0; round < MaxRounds; round++)
        {
            object Body() => new
            {
                systemInstruction = new { parts = new[] { new { text = system } } },
                contents,
                tools,
                generationConfig = thinkingOk
                    ? (object)new { temperature = 0.2, maxOutputTokens = 4096, thinkingConfig = new { thinkingBudget = ThinkingBudget } }
                    : new { temperature = 0.2, maxOutputTokens = 4096 },
            };
            var body = Body();
            JsonElement content;
            try
            {
                content = await Generate(body, model);
            }
            catch (AiApiException ex) when (ex.StatusCode == 400 && thinkingOk)
            {
                // Model không nhận thinkingConfig → bỏ, gọi lại như cũ.
                logger.LogInformation("AI agent: thinkingConfig rejected — retry without");
                thinkingOk = false;
                await Reset();
                content = await Generate(Body(), model);
            }
            catch (AiApiException ex) when (ex.StatusCode == 503)
            {
                // Google quá tải thường chỉ vài giây — thử lại một lần.
                await Task.Delay(2000, ct);
                await Reset();
                content = await Generate(body, model);
            }
            catch (AiApiException ex) when (ex.IsQuotaError && model == null)
            {
                // Khóa miễn phí hết lượt model chính — Flash Lite có hạn mức riêng, chạy tiếp các lượt sau bằng nó.
                logger.LogInformation("AI agent: quota on default model → {Model}", GeminiModels.FlashLite);
                model = GeminiModels.FlashLite;
                await Reset();
                content = await Generate(body, model);
            }
            var parts = content.TryGetProperty("parts", out var ps) && ps.ValueKind == JsonValueKind.Array
                ? ps.EnumerateArray().ToList()
                : [];
            var fnCalls = parts.Where(p => p.TryGetProperty("functionCall", out _)).ToList();
            if (fnCalls.Count == 0 || calls >= MaxToolCalls)
            {
                var text = string.Join("\n", parts
                    .Where(p => !(p.TryGetProperty("thought", out var t) && t.ValueKind == JsonValueKind.True))
                    .Where(p => p.TryGetProperty("text", out _))
                    .Select(p => p.GetProperty("text").GetString() ?? "")).Trim();
                // Model nói đã lập phiếu / mời xác nhận nhưng chưa gọi công cụ đề xuất → không có thẻ: bắt gọi thật.
                if (fnCalls.Count == 0 && actx != null && proposed.Count == 0 && !nudged && actionDecls.Count > 0
                    && ClaimsProposal(text))
                {
                    nudged = true;
                    await Reset();
                    contents.Add(content);
                    contents.Add(new { role = "user", parts = new[] { new { text =
                        "Bạn CHƯA gọi công cụ propose_* nên người dùng không thấy thẻ xác nhận. Gọi đúng công cụ ngay "
                        + "(tra find_* trước nếu cần id); thiếu thông tin thì hỏi lại, KHÔNG nói đã lập." } } });
                    continue;
                }
                if (text.Length > 0 || fnCalls.Count == 0)
                    return new Result(PlainText(text), used, proposed);
                // Hết lượt gọi công cụ mà model vẫn đòi gọi — yêu cầu trả lời bằng số liệu đã có.
                await Reset();
                contents.Add(content);
                contents.Add(new { role = "user", parts = new[] { new { text = "Đã đủ số liệu — hãy trả lời ngay, không gọi thêm công cụ." } } });
                continue;
            }

            // Giữ nguyên nội dung model (kể cả thoughtSignature) rồi trả kết quả từng lời gọi.
            await Reset();
            contents.Add(content);
            var responses = new List<object>();
            foreach (var fc in fnCalls)
            {
                calls++;
                var call = fc.GetProperty("functionCall");
                var name = call.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                var args = call.TryGetProperty("args", out var a) ? a : default;
                if (onEvent != null) await onEvent(new AgentEvent("status", StatusOf(name, args)));
                object response;
                try
                {
                    response = name switch
                    {
                        "run_report" => await RunReportAsync(args, reports, used, ct),
                        "store_overview" => await StoreOverviewAsync(storeId, perms, isSuperUser, packageModules, scope, ct),
                        _ when actx != null && actions.Handles(name) => await actions.HandleAsync(name, args, actx, proposed, ct),
                        _ => new { error = $"Không có công cụ {name}" },
                    };
                }
                catch (Exception ex) when (ex is not OperationCanceledException)
                {
                    logger.LogWarning(ex, "AI tool {Tool} failed", name);
                    response = new { error = "Không lấy được số liệu: " + ex.Message };
                }
                responses.Add(new { functionResponse = new { name, response } });
            }
            contents.Add(new { role = "user", parts = responses });
        }

        return new Result("Câu hỏi cần quá nhiều báo cáo — bạn hỏi cụ thể hơn (một chỉ số, một khoảng thời gian) nhé.", used, proposed);
    }

    /// <summary>
    /// Một vòng gọi dạng stream: gửi dần chữ (bỏ phần «suy nghĩ»), gom lại thành một nội dung như bản thường —
    /// các đoạn chữ ghép thành một part (giữ thoughtSignature nếu có), functionCall giữ nguyên từng part.
    /// </summary>
    async Task<JsonElement> StreamRoundAsync(object body, string? model, Func<AgentEvent, Task> onEvent, Action<bool> sent,
        CancellationToken ct)
    {
        var text = new StringBuilder();
        string? textSignature = null;
        var others = new JsonArray();
        await foreach (var chunk in gemini.StreamGenerateContentRawAsync(body, ct, model))
        {
            if (!chunk.TryGetProperty("parts", out var ps) || ps.ValueKind != JsonValueKind.Array) continue;
            foreach (var p in ps.EnumerateArray())
            {
                var thought = p.TryGetProperty("thought", out var t) && t.ValueKind == JsonValueKind.True;
                if (!thought && p.TryGetProperty("text", out var tx) && !p.TryGetProperty("functionCall", out _))
                {
                    var s = tx.GetString() ?? "";
                    if (p.TryGetProperty("thoughtSignature", out var sig)) textSignature ??= sig.GetString();
                    if (s.Length == 0) continue;
                    text.Append(s);
                    await onEvent(new AgentEvent("delta", s));
                    sent(true);
                    continue;
                }
                if (thought) continue;
                others.Add(JsonNode.Parse(p.GetRawText()));
            }
        }
        var parts = new JsonArray();
        if (text.Length > 0)
        {
            var tp = new JsonObject { ["text"] = text.ToString() };
            if (textSignature != null) tp["thoughtSignature"] = textSignature;
            parts.Add(tp);
        }
        foreach (var o in others.ToList())
        {
            others.Remove(o);
            parts.Add(o);
        }
        using var doc = JsonDocument.Parse(new JsonObject { ["role"] = "model", ["parts"] = parts }.ToJsonString());
        return doc.RootElement.Clone();
    }

    /// <summary>Câu trạng thái cho app khi trợ lý gọi công cụ (đang xem báo cáo…).</summary>
    static string StatusOf(string tool, JsonElement args)
    {
        string? Arg(string k) => args.ValueKind == JsonValueKind.Object && args.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String
            ? v.GetString() : null;
        return tool switch
        {
            "run_report" => $"Đang xem báo cáo «{AiAssistantReportCatalog.TitleOf(Arg("report") ?? "")}»…",
            "store_overview" => "Đang xem thông tin cửa hàng…",
            "find_employees" => "Đang tìm nhân viên…",
            "find_products" => "Đang tìm hàng hóa…",
            "find_customers" => "Đang tìm khách hàng…",
            "find_suppliers" => "Đang tìm nhà cung cấp…",
            "find_orders" => "Đang tìm hóa đơn…",
            "find_pending_requests" => "Đang xem đơn chờ duyệt…",
            _ when tool.StartsWith("find_", StringComparison.Ordinal) => "Đang tra cứu…",
            _ when tool.StartsWith("propose_", StringComparison.Ordinal) => "Đang lập phiếu để bạn xác nhận…",
            _ => "Đang xử lý…",
        };
    }

    static bool ClaimsProposal(string text)
    {
        var t = text.ToLowerInvariant();
        return t.Contains("xác nhận") || t.Contains("đã lập") || t.Contains("đã tạo") || t.Contains("bản nháp")
               || t.Contains("thẻ bên dưới") || t.Contains("đã chuẩn bị");
    }

    // ─── Công cụ ─────────────────────────────────────────────────────

    static object[] BuildTools(IReadOnlyList<AiAssistantReportCatalog.Report> reports, List<object>? extra = null)
    {
        var decls = new List<object>
        {
            new
            {
                name = "store_overview",
                description = "Hồ sơ dữ liệu của cửa hàng: tên, ngành hàng, số mặt hàng / nhóm hàng / khách / nhà cung cấp, "
                              + "nhân sự theo phòng ban, chi nhánh, ngày bán đầu tiên / gần nhất. Gọi khi cần hiểu cửa hàng có gì "
                              + "hoặc cần tên phòng ban / nhóm hàng chính xác.",
            },
        };
        if (reports.Count > 0)
        {
            decls.Add(new
            {
                name = "run_report",
                description = "Chạy một báo cáo của app (POS / nhân sự) cho cửa hàng hiện tại và nhận số liệu JSON. "
                              + "Có thể gọi nhiều lần (vd 2 kỳ để so sánh). Danh sách báo cáo xem trong hướng dẫn hệ thống.",
                parameters = new
                {
                    type = "OBJECT",
                    properties = new Dictionary<string, object>
                    {
                        ["report"] = new { type = "STRING", description = "Mã báo cáo", @enum = reports.Select(r => r.Id).ToArray() },
                        ["from"] = new { type = "STRING", description = "Từ ngày yyyy-MM-dd (giờ VN, tính cả ngày này)" },
                        ["to"] = new { type = "STRING", description = "Đến ngày yyyy-MM-dd (tính cả ngày này)" },
                        ["date"] = new { type = "STRING", description = "Một ngày yyyy-MM-dd (báo cáo theo ngày)" },
                        ["year"] = new { type = "INTEGER", description = "Năm (báo cáo theo tháng)" },
                        ["month"] = new { type = "INTEGER", description = "Tháng 1-12" },
                        ["group_by"] = new { type = "STRING", description = "Nhóm theo (tùy báo cáo)" },
                        ["mode"] = new { type = "STRING", description = "Chế độ lọc (tùy báo cáo)" },
                        ["search"] = new { type = "STRING", description = "Từ khóa tìm (tên khách, SĐT…)" },
                        ["department"] = new { type = "STRING", description = "Tên phòng ban (lọc nhân sự)" },
                        ["limit"] = new { type = "INTEGER", description = "Số dòng tối đa" },
                    },
                    required = new[] { "report" },
                },
            });
        }
        if (extra != null) decls.AddRange(extra);
        return [new { functionDeclarations = decls }];
    }

    static string NowLine()
    {
        var now = AiAssistantVnTime.NowVn();
        return $"Bây giờ: {now:HH:mm} {now.ToString("dddd", new CultureInfo("vi-VN"))} {now:dd/MM/yyyy} (giờ VN). Hôm nay = {now:yyyy-MM-dd}.";
    }

    static string AnalystInstructions(IReadOnlyList<AiAssistantReportCatalog.Report> reports)
    {
        var sb = new StringBuilder();
        sb.AppendLine("=== CHẾ ĐỘ PHÂN TÍCH SỐ LIỆU ===");
        sb.AppendLine("""
            - Câu hỏi về số liệu (doanh thu, lãi, hàng hóa, tồn kho, khách, công nợ, chấm công, đi trễ, nghỉ phép, lương, thu chi…):
              GỌI run_report để lấy số liệu thật — KHÔNG đoán. Cần so sánh thì gọi 2 kỳ (hoặc dùng pos_overview đã có kỳ trước).
            - Gọi TẤT CẢ báo cáo cần thiết trong CÙNG MỘT lượt (nhiều lời gọi song song), rồi trả lời — hạn chế gọi thêm lượt sau.
            - Tự quy đổi thời gian: "tháng này" = ngày 1 tháng hiện tại → hôm nay; "tháng trước" = trọn tháng trước;
              "tuần này" = thứ Hai tuần này → hôm nay; "quý này", "năm nay" tương tự. Báo cáo theo tháng dùng year + month.
            - Trả lời kiểu chuyên viên phân tích: con số chính trước (định dạng 1.234.567đ), so sánh % tăng/giảm, chỉ ra
              điểm bất thường (mặt hàng / nhân viên / ngày nổi bật), rồi 2–4 gợi ý hành động cụ thể. Dùng gạch đầu dòng "•", ngắn gọn.
            - Khung chat là chữ thường: KHÔNG dùng Markdown (không **, #, bảng).
            - Ghi rõ kỳ số liệu (từ … đến …). Báo cáo trả lỗi quyền → nói tài khoản không có quyền xem báo cáo đó.
            - Số liệu trống → nói rõ chưa có dữ liệu trong kỳ, gợi ý kỳ khác. Không bịa tên, không bịa số.
            - Không lộ mã báo cáo / tên API / JSON cho người dùng; có thể gợi ý mở màn báo cáo tương ứng bằng thẻ [[OPEN:Mã]].
            - So sánh từ 3 con số cùng loại trở lên (theo ngày / tháng / món / nhân viên / nhóm hàng) lấy từ báo cáo → thêm
              TỐI ĐA 1 thẻ biểu đồ ở cuối: [[CHART:bar|Tiêu đề ngắn|Nhãn=số;Nhãn=số|Mã]] — line cho chuỗi theo thời gian, pie cho
              tỷ trọng; số nguyên thô (1250000, không dấu chấm); tối đa 12 điểm; Mã = mã màn báo cáo trong ĐƯỜNG DẪN MENU
              (bỏ trống nếu không có). Vẫn viết số chính trong câu trả lời (biểu đồ chỉ minh họa).
            """);
        if (reports.Count == 0)
        {
            sb.AppendLine("Tài khoản KHÔNG có quyền xem báo cáo nào — chỉ dùng dữ liệu cá nhân phía trên; câu hỏi báo cáo → nói không có quyền.");
            return sb.ToString();
        }
        sb.AppendLine("BÁO CÁO ĐƯỢC PHÉP (report: mô tả · tham số):");
        foreach (var r in reports)
        {
            var ps = r.Params.Count == 0 ? "không tham số" : string.Join(", ", r.Params.Keys);
            sb.AppendLine($"- {r.Id}: {r.Description} · {ps}");
        }
        return sb.ToString();
    }

    async Task<object> RunReportAsync(
        JsonElement args,
        IReadOnlyList<AiAssistantReportCatalog.Report> allowed,
        List<string> used,
        CancellationToken ct)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (args.ValueKind == JsonValueKind.Object)
            foreach (var p in args.EnumerateObject())
                map[p.Name] = p.Value.ValueKind == JsonValueKind.String ? p.Value.GetString() ?? "" : p.Value.GetRawText();

        map.TryGetValue("report", out var id);
        var report = allowed.FirstOrDefault(r => string.Equals(r.Id, id, StringComparison.OrdinalIgnoreCase));
        if (report == null)
            return new { error = $"Báo cáo «{id}» không có hoặc tài khoản không có quyền xem." };

        var ctx = http.HttpContext ?? throw new InvalidOperationException("Không có phiên làm việc");
        var url = $"http://127.0.0.1:{ctx.Connection.LocalPort}{report.Path}{AiAssistantReportCatalog.BuildQuery(report, map)}";
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        if (AuthenticationHeaderValue.TryParse(ctx.Request.Headers.Authorization.ToString(), out var auth))
            req.Headers.Authorization = auth;
        var branch = ctx.Request.Headers["X-Branch-Id"].ToString();
        if (!string.IsNullOrWhiteSpace(branch)) req.Headers.TryAddWithoutValidation("X-Branch-Id", branch);
        req.Headers.TryAddWithoutValidation("X-Sbox-Ai-Assistant", "1");

        using var resp = await Loopback.SendAsync(req, ct);
        var body = await resp.Content.ReadAsStringAsync(ct);
        used.Add(report.Id);
        logger.LogInformation("AI report {Report} → {Status} ({Length} chars)", report.Id, (int)resp.StatusCode, body.Length);
        if ((int)resp.StatusCode is 401 or 403)
            return new { error = "Tài khoản không có quyền xem báo cáo này (hoặc gói dịch vụ không có)." };
        if (!resp.IsSuccessStatusCode)
            return new { error = $"Báo cáo lỗi ({(int)resp.StatusCode})." };

        JsonNode? node;
        try { node = JsonNode.Parse(body); }
        catch (JsonException) { return new { error = "Báo cáo trả dữ liệu không đọc được." }; }
        var data = node is JsonObject o && o.TryGetPropertyValue("data", out var d) ? d : node;
        if (node is JsonObject o2 && o2["isSuccess"] is JsonValue ok && ok.TryGetValue<bool>(out var success) && !success)
            return new { error = o2["message"]?.ToString() ?? "Báo cáo lỗi." };
        return new { report = report.Id, data = Compact(data) };
    }

    /// <summary>
    /// Khung chat hiện chữ thường — đổi Markdown của model thành văn bản: bỏ **đậm**, tiêu đề ### → dòng thường,
    /// gạch đầu dòng * / - → •, bỏ đường kẻ ---.
    /// </summary>
    public static string PlainText(string text)
    {
        var lines = new List<string>();
        foreach (var raw in text.Replace("\r", "").Split('\n'))
        {
            var line = raw.Replace("**", "").Replace("__", "");
            var t = line.TrimStart();
            var indent = line.Length - t.Length;
            if (t is "---" or "***" or "___") continue;
            if (t.StartsWith('#')) t = t.TrimStart('#').TrimStart();
            else if (t.StartsWith("* ") || t.StartsWith("- ")) t = "• " + t[2..].TrimStart();
            lines.Add(new string(' ', Math.Min(indent, 4)) + t);
        }
        // Gộp nhiều dòng trống liên tiếp.
        var sb = new StringBuilder();
        var blank = 0;
        foreach (var l in lines)
        {
            blank = string.IsNullOrWhiteSpace(l) ? blank + 1 : 0;
            if (blank <= 1) sb.AppendLine(l);
        }
        return sb.ToString().Trim();
    }

    /// <summary>Thu gọn JSON báo cáo cho vừa ngữ cảnh: bỏ null / id, cắt mảng dài, cắt chuỗi dài.</summary>
    public static JsonNode? Compact(JsonNode? node, int maxChars = MaxResultChars)
    {
        foreach (var cap in new[] { 40, 20, 10, 5 })
        {
            var c = Trim(node?.DeepClone(), cap);
            if ((c?.ToJsonString().Length ?? 0) <= maxChars) return c;
        }
        return Trim(node?.DeepClone(), 3);
    }

    static JsonNode? Trim(JsonNode? node, int arrayCap)
    {
        switch (node)
        {
            case JsonObject obj:
                foreach (var key in obj.Select(kv => kv.Key).ToList())
                {
                    var v = obj[key];
                    if (v == null || IsNoiseKey(key)) { obj.Remove(key); continue; }
                    var t = Trim(v, arrayCap);
                    obj.Remove(key);
                    if (t != null) obj[key] = t;
                }
                return obj;
            case JsonArray arr:
                var total = arr.Count;
                var outArr = new JsonArray();
                foreach (var item in arr.Take(arrayCap).ToList())
                {
                    arr.Remove(item);
                    outArr.Add(Trim(item, arrayCap));
                }
                if (total > arrayCap) outArr.Add(JsonValue.Create($"…còn {total - arrayCap} dòng (đã lược bớt)"));
                return outArr;
            case JsonValue val when val.TryGetValue<string>(out var s) && s.Length > 160:
                return JsonValue.Create(s[..160] + "…");
            default:
                return node;
        }
    }

    static bool IsNoiseKey(string key) =>
        key.EndsWith("Id", StringComparison.Ordinal) && key != "Id" || key is "id" or "imageUrl" or "avatarUrl" or "storeId";

    async Task<object> StoreOverviewAsync(
        Guid storeId,
        IReadOnlyDictionary<string, ModulePermissionDto> perms,
        bool isSuperUser,
        IReadOnlyCollection<string> packageModules,
        AiAssistantScope scope,
        CancellationToken ct)
    {
        bool Can(string m) => (packageModules.Count == 0 || packageModules.Contains(m, StringComparer.OrdinalIgnoreCase))
                              && (isSuperUser || (perms.TryGetValue(m, out var p) && p.CanView));
        var store = await db.Stores.AsNoTracking().Where(s => s.Id == storeId)
            .Select(s => new { s.Name, s.Code }).FirstOrDefaultAsync(ct);
        var result = new Dictionary<string, object?> { ["tenCuaHang"] = store?.Name, ["maCuaHang"] = store?.Code };

        var branches = await db.Branches.AsNoTracking()
            .Where(b => b.StoreId == storeId && b.Deleted == null).Select(b => b.Name).ToListAsync(ct);
        result["chiNhanh"] = branches;

        if (Can("PosSell") || Can("PosProducts") || Can("PosSalesReport"))
        {
            var profile = await db.PosStoreSellSettings.AsNoTracking()
                .Where(s => s.StoreId == storeId).Select(s => (PosSellProfile?)s.SellProfile).FirstOrDefaultAsync(ct);
            result["nganhHang"] = profile?.ToString();
            result["soMatHang"] = await db.PosProducts.AsNoTracking()
                .CountAsync(p => p.StoreId == storeId && p.Deleted == null && p.IsActive, ct);
            result["nhomHang"] = await db.PosProductCategories.AsNoTracking()
                .Where(c => c.StoreId == storeId && c.Deleted == null).OrderBy(c => c.Name)
                .Select(c => c.Name).Take(40).ToListAsync(ct);
            result["soKhachHang"] = await db.PosCustomers.AsNoTracking()
                .CountAsync(c => c.StoreId == storeId && c.Deleted == null, ct);
            result["soNhaCungCap"] = await db.PosSuppliers.AsNoTracking()
                .CountAsync(s => s.StoreId == storeId && s.Deleted == null, ct);
            var sales = db.PosSaleOrders.AsNoTracking()
                .Where(o => o.StoreId == storeId && o.Deleted == null && o.Status == PosSaleOrderStatus.Completed);
            var first = await sales.MinAsync(o => (DateTime?)(o.SaleDate ?? o.CreatedAt), ct);
            var last = await sales.MaxAsync(o => (DateTime?)(o.SaleDate ?? o.CreatedAt), ct);
            result["ngayBanDauTien"] = first?.AddHours(AiAssistantVnTime.OffsetHours).ToString("yyyy-MM-dd");
            result["ngayBanGanNhat"] = last?.AddHours(AiAssistantVnTime.OffsetHours).ToString("yyyy-MM-dd");
        }

        if (!scope.SelfOnly && (Can("Employee") || Can("Department") || Can("AttendanceReport") || Can("Payslip")))
        {
            var depts = await db.Departments.AsNoTracking()
                .Where(d => d.StoreId == storeId && d.Deleted == null)
                .Select(d => new { d.Id, d.Name }).ToListAsync(ct);
            var scoped = scope.EmployeeIds;
            var emps = await db.Employees.AsNoTracking()
                .Where(e => e.StoreId == storeId && e.Deleted == null && e.WorkStatus == EmployeeWorkStatus.Active)
                .Where(e => scoped == null || scoped.Contains(e.Id))
                .Select(e => e.DepartmentId).ToListAsync(ct);
            result["phamViNhanSu"] = scope.Describe();
            result["soNhanVienDangLam"] = emps.Count;
            result["nhanVienTheoPhongBan"] = depts
                .Select(d => new { phongBan = d.Name, soNguoi = emps.Count(x => x == d.Id) })
                .Where(x => x.soNguoi > 0)
                .OrderByDescending(x => x.soNguoi)
                .ToList();
        }
        return result;
    }
}
