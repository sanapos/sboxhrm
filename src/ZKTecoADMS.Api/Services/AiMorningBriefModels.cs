using System.Globalization;
using System.Text;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Services;

namespace ZKTecoADMS.Api.Services;

/// <summary>Hằng số / lựa chọn của «Bản tin sáng tự động».</summary>
public static class AiMorningBriefOptions
{
    public const string Owner = "owner";
    public const string Manager = "manager";
    public const string Accountant = "accountant";
    public const string SalesViewers = "sales_viewers";
    public static readonly string[] AllRecipients = [Owner, Manager, Accountant, SalesViewers];
    public const string DefaultRecipients = Owner + "," + Manager;

    public const string Sales = "sales";
    public const string Stock = "stock";
    public const string Approvals = "approvals";
    public const string Attendance = "attendance";
    public const string Debt = "debt";
    public static readonly string[] AllSections = [Sales, Stock, Approvals, Attendance, Debt];
    public const string DefaultSections = "sales,stock,approvals,attendance,debt";

    /// <summary>Mã chức năng gói dịch vụ của Trợ lý AI (app: canUseAiAssistant → 'aiassistant').</summary>
    public const string ModuleCode = "AIAssistant";

    /// <summary>Nhóm thông báo «Hệ thống» — người dùng tắt nhóm này thì không nhận bản tin.</summary>
    public const string CategoryCode = "system";
    public const string EntityType = "AiMorningBrief";
    public const string ActionUrl = "/ai-assistant";

    /// <summary>Chuỗi «a,b,c» → danh sách hợp lệ (bỏ mục lạ, không trùng, giữ thứ tự chuẩn).</summary>
    public static List<string> Parse(string? csv, IReadOnlyList<string> allowed)
    {
        var set = (csv ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(s => s.ToLowerInvariant()).ToHashSet();
        return allowed.Where(set.Contains).ToList();
    }

    public static string Join(IEnumerable<string>? items, IReadOnlyList<string> allowed) =>
        string.Join(",", Parse(string.Join(",", items ?? []), allowed));
}

/// <summary>Lịch gửi theo giờ VN (UTC+7).</summary>
public static class AiMorningBriefSchedule
{
    public const int DefaultSendMinute = 7 * 60;

    /// <summary>
    /// Trễ tối đa so với giờ hẹn vẫn gửi (máy chủ khởi động lại / bật tính năng muộn). Quá khung này coi như bỏ lượt
    /// hôm nay — tránh «bản tin sáng» đến lúc chiều tối.
    /// </summary>
    public const int MaxLateMinutes = 6 * 60;

    public static DateTime VnNow(DateTime utcNow) => VnTimeHelper.UtcToVn(utcNow);

    /// <summary>Ngày của bản tin (ngày VN lúc gửi, 00:00).</summary>
    public static DateTime BriefDate(DateTime utcNow) => DateTime.SpecifyKind(VnNow(utcNow).Date, DateTimeKind.Unspecified);

    /// <summary>Đến giờ gửi hôm nay và chưa gửi.</summary>
    public static bool IsDue(int sendMinute, DateTime utcNow, bool alreadySentToday)
    {
        if (alreadySentToday) return false;
        sendMinute = Math.Clamp(sendMinute, 0, 1439);
        var minute = (int)VnNow(utcNow).TimeOfDay.TotalMinutes;
        return minute >= sendMinute && minute < sendMinute + MaxLateMinutes;
    }

    public static string Format(int minute) => NotificationQuietRules.Format(minute);

