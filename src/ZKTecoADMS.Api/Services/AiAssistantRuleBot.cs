using System.Text;

namespace ZKTecoADMS.Api.Services;

public sealed record AiAssistantRuleResult(bool Matched, string Reply);

/// <summary>
/// Trả lời theo dữ liệu HRM đã nạp + hướng dẫn sử dụng — không cần Gemini.
/// Dùng khi mất API Google, hết quota, hoặc câu hỏi khớp số liệu/hướng dẫn.
/// </summary>
public static class AiAssistantRuleBot
{
    /// <summary>Lời nhắc khi câu là lệnh mà chưa có AI: bot không lập phiếu, chỉ chỉ cách làm trên app.</summary>
    public const string NoAiActionNote =
        "Trợ lý chưa bật AI nên chưa tự lập / sửa phiếu được — bạn làm trên app theo hướng dẫn dưới đây.";

    public const string NoAiActionReply =
        "Lập / sửa phiếu bằng lời cần trợ lý AI (Gemini) — cửa hàng chưa bật hoặc chưa có khóa AI nên chưa lập gì cả. "
        + "Bạn mở màn tương ứng để thao tác, hoặc vào Thiết lập SBOX › Trợ lý AI để bật.";

    /// <summary>Câu hỏi số liệu mà chưa có AI: bot không đọc báo cáo, chỉ chỉ chỗ xem.</summary>
    /// <summary>Điểm tìm kiếm tối thiểu để đưa «bài gần nhất» khi không khớp rõ bài nào (dưới mức này: menu gợi ý).</summary>
    const int NearScore = 40;

    public const string NoAiDataNote =
        "Trợ lý chưa bật AI nên chưa đọc được số liệu báo cáo — bạn xem trực tiếp theo hướng dẫn dưới đây.";

    public const string NoAiDataReply =
        "Phân tích số liệu (doanh thu, bán chạy, tồn kho, lương…) cần trợ lý AI — cửa hàng chưa bật hoặc chưa có khóa AI. "
        + "Bạn xem trực tiếp ở mục Báo cáo (POS › Báo cáo hoặc Báo cáo nhân sự).";

