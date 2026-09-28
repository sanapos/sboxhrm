using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

public class CommAttachment
{
    [JsonPropertyName("url")] public string Url { get; set; } = string.Empty;
    [JsonPropertyName("name")] public string Name { get; set; } = string.Empty;
    [JsonPropertyName("mime")] public string? Mime { get; set; }
    [JsonPropertyName("size")] public long Size { get; set; }
    /// <summary>image / pdf / word / excel / powerpoint / text / other</summary>
    [JsonPropertyName("kind")] public string Kind { get; set; } = "other";
}

public class CommAudience
{
    [JsonPropertyName("all")] public bool All { get; set; } = true;
    [JsonPropertyName("branchIds")] public List<Guid> BranchIds { get; set; } = new();
    [JsonPropertyName("departmentIds")] public List<Guid> DepartmentIds { get; set; } = new();
    [JsonPropertyName("positions")] public List<string> Positions { get; set; } = new();
    [JsonPropertyName("employeeIds")] public List<Guid> EmployeeIds { get; set; } = new();

    [JsonIgnore]
    public bool IsEveryone => All || (BranchIds.Count == 0 && DepartmentIds.Count == 0 && Positions.Count == 0 && EmployeeIds.Count == 0);
}

public class CommPollOption
{
    [JsonPropertyName("id")] public string Id { get; set; } = string.Empty;
    [JsonPropertyName("text")] public string Text { get; set; } = string.Empty;
}

public class CommPoll
{
    [JsonPropertyName("question")] public string Question { get; set; } = string.Empty;
    [JsonPropertyName("options")] public List<CommPollOption> Options { get; set; } = new();
    [JsonPropertyName("multiple")] public bool Multiple { get; set; }
    [JsonPropertyName("anonymous")] public bool Anonymous { get; set; }
    [JsonPropertyName("closesAt")] public DateTime? ClosesAt { get; set; }
}

/// <summary>Thông tin người xem để lọc bài theo đối tượng nhận.</summary>
public sealed record CommViewer(Guid UserId, Guid? EmployeeId, Guid? BranchId, Guid? DepartmentId, string? Position, bool IsManager, string DisplayName);

