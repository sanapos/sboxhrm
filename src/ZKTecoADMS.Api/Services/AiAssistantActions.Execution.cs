using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Xác nhận / bỏ / hoàn tác đề xuất của trợ lý. Đề xuất lưu ở bảng AiActionLogs (bộ nhớ đệm chỉ để đọc nhanh) nên:
/// khởi động lại máy chủ không mất thẻ, bấm hai lần chỉ ghi một lần, và có nhật ký «ai nhờ AI làm gì, kết quả ra sao».
/// </summary>
public sealed partial class AiAssistantActions
{
    /// <summary>Thẻ chờ xác nhận còn hiệu lực bao lâu.</summary>
    static readonly TimeSpan ProposalLifetime = TimeSpan.FromHours(24);

    /// <summary>Hoàn tác được trong bao lâu sau khi ghi.</summary>
    public static readonly TimeSpan UndoWindow = TimeSpan.FromMinutes(10);

    static string Key(string id) => "ai-action:" + id;

    static readonly JsonSerializerOptions StoreJson = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

    void CacheSet(Pending p) =>
        cache.Set(Key(p.Id), p, new MemoryCacheEntryOptions { AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(30), Size = 1 });

    /// <summary>Lưu đề xuất (bộ nhớ đệm + nhật ký). Bảng nhật ký lỗi (chưa chạy patch) không chặn trợ lý.</summary>
    async Task RememberAsync(Pending p, Ctx c, CancellationToken ct)
    {
        CacheSet(p);
        if (!Guid.TryParseExact(p.Id, "N", out var logId)) return;
        var log = new AiActionLog
        {
            Id = logId, StoreId = p.StoreId, UserId = p.UserId, Kind = p.Kind, Title = p.Title, Risk = p.Risk,
            Prompt = c.Prompt.Length > 2000 ? c.Prompt[..2000] : c.Prompt,
            PendingJson = JsonSerializer.Serialize(p, StoreJson), Status = "proposed",
        };
        try
        {
            db.AiActionLogs.Add(log);
            await db.SaveChangesAsync(ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            db.Entry(log).State = EntityState.Detached;
            logger.LogWarning(ex, "AI action log not saved ({Kind})", p.Kind);
        }
        finally
        {
            if (db.Entry(log).State != EntityState.Detached) db.Entry(log).State = EntityState.Detached;
        }
    }

    public async Task<Pending?> GetAsync(string id, Guid userId, Guid storeId, CancellationToken ct)
    {
        if (cache.TryGetValue(Key(id), out Pending? p) && p != null)
            return p.UserId == userId && p.StoreId == storeId ? p : null;
        if (!Guid.TryParseExact(id, "N", out var logId)) return null;
        try
        {
            var since = DateTime.UtcNow - ProposalLifetime;
            var json = await db.AiActionLogs.AsNoTracking()
                .Where(l => l.Id == logId && l.UserId == userId && l.StoreId == storeId && l.Status == "proposed" && l.CreatedAt >= since)
                .Select(l => l.PendingJson).FirstOrDefaultAsync(ct);
            return string.IsNullOrEmpty(json) ? null : JsonSerializer.Deserialize<Pending>(json, StoreJson);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "AI action log read failed");
            return null;
        }
    }