    /// <summary>
    /// Trả lời khi cửa hàng CHƯA có khóa AI (hoặc AI tắt). Không gọi Gemini nên lệnh / phân tích không làm được — thay vì từ
    /// chối, ưu tiên những gì trả lời được bằng dữ liệu sẵn có:
    /// 1. lời chào → giới thiệu; 2. câu hỏi cách dùng → bài hướng dẫn; 3. báo sự cố khớp một dòng hướng dẫn → dòng đó lên đầu;
    /// 4. dữ liệu của chính người hỏi (phép, ca, lương…); 5. câu khớp rõ một bài (kể cả câu có «tạo / xin nghỉ / tồn kho…») →
    /// bài đó — câu RA LỆNH / hỏi số liệu kèm lời nhắc chưa làm được; 6. còn lại: lệnh / số liệu → báo cần AI, câu khác → gợi ý.
    /// </summary>
    /// <param name="noOwnKeyMessage">Có = gói không cho dùng khóa AI chung: câu phân tích không khớp bài nào báo cách bật.</param>
    public static AiAssistantRuleResult AnswerWithoutAi(
        string query,
        string contextText,
        IReadOnlyList<HelpChunk> helpHits,
        IReadOnlyList<string> allowedActions,
        IReadOnlyList<string> allowedCreates,
        bool vietnamese,
        string? noOwnKeyMessage = null)
    {
        if (!vietnamese)
            return Build(query, contextText, helpHits, allowedActions, allowedCreates, includeFallback: true);
        var q = (query ?? "").Trim().ToLowerInvariant();
        if (IsGreeting(q))
            return new AiAssistantRuleResult(true, FallbackHelp(greeting: true));
        var direct = AiAssistantHelpCorpus.DirectAnswerScore(query ?? "");
        var question = LooksLikeQuestion(q);
        var action = AiAssistantIntent.LooksLikeAction(q);
        var analytical = AiAssistantAgent.LooksAnalytical(q);
        // Hỏi SỐ LIỆU («doanh thu hôm nay bao nhiêu») — khác câu chỉ có từ phân tích («tồn kho bị âm là sao», «tính lương tăng ca»).
        var dataAsk = analytical && ContainsAny(q, "bao nhiêu", "nhiều nhất", "ít nhất", "top ", "so với", "so sánh", "doanh thu",
            "lợi nhuận", "bán chạy", "bán chậm", "tăng hay giảm", "hôm nay", "tuần này", "tháng này", "tháng trước");
        // Câu hỏi («xin nghỉ phép thế nào», «bán offline được không») không cần lời nhắc; chỉ câu ra lệnh / hỏi số liệu mới cần.
        var note = dataAsk ? NoAiDataNote : action && !question ? NoAiActionNote : null;
        AiAssistantRuleResult Guide(IReadOnlyList<HelpChunk> hits, string? prefix = null)
        {
            var r = Build(query ?? "", contextText, hits, allowedActions, allowedCreates, includeFallback: false, guideQuestion: true);
            return prefix == null || !r.Matched ? r : r with { Reply = prefix + "\n\n" + r.Reply };
        }

        if (AiAssistantIntent.IsGuideQuestion(q, direct) && Guide(AiAssistantHelpCorpus.GuideAnswerHits(query ?? "")) is { Matched: true } g)
            return g;
        // Báo sự cố («máy chấm công bị offline», «két lệch») — dòng xử lý nằm ở bài «Tình huống thường gặp», trước đây bị mục
        // «máy chấm công» của bot rule chặn mất.
        var quick = LooksLikeTrouble(q) ? AiAssistantHelpCorpus.QuickAnswer(query ?? "") : null;
        if (quick is { } qa)
            return Guide([qa.Chunk]);
        // Dữ liệu cá nhân («tôi còn bao nhiêu phép», «phiếu lương tháng này») — không áp cho lệnh («xin nghỉ phép thế nào»
        // khớp mục số dư phép nhưng người hỏi cần cách xin nghỉ).
        if (!action && Build(query ?? "", contextText, helpHits, allowedActions, allowedCreates, includeFallback: false) is { Matched: true } own)
            return own;
        if (direct >= AiAssistantHelpCorpus.ConfidentScore)
            return Guide(AiAssistantHelpCorpus.GuideAnswerHits(query ?? ""), note);
        // Câu HỎI khớp vừa phải («tạo combo như thế nào» = 44) — chưa có AI để hỏi lại, đưa bài khớp nhất hơn là từ chối.
        if (question && !dataAsk && direct >= AiAssistantHelpCorpus.ConfidentScore * 7 / 10)
            return Guide(AiAssistantHelpCorpus.GuideAnswerHits(query ?? ""));
        if (action)
            return new AiAssistantRuleResult(true, NoAiActionReply);
        if (dataAsk)
            return new AiAssistantRuleResult(true, noOwnKeyMessage == null ? NoAiDataReply
                : "Trợ lý ảo trả lời được dữ liệu cá nhân và hướng dẫn. Để phân tích báo cáo bán hàng / nhân sự: " + noOwnKeyMessage);
        // Không khớp rõ bài nào nhưng có bài gần («cài đặt giá giờ vàng karaoke») → đưa bài đó kèm lời nói rõ là gần nhất,
        // thay cho menu gợi ý chung. Chỉ bài trùng đủ từ (điểm ≥ ngưỡng gần).
        if (AiAssistantHelpCorpus.SearchScored(query ?? "", topK: 1) is [var near] && near.Score >= NearScore)
            return Guide([near.Chunk], "Chưa có hướng dẫn đúng câu này — bài gần nhất:");
        return Build(query ?? "", contextText, helpHits, allowedActions, allowedCreates, includeFallback: true);
    }

    /// <summary>Câu hỏi (không phải lệnh): «thế nào», «được không», «ở đâu», «?»…</summary>
    static bool LooksLikeQuestion(string q) =>
        q.TrimEnd().EndsWith('?')
        || ContainsAny(q, "thế nào", "ra sao", "được không", "có được", "làm sao", "cách", "ở đâu", "chỗ nào", "là gì", "là sao",
            "bao nhiêu", "nào", "hướng dẫn", "có thể");