    public static int? Parse(string? hm) => NotificationQuietRules.Parse(hm);
}

// ─── Số liệu cấp cửa hàng ─────────────────────────────────────────

public sealed record BriefTopItem(string Name, decimal Qty, decimal Amount);

public sealed record BriefSales(
    int Orders, decimal Revenue,
    int LastWeekOrders, decimal LastWeekRevenue,
    int MonthOrders, decimal MonthRevenue,
    List<BriefTopItem> TopItems);

public sealed record BriefStockItem(string Name, decimal OnHand, decimal MinStock);

public sealed record BriefStock(int LowCount, int OutCount, List<BriefStockItem> Items);

public sealed record BriefDebtor(string Name, decimal Debt, decimal? Limit);

public sealed record BriefDebt(decimal TotalDebt, int DebtorCount, decimal NewDebt, int NewDebtOrders, List<BriefDebtor> OverLimit);

public sealed record BriefLate(Guid EmployeeId, string Name, int Minutes);

public sealed record BriefAbsent(Guid EmployeeId, string Name);

public sealed record BriefAttendance(int Scheduled, string? HolidayName, List<BriefLate> Late, List<BriefAbsent> Absent);

/// <summary>Số liệu bản tin của cả cửa hàng (ngày dữ liệu = hôm qua so với ngày gửi).</summary>
public sealed class AiMorningBriefStoreData
{
    public Guid StoreId { get; init; }
    public string StoreName { get; init; } = "";
    public DateTime BriefDate { get; init; }
    public DateTime DataDate => BriefDate.AddDays(-1);
    public HashSet<string> Sections { get; init; } = [];
    public BriefSales? Sales { get; set; }
    public BriefStock? Stock { get; set; }
    public BriefDebt? Debt { get; set; }
    public BriefAttendance? Attendance { get; set; }
}

/// <summary>Đơn chờ duyệt trong phạm vi người nhận — null = người nhận không có quyền duyệt loại đó.</summary>
public sealed record BriefApprovals(int? Leave, int? Advance, int? Overtime, int? Correction, int? Penalty)
{
    public int Total => (Leave ?? 0) + (Advance ?? 0) + (Overtime ?? 0) + (Correction ?? 0) + (Penalty ?? 0);
    public bool Any => Leave.HasValue || Advance.HasValue || Overtime.HasValue || Correction.HasValue || Penalty.HasValue;
}

/// <summary>Những gì một người nhận được xem trong bản tin (theo quyền + phạm vi quản lý).</summary>
public sealed class BriefRecipientView
{
    public Guid UserId { get; init; }
    public string Role { get; init; } = "";
    public bool Sales { get; init; }
    public bool Stock { get; init; }
    public bool Debt { get; init; }
    public bool Attendance { get; init; }
    public bool Ai { get; init; }
    public AiAssistantScope Scope { get; init; } = AiAssistantScope.Whole();
    public BriefApprovals? Approvals { get; init; }
}

public sealed record BriefMessage(string Title, string FullText, string PushBody);

/// <summary>Trình bày bản tin (chữ thuần, tiếng Việt).</summary>
public static class AiMorningBriefFormatter
{
    static readonly CultureInfo Vi = CultureInfo.GetCultureInfo("vi-VN");

    public const int MaxNames = 5;

    public static string Money(decimal v) => v.ToString("#,##0", Vi) + "đ";

    /// <summary>12.500.000 → «12,5tr»; 1.250.000.000 → «1,25 tỷ».</summary>
    public static string ShortMoney(decimal v)
    {
        var a = Math.Abs(v);
        if (a >= 1_000_000_000m) return (v / 1_000_000_000m).ToString("0.##", Vi) + " tỷ";
        if (a >= 1_000_000m) return (v / 1_000_000m).ToString("0.#", Vi) + "tr";
        if (a >= 1_000m) return (v / 1_000m).ToString("0", Vi) + "k";
        return v.ToString("0", Vi) + "đ";
    }

    static string Qty(decimal v) => v.ToString("0.##", Vi);

    /// <summary>Phần trăm thay đổi so với kỳ trước; null khi kỳ trước = 0.</summary>
    public static decimal? ChangePercent(decimal current, decimal previous) =>
        previous == 0 ? null : Math.Round((current - previous) / previous * 100m, 1);

    static string Pct(decimal p) => (p > 0 ? "+" : "") + p.ToString("0.#", Vi) + "%";

    public static string WeekdayName(DateTime d) => d.DayOfWeek switch
    {
        DayOfWeek.Monday => "Thứ Hai",
        DayOfWeek.Tuesday => "Thứ Ba",
        DayOfWeek.Wednesday => "Thứ Tư",
        DayOfWeek.Thursday => "Thứ Năm",
        DayOfWeek.Friday => "Thứ Sáu",
        DayOfWeek.Saturday => "Thứ Bảy",
        _ => "Chủ nhật",
    };

    public static string Title(DateTime briefDate) => $"Bản tin sáng {briefDate:dd/MM}";

    static string Names(IEnumerable<string> names)
    {
        var list = names.ToList();
        return string.Join(", ", list.Take(MaxNames)) + (list.Count > MaxNames ? $"… (+{list.Count - MaxNames})" : "");
    }

