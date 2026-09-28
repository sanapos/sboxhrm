using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>Một mục checklist: ai làm, lúc nào, ảnh chứng minh.</summary>
public class TaskChecklistItem
{
    [JsonPropertyName("id")] public string Id { get; set; } = Guid.NewGuid().ToString("N")[..10];
    [JsonPropertyName("text")] public string Text { get; set; } = string.Empty;
    [JsonPropertyName("done")] public bool Done { get; set; }
    [JsonPropertyName("requirePhoto")] public bool RequirePhoto { get; set; }
    [JsonPropertyName("photoUrl")] public string? PhotoUrl { get; set; }
    [JsonPropertyName("note")] public string? Note { get; set; }
    [JsonPropertyName("doneById")] public Guid? DoneById { get; set; }
    [JsonPropertyName("doneBy")] public string? DoneBy { get; set; }
    [JsonPropertyName("doneAt")] public DateTime? DoneAt { get; set; }
}

/// <summary>Một giai đoạn trong quy trình dự án (theo ngành).</summary>
public class TaskStage
{
    [JsonPropertyName("key")] public string Key { get; set; } = string.Empty;
    [JsonPropertyName("name")] public string Name { get; set; } = string.Empty;
    [JsonPropertyName("color")] public string? Color { get; set; }
    /// <summary>Kéo việc vào giai đoạn này = hoàn thành.</summary>
    [JsonPropertyName("done")] public bool Done { get; set; }
}