    public static AiAssistantRuleResult Build(
        string query,
        string contextText,
        IReadOnlyList<HelpChunk> helpHits,
        IReadOnlyList<string> allowedActions,
        IReadOnlyList<string> allowedCreates,
        bool includeFallback,
        bool guideQuestion = false)
    {
        var q = (query ?? "").Trim().ToLowerInvariant();
        var ctx = contextText ?? "";
        var sb = new StringBuilder();
        var matched = false;

        // Câu soạn thảo / sáng tạo → để Gemini (nếu có); bot rule chỉ số liệu + hướng dẫn.
        if (!includeFallback && LooksLikeCompose(q))
            return new AiAssistantRuleResult(false, "");

        // Hỏi cách dùng: chỉ trả bài hướng dẫn — «duyệt lịch làm việc ở đâu» không kèm mục «Lịch làm hôm nay» của người hỏi.
        if (guideQuestion && helpHits.Count > 0)
        {
            var hits = helpHits.Take(2).ToList();
            // Báo sự cố («không thanh toán được», «két lệch»): dòng nói đúng nguyên nhân / cách xử lý lên đầu, bài chứa dòng đó
            // đứng trước — trước đây trả nguyên bài màn hình mà nguyên nhân nằm ở bài «Tình huống thường gặp».
            if (LooksLikeTrouble(q) && AiAssistantHelpCorpus.QuickAnswer(query) is { } quick)
            {
                sb.AppendLine("Cách xử lý nhanh: " + quick.Bullet.Trim().TrimStart('•').Trim());
                hits.RemoveAll(h => ReferenceEquals(h, quick.Chunk));
                hits.Insert(0, quick.Chunk);
                hits = hits.Take(2).ToList();
            }
            foreach (var hit in hits)
                AppendHelp(sb, hit, allowedActions);
            return new AiAssistantRuleResult(true, sb.ToString().Trim());
        }

        if (LooksLikeProfile(q))
        {
            matched = true;
            AppendHeading(sb, "Hồ sơ của bạn");
            var profile = ExtractProfile(ctx);
            sb.AppendLine(string.IsNullOrWhiteSpace(profile)
                ? "Chưa liên kết hồ sơ nhân viên."
                : profile);
            AddAction(sb, allowedActions, "nav_dashboard");
        }

        if (LooksLikeLeaveBalance(q))
        {
            matched = true;
            AppendSectionOrMissing(sb, ctx, "Số dư phép",
                "Chưa có cấu hình số dư phép trên hồ sơ.",
                "SỐ DƯ PHÉP");
            AddAction(sb, allowedActions, "nav_leave");
        }

        if (LooksLikeLeaveHistory(q))
        {
            matched = true;
            AppendSectionOrMissing(sb, ctx, "Lịch sử nghỉ phép (90 ngày)",
                "Chưa có đơn nghỉ trong 90 ngày.",
                "LỊCH SỬ NGHỈ PHÉP");
            AddAction(sb, allowedActions, "nav_leave");
        }

        if (LooksLikeSchedule(q))
        {
            matched = true;
            AppendSectionOrMissing(sb, ctx, "Lịch làm hôm nay",
                "Chưa có ca xếp lịch cho hôm nay.",
                "LỊCH LÀM HÔM NAY");
            AddAction(sb, allowedActions, "nav_work_schedule");
        }

        if (LooksLikeAttendanceToday(q))
        {
            matched = true;
            AppendSectionOrMissing(sb, ctx, "Chấm công hôm nay",
                "Chưa có lượt chấm công hôm nay.",
                "CHẤM CÔNG HÔM NAY");
            AddAction(sb, allowedActions, "nav_attendance");
        }

        if (LooksLikeAttendanceWeek(q))
        {
            matched = true;
            AppendSectionOrMissing(sb, ctx, "Chấm công 7 ngày gần nhất",
                "Chưa có dữ liệu chấm công 7 ngày.",
                "CHẤM CÔNG 7 NGÀY");
            AddAction(sb, allowedActions, "nav_attendance_history");
        }

        if (LooksLikePayslip(q))
        {
            matched = true;
            AppendSectionOrMissing(sb, ctx, "Phiếu lương gần nhất",
                "Chưa có phiếu lương.",
                "PHIẾU LƯƠNG GẦN NHẤT");
            AddAction(sb, allowedActions, "nav_payslip");
        }

        if (LooksLikeAdvance(q))
        {
            matched = true;
            AppendSectionOrMissing(sb, ctx, "Ứng lương",
                "Chưa có phiếu ứng lương.",
                "ỨNG LƯƠNG");
            AddAction(sb, allowedActions, "nav_advance");
        }

        if (LooksLikeTasks(q))
        {
            matched = true;
            AppendSectionOrMissing(sb, ctx, "Công việc chưa hoàn thành",
                "Không có việc được giao đang mở.",
                "CÔNG VIỆC ĐƯỢC GIAO");
            AddAction(sb, allowedActions, "nav_tasks");
        }

        if (LooksLikeMyPending(q))
        {
            matched = true;
            AppendSectionOrMissing(sb, ctx, "Phiếu đang chờ duyệt (của bạn)",
                "Bạn không có phiếu chờ duyệt.",
                "PHIẾU ĐANG CHỜ DUYỆT (của bạn)");
        }

        if (LooksLikeStorePending(q) && !q.Contains("của tôi", StringComparison.Ordinal)
            && !q.Contains("cua toi", StringComparison.Ordinal))
        {
            matched = true;
            // Quản lý theo phạm vi: tiêu đề là «ĐƠN CHỜ DUYỆT (trong phạm vi…)» / «CHỜ DUYỆT (theo quyền, trong phạm vi…)».
            var store = ExtractSection(ctx, "ĐƠN CHỜ DUYỆT (", "CHỜ DUYỆT (theo quyền");
            AppendHeading(sb, "Chờ duyệt");
            sb.AppendLine(string.IsNullOrWhiteSpace(store)
                ? "Không có bảng chờ duyệt (hoặc tài khoản không có quyền)."
                : store);
            AddAction(sb, allowedActions, "nav_leave");
        }

        if (LooksLikeLate(q))
        {
            matched = true;
            AppendSectionOrMissing(sb, ctx, "Đi trễ hôm nay",
                "Không có dữ liệu đi trễ (cần quyền chấm công / dashboard).",
                "AI ĐI TRỄ HÔM NAY");
            AddAction(sb, allowedActions, "nav_attendance");
        }

        if (LooksLikeTeamToday(q))
        {
            matched = true;
            AppendSectionOrMissing(sb, ctx, "Nhân sự hôm nay",
                "Không có thống kê nhân sự (cần quyền chấm công / dashboard).",
                "TÌNH HÌNH NHÂN SỰ HÔM NAY");
            AddAction(sb, allowedActions, "nav_dashboard");
        }

        if (LooksLikeCash(q))
        {
            matched = true;
            AppendSectionOrMissing(sb, ctx, "Thu chi 30 ngày",
                "Không có dữ liệu thu chi (cần quyền quỹ).",
                "THU CHI");
            AddAction(sb, allowedActions, "nav_cash");
        }

        if (LooksLikePenalty(q))
        {
            matched = true;
            AppendSectionOrMissing(sb, ctx, "Phiếu phạt 30 ngày",
                "Không có phiếu phạt (cần quyền).",
                "PHIẾU PHẠT");
            AddAction(sb, allowedActions, "nav_penalty");
        }

        if (LooksLikeBusinessTrip(q))
        {
            matched = true;
            AppendSectionOrMissing(sb, ctx, "Công tác phí",
                "Chưa có hồ sơ công tác (cần quyền).",
                "CÔNG TÁC PHÍ");
            AddAction(sb, allowedActions, "nav_business_trip");
        }

        // guideQuestion: controller đã nhận là câu hỏi cách dùng / sự cố (xem AiAssistantIntent.IsGuideQuestion).
        if (guideQuestion || AiAssistantReplyParser.LooksLikeHowTo(q) || LooksLikeSetup(q))
        {
            matched = true;
            if (helpHits.Count == 0)
            {
                AppendHeading(sb, "Hướng dẫn");
                sb.AppendLine("Chưa khớp mục hướng dẫn. Hỏi cụ thể hơn: chấm công, xin nghỉ, phân ca, lương, máy in, bán hàng POS…");
            }
            else
            {
                foreach (var hit in helpHits.Take(2))
                    AppendHelp(sb, hit, allowedActions);
            }
        }

        if (TryCreateIntent(q, allowedCreates, out var createType, out var createNav, out var createLabel))
        {
            matched = true;
            AppendHeading(sb, createLabel);
            sb.AppendLine("Tôi sẽ mở form để bạn điền. Hệ thống chưa tạo phiếu cho đến khi bạn bấm gửi.");
            sb.AppendLine($"[[CREATE:{createType}]]");
            AddAction(sb, allowedActions, createNav);
            if (helpHits.Count > 0 && !AiAssistantReplyParser.LooksLikeHowTo(q))
                AppendHelp(sb, helpHits[0], allowedActions);
        }

        if (matched)
            return new AiAssistantRuleResult(true, sb.ToString().Trim());

        if (!includeFallback)
            return new AiAssistantRuleResult(false, "");

        return new AiAssistantRuleResult(true, FallbackHelp(IsGreeting(q)));
    }