public static class CommV2Helper
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public static string Serialize<T>(T value) => JsonSerializer.Serialize(value, Json);

    public static T? Parse<T>(string? raw) where T : class
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        try { return JsonSerializer.Deserialize<T>(raw, Json); }
        catch (JsonException) { return null; }
    }

    public static List<CommAttachment> Attachments(string? raw) => Parse<List<CommAttachment>>(raw) ?? new();

    /// <summary>Ảnh cũ (AttachedImages) là mảng URL.</summary>
    public static List<string> Images(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return new();
        try { return JsonSerializer.Deserialize<List<string>>(raw) ?? new(); }
        catch (JsonException) { return raw.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList(); }
    }

    public static CommAudience Audience(string? raw) => Parse<CommAudience>(raw) ?? new CommAudience();

    /// <summary>Người xem có thuộc đối tượng nhận của bài + kênh không.</summary>
    public static bool Matches(CommAudience a, CommChannel? channel, CommViewer v)
    {
        if (v.IsManager) return true;
        if (channel?.BranchId != null && channel.BranchId != v.BranchId) return false;
        if (channel?.DepartmentId != null && channel.DepartmentId != v.DepartmentId) return false;
        if (a.IsEveryone) return true;
        if (v.EmployeeId.HasValue && a.EmployeeIds.Contains(v.EmployeeId.Value)) return true;
        if (v.BranchId.HasValue && a.BranchIds.Contains(v.BranchId.Value)) return true;
        if (v.DepartmentId.HasValue && a.DepartmentIds.Contains(v.DepartmentId.Value)) return true;
        if (!string.IsNullOrWhiteSpace(v.Position) &&
            a.Positions.Any(p => string.Equals(p.Trim(), v.Position.Trim(), StringComparison.OrdinalIgnoreCase)))
            return true;
        return false;
    }

    /// <summary>Nhân viên (đang làm) thuộc đối tượng nhận — để đếm tỷ lệ đọc và gửi thông báo.</summary>
    public static async Task<List<(Guid EmployeeId, Guid? UserId, string Name)>> AudienceEmployeesAsync(
        ZKTecoDbContext db, Guid storeId, CommAudience a, CommChannel? channel, CancellationToken ct = default)
    {
        var q = db.Employees.AsNoTracking().Where(e => e.StoreId == storeId && e.Deleted == null &&
                                                       e.WorkStatus != EmployeeWorkStatus.Resigned);
        if (channel?.BranchId != null) q = q.Where(e => e.BranchId == channel.BranchId);
        if (channel?.DepartmentId != null) q = q.Where(e => e.DepartmentId == channel.DepartmentId);
        var list = await q.Select(e => new { e.Id, e.ApplicationUserId, e.LastName, e.FirstName, e.BranchId, e.DepartmentId, e.Position })
            .ToListAsync(ct);
        return list
            .Where(e => a.IsEveryone ||
                        a.EmployeeIds.Contains(e.Id) ||
                        (e.BranchId.HasValue && a.BranchIds.Contains(e.BranchId.Value)) ||
                        (e.DepartmentId.HasValue && a.DepartmentIds.Contains(e.DepartmentId.Value)) ||
                        (!string.IsNullOrWhiteSpace(e.Position) &&
                         a.Positions.Any(p => string.Equals(p.Trim(), e.Position!.Trim(), StringComparison.OrdinalIgnoreCase))))
            .Select(e => (e.Id, e.ApplicationUserId, $"{e.LastName} {e.FirstName}".Trim()))
            .ToList();
    }

    // ─── Kênh mặc định ────────────────────────────────────────────

    public sealed record DefaultChannel(string Key, string Name, string Icon, string Color, int PostPolicy, bool RequireApproval, string Description);

    public static readonly DefaultChannel[] Defaults =
    {
        new("feed", "Bảng tin", "home", "#158DC0", 0, false, "Chia sẻ chung của mọi người"),
        new("announcement", "Thông báo", "campaign", "#DC2626", 1, false, "Thông báo chính thức từ công ty"),
        new("policy", "Nội quy & chính sách", "gavel", "#7C3AED", 1, false, "Nội quy, quy định, chính sách — có xác nhận đã đọc"),
        new("hr", "Nhân sự", "badge", "#0891B2", 1, false, "Tuyển dụng, bổ nhiệm, chế độ, phúc lợi"),
        new("event", "Sự kiện", "event", "#D97706", 1, false, "Sự kiện, team building, lịch họp lớn"),
        new("training", "Đào tạo", "school", "#16A34A", 1, false, "Tài liệu và lịch đào tạo"),
        new("culture", "Văn hóa", "celebration", "#DB2777", 0, false, "Khen thưởng, sinh nhật, hoạt động tập thể"),
        new("docs", "Tài liệu", "folder", "#475569", 1, false, "Biểu mẫu, quy trình, tài liệu dùng chung"),
    };

    /// <summary>Loại bài cũ → kênh mặc định.</summary>
    public static string ChannelKeyForType(CommunicationType t) => t switch
    {
        CommunicationType.Announcement => "announcement",
        CommunicationType.Policy or CommunicationType.Regulation => "policy",
        CommunicationType.Recruitment => "hr",
        CommunicationType.Event => "event",
        CommunicationType.Training => "training",
        CommunicationType.Culture => "culture",
        _ => "feed",
    };

    public static CommunicationType TypeForChannelKey(string? key) => key switch
    {
        "announcement" => CommunicationType.Announcement,
        "policy" => CommunicationType.Policy,
        "hr" => CommunicationType.Recruitment,
        "event" => CommunicationType.Event,
        "training" => CommunicationType.Training,
        "culture" => CommunicationType.Culture,
        "docs" => CommunicationType.Other,
        _ => CommunicationType.News,
    };

    /// <summary>
    /// Tạo kênh mặc định lần đầu và gắn bài cũ vào kênh theo loại bài (không mất dữ liệu cũ).
    /// </summary>
    public static async Task<List<CommChannel>> EnsureChannelsAsync(ZKTecoDbContext db, Guid storeId, string? by, CancellationToken ct = default)
    {
        var channels = await db.CommChannels.AsNoTracking()
            .Where(c => c.StoreId == storeId).OrderBy(c => c.SortOrder).ThenBy(c => c.Name).ToListAsync(ct);
        var missing = Defaults.Where(d => !channels.Any(c => c.Key == d.Key)).ToList();
        var anySystem = channels.Any(c => c.IsSystem);
        if (missing.Count == 0) return channels;

        var order = 0;
        var created = new List<CommChannel>();
        foreach (var d in Defaults)
        {
            order += 10;
            if (!missing.Contains(d)) continue;
            var c = new CommChannel
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                Key = d.Key,
                Name = d.Name,
                Icon = d.Icon,
                Color = d.Color,
                PostPolicy = d.PostPolicy,
                RequireApproval = d.RequireApproval,
                Description = d.Description,
                SortOrder = order,
                IsSystem = true,
                IsActive = true,
                CreatedBy = by,
            };
            db.CommChannels.Add(c);
            created.Add(c);
        }
        await db.SaveChangesAsync(ct);

        var all = channels.Concat(created).ToList();
        if (anySystem) return all.OrderBy(c => c.SortOrder).ThenBy(c => c.Name).ToList();

        // Lần đầu: gắn bài cũ chưa có kênh theo loại bài.
        var legacy = await db.InternalCommunications.AsTracking()
            .Where(p => p.StoreId == storeId && p.ChannelId == null)
            .ToListAsync(ct);
        foreach (var p in legacy)
            p.ChannelId = all.FirstOrDefault(c => c.Key == ChannelKeyForType(p.Type))?.Id;
        if (legacy.Count > 0) await db.SaveChangesAsync(ct);

        return all.OrderBy(c => c.SortOrder).ThenBy(c => c.Name).ToList();
    }

    /// <summary>Chuyển HTML sang chữ thuần (tóm tắt, tìm kiếm, gửi AI).</summary>
    public static string HtmlToText(string? html)
    {
        if (string.IsNullOrWhiteSpace(html)) return string.Empty;
        var s = System.Text.RegularExpressions.Regex.Replace(html, @"<(br|/p|/h\d|/li|/tr)\s*/?>", "\n", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        s = System.Text.RegularExpressions.Regex.Replace(s, "<li[^>]*>", "- ", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        s = System.Text.RegularExpressions.Regex.Replace(s, "<[^>]+>", string.Empty);
        s = System.Net.WebUtility.HtmlDecode(s);
        return System.Text.RegularExpressions.Regex.Replace(s, @"\n{3,}", "\n\n").Trim();
    }

    /// <summary>Làm sạch HTML từ trình soạn thảo: bỏ script/style/iframe/sự kiện on*/javascript:.</summary>
    public static string SanitizeHtml(string? html)
    {
        if (string.IsNullOrWhiteSpace(html)) return string.Empty;
        var s = System.Text.RegularExpressions.Regex.Replace(html,
            @"<\s*(script|style|iframe|object|embed|form|link|meta)[^>]*>.*?<\s*/\s*\1\s*>", string.Empty,
            System.Text.RegularExpressions.RegexOptions.IgnoreCase | System.Text.RegularExpressions.RegexOptions.Singleline);
        s = System.Text.RegularExpressions.Regex.Replace(s, @"<\s*(script|style|iframe|object|embed|form|link|meta)[^>]*/?>", string.Empty,
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        s = System.Text.RegularExpressions.Regex.Replace(s, @"\son\w+\s*=\s*(""[^""]*""|'[^']*'|[^\s>]+)", string.Empty,
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        s = System.Text.RegularExpressions.Regex.Replace(s, @"(href|src)\s*=\s*([""'])\s*(javascript|vbscript|data:text)[^""']*\2", "$1=\"#\"",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        return s;
    }
}