/// <summary>Logic dùng chung của Công việc v2: checklist, giai đoạn, tiến độ, lịch lặp.</summary>
public static class TaskV2Helper
{
    private static readonly JsonSerializerOptions Json = new()
    {
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    // ─── Checklist ────────────────────────────────────────────────

    /// <summary>
    /// Đọc checklist: hỗ trợ định dạng mới (mảng object) và cũ (mảng chuỗi,
    /// hoặc object có title/isDone/completed).
    /// </summary>
    public static List<TaskChecklistItem> ParseChecklist(string? raw)
    {
        var list = new List<TaskChecklistItem>();
        if (string.IsNullOrWhiteSpace(raw)) return list;
        try
        {
            using var doc = JsonDocument.Parse(raw);
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return list;
            var i = 0;
            foreach (var el in doc.RootElement.EnumerateArray())
            {
                i++;
                if (el.ValueKind == JsonValueKind.String)
                {
                    var t = el.GetString();
                    if (!string.IsNullOrWhiteSpace(t))
                        list.Add(new TaskChecklistItem { Id = $"c{i}", Text = t.Trim() });
                    continue;
                }
                if (el.ValueKind != JsonValueKind.Object) continue;
                string? S(params string[] names)
                {
                    foreach (var n in names)
                        foreach (var p in el.EnumerateObject())
                            if (string.Equals(p.Name, n, StringComparison.OrdinalIgnoreCase) &&
                                p.Value.ValueKind == JsonValueKind.String)
                                return p.Value.GetString();
                    return null;
                }
                bool B(params string[] names)
                {
                    foreach (var n in names)
                        foreach (var p in el.EnumerateObject())
                            if (string.Equals(p.Name, n, StringComparison.OrdinalIgnoreCase))
                                return p.Value.ValueKind == JsonValueKind.True;
                    return false;
                }
                var text = S("text", "title", "name", "content");
                if (string.IsNullOrWhiteSpace(text)) continue;
                var item = new TaskChecklistItem
                {
                    Id = S("id") is { Length: > 0 } id ? id : $"c{i}",
                    Text = text.Trim(),
                    Done = B("done", "isDone", "completed", "checked"),
                    RequirePhoto = B("requirePhoto"),
                    PhotoUrl = S("photoUrl"),
                    Note = S("note"),
                    DoneBy = S("doneBy"),
                };
                if (Guid.TryParse(S("doneById"), out var by)) item.DoneById = by;
                if (DateTime.TryParse(S("doneAt"), CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var at))
                    item.DoneAt = at;
                list.Add(item);
            }
        }
        catch (JsonException)
        {
            // Dữ liệu cũ dạng văn bản: mỗi dòng một mục.
            var n = 0;
            foreach (var line in raw.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
                list.Add(new TaskChecklistItem { Id = $"c{++n}", Text = line.TrimStart('-', '*', ' ') });
        }
        // Id trùng → đánh lại để thao tác theo id không nhầm mục.
        var seen = new HashSet<string>();
        foreach (var it in list)
            if (!seen.Add(it.Id)) { it.Id = Guid.NewGuid().ToString("N")[..10]; seen.Add(it.Id); }
        return list;
    }

    public static string SerializeChecklist(IEnumerable<TaskChecklistItem> items) =>
        JsonSerializer.Serialize(items, Json);

    /// <summary>Chuẩn hóa checklist gửi lên (gán id, cắt chuỗi) — giữ thông tin đã làm.</summary>
    public static string? NormalizeChecklist(string? raw)
    {
        if (raw == null) return null;
        var items = ParseChecklist(raw);
        return items.Count == 0 ? null : SerializeChecklist(items);
    }

    // ─── Giai đoạn ────────────────────────────────────────────────

    public static List<TaskStage> ParseStages(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return new();
        try
        {
            return (JsonSerializer.Deserialize<List<TaskStage>>(raw, Json) ?? new())
                .Where(s => !string.IsNullOrWhiteSpace(s.Key) && !string.IsNullOrWhiteSpace(s.Name))
                .GroupBy(s => s.Key.Trim())
                .Select(g => { var s = g.First(); s.Key = s.Key.Trim(); s.Name = s.Name.Trim(); return s; })
                .ToList();
        }
        catch (JsonException)
        {
            return new();
        }
    }

    public static string? SerializeStages(IEnumerable<TaskStage>? stages)
    {
        var list = stages?.Where(s => !string.IsNullOrWhiteSpace(s.Key)).ToList();
        return list == null || list.Count == 0 ? null : JsonSerializer.Serialize(list, Json);
    }

    // ─── Tiến độ ─────────────────────────────────────────────────

    /// <summary>% tiến độ tự tính; null = giữ nguyên (chế độ nhập tay hoặc không có dữ liệu).</summary>
    public static int? AutoProgress(WorkTask task, int subTotal = 0, int subDone = 0)
    {
        switch (task.ProgressMode)
        {
            case TaskProgressMode.Checklist:
                var items = ParseChecklist(task.Checklist);
                if (items.Count == 0) return null;
                return (int)Math.Round(items.Count(i => i.Done) * 100.0 / items.Count);
            case TaskProgressMode.SubTasks:
                if (subTotal == 0) return null;
                return (int)Math.Round(subDone * 100.0 / subTotal);
            default:
                return null;
        }
    }

    /// <summary>Tính lại tiến độ việc cha (chế độ theo việc con). Gọi trước SaveChanges.</summary>
    public static async Task RecalcParentAsync(ZKTecoDbContext db, Guid? parentId)
    {
        if (parentId == null) return;
        var parent = await db.WorkTasks.AsTracking().FirstOrDefaultAsync(t => t.Id == parentId);
        if (parent == null || parent.ProgressMode != TaskProgressMode.SubTasks) return;
        var subs = await db.WorkTasks.AsNoTracking()
            .Where(t => t.ParentTaskId == parentId && t.IsActive && t.Status != WorkTaskStatus.Cancelled)
            .Select(t => new { t.Id, t.Status })
            .ToListAsync();
        // Việc con vừa đổi trong cùng request chưa lưu → lấy trạng thái đang theo dõi.
        var tracked = db.ChangeTracker.Entries<WorkTask>()
            .Where(e => e.Entity.ParentTaskId == parentId)
            .ToDictionary(e => e.Entity.Id, e => e.Entity.Status);
        var total = subs.Count;
        var done = subs.Count(s => (tracked.TryGetValue(s.Id, out var st) ? st : s.Status) == WorkTaskStatus.Completed);
        var p = AutoProgress(parent, total, done);
        if (p.HasValue) parent.Progress = p.Value;
    }

    // ─── Mã dự án ────────────────────────────────────────────────

    public static async Task<string> GenerateProjectCodeAsync(ZKTecoDbContext db, Guid storeId)
    {
        var codes = await db.TaskProjects.IgnoreQueryFilters()
            .Where(p => p.StoreId == storeId && p.Code.StartsWith("DA-"))
            .Select(p => p.Code)
            .ToListAsync();
        var max = codes.Select(c => int.TryParse(c[3..], out var n) ? n : 0).DefaultIfEmpty(0).Max();
        return $"DA-{max + 1:D4}";
    }

    // ─── Lịch lặp lại ────────────────────────────────────────────

    /// <summary>
    /// Lần chạy kế tiếp SAU thời điểm <paramref name="after"/> (giờ địa phương máy chủ, như DueDate).
    /// null = không lặp / cấu hình sai.
    /// </summary>
    public static DateTime? NextRun(TaskRecurrenceType type, string? days, string? time, DateTime after)
    {
        if (type == TaskRecurrenceType.None) return null;
        var (hh, mm) = ParseTime(time);
        var dayList = (days ?? string.Empty)
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(d => int.TryParse(d, out var n) ? n : -1)
            .Where(n => n >= 0)
            .ToHashSet();
        for (var i = 0; i <= 62; i++)
        {
            var d = after.Date.AddDays(i);
            var at = d.AddHours(hh).AddMinutes(mm);
            if (at <= after) continue;
            var ok = type switch
            {
                TaskRecurrenceType.Daily => true,
                // DayOfWeek: CN=0 … T7=6 → quy ước 1=T2 … 7=CN
                TaskRecurrenceType.Weekly => dayList.Count == 0 || dayList.Contains(d.DayOfWeek == DayOfWeek.Sunday ? 7 : (int)d.DayOfWeek),
                TaskRecurrenceType.Monthly => dayList.Count == 0
                    ? d.Day == 1
                    : dayList.Contains(d.Day) || (dayList.Contains(0) && d.Day == DateTime.DaysInMonth(d.Year, d.Month)),
                _ => false,
            };
            if (ok) return at;
        }
        return null;
    }

    public static (int h, int m) ParseTime(string? time)
    {
        if (!string.IsNullOrWhiteSpace(time))
        {
            var parts = time.Split(':');
            if (parts.Length >= 2 && int.TryParse(parts[0], out var h) && int.TryParse(parts[1], out var m) &&
                h is >= 0 and < 24 && m is >= 0 and < 60)
                return (h, m);
        }
        return (8, 0);
    }

    public static List<Guid> ParseGuidList(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return new();
        try
        {
            return (JsonSerializer.Deserialize<List<Guid>>(raw) ?? new()).Where(g => g != Guid.Empty).Distinct().ToList();
        }
        catch (JsonException)
        {
            return raw.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(s => Guid.TryParse(s, out var g) ? g : Guid.Empty)
                .Where(g => g != Guid.Empty).Distinct().ToList();
        }
    }
}
