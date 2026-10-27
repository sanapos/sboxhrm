using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Trợ lý ảo: bot rule (dữ liệu cá nhân + hướng dẫn) và Gemini có công cụ báo cáo POS / HRM (phân tích).
/// </summary>
[ApiController]
[Route("api/ai/assistant")]
[Authorize]
public class AiAssistantController(
    ZKTecoDbContext db,
    IModulePermissionService modulePermissionService,
    IGeminiAiService geminiAiService,
    AiAssistantAgent agent,
    AiAssistantActions actions,
    AiVoiceService voice,
    IDataScopeService dataScope,
    IMemoryCache cache,
    ILogger<AiAssistantController> logger) : AuthenticatedControllerBase
{
    /// <summary>Câu hỏi số liệu giống hệt hỏi lại trong khoảng này → trả câu đã có, không tốn lượt AI.</summary>
    static readonly TimeSpan AnswerCacheTtl = TimeSpan.FromMinutes(3);

    public sealed record SpeakRequest(string Text, string? Voice, string? Language = null);

    /// <summary>Ghi âm → chữ (Gemini nghe, có từ vựng cửa hàng). 409 = cửa hàng chưa có AI → app dùng nhận dạng của máy.</summary>
    [HttpPost("transcribe")]
    [RequestSizeLimit(12 * 1024 * 1024)]
    public async Task<IActionResult> Transcribe(IFormFile audio, CancellationToken ct, [FromQuery] string? language = null)
    {
        if (audio == null || audio.Length == 0) return BadRequest(AppResponse<string>.Fail("Chưa có ghi âm"));
        if (!geminiAiService.IsConfigured || !geminiAiService.IsEnabled)
            return StatusCode(409, AppResponse<string>.Fail("Cửa hàng chưa bật AI"));
        await using var ms = new MemoryStream();
        await audio.CopyToAsync(ms, ct);
        try
        {
            var text = await voice.TranscribeAsync(ms.ToArray(), audio.ContentType, RequiredStoreId, ct, language);
            return Ok(AppResponse<string>.Success(text));
        }
        catch (AiApiException ex)
        {
            logger.LogWarning(ex, "AI transcribe failed");
            return StatusCode(ex.IsQuotaError ? 429 : 502, AppResponse<string>.Fail(ex.Message));
        }
    }

    /// <summary>Đọc câu trả lời bằng giọng Gemini TTS → audio/wav. Lỗi → app đọc bằng giọng của máy.</summary>
    [HttpPost("speak")]
    public async Task<IActionResult> Speak([FromBody] SpeakRequest dto, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(dto?.Text)) return BadRequest(AppResponse<string>.Fail("Thiếu nội dung"));
        if (!geminiAiService.IsConfigured || !geminiAiService.IsEnabled)
            return StatusCode(409, AppResponse<string>.Fail("Cửa hàng chưa bật AI"));
        try
        {
            var wav = await voice.SpeakAsync(dto.Text, dto.Voice, ct, dto.Language);
            return File(wav, "audio/wav");
        }
        catch (AiApiException ex)
        {
            logger.LogWarning(ex, "AI TTS failed");
            return StatusCode(ex.IsQuotaError ? 429 : 502, AppResponse<string>.Fail(ex.Message));
        }
    }

    [HttpGet("voices")]
    public IActionResult VoiceList() => Ok(AppResponse<object>.Success(new
    {
        defaultVoice = AiVoiceService.DefaultVoice,
        voices = AiVoiceService.Voices.Select(v => new { id = v.Key, label = v.Value }),
    }));

    public class ChatMessage
    {
        public string Role { get; set; } = "user"; // "user" | "assistant"
        public string Content { get; set; } = "";
    }

    public class ChatRequest
    {
        public List<ChatMessage> Messages { get; set; } = new();
        public string? Provider { get; set; } // "gemini" (only supported provider)
        /// <summary>Ngôn ngữ giao diện (vi / en / ko / ja / zh) — trợ lý trả lời bằng ngôn ngữ này.</summary>
        public string? Language { get; set; }
    }

    public class ChatResponse
    {
        public string Reply { get; set; } = "";
        public string Provider { get; set; } = "";
        public List<string> Actions { get; set; } = new();
        /// <summary>Structured create intents: "type,key=val,key=val" — Flutter parses and calls API directly.</summary>
        public List<string> Creates { get; set; } = new();
        /// <summary>Guide deep links: "basic/leave", "advanced/kpi".</summary>
        public List<string> Guides { get; set; } = new();
        /// <summary>Báo cáo trợ lý đã xem để trả lời (tên hiển thị).</summary>
        public List<string> Reports { get; set; } = new();
        /// <summary>Phiếu trợ lý đã dựng sẵn — chờ người dùng bấm Xác nhận.</summary>
        public List<PendingActionDto> PendingActions { get; set; } = new();
        /// <summary>Biểu đồ nhỏ minh họa số liệu trong câu trả lời (tối đa 2).</summary>
        public List<AiChart> Charts { get; set; } = new();
    }

    /// <param name="Risk">normal | high — high: app hiện thẻ đỏ, hỏi lại trước khi gửi xác nhận (acknowledged).</param>
    public sealed record PendingActionDto(
        string Id, string Kind, string Title, List<AiAssistantActions.Line> Lines, List<string> Warnings, string? OpenModule,
        string Risk = "normal");

    /// <param name="CanUndo">Hoàn tác được trong <see cref="AiAssistantActions.UndoWindow"/>.</param>
    /// <param name="NeedsAcknowledge">Thao tác rủi ro cao — gửi lại kèm acknowledged = true sau khi người dùng xác nhận lần hai.</param>
    public sealed record ActionResultDto(bool Ok, string Message, string? DocNo, string? OpenModule,
        bool CanUndo = false, int UndoSeconds = 0, bool NeedsAcknowledge = false);

    public sealed class ConfirmRequest
    {
        public bool Acknowledged { get; set; }
    }

    static ActionResultDto Dto(AiAssistantActions.ExecResult r) => new(r.Ok, r.Message, r.DocNo, r.OpenModule,
        r.CanUndo, r.CanUndo ? (int)AiAssistantActions.UndoWindow.TotalSeconds : 0, r.NeedsAcknowledge);

    /// <summary>Người dùng xác nhận phiếu trợ lý đề xuất → gọi API thật của app bằng phiên của họ.</summary>
    [HttpPost("actions/{id}/confirm")]
    public async Task<IActionResult> ConfirmAction(string id, [FromBody] ConfirmRequest? body, CancellationToken ct)
    {
        var r = await actions.ExecuteAsync(id, CurrentUserId, RequiredStoreId, ct, body?.Acknowledged == true);
        var dto = Dto(r);
        return Ok(r.Ok ? AppResponse<ActionResultDto>.Success(dto) : AppResponse<ActionResultDto>.Create(false, dto, [r.Message]));
    }

    [HttpPost("actions/{id}/discard")]
    public async Task<IActionResult> DiscardAction(string id, CancellationToken ct)
    {
        await actions.DiscardAsync(id, CurrentUserId, RequiredStoreId, ct);
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>Hoàn tác thao tác trợ lý vừa ghi (trong 10 phút, chỉ người đã xác nhận).</summary>
    [HttpPost("actions/{id}/undo")]
    public async Task<IActionResult> UndoAction(string id, CancellationToken ct)
    {
        var r = await actions.UndoAsync(id, CurrentUserId, RequiredStoreId, ct);
        return Ok(r.Ok ? AppResponse<ActionResultDto>.Success(Dto(r)) : AppResponse<ActionResultDto>.Fail(r.Message));
    }

    public sealed record RecentActionsDto(bool WholeStore, bool CanSeeWholeStore, List<AiAssistantActions.LogRow> Items);

    /// <summary>
    /// Nhật ký thao tác trợ lý: của chính người dùng; [all]=true → cả cửa hàng (chỉ chủ / người có quyền sửa thiết lập AI).
    /// </summary>
    [HttpGet("actions/recent")]
    public async Task<IActionResult> RecentActions([FromQuery] int take = 50, [FromQuery] bool all = false,
        [FromQuery] string? status = null, [FromQuery] bool highRisk = false, CancellationToken ct = default)
    {
        var canAll = await CanEditStoreProfileAsync(ct);
        var whole = all && canAll;
        var items = await actions.RecentAsync(CurrentUserId, RequiredStoreId, take, ct, whole, status, highRisk);
        return Ok(AppResponse<RecentActionsDto>.Success(new RecentActionsDto(whole, canAll, items)));
    }

    // ─── Hồ sơ cửa hàng cho trợ lý ───────────────────────────────────

    public sealed class StoreProfileDto
    {
        public string Content { get; set; } = "";
        public DateTime? UpdatedAt { get; set; }
        public int MaxLength { get; set; } = AiAssistantStoreKnowledge.MaxProfileChars;
        public bool CanEdit { get; set; }
    }

    async Task<bool> CanEditStoreProfileAsync(CancellationToken ct)
    {
        var role = CurrentUserRole;
        if (ModulePermissionDefaults.IsSuperRole(role)) return true;
        var perms = await modulePermissionService.GetEffectivePermissionsAsync(CurrentUserId, role, CurrentStoreId, ct);
        return perms.TryGetValue("AIGemini", out var p) && p.CanEdit;
    }

    [HttpGet("store-profile")]
    public async Task<IActionResult> GetStoreProfile(CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var row = await db.AiStoreProfiles.AsNoTracking().Where(p => p.StoreId == storeId)
            .Select(p => new { p.Content, p.UpdatedAt, p.CreatedAt }).FirstOrDefaultAsync(ct);
        return Ok(AppResponse<StoreProfileDto>.Success(new StoreProfileDto
        {
            Content = row?.Content ?? "", UpdatedAt = row?.UpdatedAt ?? row?.CreatedAt, CanEdit = await CanEditStoreProfileAsync(ct),
        }));
    }

    [HttpPut("store-profile")]
    public async Task<IActionResult> SaveStoreProfile([FromBody] StoreProfileDto dto, CancellationToken ct)
    {
        if (!await CanEditStoreProfileAsync(ct))
            return StatusCode(403, AppResponse<StoreProfileDto>.Fail("Tài khoản không có quyền sửa thiết lập Trợ lý AI."));
        var content = (dto?.Content ?? "").Trim();
        if (content.Length > AiAssistantStoreKnowledge.MaxProfileChars)
            return BadRequest(AppResponse<StoreProfileDto>.Fail($"Tối đa {AiAssistantStoreKnowledge.MaxProfileChars} ký tự."));
        var storeId = RequiredStoreId;
        var row = await db.AiStoreProfiles.AsTracking().FirstOrDefaultAsync(p => p.StoreId == storeId, ct);
        if (row == null)
        {
            row = new AiStoreProfile { Id = Guid.NewGuid(), StoreId = storeId, Content = content, CreatedBy = CurrentUserId.ToString() };
            db.AiStoreProfiles.Add(row);
        }
        else
        {
            row.Content = content;
            row.UpdatedAt = DateTime.UtcNow;
            row.UpdatedBy = CurrentUserId.ToString();
        }
        await db.SaveChangesAsync(ct);
        cache.Remove(AiAssistantStoreKnowledge.ProfileKey(storeId));
        return Ok(AppResponse<StoreProfileDto>.Success(new StoreProfileDto
        {
            Content = content, UpdatedAt = row.UpdatedAt ?? row.CreatedAt, CanEdit = true,
        }));
    }

    /// <summary>
    /// Chat với trợ lý ảo. Server nạp context cá nhân (profile, leave balance, attendance, payslip gần đây)
    /// rồi chuyển tới Gemini. AI có thể trả về text + tag ACTION gợi ý Flutter điều hướng.
    /// </summary>
    [HttpPost("chat")]
    public Task<IActionResult> Chat([FromBody] ChatRequest dto, CancellationToken ct) => ChatCoreAsync(dto, null, ct);

    static readonly System.Text.Json.JsonSerializerOptions SseJson = new(System.Text.Json.JsonSerializerDefaults.Web);

    /// <summary>
    /// Như <see cref="Chat"/> nhưng trả dần (Server-Sent Events): <c>status</c> (đang xem báo cáo…), <c>delta</c> (đoạn chữ
    /// mới), <c>reset</c> (bỏ chữ tạm), cuối cùng <c>done</c> = đúng phản hồi của /chat (status + body). Người dùng thấy chữ
    /// chạy ngay thay vì chờ cả câu trả lời; bot rule / câu đã lưu đệm chỉ có <c>done</c>.
    /// </summary>
    [HttpPost("chat/stream")]
    public async Task ChatStream([FromBody] ChatRequest dto, CancellationToken ct)
    {
        Response.ContentType = "text/event-stream; charset=utf-8";
        Response.Headers.CacheControl = "no-cache";
        Response.Headers["X-Accel-Buffering"] = "no"; // nginx không gom cả luồng rồi mới gửi
        var gate = new SemaphoreSlim(1, 1);
        async Task Send(string evt, object data)
        {
            await gate.WaitAsync(ct);
            try
            {
                await Response.WriteAsync($"event: {evt}\ndata: {System.Text.Json.JsonSerializer.Serialize(data, SseJson)}\n\n", ct);
                await Response.Body.FlushAsync(ct);
            }
            finally
            {
                gate.Release();
            }
        }
        IActionResult result;
        try
        {
            result = await ChatCoreAsync(dto, e => Send(e.Type, new { text = e.Text }), ct);
        }
        catch (OperationCanceledException) when (ct.IsCancellationRequested)
        {
            return; // người dùng đóng trợ lý giữa chừng
        }
        var obj = result as ObjectResult;
        await Send("done", new { status = obj?.StatusCode ?? 200, body = obj?.Value });
    }

    async Task<IActionResult> ChatCoreAsync(ChatRequest dto, Func<AiAssistantAgent.AgentEvent, Task>? onEvent, CancellationToken ct)
    {
        try
        {
            if (dto.Messages == null || dto.Messages.Count == 0)
                return BadRequest(AppResponse<ChatResponse>.Fail("Thiếu nội dung chat"));

            var lastUserMessage = dto.Messages.LastOrDefault(m =>
                string.Equals(m.Role, "user", StringComparison.OrdinalIgnoreCase));
            if (lastUserMessage == null || string.IsNullOrWhiteSpace(lastUserMessage.Content))
                return BadRequest(AppResponse<ChatResponse>.Fail("Tin nhắn trống"));

            var role = CurrentUserRole;
            var permMap = await modulePermissionService.GetEffectivePermissionsAsync(
                CurrentUserId, role, CurrentStoreId, ct);
            var isSuperUser = ModulePermissionDefaults.IsSuperRole(role);
            var allowedActions = AiAssistantPermissionRules.AllowedActionTags(permMap, isSuperUser);
            var allowedCreates = AiAssistantPermissionRules.AllowedCreateExamples(permMap, isSuperUser);
            // Phạm vi nhân sự của người hỏi (cả cửa hàng / cấp dưới / chỉ bản thân) — mọi tra cứu trực tiếp của trợ lý lọc theo.
            var scope = await AiAssistantScope.ResolveAsync(db, dataScope, HttpContext, CurrentUserId, RequiredStoreId, role, ct);

            var contextText = await AiAssistantContextBuilder.BuildAsync(
                db, CurrentUserId, RequiredStoreId, role, logger, ct, permMap, isSuperUser, scope);
            contextText += "\n\n=== QUYỀN TÀI KHOẢN ===\n";
            contextText += AiAssistantPermissionRules.BuildPermissionsSummary(permMap, isSuperUser, role);

            var extra = await AiAssistantQueryTools.BuildExtraContextAsync(
                db, CurrentUserId, RequiredStoreId, role, lastUserMessage.Content,
                permMap, isSuperUser, logger, ct, scope);
            if (!string.IsNullOrWhiteSpace(extra))
                contextText += "\n\n" + extra;

            // Gợi ý GUIDE từ kết quả search (kể cả khi model quên tag)
            var helpHits = AiAssistantHelpCorpus.Search(lastUserMessage.Content, topK: 4);
            var suggestedGuides = helpHits
                .Select(h => $"{h.Mode}/{h.StepId}")
                .Distinct()
                .ToList();
            // Bổ sung ACTION từ help nếu user hỏi hướng dẫn
            foreach (var hit in helpHits)
            {
                foreach (var tag in hit.ActionTags)
                {
                    if (AiAssistantPermissionRules.CanAction(tag, permMap, isSuperUser)
                        && !allowedActions.Contains(tag))
                        allowedActions.Add(tag);
                }
            }

            // Đường dẫn menu đúng tên trên app — chỉ các mục người hỏi được xem.
            var menuPaths = AiAssistantMenuMap.Paths
                .Where(kv => isSuperUser || (permMap.TryGetValue(kv.Key, out var mp) && mp.CanView))
                .Select(kv => $"{kv.Value} [{kv.Key}]")
                .Distinct()
                .OrderBy(p => p, StringComparer.Ordinal)
                .ToList();
            bool CanView(string m) => isSuperUser || (permMap.TryGetValue(m, out var mp) && mp.CanView);
            var storeKnowledge = await AiAssistantStoreKnowledge.BuildAsync(db, cache, RequiredStoreId,
                pos: CanView("PosSell") || CanView("PosProducts") || CanView("PosSalesReport"),
                hr: scope.WholeStore && (CanView("Employee") || CanView("Department")), logger, ct);
            var lang = AiLanguage.Normalize(dto.Language);
            var systemPrompt = AiAssistantPromptBuilder.Build(
                contextText, allowedActions, allowedCreates, suggestedGuides, menuPaths, storeKnowledge, lang);
            logger.LogInformation(
                "AI assistant context for {UserId}: {Length} chars, digest: {Digest}",
                CurrentUserId,
                contextText.Length,
                AiAssistantContextBuilder.BuildDigest(contextText));

            // 12 lượt gần nhất; câu trả lời dài cũ chỉ giữ phần đầu — mỗi vòng gọi AI đều gửi lại toàn bộ lịch sử.
            var chatTurns = dto.Messages
                .Where(m => !string.IsNullOrWhiteSpace(m.Content))
                .Where(m => !IsBoilerplateAssistantMessage(m))
                .TakeLast(12)
                .Select(m => (
                    Role: string.Equals(m.Role, "assistant", StringComparison.OrdinalIgnoreCase)
                        ? "assistant" : "user",
                    Content: m.Content.Trim()))
                .ToList();
            for (var i = 0; i < chatTurns.Count - 2; i++)
                if (chatTurns[i].Role == "assistant" && chatTurns[i].Content.Length > 700)
                    chatTurns[i] = (chatTurns[i].Role, chatTurns[i].Content[..700] + "…");
            var userTurns = dto.Messages.Where(m => string.Equals(m.Role, "user", StringComparison.OrdinalIgnoreCase))
                .Select(m => m.Content).ToList();
            var recentUser = userTurns.TakeLast(3).ToList();

            // Ghim tóm tắt dữ liệu vào câu hỏi cuối — tránh model bỏ qua system instruction dài.
            if (chatTurns.Count > 0)
            {
                var digest = AiAssistantContextBuilder.BuildDigest(contextText);
                var last = chatTurns[^1];
                if (last.Role == "user")
                {
                    chatTurns[^1] = (
                        "user",
                        $"[Dữ liệu hệ thống đã nạp]\n{digest}\n\n[Câu hỏi]\n{last.Content}");
                }
            }

            if (string.Equals(dto.Provider, "deepseek", StringComparison.OrdinalIgnoreCase))
            {
                return BadRequest(AppResponse<ChatResponse>.Fail(
                    "DeepSeek đã ngừng hỗ trợ. Hệ thống dùng bot nội bộ và Google Gemini."));
            }

            var geminiOk = geminiAiService.IsConfigured && geminiAiService.IsEnabled;
            // Thêm / sửa / xóa / duyệt bằng lời → agent có công cụ đề xuất (bot rule chỉ mở form). Câu trả lời ngắn tiếp
            // theo một lệnh («ừ, 500k», «người thứ hai») vẫn thuộc lệnh đó → xét cả vài câu trước.
            var lastText = lastUserMessage.Content;
            // Bộ dò từ khóa (ý định, bot rule) chỉ hiểu tiếng Việt — câu tiếng Anh / Hàn / Nhật / Trung để Gemini tự hiểu,
            // kèm đủ công cụ thao tác (tốn token hơn nhưng không bỏ sót lệnh).
            var vi = lang == AiLanguage.Vietnamese;
            var withActions = !vi || AiAssistantIntent.LooksLikeAction(lastText)
                              || (!AiAssistantAgent.LooksAnalytical(lastText) && recentUser.SkipLast(1).Any(AiAssistantIntent.LooksLikeAction));
            var toolGroups = withActions && vi ? AiAssistantIntent.Groups(recentUser) : null;
            // Câu hỏi phân tích / báo cáo → đi thẳng agent (gọi báo cáo thật); câu cá nhân đơn giản → bot rule (nhanh, không tốn lượt).
            var analytical = geminiOk && (!vi || AiAssistantAgent.LooksAnalytical(lastText) || withActions);
            var rule = analytical
                ? new AiAssistantRuleResult(false, "")
                : AiAssistantRuleBot.Build(
                    lastUserMessage.Content, contextText, helpHits,
                    allowedActions, allowedCreates, includeFallback: !geminiOk);
            var reportsUsed = new List<string>();
            var proposed = new List<AiAssistantActions.Pending>();
            logger.LogInformation("AI chat route: gemini={GeminiOk} analytical={Analytical} rule={Rule}",
                geminiOk, analytical, rule.Matched);

            string reply;
            string usedProvider;
            if (!geminiOk && AiAssistantAgent.LooksAnalytical(lastUserMessage.Content)
                && geminiAiService is TenantScopedGeminiAiService { SharedBlocked: true })
            {
                // Câu phân tích cần AI: cửa hàng chưa có khóa riêng, gói không cho dùng khóa chung.
                reply = "Trợ lý ảo trả lời được dữ liệu cá nhân và hướng dẫn. Để phân tích báo cáo bán hàng / nhân sự: "
                        + TenantScopedGeminiAiService.NoOwnKeyMessage;
                usedProvider = "sbox";
            }
            else if (rule.Matched)
            {
                reply = rule.Reply;
                usedProvider = "sbox";
            }
            else if (!withActions && userTurns.Count == 1
                     && cache.TryGetValue(AnswerKey(lastText, lang), out ChatResponse? cachedAnswer) && cachedAnswer != null)
            {
                // Hỏi lại đúng câu số liệu vừa hỏi (mở lại trợ lý, bấm gợi ý hai lần) → không tốn thêm lượt AI.
                logger.LogInformation("AI chat: answer cache hit");
                return Ok(AppResponse<ChatResponse>.Success(cachedAnswer));
            }
            else
            {
                try
                {
                    var result = await agent.RunAsync(
                        systemPrompt, chatTurns, RequiredStoreId, permMap, isSuperUser, ct, CurrentUserId, role,
                        new AiAssistantAgent.Options(scope, lastText, withActions, toolGroups, onEvent));
                    reply = result.Reply;
                    reportsUsed = result.ReportsUsed;
                    proposed = result.Proposed;
                    usedProvider = "gemini";
                }
                catch (Exception gemEx) when (gemEx is not OperationCanceledException)
                {
                    logger.LogWarning(gemEx, "Gemini failed — falling back to rule bot");
                    usedProvider = "sbox";
                    if (analytical)
                    {
                        // Bot rule không phân tích được — báo rõ thay vì trả lời lạc đề.
                        var why = gemEx is AiApiException { IsQuotaError: true }
                            ? "Trợ lý ảo đang hết lượt phân tích (giới hạn của khóa AI)."
                            : "Máy chủ AI đang bận.";
                        reply = why + " Bạn thử lại sau khoảng 1 phút, hoặc mở trực tiếp màn Báo cáo để xem số liệu.";
                    }
                    else
                    {
                        rule = AiAssistantRuleBot.Build(
                            lastUserMessage.Content, contextText, helpHits,
                            allowedActions, allowedCreates, includeFallback: true);
                        reply = rule.Reply;
                    }
                }
            }

            var parsed = AiAssistantReplyParser.Parse(
                reply, permMap, isSuperUser, suggestedGuides, lastUserMessage.Content);

            var response = new ChatResponse
            {
                Reply = parsed.Text,
                Provider = usedProvider,
                Actions = parsed.Actions,
                Guides = parsed.Guides,
                Reports = reportsUsed.Distinct().Select(AiAssistantReportCatalog.TitleOf).ToList(),
                // Chỉ vẽ khi số liệu lấy từ báo cáo thật (không vẽ số bot rule / AI tự nghĩ ra).
                Charts = reportsUsed.Count > 0 ? parsed.Charts ?? [] : [],
                PendingActions = proposed
                    .Select(p => new PendingActionDto(p.Id, p.Kind, p.Title, p.Lines, p.Warnings, p.OpenModule, p.Risk))
                    .ToList(),
                // Đã có thẻ xác nhận thì bỏ thẻ CREATE cũ (tránh hai nút cho cùng một phiếu).
                Creates = proposed.Count > 0 ? new List<string>() : parsed.Creates,
            };
            if (usedProvider == "gemini" && !withActions && proposed.Count == 0 && userTurns.Count == 1 && reportsUsed.Count > 0)
                cache.Set(AnswerKey(lastText, lang), response,
                    new MemoryCacheEntryOptions { AbsoluteExpirationRelativeToNow = AnswerCacheTtl, Size = 1 });
            return Ok(AppResponse<ChatResponse>.Success(response));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "AI Assistant chat failed");
            return StatusCode(500, AppResponse<ChatResponse>.Fail("Lỗi trợ lý ảo: " + ex.Message));
        }
    }

    /// <summary>Khóa đệm câu trả lời: theo người hỏi (quyền + phạm vi riêng), ngôn ngữ trả lời và câu hỏi đã bỏ dấu.</summary>
    string AnswerKey(string question, string lang) =>
        $"ai-answer:{RequiredStoreId}:{CurrentUserId}:{lang}:{VnSearch.FoldText(question)}";

    private static bool IsBoilerplateAssistantMessage(ChatMessage m)
    {
        if (!string.Equals(m.Role, "assistant", StringComparison.OrdinalIgnoreCase))
            return false;
        var c = m.Content.Trim();
        // Lời chào mở đầu của app không mang thông tin — không gửi lại cho AI (đỡ token mỗi lượt).
        return c.StartsWith("Xin chào! Tôi là trợ lý", StringComparison.OrdinalIgnoreCase)
               || c.StartsWith("Xin chào! Tôi trả lời phép", StringComparison.Ordinal)
               || c.StartsWith("⚠️", StringComparison.Ordinal)
               || c.StartsWith("❌", StringComparison.Ordinal)
               || c.StartsWith("✅ Đã tạo", StringComparison.Ordinal)
               || c.StartsWith("📋 Đã mở", StringComparison.Ordinal);
    }

}
#if false // removed legacy context — see AiAssistantContextBuilder
    private async Task<string> BuildUserContextAsync_Legacy(CancellationToken ct)
    {
        var userId = CurrentUserId;
        var storeId = CurrentStoreId;
        var role = string.Empty;
        try { role = CurrentUserRole; } catch { /* token may not have role */ }
        var buf = new StringBuilder();

        try
        {
            buf.AppendLine($"Vai trò: {(string.IsNullOrEmpty(role) ? "(không rõ)" : role)}");

            // Profile
            var emp = await db.Employees
                .AsNoTracking()
                .Where(e => e.ApplicationUserId == userId)
                .Select(e => new
                {
                    e.Id,
                    e.EmployeeCode,
                    e.FirstName,
                    e.LastName,
                    e.DepartmentId,
                    e.Position,
                    e.JoinDate
                })
                .FirstOrDefaultAsync(ct);

            if (emp != null)
            {
                var dept = emp.DepartmentId.HasValue
                    ? await db.Departments.AsNoTracking()
                        .Where(d => d.Id == emp.DepartmentId.Value)
                        .Select(d => d.Name)
                        .FirstOrDefaultAsync(ct)
                    : null;

                buf.AppendLine($"Họ tên: {emp.LastName} {emp.FirstName}");
                buf.AppendLine($"Mã NV: {emp.EmployeeCode}");
                if (!string.IsNullOrEmpty(emp.Position)) buf.AppendLine($"Chức vụ: {emp.Position}");
                if (!string.IsNullOrEmpty(dept)) buf.AppendLine($"Phòng ban: {dept}");
                if (emp.JoinDate.HasValue) buf.AppendLine($"Ngày vào làm: {emp.JoinDate.Value:dd/MM/yyyy}");
            }
            else
            {
                buf.AppendLine("(Chưa liên kết hồ sơ nhân viên)");
            }

            var today = DateTime.UtcNow.Date;
            var startOfYear = new DateTime(today.Year, 1, 1);

            // Leaves: pending + recent + total this year
            var leaves = await db.Leaves
                .AsNoTracking()
                .Where(l => l.EmployeeUserId == userId && l.StartDate >= today.AddDays(-90))
                .OrderByDescending(l => l.StartDate)
                .Take(10)
                .Select(l => new { l.StartDate, l.EndDate, l.Status, l.Type, l.Reason })
                .ToListAsync(ct);

            var leavesYearStats = await db.Leaves
                .AsNoTracking()
                .Where(l => l.EmployeeUserId == userId && l.StartDate >= startOfYear)
                .GroupBy(l => l.Status)
                .Select(g => new { Status = g.Key, Count = g.Count() })
                .ToListAsync(ct);

            if (leavesYearStats.Count > 0)
            {
                buf.AppendLine();
                buf.AppendLine("Tổng số đơn nghỉ năm nay (theo trạng thái):");
                foreach (var s in leavesYearStats)
                    buf.AppendLine($"- {s.Status}: {s.Count} đơn");
            }
            if (leaves.Count > 0)
            {
                buf.AppendLine();
                buf.AppendLine("Lịch sử nghỉ phép (90 ngày gần nhất):");
                foreach (var l in leaves)
                {
                    buf.AppendLine(
                        $"- {l.StartDate:dd/MM/yyyy}..{l.EndDate:dd/MM/yyyy} | Loại {(int)l.Type} | {l.Status}");
                }
            }

            // Attendance: last 7 days count + 30 days summary
            var weekAgo = today.AddDays(-7);
            var monthAgo = today.AddDays(-30);
            var empId = emp?.Id;
            if (empId.HasValue)
            {
                var attCount7 = await db.AttendanceLogs
                    .AsNoTracking()
                    .Where(a => a.AttendanceTime >= weekAgo && a.EmployeeId == empId.Value)
                    .CountAsync(ct);
                var attCount30 = await db.AttendanceLogs
                    .AsNoTracking()
                    .Where(a => a.AttendanceTime >= monthAgo && a.EmployeeId == empId.Value)
                    .CountAsync(ct);
                buf.AppendLine();
                buf.AppendLine($"Chấm công 7 ngày gần đây: {attCount7} lượt | 30 ngày: {attCount30} lượt");
            }

            // Advance requests recent
            var advances = await db.AdvanceRequests
                .AsNoTracking()
                .Where(a => a.EmployeeUserId == userId && a.RequestDate >= today.AddDays(-180))
                .OrderByDescending(a => a.RequestDate)
                .Take(5)
                .Select(a => new { a.RequestDate, a.Amount, a.Status, a.Reason })
                .ToListAsync(ct);
            if (advances.Count > 0)
            {
                buf.AppendLine();
                buf.AppendLine("Yêu cầu ứng lương (180 ngày gần nhất):");
                foreach (var a in advances)
                    buf.AppendLine($"- {a.RequestDate:dd/MM/yyyy} | {a.Amount:N0}đ | {a.Status} | {a.Reason}");
            }

            // Last 3 payslips
            var payslips = await db.Payslips
                .AsNoTracking()
                .Where(p => p.EmployeeUserId == userId)
                .OrderByDescending(p => p.Year).ThenByDescending(p => p.Month)
                .Take(3)
                .Select(p => new { p.Year, p.Month, p.NetSalary, p.Status })
                .ToListAsync(ct);
            if (payslips.Count > 0)
            {
                buf.AppendLine();
                buf.AppendLine("Phiếu lương gần nhất:");
                foreach (var p in payslips)
                    buf.AppendLine($"- {p.Month:D2}/{p.Year}: {p.NetSalary:N0}đ ({p.Status})");
            }

            // Manager-only: pending approvals + today attendance/absent summary
            var roleLower = role.ToLowerInvariant();
            if (roleLower == "owner" || roleLower == "admin" || roleLower == "director" ||
                roleLower == "manager" || roleLower == "departmenthead")
            {
                try
                {
                    var pendingLeaves = await db.Leaves.AsNoTracking()
                        .Where(l => l.StoreId == storeId && l.Status == Domain.Enums.LeaveStatus.Pending)
                        .CountAsync(ct);
                    var pendingAdv = await db.AdvanceRequests.AsNoTracking()
                        .Where(a => a.StoreId == storeId && a.Status == Domain.Enums.AdvanceRequestStatus.Pending)
                        .CountAsync(ct);
                    buf.AppendLine();
                    buf.AppendLine("Đơn chờ duyệt (toàn cửa hàng):");
                    buf.AppendLine($"- Nghỉ phép: {pendingLeaves} | Ứng lương: {pendingAdv}");
                }
                catch { /* ignore */ }

                // Today's attendance vs leave cross-reference (nghỉ có phép / nghỉ không phép)
                try
                {
                    var todayVn = DateTime.UtcNow.AddHours(7).Date;
                    var tomorrowVn = todayVn.AddDays(1);

                    // All active employees in this store
                    var activeEmps = await db.Employees
                        .AsNoTracking()
                        .Where(e => e.StoreId == storeId && e.WorkStatus == Domain.Enums.EmployeeWorkStatus.Active)
                        .Select(e => new { e.Id, e.ApplicationUserId, e.FirstName, e.LastName })
                        .ToListAsync(ct);

                    var activeEmpIds = activeEmps.Select(e => e.Id).ToList();
                    var activeUserIds = activeEmps
                        .Where(e => e.ApplicationUserId.HasValue)
                        .Select(e => e.ApplicationUserId!.Value)
                        .ToList();

                    // Employees who checked in today (any punch counts as present)
                    var checkedInEmpIds = await db.AttendanceLogs
                        .AsNoTracking()
                        .Where(a => a.AttendanceTime >= todayVn && a.AttendanceTime < tomorrowVn
                                    && a.EmployeeId.HasValue && activeEmpIds.Contains(a.EmployeeId.Value))
                        .Select(a => a.EmployeeId!.Value)
                        .Distinct()
                        .ToListAsync(ct);

                    // Employees with approved leave covering today
                    var approvedLeaveUserIds = await db.Leaves
                        .AsNoTracking()
                        .Where(l => l.StoreId == storeId
                                    && l.Status == Domain.Enums.LeaveStatus.Approved
                                    && l.StartDate.Date <= todayVn && l.EndDate.Date >= todayVn
                                    && activeUserIds.Contains(l.EmployeeUserId))
                        .Select(l => l.EmployeeUserId)
                        .Distinct()
                        .ToListAsync(ct);

                    var absentWithLeave = activeEmps
                        .Where(e => !checkedInEmpIds.Contains(e.Id)
                                    && e.ApplicationUserId.HasValue
                                    && approvedLeaveUserIds.Contains(e.ApplicationUserId.Value))
                        .ToList();

                    var absentNoLeave = activeEmps
                        .Where(e => !checkedInEmpIds.Contains(e.Id)
                                    && !(e.ApplicationUserId.HasValue
                                         && approvedLeaveUserIds.Contains(e.ApplicationUserId.Value)))
                        .ToList();

                    buf.AppendLine();
                    buf.AppendLine($"Tình hình nhân sự hôm nay ({todayVn:dd/MM/yyyy}):");
                    buf.AppendLine($"- Tổng nhân viên (đang làm việc): {activeEmps.Count}");
                    buf.AppendLine($"- Đã chấm công: {checkedInEmpIds.Count}");
                    buf.AppendLine($"- Vắng CÓ PHÉP (đơn nghỉ được duyệt): {absentWithLeave.Count}");
                    buf.AppendLine($"- Vắng KHÔNG PHÉP (không chấm công, không có đơn duyệt): {absentNoLeave.Count}");

                    if (absentWithLeave.Count > 0)
                    {
                        buf.AppendLine("Danh sách nghỉ CÓ PHÉP hôm nay:");
                        foreach (var e in absentWithLeave.Take(20))
                            buf.AppendLine($"  • {e.LastName} {e.FirstName}");
                        if (absentWithLeave.Count > 20)
                            buf.AppendLine($"  ...và {absentWithLeave.Count - 20} người khác");
                    }

                    if (absentNoLeave.Count > 0)
                    {
                        buf.AppendLine("Danh sách vắng KHÔNG PHÉP hôm nay:");
                        foreach (var e in absentNoLeave.Take(20))
                            buf.AppendLine($"  • {e.LastName} {e.FirstName}");
                        if (absentNoLeave.Count > 20)
                            buf.AppendLine($"  ...và {absentNoLeave.Count - 20} người khác");
                    }
                }
                catch (Exception ex)
                {
                    logger.LogWarning(ex, "Failed to load today absent summary");
                }
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "BuildUserContext partial failure");
            buf.AppendLine("(Không tải được đầy đủ context)");
        }

        return buf.ToString();
    }

    private static string BuildSystemPrompt(
        string userContext,
        IReadOnlyList<string> allowedActions,
        IReadOnlyList<string> allowedCreates)
    {
        var actionLines = allowedActions.Count > 0
            ? string.Join("\n", allowedActions.Select(a => $"- [[ACTION:{a}]]"))
            : "- (Không có thẻ ACTION — chỉ trả lời câu hỏi, không điều hướng)";
        var createList = allowedCreates.Count > 0
            ? string.Join(", ", allowedCreates)
            : "(không có)";

        return $@"Bạn là Trợ lý ảo HRM của hệ thống SBOX HRM, chuyên hỗ trợ nhân viên và quản lý bằng tiếng Việt.

NGUYÊN TẮC:
- Luôn trả lời BẰNG TIẾNG VIỆT, ngắn gọn, thân thiện, chuyên nghiệp.
- Chỉ trả lời dựa trên DỮ LIỆU CÁ NHÂN của chính người dùng được cung cấp bên dưới.
- KHÔNG bịa số liệu. Nếu không đủ thông tin, nói thẳng ""Tôi không thể truy cập dữ liệu này"".
- Tôn trọng phân quyền: CHỈ gợi ý thao tác/tạo phiếu mà tài khoản ĐƯỢC PHÉP (danh sách thẻ ACTION/CREATE bên dưới).
- Nếu người dùng yêu cầu chức năng KHÔNG có trong danh sách được phép → trả lời: ""Tài khoản của bạn không có quyền thực hiện thao tác này."" — KHÔNG gắn thẻ ACTION/CREATE.
- Nếu user là nhân viên (Employee) thì chỉ nói về dữ liệu CỦA HỌ. Nếu là quản lý/admin thì có thể nói về số đơn chờ duyệt toàn cửa hàng (đã cung cấp ở context).
- Khi người dùng muốn thực hiện tác vụ (tạo/sửa/xem) VÀ có quyền, hãy hướng dẫn ngắn gọn VÀ kèm thẻ hành động ở cuối tin nhắn.

XỬ LÝ CÂU HỎI DỮ LIỆU TỔ CHỨC (quan trọng):
- Nếu trong phần ""Tình hình nhân sự hôm nay"" ở context có dữ liệu → DÙNG DỮ LIỆU ĐÓ để trả lời trực tiếp khi người dùng hỏi ""hôm nay ai nghỉ"", ""ai vắng không phép"", ""danh sách vắng mặt"" v.v. Đây là dữ liệu thật, không bịa.
- LƯU Ý: Danh sách ""vắng KHÔNG PHÉP"" có thể bao gồm nhân viên nghỉ ngày nghỉ trong tuần (thứ 7, CN) hoặc nghỉ lễ — hãy nhắc điều này khi trả lời nếu số lượng lớn bất thường.
- Nếu KHÔNG có dữ liệu tình hình nhân sự trong context (user là nhân viên thường, không phải quản lý) → Trả lời: ""Tôi không thể truy cập dữ liệu này. Bạn có thể xem tại đây:"" + kèm thẻ điều hướng phù hợp.
- Câu hỏi vắng mặt/nghỉ phép của người khác mà không có dữ liệu → kèm [[ACTION:nav_leave]]
- Câu hỏi chấm công của người khác mà không có dữ liệu → kèm [[ACTION:nav_attendance_history]]
- Câu hỏi dữ liệu khác mà không có trong context → chỉ nói ""Tôi không thể truy cập dữ liệu này"".

XỬ LÝ ĐẦU VÀO GIỌNG NÓI:
- Câu hỏi có thể nhập qua MICRO nên có thể NHẬN DẠNG SAI, THIẾU DẤU, SAI CHÍNH TẢ.
- Tự động ĐOÁN Ý theo NGỮ CẢNH HRM. KHÔNG yêu cầu người dùng nói lại.
- VD đoán: ""chấm cong""→""chấm công""; ""nghi phep""→""nghỉ phép""; ""ung luong""→""ứng lương""; ""tang ca""→""tăng ca""; ""di cong tac""→""đi công tác"".
- KHÔNG nhắc lại lỗi nhận dạng.

THẺ ACTION ĐƯỢC PHÉP DÙNG (CHỈ các thẻ sau — đặt CUỐI tin nhắn, mỗi thẻ 1 dòng):
{actionLines}

QUY TẮC DÙNG THẺ:
- Người dùng nói ""thêm"", ""tạo"", ""đăng ký"", ""xin"", ""gửi"" → ưu tiên thẻ ""_create"".
- Người dùng nói ""xem"", ""danh sách"", ""kiểm tra"", ""trạng thái"", ""bao nhiêu"" → dùng thẻ xem.
- Tối đa 2 thẻ ACTION mỗi câu trả lời. Đặt ở cuối, mỗi thẻ 1 dòng.
- Tuyệt đối KHÔNG đặt thẻ giữa câu.

— TẠO PHIẾU TRỰC TIẾP (thẻ [[CREATE:...]]) —
Khi người dùng muốn TẠO một phiếu VÀ đã cung cấp đầy đủ dữ liệu bắt buộc → dùng thẻ [[CREATE:...]] thay cho [[ACTION:...]].
Hệ thống sẽ tạo phiếu trực tiếp khi người dùng nhấn xác nhận, KHÔNG cần mở màn hình.

LOẠI CREATE ĐƯỢC PHÉP: {createList}
(Chỉ hướng dẫn / gắn thẻ CREATE cho các loại trên.)

LOẠI TẠO HỖ TRỢ (chi tiết — chỉ dùng nếu loại đó nằm trong danh sách được phép):
1. Phiếu sửa giờ / báo quên chấm công (attendance_correction):
   Dữ liệu bắt buộc: ngày + giờ + lý do
   Thẻ: [[CREATE:attendance_correction,date=YYYY-MM-DD,time=HH:MM,action=add,reason=lý do không có dấu phẩy]]
   - action=add (thêm lần chấm mới / quên chấm) hoặc action=edit (sửa giờ chấm sai)
   - date: ngày theo định dạng YYYY-MM-DD (""hôm nay"" = {DateTime.UtcNow.AddHours(7).ToString("yyyy-MM-dd")})
   - time: giờ theo HH:MM
   - reason: KHÔNG dùng dấu phẩy trong lý do; thay bằng dấu gạch ngang hoặc chữ khác
   Ví dụ: [[CREATE:attendance_correction,date=2026-05-07,time=13:00,action=add,reason=quên chấm công buổi chiều]]

2. Phiếu nghỉ phép (mở form, user chọn ca):
   Thẻ: [[CREATE:leave,date=YYYY-MM-DD,reason=lý do,type=0]]
   - date: ngày nghỉ; type: 0=phép năm, 1=ốm, 2=việc riêng (mặc định 0)
   - Thiếu ngày hoặc lý do → hỏi lại hoặc dùng [[ACTION:nav_leave_create]]

3. Ứng lương:
   Nếu có số tiền + lý do: [[CREATE:advance,amount=5000000,reason=lý do]]
   Nếu thiếu số tiền: [[ACTION:nav_advance_create]] hoặc [[CREATE:advance,reason=lý do]] (mở form)
   - amount: số VNĐ, không dấu phẩy/chấm phân cách

4. Phản ánh / ý kiến:
   Nếu đủ tiêu đề + nội dung: [[CREATE:feedback,title=tiêu đề,content=nội dung,category=General]]
   - category: General | Complaint | Suggestion | Other
   - Thiếu → [[ACTION:nav_feedback_create]]

5. Chấm cơm / báo ăn (mở form):
   [[CREATE:meal,date=YYYY-MM-DD,time=HH:MM,session=trưa]]
   - session: tên buổi (sáng/trưa/tối) — hệ thống khớp gần đúng
   - Thiếu → [[ACTION:nav_meal_register]]

6. Giao điểm công tác (quản lý, mở form):
   [[CREATE:field_assignment,employeeId=...,locationId=...,dayOfWeek=1]]
   - dayOfWeek: 1=T2 … 7=CN; bỏ trống = tất cả ngày
   - Thiếu → [[ACTION:nav_field_checkin_create]]

7. Đổi ca:
   [[CREATE:shift_swap,date=YYYY-MM-DD,note=ghi chú]]
   - date: ngày ca muốn đổi; hệ thống mở form đổi ca nếu tìm được ca đã duyệt
   - Thiếu ngày → [[ACTION:nav_shift_change]]

8. Nếu thiếu dữ liệu → hỏi lại thông tin còn thiếu, KHÔNG phát thẻ CREATE.
9. Nếu người dùng chưa xác nhận → mô tả ngắn gọn thông tin sẽ tạo + kèm thẻ CREATE để họ nhấn xác nhận.
10. Chỉ 1 thẻ CREATE mỗi câu trả lời.

=== THÔNG TIN NGƯỜI DÙNG ===
{userContext}
=== HẾT THÔNG TIN ===

Bắt đầu trả lời câu hỏi của người dùng.";
    }
#endif