    static string FallbackHelp(bool greeting)
    {
        var open = greeting
            ? "Xin chào! Tôi là trợ lý của SBOX — trả lời cách dùng phần mềm (bán hàng, kho, nhân sự, chấm công, lương) và dữ liệu của chính bạn."
            : "Tôi chưa tìm thấy hướng dẫn khớp câu đó. Bạn thử hỏi ngắn, nêu tên chức năng, ví dụ:";
        return $@"{open}

• Bán hàng / POS: ""cách hủy hóa đơn"", ""máy in bếp không in"", ""kết nối hóa đơn điện tử"", ""đặt bàn trước""
• Kho: ""cách nhập hàng"", ""kiểm kho"", ""tồn kho bị âm""
• Nhân sự: ""cách xin nghỉ phép"", ""chấm công bằng điện thoại"", ""cách chốt lương"", ""phân quyền thu ngân""
• Của bạn: ""tôi còn bao nhiêu ngày phép"", ""ca hôm nay"", ""phiếu lương tháng này""";
    }

    /// <summary>Câu báo sự cố / lỗi (câu không dấu so với từ đã bỏ dấu — xem ContainsAny).</summary>
    static bool LooksLikeTrouble(string q) =>
        (q.Contains("không") && q.Contains("được")) || (q.Contains("khong") && q.Contains("duoc"))
        || ContainsAny(q, "không được", "không in", "không hiện", "không thấy", "không ra", "không đủ", "không kết nối", "bị lỗi",
            "báo lỗi", "lỗi", "bị âm", "lệch", "offline", "mất kết nối", "chờ ký", "phạt oan", "bị treo", "trắng");

    static void AppendHeading(StringBuilder sb, string title)
    {
        if (sb.Length > 0) sb.AppendLine();
        sb.AppendLine(title);
    }

    static void AppendSectionOrMissing(
        StringBuilder sb, string ctx, string title, string missing, params string[] headers)
    {
        AppendHeading(sb, title);
        var body = ExtractSection(ctx, headers);
        sb.AppendLine(string.IsNullOrWhiteSpace(body) ? missing : body);
    }

    static void AppendHelp(StringBuilder sb, HelpChunk hit, IReadOnlyList<string> allowedActions)
    {
        AppendHeading(sb, hit.Title);
        if (!string.IsNullOrWhiteSpace(hit.Summary))
            sb.AppendLine(hit.Summary);
        foreach (var b in hit.Bullets)
        {
            if (string.IsNullOrWhiteSpace(b)) continue;
            var t = b.Trim();
            // Ý con trong hướng dẫn đã có «•» sẵn → thụt lề, không thành «• •».
            sb.AppendLine(t.StartsWith('•') ? "   – " + t.TrimStart('•').TrimStart() : "• " + t);
        }
        if (!string.IsNullOrWhiteSpace(hit.Tip))
            sb.AppendLine("Mẹo: " + hit.Tip);
        if (!string.IsNullOrWhiteSpace(hit.SourceUrl))
            sb.AppendLine("Xem đầy đủ: " + hit.SourceUrl);
        if (AiAssistantHelpCorpus.HasAppGuide(hit))
            sb.AppendLine($"[[GUIDE:{hit.Mode}/{hit.StepId}]]");
        foreach (var tag in hit.ActionTags)
            AddAction(sb, allowedActions, tag);
    }

    static void AddAction(StringBuilder sb, IReadOnlyList<string> allowed, string tag)
    {
        if (allowed.Contains(tag, StringComparer.Ordinal))
            sb.AppendLine($"[[ACTION:{tag}]]");
    }

    static string ExtractProfile(string ctx)
    {
        var keys = new[] { "Họ tên:", "Mã NV:", "Chức vụ:", "Phòng ban:", "Ngày vào làm:", "Vai trò:" };
        var lines = new List<string>();
        foreach (var line in ctx.Split('\n'))
        {
            var t = line.Trim();
            if (keys.Any(k => t.StartsWith(k, StringComparison.Ordinal)))
                lines.Add("• " + t);
            if (t.Contains("Chưa liên kết hồ sơ", StringComparison.Ordinal))
                return "Chưa liên kết hồ sơ nhân viên.";
        }
        return string.Join("\n", lines);
    }

    static string? ExtractSection(string ctx, params string[] headerNeedles)
    {
        foreach (var needle in headerNeedles)
        {
            var idx = 0;
            while (true)
            {
                var h = ctx.IndexOf("=== ", idx, StringComparison.Ordinal);
                if (h < 0) break;
                var hEnd = ctx.IndexOf(" ===", h, StringComparison.Ordinal);
                if (hEnd < 0) break;
                var header = ctx.Substring(h + 4, hEnd - (h + 4));
                if (header.Contains("TÓM TẮT DỮ LIỆU", StringComparison.OrdinalIgnoreCase))
                {
                    idx = hEnd + 4;
                    continue;
                }
                if (header.Contains(needle, StringComparison.OrdinalIgnoreCase))
                {
                    var start = hEnd + 4;
                    while (start < ctx.Length && (ctx[start] == '\r' || ctx[start] == '\n'))
                        start++;
                    var next = ctx.IndexOf("\n=== ", start, StringComparison.Ordinal);
                    var body = next < 0 ? ctx[start..] : ctx[start..next];
                    return CleanBody(body);
                }
                idx = hEnd + 4;
            }
        }
        return null;
    }

    static string CleanBody(string body)
    {
        var lines = body.Replace("\r\n", "\n").Split('\n')
            .Select(l => l.Trim())
            .Where(l => l.Length > 0 && !l.StartsWith("===", StringComparison.Ordinal))
            .Select(l => l.StartsWith("- ", StringComparison.Ordinal) ? "• " + l[2..] : l);
        return string.Join("\n", lines).Trim();
    }

    // Câu gõ không dấu so với từ khóa đã bỏ dấu (xem AiAssistantIntent.ContainsAny).
    static bool ContainsAny(string q, params string[] keys) => AiAssistantIntent.ContainsAny(q, keys);

    static bool LooksLikeProfile(string q) =>
        ContainsAny(q, "tôi là ai", "ho so cua toi", "hồ sơ của tôi", "hồ sơ tôi",
            "mã nhân viên", "ma nhan vien", "tên tôi", "phòng ban của tôi");

    static bool LooksLikeLeaveBalance(string q) =>
        ContainsAny(q, "số dư phép", "so du phep", "phép còn", "phep con",
            "còn phép", "con phep", "bao nhiêu ngày phép", "bao nhieu ngay phep",
            "phép năm", "phep nam", "phép có lương", "ngày phép",
            "nghỉ phép", "nghi phep");

    static bool LooksLikeLeaveHistory(string q) =>
        ContainsAny(q, "lịch sử nghỉ", "lich su nghi", "đơn nghỉ của", "don nghi cua",
            "đã nghỉ", "nghi phép gần");

    static bool LooksLikeSchedule(string q) =>
        ContainsAny(q, "ca hôm nay", "ca hom nay", "lịch làm", "lich lam",
            "ca làm", "xếp ca", "today shift");

    static bool LooksLikeAttendanceToday(string q) =>
        ContainsAny(q, "chấm công hôm nay", "cham cong hom nay", "đã chấm", "da cham",
            "chấm chưa", "cham chua", "quẹt thẻ", "check in", "check-in",
            "vào ca chưa", "ra ca");

    static bool LooksLikeAttendanceWeek(string q) =>
        ContainsAny(q, "7 ngày", "7 ngay", "tuần này", "tuan nay",
            "lịch sử chấm", "lich su cham", "chấm công tuần");

    static bool LooksLikePayslip(string q) =>
        ContainsAny(q, "phiếu lương", "phieu luong", "bảng lương", "bang luong",
            "lương tháng", "luong thang", "thực lĩnh", "thuc linh", "payslip");

    static bool LooksLikeAdvance(string q) =>
        ContainsAny(q, "ứng lương", "ung luong", "tạm ứng", "tam ung", "phiếu ứng");

    static bool LooksLikeTasks(string q) =>
        ContainsAny(q, "công việc", "cong viec", "việc được giao", "task của tôi", "việc chưa");

    static bool LooksLikeMyPending(string q) =>
        ContainsAny(q, "phiếu của tôi", "đơn của tôi", "chờ duyệt của tôi", "phiếu đang chờ");

    static bool LooksLikeStorePending(string q) =>
        ContainsAny(q, "chờ duyệt", "cho duyet", "cần duyệt", "phê duyệt", "duyệt đơn", "pending");

    static bool LooksLikeLate(string q) =>
        ContainsAny(q, "đi trễ", "di tre", "ai trễ", "đi muộn", "di muon");

    static bool LooksLikeTeamToday(string q) =>
        ContainsAny(q, "ai vắng", "ai vang", "nhân sự hôm nay", "nhan su hom nay",
            "có mặt", "vắng mặt", "vang mat");

    static bool LooksLikeCash(string q) =>
        ContainsAny(q, "thu chi", "quỹ", "phiếu chi", "phiếu thu", "cash");

    static bool LooksLikePenalty(string q) =>
        ContainsAny(q, "phiếu phạt", "phieu phat", "phạt nhân", "penalty");

    static bool LooksLikeBusinessTrip(string q) =>
        ContainsAny(q, "công tác", "cong tac", "hạch toán", "hoạch toán", "ứng công tác", "quyết toán");

    static bool LooksLikeSetup(string q) =>
        ContainsAny(q, "thiết lập", "thiet lap", "cấu hình", "cau hinh",
            "máy chấm công", "may cham cong", "máy in", "mẫu in");

    static bool LooksLikeCompose(string q) =>
        ContainsAny(q, "viết", "viet ", "soạn", "soan ", "draft", "diễn giải",
            "viết giúp", "soạn giúp", "làm văn", "bài truyền thông");

    static bool IsGreeting(string q)
    {
        var t = q.Trim();
        return t is "hi" or "hello" or "hey" or "chào" or "chao"
               || t.StartsWith("xin chào", StringComparison.Ordinal)
               || t.StartsWith("xin chao", StringComparison.Ordinal)
               || t.StartsWith("chào bạn", StringComparison.Ordinal)
               || t.StartsWith("trợ giúp", StringComparison.Ordinal)
               || t is "help" or "giúp" or "giup toi";
    }

    static bool TryCreateIntent(
        string q,
        IReadOnlyList<string> allowedCreates,
        out string type,
        out string nav,
        out string label)
    {
        type = "";
        nav = "";
        label = "";
        (string Type, string Nav, string Label, string[] Keys)[] map =
        [
            ("leave", "nav_leave_create", "Đăng ký nghỉ phép",
                ["xin nghỉ", "xin nghi", "đăng ký nghỉ", "dang ky nghi", "tạo đơn nghỉ", "xin phép năm"]),
            ("advance", "nav_advance_create", "Đăng ký ứng lương",
                ["xin ứng", "xin ung", "đăng ký ứng", "tạo ứng lương"]),
            ("overtime", "nav_overtime_create", "Đăng ký tăng ca",
                ["xin tăng ca", "đăng ký tăng ca", "dang ky tang ca"]),
            ("feedback", "nav_feedback_create", "Gửi phản ánh",
                ["gửi phản ánh", "gui phan anh", "góp ý", "tạo phản ánh"]),
            ("attendance_correction", "nav_attendance_correction_create", "Báo quên / sửa giờ chấm",
                ["quên chấm", "quen cham", "sửa giờ", "báo quên", "đơn sửa công"]),
            ("shift_swap", "nav_shift_change", "Đổi ca",
                ["đổi ca", "doi ca", "xin đổi ca"]),
            ("meal", "nav_meal_register", "Đăng ký cơm",
                ["đăng ký cơm", "dang ky com", "đăng ký suất"]),
            ("business_trip", "nav_business_trip_create", "Đăng ký công tác",
                ["đăng ký công tác", "tạo công tác", "xin công tác"]),
        ];
        foreach (var row in map)
        {
            if (!allowedCreates.Contains(row.Type, StringComparer.Ordinal))
                continue;
            if (!ContainsAny(q, row.Keys))
                continue;
            type = row.Type;
            nav = row.Nav;
            label = row.Label;
            return true;
        }
        return false;
    }
}