    static void AppendSales(StringBuilder sb, AiMorningBriefStoreData d, BriefSales s)
    {
        sb.AppendLine("DOANH THU");
        sb.AppendLine($"- Hôm qua: {Money(s.Revenue)} · {s.Orders} đơn" + (s.Orders > 0 ? $" (TB {Money(s.Revenue / s.Orders)}/đơn)" : ""));
        var lw = d.DataDate.AddDays(-7);
        var pct = ChangePercent(s.Revenue, s.LastWeekRevenue);
        sb.AppendLine($"- {WeekdayName(lw)} tuần trước ({lw:dd/MM}): {Money(s.LastWeekRevenue)} · {s.LastWeekOrders} đơn"
                      + (pct is decimal p ? $" → {Pct(p)}" : s.Revenue > 0 ? " → tuần trước chưa có doanh thu" : ""));
        sb.AppendLine($"- Lũy kế tháng {d.DataDate:MM/yyyy}: {Money(s.MonthRevenue)} · {s.MonthOrders} đơn");
        if (s.TopItems.Count > 0)
            sb.AppendLine("- Bán chạy: " + string.Join("; ", s.TopItems.Select(t => $"{t.Name} ×{Qty(t.Qty)} ({Money(t.Amount)})")));
    }

    static void AppendStock(StringBuilder sb, BriefStock s)
    {
        sb.AppendLine("TỒN KHO");
        if (s.LowCount == 0)
        {
            sb.AppendLine("- Không có hàng dưới tồn tối thiểu");
            return;
        }
        sb.AppendLine($"- {s.LowCount} mặt hàng dưới tồn tối thiểu" + (s.OutCount > 0 ? $" ({s.OutCount} đã hết)" : "") + ": "
                      + Names(s.Items.Select(i => $"{i.Name} {Qty(i.OnHand)}/{Qty(i.MinStock)}")));
    }

    static void AppendDebt(StringBuilder sb, BriefDebt s)
    {
        sb.AppendLine("CÔNG NỢ KHÁCH");
        sb.AppendLine(s.DebtorCount == 0
            ? "- Không có khách còn nợ"
            : $"- Tổng nợ: {Money(s.TotalDebt)} ({s.DebtorCount} khách)");
        if (s.NewDebtOrders > 0)
            sb.AppendLine($"- Phát sinh hôm qua: {Money(s.NewDebt)} ({s.NewDebtOrders} đơn chưa thu đủ)");
        if (s.OverLimit.Count > 0)
            sb.AppendLine("- Vượt hạn mức: " + Names(s.OverLimit.Select(c => $"{c.Name} {Money(c.Debt)}/{Money(c.Limit ?? 0)}")));
    }

    static void AppendAttendance(StringBuilder sb, BriefAttendance a, string? scopeNote)
    {
        sb.AppendLine("CHẤM CÔNG HÔM QUA" + (scopeNote == null ? "" : $" ({scopeNote})"));
        if (a.HolidayName != null) sb.AppendLine($"- Ngày lễ: {a.HolidayName}");
        if (a.Scheduled == 0)
        {
            sb.AppendLine("- Chưa xếp lịch ca nên chưa tính đi trễ / vắng");
            return;
        }
        sb.AppendLine(a.Late.Count == 0
            ? "- Không ai đi trễ"
            : $"- Đi trễ {a.Late.Count} người: " + Names(a.Late.Select(l => $"{l.Name} ({l.Minutes} phút)")));
        if (a.HolidayName == null)
            sb.AppendLine(a.Absent.Count == 0
                ? "- Không ai vắng không phép"
                : $"- Vắng không phép {a.Absent.Count} người: " + Names(a.Absent.Select(x => x.Name)));
    }

    static void AppendApprovals(StringBuilder sb, BriefApprovals ap, bool wholeStore)
    {
        sb.AppendLine(wholeStore ? "CHỜ DUYỆT" : "CHỜ DUYỆT (trong phạm vi bạn quản lý)");
        var parts = new List<string>();
        if (ap.Leave is int l) parts.Add($"Nghỉ phép {l}");
        if (ap.Advance is int a) parts.Add($"Ứng lương {a}");
        if (ap.Overtime is int o) parts.Add($"Tăng ca {o}");
        if (ap.Correction is int c) parts.Add($"Chỉnh công {c}");
        if (ap.Penalty is int p) parts.Add($"Phiếu phạt {p}");
        sb.AppendLine(ap.Total == 0 ? "- Không có đơn chờ duyệt" : "- " + string.Join(" · ", parts));
    }

    static void AppendSuggestions(StringBuilder sb, IReadOnlyList<string> suggestions)
    {
        sb.AppendLine("GỢI Ý TỪ AI");
        foreach (var s in suggestions) sb.AppendLine("- " + s);
    }

    static string Header(AiMorningBriefStoreData d) =>
        $"Bản tin sáng {d.BriefDate:dd/MM} — {d.StoreName}\nSố liệu ngày {d.DataDate:dd/MM} ({WeekdayName(d.DataDate)})";

