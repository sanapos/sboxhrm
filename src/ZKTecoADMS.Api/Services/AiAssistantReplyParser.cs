using ZKTecoADMS.Application.DTOs.Permissions;

namespace ZKTecoADMS.Api.Services;

public sealed record AiAssistantParsedReply(
    string Text,
    List<string> Actions,
    List<string> Creates,
    List<string> Guides);

/// <summary>Gỡ thẻ [[ACTION]] / [[CREATE]] / [[GUIDE]] khỏi câu trả lời (Gemini hoặc bot rule).</summary>
public static class AiAssistantReplyParser
{
    public static AiAssistantParsedReply Parse(
        string reply,
        IReadOnlyDictionary<string, ModulePermissionDto> permMap,
        bool isSuperUser,
        IReadOnlyList<string> suggestedGuides,
        string userQuery)
    {
        var actions = new List<string>();
        var creates = new List<string>();
        var guides = new List<string>();
        var cleaned = reply ?? string.Empty;

        var start = 0;
        while (true)
        {
            var i = cleaned.IndexOf("[[ACTION:", start, StringComparison.Ordinal);
            if (i < 0) break;
            var j = cleaned.IndexOf("]]", i, StringComparison.Ordinal);
            if (j < 0) break;
            var tag = cleaned.Substring(i + 9, j - (i + 9)).Trim();
            if (!string.IsNullOrWhiteSpace(tag)) actions.Add(tag);
            cleaned = cleaned.Remove(i, j - i + 2);
            start = i;
        }

        var cStart = 0;
        while (true)
        {
            var ci = cleaned.IndexOf("[[CREATE:", cStart, StringComparison.Ordinal);
            if (ci < 0) break;
            var cj = cleaned.IndexOf("]]", ci, StringComparison.Ordinal);
            if (cj < 0) break;
            var ctag = cleaned.Substring(ci + 9, cj - (ci + 9)).Trim();
            if (!string.IsNullOrWhiteSpace(ctag))
            {
                var validated = AiAssistantCreateValidator.ExtractAndValidate(
                    ctag, permMap, isSuperUser, out _);
                creates.AddRange(validated);
            }
            cleaned = cleaned.Remove(ci, cj - ci + 2);
            cStart = ci;
        }

        // [[OPEN:MãChứcNăng]] — mở màn bất kỳ trong ĐƯỜNG DẪN MENU (khi không có thẻ ACTION riêng).
        var oStart = 0;
        while (true)
        {
            var oi = cleaned.IndexOf("[[OPEN:", oStart, StringComparison.Ordinal);
            if (oi < 0) break;
            var oj = cleaned.IndexOf("]]", oi, StringComparison.Ordinal);
            if (oj < 0) break;
            var code = cleaned.Substring(oi + 7, oj - (oi + 7)).Trim();
            if (AiAssistantMenuMap.Paths.ContainsKey(code)
                && (isSuperUser || (permMap.TryGetValue(code, out var mp) && mp.CanView)))
                actions.Add("open:" + code);
            cleaned = cleaned.Remove(oi, oj - oi + 2);
            oStart = oi;
        }

        var gStart = 0;
        while (true)
        {
            var gi = cleaned.IndexOf("[[GUIDE:", gStart, StringComparison.Ordinal);
            if (gi < 0) break;
            var gj = cleaned.IndexOf("]]", gi, StringComparison.Ordinal);
            if (gj < 0) break;
            var gtag = cleaned.Substring(gi + 8, gj - (gi + 8)).Trim();
            if (AiAssistantHelpCorpus.TryParseGuideTag(gtag, out var mode, out var stepId))
                guides.Add($"{mode}/{stepId}");
            cleaned = cleaned.Remove(gi, gj - gi + 2);
            gStart = gi;
        }

        if (guides.Count == 0 && suggestedGuides.Count > 0 && LooksLikeHowTo(userQuery))
            guides.Add(suggestedGuides[0]);

        actions = actions
            .Where(a => a.StartsWith("open:", StringComparison.Ordinal) || AiAssistantPermissionRules.CanAction(a, permMap, isSuperUser))
            .Distinct()
            .ToList();
        creates = creates.Distinct().ToList();
        guides = guides.Distinct().Take(2).ToList();

        return new AiAssistantParsedReply(cleaned.Trim(), actions, creates, guides);
    }

    public static bool LooksLikeHowTo(string query)
    {
        var q = (query ?? "").ToLowerInvariant();
        return q.Contains("cách") || q.Contains("hướng dẫn") || q.Contains("làm sao")
               || q.Contains("thế nào") || q.Contains("ở đâu") || q.Contains("menu nào")
               || q.Contains("mở đâu") || q.Contains("howto") || q.Contains("help")
               || q.Contains("hướng dan") || q.Contains("lam sao");
    }
}