    /// <summary>
    /// Chuyển trạng thái nhật ký nguyên tử (vd proposed → running). false = đã có lời xác nhận khác xử lý trước.
    /// null = bảng nhật ký không dùng được → chỉ dựa vào bộ nhớ đệm như trước.
    /// </summary>
    async Task<bool?> TransitionAsync(string id, string from, string to, CancellationToken ct)
    {
        if (!Guid.TryParseExact(id, "N", out var logId)) return null;
        try
        {
            var n = await db.AiActionLogs.Where(l => l.Id == logId && l.Status == from)
                .ExecuteUpdateAsync(s => s.SetProperty(l => l.Status, to).SetProperty(l => l.UpdatedAt, DateTime.UtcNow), ct);
            if (n > 0) return true;
            return await db.AiActionLogs.AnyAsync(l => l.Id == logId, ct) ? false : null;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "AI action log transition failed");
            return null;
        }
    }

    async Task FinishLogAsync(string id, string status, ExecResult r, string? docId, List<Step>? undo, CancellationToken ct)
    {
        if (!Guid.TryParseExact(id, "N", out var logId)) return;
        try
        {
            var undoJson = undo is { Count: > 0 } ? JsonSerializer.Serialize(undo, StoreJson) : null;
            var now = DateTime.UtcNow;
            await db.AiActionLogs.Where(l => l.Id == logId).ExecuteUpdateAsync(s => s
                .SetProperty(l => l.Status, status)
                .SetProperty(l => l.ResultMessage, r.Message)
                .SetProperty(l => l.DocNo, r.DocNo)
                .SetProperty(l => l.DocId, docId)
                .SetProperty(l => l.UndoJson, undoJson)
                .SetProperty(l => l.ExecutedAt, now)
                .SetProperty(l => l.UpdatedAt, now), ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "AI action log update failed");
        }
    }

    /// <param name="NeedsAcknowledge">Thao tác rủi ro cao chưa được xác nhận lần hai — app hỏi lại rồi gửi acknowledged.</param>
    public sealed record ExecResult(bool Ok, string Message, string? DocNo, string? OpenModule,
        bool CanUndo = false, bool NeedsAcknowledge = false);

    public async Task<ExecResult> ExecuteAsync(string id, Guid userId, Guid storeId, CancellationToken ct, bool acknowledged = false)
    {
        var p = await GetAsync(id, userId, storeId, ct);
        if (p == null) return new(false, "Phiếu đề xuất đã hết hạn hoặc đã xử lý — hỏi lại trợ lý.", null, null);
        if (p.Risk == "high" && !acknowledged)
            return new(false, "Thao tác rủi ro cao — cần xác nhận thêm một lần (không thấy hộp hỏi lại thì cập nhật app bản mới).",
                null, p.OpenModule, NeedsAcknowledge: true);

        // Mỗi đề xuất chỉ ghi một lần (bấm hai lần / hai thiết bị không tạo trùng).
        if (await TransitionAsync(id, "proposed", "running", ct) == false)
            return new(false, "Phiếu này đang được xử lý hoặc đã xử lý.", null, p.OpenModule);
        cache.Remove(Key(id));

        var ctx = http.HttpContext ?? throw new InvalidOperationException("Không có phiên làm việc");
        ExecResult r;
        string? docId = null;
        List<Step>? undo = null;
        if (p.Batch)
            (r, undo) = await ExecuteBatchAsync(p, ctx, ct);
        else if (p.Steps is { Count: > 0 })
            (r, docId) = await ExecuteStepsAsync(p, ctx, ct);
        else
            (r, docId, undo) = await ExecuteSingleAsync(p, ctx, storeId, ct);

        if (r.Ok)
        {
            if (!p.Batch && p.Steps is { Count: > 0 }) undo = UndoSteps(p, docId, null);
            await FinishLogAsync(id, "done", r, docId, undo, ct);
            return r with { CanUndo = undo is { Count: > 0 } };
        }
        // Lỗi nghiệp vụ (thiếu tồn, sai số liệu…) → giữ đề xuất để người dùng thử lại; không có quyền → kết thúc.
        var retry = !r.Message.StartsWith("Tài khoản không có quyền", StringComparison.Ordinal) && !p.Batch && p.Steps is not { Count: > 0 };
        if (retry)
        {
            CacheSet(p);
            await TransitionAsync(id, "running", "proposed", ct);
        }
        else await FinishLogAsync(id, "failed", r, docId, null, ct);
        return r;
    }

    async Task<(ExecResult, string?, List<Step>?)> ExecuteSingleAsync(Pending p, HttpContext ctx, Guid storeId, CancellationToken ct)
    {
        var payload = p.Body;
        if (payload != null && p.Kind is "cash" or "update_cash" && JsonNode.Parse(payload) is JsonObject bo
            && bo["categoryId"]?.ToString() == Guid.Empty.ToString())
        {
            bo["categoryId"] = (await EnsureGeneralCategoryAsync(storeId,
                (CashTransactionType)(int)bo["type"]!, ct)).ToString();
            payload = bo.ToJsonString();
        }
        if (p.MergeFrom != null)
        {
            // Sửa hàng / khách / NCC: lấy bản hiện tại rồi chỉ đổi các trường người dùng nói — không xóa trắng trường khác.
            var cur = await CallApiAsync(ctx, "GET", p.MergeFrom, null, p.Kind, ct);
            if (!cur.Ok || cur.Data is not JsonObject baseObj) return (new(false, cur.Message, null, null), null, null);
            foreach (var (k, v) in JsonNode.Parse(payload ?? "{}")!.AsObject())
                baseObj[k] = v?.DeepClone();
            payload = baseObj.ToJsonString();
        }

        var res = await CallApiAsync(ctx, p.Method, p.Path, payload, p.Kind, ct);
        if (!res.Ok) return (new(false, res.Message, null, null), null, null);
        var data = res.Data;
        string? docNo = null;
        foreach (var k in new[] { "returnNo", "receiptNo", "ticketCode", "transactionCode", "requestCode", "orderNo", "code", "documentNo" })
            if (data?[k] is JsonValue dv && dv.ToString() is { Length: > 0 } dn) { docNo = dn; break; }
        var docId = data is JsonObject o && o["id"] is JsonValue idv ? idv.ToString() : null;
        var done = p.Title switch
        {
            var t when t.StartsWith("Sửa ", StringComparison.Ordinal) || t.StartsWith("Xóa ", StringComparison.Ordinal)
                       || t.StartsWith("Hủy ", StringComparison.Ordinal) || t.StartsWith("Duyệt ", StringComparison.Ordinal)
                       || t.StartsWith("Từ chối ", StringComparison.Ordinal) => "Đã " + t.ToLower(Vi),
            var t => "Đã tạo " + t.ToLower(Vi),
        };
        return (new(true, $"{done}{(docNo != null ? " " + docNo : "")}.", docNo, p.OpenModule), docId, UndoSteps(p, docId, data));
    }

    /// <summary>Phiếu kho nhiều bước: id phiếu từ bước đầu; bước điền dòng ghép lineId theo hàng.</summary>
    async Task<(ExecResult, string?)> ExecuteStepsAsync(Pending p, HttpContext ctx, CancellationToken ct)
    {
        string? docId = null;
        JsonNode? lastData = null;
        string? docNo = null;
        foreach (var step in p.Steps!)
        {
            var path = step.Path.Replace("{id}", docId ?? "");
            var body = step.Body;
            if (step.LinesFrom != null)
            {
                var lineList = new JsonArray();
                foreach (var l in lastData?["lines"]?.AsArray() ?? [])
                {
                    if (l?["productId"]?.ToString() is not { } pid || !Guid.TryParse(pid, out var g)
                        || p.LineQty?.TryGetValue(g, out var q) != true) continue;
                    var o = new JsonObject { ["lineId"] = l["id"]?.ToString() };
                    if (step.LinesFrom == "counted") { o["countedQty"] = q; o["isChecked"] = true; }
                    else o["qty"] = q;
                    lineList.Add(o);
                }
                body = new JsonObject { ["lines"] = lineList }.ToJsonString();
            }
            var res = await CallApiAsync(ctx, step.Method, path, body, p.Kind, ct);
            if (!res.Ok)
            {
                // Phiếu đã tạo dở (nháp) vẫn nằm ở màn tương ứng — báo để người dùng xử lý tiếp.
                return (new(false, docId == null ? res.Message : $"{res.Message} Phiếu nháp đã tạo — mở màn {p.Title.ToLower(Vi)} để hoàn tất.",
                    null, p.OpenModule), docId);
            }
            lastData = res.Data;
            docId ??= lastData?["id"]?.ToString();
            foreach (var k in new[] { "issueNo", "countNo", "code", "documentNo" })
                if (lastData?[k] is JsonValue dv && dv.ToString() is { Length: > 0 } dn) { docNo = dn; break; }
        }
        return (new(true, $"Đã tạo và hoàn thành {p.Title.ToLower(Vi)}{(docNo != null ? " " + docNo : "")}.", docNo, p.OpenModule), docId);
    }

    /// <summary>Duyệt / từ chối nhiều đơn: mỗi bước độc lập, đơn lỗi không chặn đơn khác.</summary>
    async Task<(ExecResult, List<Step>)> ExecuteBatchAsync(Pending p, HttpContext ctx, CancellationToken ct)
    {
        var ok = 0;
        var errors = new List<string>();
        var undo = new List<Step>();
        var steps = p.Steps ?? [];
        for (var i = 0; i < steps.Count; i++)
        {
            var step = steps[i];
            var res = await CallApiAsync(ctx, step.Method, step.Path, step.Body, p.Kind, ct);
            if (res.Ok)
            {
                ok++;
                if (p.BatchUndo is { } bu && i < bu.Count && bu[i] is { } u) undo.Add(u);
            }
            else errors.Add((step.Label is { Length: > 0 } label ? label + ": " : "") + res.Message);
        }
        var verb = p.Title.ToLower(Vi);
        var unit = p.Kind.StartsWith("review", StringComparison.Ordinal) ? " đơn" : " bước";
        if (ok == steps.Count)
            return (new(true, unit == " đơn" ? $"Đã {verb}: {ok}/{steps.Count} đơn." : $"Đã {verb}.", null, p.OpenModule), undo);
        var msg = $"Đã {verb} {ok}/{steps.Count}{unit}. Lỗi: " + string.Join("; ", errors.Take(4));
        return (new(ok > 0, msg, null, p.OpenModule), undo);
    }

    sealed record ApiResult(bool Ok, string Message, JsonNode? Data);

    /// <summary>Gọi API thật của app bằng phiên của người dùng (cùng quyền, gói, chi nhánh).</summary>
    async Task<ApiResult> CallApiAsync(HttpContext ctx, string method, string path, string? body, string kind, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(new HttpMethod(method), $"http://127.0.0.1:{ctx.Connection.LocalPort}{path}");
        if (body != null) req.Content = new StringContent(body, Encoding.UTF8, "application/json");
        else if (method is "POST" or "PUT" or "PATCH") req.Content = new StringContent("{}", Encoding.UTF8, "application/json");
        if (AuthenticationHeaderValue.TryParse(ctx.Request.Headers.Authorization.ToString(), out var auth))
            req.Headers.Authorization = auth;
        var branch = ctx.Request.Headers["X-Branch-Id"].ToString();
        if (!string.IsNullOrWhiteSpace(branch)) req.Headers.TryAddWithoutValidation("X-Branch-Id", branch);
        req.Headers.TryAddWithoutValidation("X-Sbox-Ai-Assistant", "1");
        using var resp = await Loopback.SendAsync(req, ct);
        var text = await resp.Content.ReadAsStringAsync(ct);
        logger.LogInformation("AI action {Kind} {Method} {Path} → {Status}", kind, method, path, (int)resp.StatusCode);
        JsonNode? node = null;
        try { node = JsonNode.Parse(text); } catch (JsonException) { }
        var ok = resp.IsSuccessStatusCode && (node?["isSuccess"] is not JsonValue v || !v.TryGetValue<bool>(out var s) || s);
        if (ok) return new(true, "", node is JsonObject obj && obj.ContainsKey("data") ? obj["data"] : node);
        var msg = (int)resp.StatusCode is 401 or 403
            ? "Tài khoản không có quyền thực hiện thao tác này."
            : node?["message"]?.ToString() is { Length: > 0 } m ? m : $"Không thực hiện được ({(int)resp.StatusCode}).";
        return new(false, msg, null);
    }

    async Task<Guid> EnsureGeneralCategoryAsync(Guid storeId, CashTransactionType type, CancellationToken ct)
    {
        var name = type == CashTransactionType.Income ? "Thu khác" : "Chi khác";
        var existing = await db.TransactionCategories
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Type == type && x.Name == name)
            .Select(x => (Guid?)x.Id).FirstOrDefaultAsync(ct);
        if (existing is Guid g) return g;
        var cat = new TransactionCategory
        {
            Id = Guid.NewGuid(), StoreId = storeId, Name = name, Type = type, IsActive = true, SortOrder = 99,
        };
        db.TransactionCategories.Add(cat);
        await db.SaveChangesAsync(ct);
        return cat.Id;
    }

    public async Task DiscardAsync(string id, Guid userId, Guid storeId, CancellationToken ct)
    {
        if (await GetAsync(id, userId, storeId, ct) == null) return;
        cache.Remove(Key(id));
        await TransitionAsync(id, "proposed", "discarded", ct);
    }

    /// <summary>Hoàn tác thao tác vừa ghi (trong <see cref="UndoWindow"/>, chỉ người đã xác nhận).</summary>
    public async Task<ExecResult> UndoAsync(string id, Guid userId, Guid storeId, CancellationToken ct)
    {
        if (!Guid.TryParseExact(id, "N", out var logId)) return new(false, "Không tìm thấy thao tác.", null, null);
        AiActionLog? log;
        try
        {
            log = await db.AiActionLogs.AsNoTracking()
                .FirstOrDefaultAsync(l => l.Id == logId && l.UserId == userId && l.StoreId == storeId, ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "AI action log read failed");
            return new(false, "Chưa hoàn tác được — thử lại sau.", null, null);
        }
        if (log == null || log.Status != "done" || string.IsNullOrEmpty(log.UndoJson))
            return new(false, "Thao tác này không hoàn tác được.", null, null);
        if (log.ExecutedAt is not DateTime at || DateTime.UtcNow - at > UndoWindow)
            return new(false, $"Đã quá {UndoWindow.TotalMinutes:0} phút — mở màn chứng từ để sửa / xóa trực tiếp.", null, null);
        if (await TransitionAsync(id, "done", "undoing", ct) != true)
            return new(false, "Thao tác này đang được hoàn tác.", null, null);

        var steps = JsonSerializer.Deserialize<List<Step>>(log.UndoJson, StoreJson) ?? [];
        var ctx = http.HttpContext ?? throw new InvalidOperationException("Không có phiên làm việc");
        foreach (var s in steps)
        {
            var res = await CallApiAsync(ctx, s.Method, s.Path, s.Body, log.Kind + ":undo", ct);
            if (!res.Ok)
            {
                await TransitionAsync(id, "undoing", "done", ct);
                return new(false, "Không hoàn tác được: " + res.Message, log.DocNo, null);
            }
        }
        try
        {
            var now = DateTime.UtcNow;
            await db.AiActionLogs.Where(l => l.Id == logId).ExecuteUpdateAsync(x => x
                .SetProperty(l => l.Status, "undone").SetProperty(l => l.UndoneAt, now).SetProperty(l => l.UpdatedAt, now), ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "AI action log update failed");
        }
        return new(true, $"Đã hoàn tác: {log.Title.ToLower(Vi)}{(log.DocNo != null ? " " + log.DocNo : "")}.", log.DocNo, null);
    }

    /// <param name="UserName">Người đã nhờ trợ lý (màn nhật ký toàn cửa hàng).</param>
    /// <param name="Lines">Nội dung phiếu như trên thẻ xác nhận.</param>
    public sealed record LogRow(string Id, DateTime CreatedAt, string Kind, string Title, string Risk, string Status,
        string? Prompt, string? ResultMessage, string? DocNo, bool CanUndo, string? UserName = null, bool IsMine = true,
        List<Line>? Lines = null);

    /// <summary>
    /// Thao tác AI gần đây (màn «Nhật ký thao tác AI»): mặc định của chính người dùng; [wholeStore] = mọi người trong cửa
    /// hàng (chủ / người có quyền sửa thiết lập AI) — biết ai đã nhờ AI xóa, hủy, duyệt gì. Hoàn tác chỉ người làm.
    /// [status] lọc: done | failed | undone | discarded (trống = tất cả trừ đang chờ xác nhận).
    /// </summary>
    public async Task<List<LogRow>> RecentAsync(Guid userId, Guid storeId, int take, CancellationToken ct,
        bool wholeStore = false, string? status = null, bool highRiskOnly = false)
    {
        try
        {
            var limit = DateTime.UtcNow - UndoWindow;
            var rows = await db.AiActionLogs.AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Status != "proposed")
                .Where(l => wholeStore || l.UserId == userId)
                .Where(l => string.IsNullOrEmpty(status) || l.Status == status)
                .Where(l => !highRiskOnly || l.Risk == "high")
                .OrderByDescending(l => l.CreatedAt).Take(Math.Clamp(take, 1, 200))
                .Select(l => new
                {
                    l.Id, l.UserId, l.CreatedAt, l.Kind, l.Title, l.Risk, l.Status, l.Prompt, l.ResultMessage, l.DocNo,
                    l.UndoJson, l.ExecutedAt, l.PendingJson,
                })
                .ToListAsync(ct);
            var userIds = rows.Select(r => r.UserId).Distinct().ToList();
            var names = await db.Users.AsNoTracking().Where(u => userIds.Contains(u.Id))
                .Select(u => new { u.Id, Name = ((u.FirstName ?? "") + " " + (u.LastName ?? "")).Trim(), u.Email })
                .ToDictionaryAsync(u => u.Id, u => string.IsNullOrWhiteSpace(u.Name) ? u.Email : u.Name, ct);
            List<Line>? LinesOf(string json)
            {
                try { return JsonSerializer.Deserialize<Pending>(json, StoreJson)?.Lines; }
                catch (JsonException) { return null; }
            }
            return rows.Select(l => new LogRow(l.Id.ToString("N"), l.CreatedAt, l.Kind, l.Title, l.Risk, l.Status, l.Prompt,
                    l.ResultMessage, l.DocNo,
                    l.UserId == userId && l.Status == "done" && l.UndoJson != null && l.ExecutedAt >= limit,
                    names.GetValueOrDefault(l.UserId), l.UserId == userId, LinesOf(l.PendingJson)))
                .ToList();
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "AI action log list failed");
            return [];
        }
    }
}