    /// <summary>Bản tin cả cửa hàng (gửi AI + lưu lịch sử). Không có phần chờ duyệt — phần đó tính riêng từng người.</summary>
    public static string StoreText(AiMorningBriefStoreData d, IReadOnlyList<string>? suggestions = null)
    {
        var sb = new StringBuilder();
        sb.AppendLine(Header(d));
        if (d.Sales is { } s) { sb.AppendLine(); AppendSales(sb, d, s); }
        if (d.Stock is { } st) { sb.AppendLine(); AppendStock(sb, st); }
        if (d.Attendance is { } a) { sb.AppendLine(); AppendAttendance(sb, a, null); }
        if (d.Debt is { } db) { sb.AppendLine(); AppendDebt(sb, db); }
        if (suggestions is { Count: > 0 }) { sb.AppendLine(); AppendSuggestions(sb, suggestions); }
        return sb.ToString().Trim();
    }

    /// <summary>Chấm công đã lọc theo phạm vi người nhận.</summary>
    public static BriefAttendance? ScopeAttendance(BriefAttendance? a, AiAssistantScope scope) =>
        a == null || scope.WholeStore
            ? a
            : a with
            {
                Late = a.Late.Where(l => scope.HasEmployee(l.EmployeeId)).ToList(),
                Absent = a.Absent.Where(x => scope.HasEmployee(x.EmployeeId)).ToList(),
            };

    /// <summary>
    /// Bản tin của một người nhận: chỉ các mục người đó được xem; null = không có mục nào để gửi.
    /// </summary>
    public static BriefMessage? ForRecipient(AiMorningBriefStoreData d, BriefRecipientView v, IReadOnlyList<string>? suggestions)
    {
        var sb = new StringBuilder();
        sb.AppendLine(Header(d));
        var sections = 0;
        var push = new List<string>();
        var line2 = new List<string>();
        var line3 = new List<string>();

        if (v.Sales && d.Sales is { } s)
        {
            sb.AppendLine(); AppendSales(sb, d, s); sections++;
            var pct = ChangePercent(s.Revenue, s.LastWeekRevenue);
            push.Add($"Doanh thu {d.DataDate:dd/MM}: {ShortMoney(s.Revenue)} · {s.Orders} đơn"
                     + (pct is decimal p ? $" ({Pct(p)} so với tuần trước)" : ""));
        }
        if (v.Stock && d.Stock is { } st)
        {
            sb.AppendLine(); AppendStock(sb, st); sections++;
            if (st.LowCount > 0) line2.Add($"{st.LowCount} hàng sắp hết" + (st.OutCount > 0 ? $" ({st.OutCount} đã hết)" : ""));
        }
        if (v.Approvals is { Any: true } ap && d.Sections.Contains(AiMorningBriefOptions.Approvals))
        {
            sb.AppendLine(); AppendApprovals(sb, ap, v.Scope.WholeStore); sections++;
            if (ap.Total > 0) line2.Insert(0, $"{ap.Total} đơn chờ duyệt");
        }
        if (v.Attendance && ScopeAttendance(d.Attendance, v.Scope) is { } a)
        {
            sb.AppendLine(); AppendAttendance(sb, a, v.Scope.WholeStore ? null : "trong phạm vi bạn quản lý"); sections++;
            if (a.Late.Count > 0) line3.Add($"{a.Late.Count} người đi trễ");
            if (a.Absent.Count > 0 && a.HolidayName == null) line3.Add($"{a.Absent.Count} vắng không phép");
        }
        if (v.Debt && d.Debt is { } db)
        {
            sb.AppendLine(); AppendDebt(sb, db); sections++;
            if (db.NewDebtOrders > 0) line3.Add($"nợ mới {ShortMoney(db.NewDebt)}");
        }
        if (sections == 0) return null;
        if (v.Ai && suggestions is { Count: > 0 }) { sb.AppendLine(); AppendSuggestions(sb, suggestions); }

        if (line2.Count > 0) push.Add(Capitalize(string.Join(" · ", line2)));
        if (line3.Count > 0) push.Add(Capitalize(string.Join(" · ", line3)));
        if (push.Count == 0) push.Add("Không có việc cần chú ý — mở để xem chi tiết");
        return new BriefMessage(Title(d.BriefDate), sb.ToString().Trim(), string.Join("\n", push.Take(3)));
    }

    static string Capitalize(string s) => s.Length == 0 ? s : char.ToUpper(s[0], Vi) + s[1..];
}
