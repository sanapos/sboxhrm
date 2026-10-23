using System.Globalization;
using System.Net;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Trang công khai của hội viên gym (link gửi qua Zalo, không cần đăng nhập) — mặc định trên sboxhrm.com:
/// thẻ / gói còn hạn (ngày, buổi), lịch tập 12 tuần, giờ vào – ra từng buổi kèm đánh giá PT, thể trạng (xu hướng
/// cân nặng, số đo) và phác đồ tập PT giao. Mã link ngẫu nhiên 20 ký tự; đổi mã ở app làm link cũ hết hiệu lực.
/// </summary>
[ApiController]
[AllowAnonymous]
public class PosGymPublicController(ZKTecoDbContext db, IConfiguration configuration) : ControllerBase
{
    static readonly CultureInfo Vi = CultureInfo.GetCultureInfo("vi-VN");
    static readonly string[] Wd = ["T2", "T3", "T4", "T5", "T6", "T7", "CN"];

    static string H(string? s) => WebUtility.HtmlEncode(s ?? "");
    static DateTime Vn(DateTime utc) => utc.AddHours(7);
    static int WeekdayIndex(DateTime d) => ((int)d.DayOfWeek + 6) % 7;
    static string Num(decimal d) => d.ToString("0.#", Vi);

    /// <summary>Tên miền link gửi khách (mặc định https://sboxhrm.com) — cấu hình AppSettings:MemberPortalUrl.</summary>
    public static string PortalBase(IConfiguration cfg) =>
        (cfg["AppSettings:MemberPortalUrl"] ?? "https://sboxhrm.com").TrimEnd('/');

    [HttpGet("/o/hv/{token}")]
    [Produces("text/html")]
    public async Task<IActionResult> Member(string token)
    {
        token = (token ?? "").Trim();
        if (token.Length < 12 || token.Length > 40) return NotFoundPage();
        var c = await db.PosCustomers.IgnoreQueryFilters().AsNoTracking()
            .Where(x => x.GymShareToken == token && x.Deleted == null)
            .Select(x => new { x.Id, x.StoreId, x.Name, x.Phone, x.GymTrainerName })
            .FirstOrDefaultAsync();
        if (c == null) return NotFoundPage();

        var store = await db.Stores.IgnoreQueryFilters().AsNoTracking()
            .Where(s => s.Id == c.StoreId)
            .Select(s => new { s.Name, s.Phone, s.Address })
            .FirstOrDefaultAsync();
        var storeName = store?.Name ?? "";
        var now = DateTime.UtcNow;
        var todayVn = Vn(now).Date;
        var balances = await db.PosCustomerSessionBalances.IgnoreQueryFilters().AsNoTracking()
            .Where(b => b.StoreId == c.StoreId && b.CustomerId == c.Id && b.Deleted == null)
            .OrderByDescending(b => b.ExpiresAt ?? b.CreatedAt)
            .Take(30)
            .ToListAsync();
        var since = now.AddDays(-90);
        var visits = await db.PosGymVisits.IgnoreQueryFilters().AsNoTracking()
            .Where(v => v.StoreId == c.StoreId && v.CustomerId == c.Id && v.Deleted == null && v.CheckInAt >= since)
            .OrderByDescending(v => v.CheckInAt)
            .Take(300)
            .Select(v => new { v.Id, v.CheckInAt, v.CheckOutAt, v.DurationMinutes, v.Status, v.PackageName })
            .ToListAsync();
        var assessments = await db.PosGymAssessments.IgnoreQueryFilters().AsNoTracking()
            .Where(a => a.StoreId == c.StoreId && a.CustomerId == c.Id && a.Deleted == null)
            .OrderByDescending(a => a.AssessedAt)
            .Take(100)
            .ToListAsync();
        var sessionNotes = assessments.Where(a => a.Kind == 1 && a.VisitId != null)
            .GroupBy(a => a.VisitId!.Value).ToDictionary(g => g.Key, g => g.First());
        var body = assessments.Where(a => a.Kind == 0).Take(24).ToList(); // mới nhất trước
        var plans = await db.PosGymWorkoutPlans.IgnoreQueryFilters().AsNoTracking()
            .Where(p => p.StoreId == c.StoreId && p.CustomerId == c.Id && p.Deleted == null)
            .OrderByDescending(p => p.StartDate ?? p.CreatedAt)
            .Take(20)
            .ToListAsync();

        // ── Tóm tắt thẻ / gói ──────────────────────────────────────────────
        bool Live(PosCustomerSessionBalance b) => b.RemainingSessions > 0 && (b.ExpiresAt == null || b.ExpiresAt > now);
        bool Frozen(PosCustomerSessionBalance b) => b.FrozenAt != null && (b.FrozenUntil == null || b.FrozenUntil > now);
        var liveCards = balances.Where(b => Live(b) && PosCustomerSessionBalance.IsUnlimitedCount(b.TotalSessions)).ToList();
        var livePacks = balances.Where(b => Live(b) && !PosCustomerSessionBalance.IsUnlimitedCount(b.TotalSessions)).ToList();
        var cardEnd = liveCards.Where(b => b.ExpiresAt != null).Select(b => b.ExpiresAt!.Value).DefaultIfEmpty().Max();
        var cardStart = liveCards.Select(b => b.CreatedAt).DefaultIfEmpty().Min();
        var cardDaysLeft = liveCards.Count == 0 || cardEnd == default ? (int?)null
            : Math.Max(0, (int)Math.Ceiling((Vn(cardEnd).Date - todayVn).TotalDays));
        var anyFrozen = balances.Any(b => Live(b) && Frozen(b));
        var soon = (cardDaysLeft is int dl && dl <= 7)
            || livePacks.Any(p => p.RemainingSessions <= 2 || (p.ExpiresAt is DateTime e && e <= now.AddDays(7)));
        var nothing = liveCards.Count == 0 && livePacks.Count == 0;
        var (statusCls, statusLabel) = nothing ? ("bad", balances.Count == 0 ? "Chưa có thẻ" : "Hết hạn")
            : anyFrozen ? ("warn", "Đang bảo lưu") : soon ? ("warn", "Sắp hết hạn") : ("ok", "Đang hoạt động");

        // ── Lượt tập ───────────────────────────────────────────────────────
        var entered = visits.Where(v => !GymVisitRules.IsDenied(v.Status, v.CheckInAt, v.CheckOutAt)).ToList();
        var days = entered.Select(v => Vn(v.CheckInAt).Date).ToHashSet();
        var last30 = entered.Where(v => v.CheckInAt >= now.AddDays(-30)).ToList();
        var mins30 = last30.Where(v => v.DurationMinutes is > 0).Select(v => v.DurationMinutes!.Value).ToList();
        var minsAll = entered.Where(v => v.DurationMinutes is > 0).Select(v => v.DurationMinutes!.Value).ToList();
        var weekStart = todayVn.AddDays(-WeekdayIndex(todayVn));
        // Chuỗi tuần liên tiếp có tập (tính cả tuần này nếu đã tập, không thì từ tuần trước).
        var streak = 0;
        for (var w = days.Any(d => d >= weekStart) ? weekStart : weekStart.AddDays(-7); ; w = w.AddDays(-7))
        {
            var wEnd = w.AddDays(7);
            if (!days.Any(d => d >= w && d < wEnd)) break;
            streak++;
        }

        var portal = PortalBase(configuration);
        var url = $"{portal}/o/hv/{token}";
        var sb = new StringBuilder(32_000);
        var desc = nothing ? $"Thẻ tập tại {storeName}"
            : cardDaysLeft is int d0 ? $"Thẻ tập còn {d0} ngày · {last30.Count} buổi tập 30 ngày qua"
            : string.Join(" · ", livePacks.Select(p => $"{p.PackageName}: còn {p.RemainingSessions} buổi"))
              + $" · {last30.Count} buổi tập 30 ngày qua";

        sb.Append("<!doctype html><html lang=\"vi\"><head><meta charset=\"utf-8\">")
          .Append("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1,viewport-fit=cover\">")
          .Append("<meta name=\"robots\" content=\"noindex,nofollow\">")
          .Append("<meta name=\"theme-color\" content=\"#0e7490\">")
          .Append("<title>").Append(H(c.Name)).Append(" · ").Append(H(storeName)).Append("</title>")
          .Append("<link rel=\"canonical\" href=\"").Append(H(url)).Append("\">")
          .Append("<meta property=\"og:type\" content=\"website\">")
          .Append("<meta property=\"og:title\" content=\"").Append(H($"{c.Name} · {storeName}")).Append("\">")
          .Append("<meta property=\"og:description\" content=\"").Append(H(desc)).Append("\">")
          .Append("<meta property=\"og:url\" content=\"").Append(H(url)).Append("\">")
          .Append("<meta property=\"og:site_name\" content=\"SBOX HRM\">")
          .Append(Css)
          .Append("</head><body>");

        // ── Header ──
        var initials = string.Concat((c.Name ?? "?").Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .TakeLast(2).Select(w => char.ToUpper(w[0], Vi)));
        sb.Append("<header class=\"hero\"><div class=\"wrap\"><div class=\"store\">").Append(H(storeName)).Append("</div>")
          .Append("<div class=\"who\"><div class=\"avatar\">").Append(H(initials)).Append("</div><div>")
          .Append("<h1>").Append(H(c.Name)).Append("</h1><div class=\"chips\">")
          .Append("<span class=\"chip ").Append(statusCls).Append("\">").Append(statusLabel).Append("</span>");
        if (!string.IsNullOrWhiteSpace(c.GymTrainerName))
            sb.Append("<span class=\"chip glass\">PT: ").Append(H(c.GymTrainerName)).Append("</span>");
        sb.Append("</div></div></div></div></header>");

        sb.Append("<main class=\"wrap\">");

        // ── Thẻ tóm tắt ──
        sb.Append("<section class=\"card summary\">");
        if (cardDaysLeft is int left)
        {
            var total = Math.Max(1, (Vn(cardEnd).Date - Vn(cardStart).Date).TotalDays);
            var pct = Math.Clamp(left / total, 0, 1);
            sb.Append("<div class=\"big\"><b>").Append(left).Append("</b><span>ngày tập còn lại</span></div>")
              .Append("<div class=\"bar\"><i style=\"width:").Append((pct * 100).ToString("0", CultureInfo.InvariantCulture)).Append("%\" class=\"")
              .Append(left <= 7 ? "warn" : "").Append("\"></i></div>")
              .Append("<div class=\"muted\">Thẻ tập đến <b>").Append(Vn(cardEnd).ToString("dd/MM/yyyy")).Append("</b>")
              .Append(liveCards.Count > 1 ? $" · đã cộng nối {liveCards.Count} thẻ" : "").Append("</div>");
        }
        foreach (var p in livePacks)
        {
            var pct = Math.Clamp(p.RemainingSessions / (double)Math.Max(1, p.TotalSessions), 0, 1);
            sb.Append("<div class=\"pack-row\"><div class=\"big sm\"><b>").Append(p.RemainingSessions).Append("</b><span>/")
              .Append(p.TotalSessions).Append(" buổi · ").Append(H(p.PackageName)).Append("</span></div>")
              .Append("<div class=\"bar\"><i style=\"width:").Append((pct * 100).ToString("0", CultureInfo.InvariantCulture)).Append("%\" class=\"")
              .Append(p.RemainingSessions <= 2 ? "warn" : "").Append("\"></i></div>");
            if (p.ExpiresAt is DateTime pe) sb.Append("<div class=\"muted\">Dùng trước ").Append(Vn(pe).ToString("dd/MM/yyyy")).Append("</div>");
            sb.Append("</div>");
        }
        if (nothing)
            sb.Append("<div class=\"big\"><b>0</b><span>").Append(balances.Count == 0 ? "chưa có thẻ / gói tập" : "thẻ / gói đã hết hạn").Append("</span></div>");
        if ((nothing || soon) && !string.IsNullOrWhiteSpace(store?.Phone))
        {
            var tel = new string(store!.Phone!.Where(ch => char.IsDigit(ch) || ch == '+').ToArray());
            sb.Append("<a class=\"cta\" href=\"tel:").Append(H(tel)).Append("\">Gọi phòng tập để gia hạn · ").Append(H(store.Phone)).Append("</a>");
        }
        sb.Append("</section>");

        // ── Mục lục ──
        sb.Append("<nav class=\"tabs\"><a href=\"#lich\">Lịch tập</a>");
        if (body.Count > 0) sb.Append("<a href=\"#the-trang\">Thể trạng</a>");
        sb.Append("<a href=\"#phac-do\">Phác đồ</a><a href=\"#goi\">Thẻ &amp; gói</a></nav>");

        // ── Lịch tập ──
        sb.Append("<section class=\"card\" id=\"lich\"><h2>Lịch tập</h2><div class=\"stats\">")
          .Append(Stat("Buổi tập · 30 ngày", last30.Count.ToString()))
          .Append(Stat("Giờ tập · 30 ngày", mins30.Count == 0 ? "—" : $"{Num(Math.Round(mins30.Sum() / 60m, 1))}h"))
          .Append(Stat("TB mỗi buổi", minsAll.Count == 0 ? "—" : $"{(int)Math.Round(minsAll.Average())}′"))
          .Append(Stat("Tuần liên tiếp", streak == 0 ? "—" : $"{streak} 🔥"))
          .Append("</div>");

        // Lịch 12 tuần (cột = tuần, hàng = thứ).
        var gridStart = weekStart.AddDays(-7 * 11);
        sb.Append("<div class=\"heat\" aria-label=\"Lịch tập 12 tuần\"><div class=\"heat-wd\">");
        foreach (var w in Wd) sb.Append("<span>").Append(w).Append("</span>");
        sb.Append("</div><div class=\"heat-grid\">");
        for (var col = 0; col < 12; col++)
            for (var row = 0; row < 7; row++)
            {
                var d = gridStart.AddDays(col * 7 + row);
                var cls = d > todayVn ? "fut" : days.Contains(d) ? "on" : "";
                if (d == todayVn) cls += " today";
                sb.Append("<i class=\"").Append(cls.Trim()).Append("\" title=\"").Append(d.ToString("dd/MM")).Append("\"></i>");
            }
        sb.Append("</div></div><div class=\"heat-legend muted\">12 tuần gần nhất · ô đậm = ngày có tập</div>");

        if (entered.Count == 0) sb.Append("<p class=\"muted\">Chưa có buổi tập nào.</p>");
        else sb.Append("<div class=\"visits\">");
        var shown = 0;
        foreach (var v in entered)
        {
            if (shown++ == 15)
                sb.Append("</div><details><summary>Xem thêm ").Append(entered.Count - 15).Append(" buổi</summary><div class=\"visits\">");
            var inVn = Vn(v.CheckInAt);
            var open = v.CheckOutAt == null && now - v.CheckInAt < GymVisitRules.MaxOpenVisit;
            sb.Append("<div class=\"visit\"><div class=\"date\"><small>").Append(Wd[WeekdayIndex(inVn.Date)]).Append("</small><b>")
              .Append(inVn.ToString("dd")).Append("</b><small>th").Append(inVn.Month).Append("</small></div><div class=\"vbody\">")
              .Append("<div class=\"times\">").Append(inVn.ToString("HH:mm")).Append(" → ")
              .Append(v.CheckOutAt is DateTime o ? Vn(o).ToString("HH:mm") : open ? "đang tập" : "quên quét ra");
            if (v.DurationMinutes is int dm && dm > 0)
                sb.Append("<span class=\"dur\">").Append(dm >= 60 ? $"{dm / 60}h{dm % 60:00}" : $"{dm} phút").Append("</span>");
            else if (open) sb.Append("<span class=\"dur live\">●</span>");
            sb.Append("</div>");
            if (!string.IsNullOrEmpty(v.PackageName)) sb.Append("<div class=\"muted\">").Append(H(v.PackageName)).Append("</div>");
            if (sessionNotes.TryGetValue(v.Id, out var sn))
            {
                sb.Append("<div class=\"review\">");
                if (sn.Rating is int r) sb.Append("<span class=\"star\">").Append(new string('★', r)).Append("<s>").Append(new string('★', 5 - r)).Append("</s></span> ");
                sb.Append(H(sn.Condition));
                if (sn.WeightKg is decimal w) sb.Append(" · ").Append(Num(w)).Append("kg");
                sb.Append("</div>");
            }
            sb.Append("</div></div>");
        }
        if (entered.Count > 15) sb.Append("</div></details>");
        else if (entered.Count > 0) sb.Append("</div>");
        sb.Append("</section>");

        // ── Thể trạng ──
        if (body.Count > 0)
        {
            var latest = body[0];
            var first = body[^1];
            sb.Append("<section class=\"card\" id=\"the-trang\"><h2>Thể trạng</h2><div class=\"muted\">Đo gần nhất ")
              .Append(Vn(latest.AssessedAt).ToString("dd/MM/yyyy"));
            if (!string.IsNullOrWhiteSpace(latest.TrainerName)) sb.Append(" · ").Append(H(latest.TrainerName));
            sb.Append("</div><div class=\"stats\">");
            string Metric(string label, decimal? now_, decimal? first_, string unit, bool lowerIsBetter)
            {
                if (now_ is not decimal n) return "";
                var delta = "";
                if (body.Count > 1 && first_ is decimal f && Math.Abs(n - f) >= 0.05m)
                {
                    var down = n < f;
                    var good = down == lowerIsBetter;
                    delta = $"<em class=\"{(good ? "up" : "down")}\">{(down ? "▼" : "▲")}{Num(Math.Abs(n - f))}{unit}</em>";
                }
                return $"<div class=\"stat\"><span>{label}</span><b>{Num(n)}<small>{unit}</small></b>{delta}</div>";
            }
            sb.Append(Metric("Cân nặng", latest.WeightKg, first.WeightKg, "kg", true))
              .Append(Metric("% mỡ", latest.BodyFatPercent, first.BodyFatPercent, "%", true))
              .Append(Metric("Cơ", latest.MuscleKg, first.MuscleKg, "kg", false))
              .Append(Metric("Vòng eo", latest.WaistCm, first.WaistCm, "cm", true));
            if (latest.WeightKg is decimal bw && latest.HeightCm is decimal bh && bh > 50)
                sb.Append($"<div class=\"stat\"><span>BMI</span><b>{Num(Math.Round(bw / (bh / 100m * (bh / 100m)), 1))}</b></div>");
            sb.Append("</div>");
            if (body.Count > 1) sb.Append("<div class=\"muted small\">▲▼ so với lần đo đầu ").Append(Vn(first.AssessedAt).ToString("dd/MM/yyyy")).Append("</div>");

            // Biểu đồ cân nặng.
            var pts = body.Where(a => a.WeightKg != null).OrderBy(a => a.AssessedAt).ToList();
            if (pts.Count >= 2)
            {
                var min = pts.Min(a => a.WeightKg!.Value);
                var max = pts.Max(a => a.WeightKg!.Value);
                var span = Math.Max(0.5m, max - min);
                var coords = pts.Select((a, i) =>
                {
                    var x = 8 + i * (304.0 / (pts.Count - 1));
                    var y = 8 + (double)((max - a.WeightKg!.Value) / span) * 54;
                    return (x, y, a);
                }).ToList();
                sb.Append("<svg class=\"spark\" viewBox=\"0 0 320 92\" role=\"img\" aria-label=\"Cân nặng theo thời gian\"><polyline points=\"")
                  .Append(string.Join(' ', coords.Select(p => $"{p.x.ToString("0.#", CultureInfo.InvariantCulture)},{p.y.ToString("0.#", CultureInfo.InvariantCulture)}")))
                  .Append("\"/>");
                foreach (var (x, y, a) in coords)
                    sb.Append("<circle cx=\"").Append(x.ToString("0.#", CultureInfo.InvariantCulture)).Append("\" cy=\"")
                      .Append(y.ToString("0.#", CultureInfo.InvariantCulture)).Append("\" r=\"3.5\"/>");
                sb.Append("<text x=\"8\" y=\"88\">").Append(Vn(pts[0].AssessedAt).ToString("dd/MM")).Append(" · ").Append(Num(pts[0].WeightKg!.Value)).Append("kg</text>")
                  .Append("<text x=\"312\" y=\"88\" text-anchor=\"end\">").Append(Vn(pts[^1].AssessedAt).ToString("dd/MM")).Append(" · ").Append(Num(pts[^1].WeightKg!.Value)).Append("kg</text></svg>");
            }

            var vong = new List<string>();
            if (latest.ChestCm is decimal ch) vong.Add($"Ngực <b>{Num(ch)}</b>");
            if (latest.WaistCm is decimal wc) vong.Add($"Eo <b>{Num(wc)}</b>");
            if (latest.HipCm is decimal hp) vong.Add($"Mông <b>{Num(hp)}</b>");
            if (latest.ArmCm is decimal ar) vong.Add($"Bắp tay <b>{Num(ar)}</b>");
            if (latest.ThighCm is decimal th) vong.Add($"Đùi <b>{Num(th)}</b>");
            if (vong.Count > 0) sb.Append("<div class=\"rings\">Số đo (cm): ").Append(string.Join(" · ", vong)).Append("</div>");
            var goal = body.FirstOrDefault(a => !string.IsNullOrWhiteSpace(a.Goal))?.Goal;
            if (!string.IsNullOrWhiteSpace(goal)) sb.Append("<div class=\"goal\"><span>🎯 Mục tiêu</span>").Append(H(goal)).Append("</div>");
            if (!string.IsNullOrWhiteSpace(latest.Condition)) sb.Append("<div class=\"note\"><span>PT ghi chú</span>").Append(H(latest.Condition)).Append("</div>");

            if (body.Count > 1)
            {
                sb.Append("<details><summary>Lịch sử đo (").Append(body.Count).Append(" lần)</summary><div class=\"tbl\"><table><tr><th>Ngày</th><th>Cân</th><th>Mỡ</th><th>Cơ</th><th>Eo</th></tr>");
                static string N(decimal? x, string u) => x is decimal d ? $"{d.ToString("0.#", Vi)}{u}" : "—";
                foreach (var a in body)
                    sb.Append("<tr><td>").Append(Vn(a.AssessedAt).ToString("dd/MM/yy")).Append("</td><td>").Append(N(a.WeightKg, "kg"))
                      .Append("</td><td>").Append(N(a.BodyFatPercent, "%")).Append("</td><td>").Append(N(a.MuscleKg, "kg"))
                      .Append("</td><td>").Append(N(a.WaistCm, "cm")).Append("</td></tr>");
                sb.Append("</table></div></details>");
            }
            sb.Append("</section>");
        }

        // ── Phác đồ ──
        sb.Append("<section class=\"card\" id=\"phac-do\"><h2>Phác đồ tập</h2>");
        if (plans.Count == 0) sb.Append("<p class=\"muted\">PT chưa giao phác đồ.</p>");
        for (var i = 0; i < plans.Count; i++)
        {
            var p = plans[i];
            var meta = new List<string>();
            if (p.StartDate is DateTime sd) meta.Add("áp dụng từ " + sd.ToString("dd/MM/yyyy"));
            if (!string.IsNullOrWhiteSpace(p.TrainerName))
                meta.Add(p.TrainerName.StartsWith("PT", StringComparison.OrdinalIgnoreCase) ? p.TrainerName : "PT " + p.TrainerName);
            sb.Append(i == 0 ? "<details class=\"plan\" open>" : "<details class=\"plan\">")
              .Append("<summary><b>").Append(H(p.Title)).Append("</b>");
            if (i == 0 && plans.Count > 1) sb.Append(" <span class=\"chip ok\">Đang áp dụng</span>");
            sb.Append("<div class=\"muted\">").Append(H(string.Join(" · ", meta))).Append("</div></summary>");
            AppendPlan(sb, p.Content);
            sb.Append("</details>");
        }
        sb.Append("</section>");

        // ── Thẻ & gói (đầy đủ) ──
        sb.Append("<section class=\"card\" id=\"goi\"><h2>Thẻ &amp; gói tập</h2>");
        if (balances.Count == 0) sb.Append("<p class=\"muted\">Chưa có thẻ / gói tập.</p>");
        var active = balances.Where(b => Live(b)).ToList();
        var ended = balances.Where(b => !Live(b)).ToList();
        foreach (var b in active) AppendPack(sb, b, now);
        if (ended.Count > 0)
        {
            sb.Append("<details><summary>Thẻ / gói đã dùng hết (").Append(ended.Count).Append(")</summary>");
            foreach (var b in ended) AppendPack(sb, b, now);
            sb.Append("</details>");
        }
        sb.Append("</section>");

        // ── Chân trang ──
        sb.Append("<footer><b>").Append(H(storeName)).Append("</b>");
        if (!string.IsNullOrWhiteSpace(store?.Address)) sb.Append("<div>").Append(H(store!.Address)).Append("</div>");
        if (!string.IsNullOrWhiteSpace(store?.Phone))
        {
            var tel = new string(store!.Phone!.Where(ch => char.IsDigit(ch) || ch == '+').ToArray());
            sb.Append("<div><a href=\"tel:").Append(H(tel)).Append("\">").Append(H(store.Phone)).Append("</a></div>");
        }
        sb.Append("<p class=\"muted small\">Lưu link này (hoặc «Thêm vào màn hình chính») để xem lại bất cứ lúc nào. Cập nhật ")
          .Append(Vn(now).ToString("HH:mm dd/MM/yyyy")).Append("</p>")
          .Append("<p class=\"muted small\">Vận hành bởi <a href=\"https://sboxhrm.com\" rel=\"noopener\">SBOX HRM</a></p></footer>");
        sb.Append("</main></body></html>");

        Response.Headers.CacheControl = "no-store";
        return Content(sb.ToString(), "text/html; charset=utf-8");
    }

    static string Stat(string label, string value) => $"<div class=\"stat\"><span>{label}</span><b>{value}</b></div>";

    static void AppendPack(StringBuilder sb, PosCustomerSessionBalance b, DateTime now)
    {
        var unlimited = PosCustomerSessionBalance.IsUnlimitedCount(b.TotalSessions);
        var expired = b.ExpiresAt is DateTime e && e <= now;
        var frozen = b.FrozenAt != null && (b.FrozenUntil == null || b.FrozenUntil > now);
        var left = !unlimited && b.RemainingSessions <= 0;
        var (cls, label) = expired ? ("bad", "Hết hạn") : left ? ("bad", "Hết buổi") : frozen ? ("warn", "Bảo lưu")
            : b.ExpiresAt is DateTime soon && soon <= now.AddDays(7) ? ("warn", "Sắp hết hạn") : ("ok", "Còn hạn");
        sb.Append("<div class=\"pack\"><div><b>").Append(H(b.PackageName)).Append("</b><div class=\"muted\">")
          .Append(unlimited ? "Không giới hạn buổi" : $"Còn {b.RemainingSessions}/{b.TotalSessions} buổi");
        if (b.ExpiresAt is DateTime ex) sb.Append(" · hạn ").Append(Vn(ex).ToString("dd/MM/yyyy"));
        if (!string.IsNullOrEmpty(b.AccessHours)) sb.Append(" · giờ tập ").Append(H(b.AccessHours));
        if (frozen && b.FrozenUntil is DateTime fu) sb.Append(" · bảo lưu đến ").Append(Vn(fu).ToString("dd/MM/yyyy"));
        sb.Append("</div></div><span class=\"chip ").Append(cls).Append("\">").Append(label).Append("</span></div>");
    }

    /// <summary>
    /// Phác đồ dạng chữ → khối theo ngày: dòng «Thứ 2: …», «Chủ nhật…», «Ngày 1…», «Dinh dưỡng:…» là tiêu đề;
    /// dòng «- …» / «• …» là bài tập (danh sách); còn lại là đoạn văn.
    /// </summary>
    static void AppendPlan(StringBuilder sb, string? content)
    {
        if (string.IsNullOrWhiteSpace(content)) return;
        var inList = false;
        void CloseList()
        {
            if (!inList) return;
            sb.Append("</ul>");
            inList = false;
        }
        sb.Append("<div class=\"plan-body\">");
        foreach (var raw in content.Replace("\r", "").Split('\n'))
        {
            var line = raw.Trim();
            if (line.Length == 0) { CloseList(); continue; }
            if (line.StartsWith('-') || line.StartsWith('•') || line.StartsWith('+'))
            {
                if (!inList) { sb.Append("<ul>"); inList = true; }
                sb.Append("<li>").Append(H(line.TrimStart('-', '•', '+', ' '))).Append("</li>");
                continue;
            }
            CloseList();
            var head = line.StartsWith("Thứ", StringComparison.OrdinalIgnoreCase)
                || line.StartsWith("Chủ nhật", StringComparison.OrdinalIgnoreCase)
                || line.StartsWith("Ngày", StringComparison.OrdinalIgnoreCase)
                || line.StartsWith("Tuần", StringComparison.OrdinalIgnoreCase)
                || line.StartsWith("Buổi", StringComparison.OrdinalIgnoreCase);
            var colon = line.IndexOf(':');
            if (head)
            {
                sb.Append("<h3>").Append(H(colon > 0 ? line[..colon] : line)).Append("</h3>");
                if (colon > 0 && colon < line.Length - 1)
                    sb.Append("<div class=\"focus\">").Append(H(line[(colon + 1)..].Trim())).Append("</div>");
            }
            else if (colon > 0 && colon < 24)
                sb.Append("<p class=\"tip\"><b>").Append(H(line[..colon])).Append(":</b> ").Append(H(line[(colon + 1)..].Trim())).Append("</p>");
            else
                sb.Append("<p>").Append(H(line)).Append("</p>");
        }
        CloseList();
        sb.Append("</div>");
    }

    const string Css = """
<style>
:root{--bg:#eef3f7;--card:#fff;--ink:#0f172a;--muted:#64748b;--brand:#0e7490;--brand2:#155e75;--soft:#e0f2fe;
--ok:#15803d;--okbg:#dcfce7;--warn:#b45309;--warnbg:#fef3c7;--bad:#b91c1c;--badbg:#fee2e2;--line:#e2e8f0;--heat:#e2e8f0;--heaton:#0e7490}
@media (prefers-color-scheme:dark){:root{--bg:#0b1220;--card:#111a2b;--ink:#e2e8f0;--muted:#94a3b8;--soft:#0c3446;--line:#1f2b40;
--okbg:#0f2f1d;--ok:#4ade80;--warnbg:#3a2a0a;--warn:#fbbf24;--badbg:#3b1212;--bad:#f87171;--heat:#1f2b40;--heaton:#22d3ee}}
*{box-sizing:border-box}html{scroll-behavior:smooth}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.55 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;-webkit-text-size-adjust:100%}
a{color:var(--brand)}.wrap{max-width:720px;margin:0 auto;padding:0 16px}
.hero{background:linear-gradient(135deg,#0e7490,#155e75 60%,#1e3a5f);color:#fff;padding:20px 0 56px}
.hero .store{opacity:.85;font-size:13px;letter-spacing:.3px;text-transform:uppercase}
.who{display:flex;gap:14px;align-items:center;margin-top:10px}
.avatar{width:56px;height:56px;border-radius:50%;background:rgba(255,255,255,.18);display:grid;place-items:center;font-weight:700;font-size:20px;flex:none}
h1{margin:0;font-size:24px;line-height:1.2}
.chips{display:flex;flex-wrap:wrap;gap:6px;margin-top:6px}
.chip{display:inline-block;font-size:12px;font-weight:600;border-radius:999px;padding:2px 10px;background:var(--soft);color:var(--brand)}
.chip.ok{background:var(--okbg);color:var(--ok)}.chip.warn{background:var(--warnbg);color:var(--warn)}.chip.bad{background:var(--badbg);color:var(--bad)}
.chip.glass{background:rgba(255,255,255,.16);color:#fff}
main{padding-bottom:32px}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:16px;margin-top:12px;scroll-margin-top:60px}
.summary{margin-top:-40px;box-shadow:0 10px 30px rgba(15,23,42,.12)}
h2{font-size:17px;margin:0 0 10px}
.muted{color:var(--muted);font-size:13px}.small{font-size:12px}
.big{display:flex;align-items:baseline;gap:8px}.big b{font-size:44px;line-height:1;color:var(--brand)}.big span{color:var(--muted)}
.big.sm b{font-size:30px}
.bar{height:10px;border-radius:99px;background:var(--heat);overflow:hidden;margin:10px 0 6px}
.bar i{display:block;height:100%;border-radius:99px;background:linear-gradient(90deg,#06b6d4,#0e7490)}.bar i.warn{background:linear-gradient(90deg,#f59e0b,#d97706)}
.pack-row{border-top:1px dashed var(--line);margin-top:12px;padding-top:12px}.pack-row:first-child{border:0;margin:0;padding:0}
.cta{display:block;text-align:center;margin-top:14px;padding:12px;border-radius:12px;background:var(--brand);color:#fff;font-weight:700;text-decoration:none}
.tabs{position:sticky;top:0;z-index:5;display:flex;gap:6px;overflow-x:auto;padding:10px 0;margin-top:4px;background:var(--bg)}
.tabs{scrollbar-width:none}.tabs::-webkit-scrollbar{display:none}
.tabs a{flex:none;padding:6px 14px;border-radius:999px;background:var(--card);border:1px solid var(--line);color:var(--ink);text-decoration:none;font-size:14px;font-weight:600}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:8px;margin:8px 0}
.stat{background:var(--bg);border-radius:12px;padding:10px 12px}.stat span{display:block;font-size:12px;color:var(--muted)}
.stat b{font-size:22px}.stat small{font-size:13px;font-weight:600;margin-left:2px}.stat em{display:block;font-style:normal;font-size:12px;font-weight:700}
em.up{color:var(--ok)}em.down{color:var(--bad)}
.heat{display:flex;gap:6px;margin:12px 0 4px}.heat-wd{display:grid;grid-template-rows:repeat(7,1fr);gap:3px;font-size:10px;color:var(--muted)}
.heat-wd span{line-height:1;display:flex;align-items:center}
.heat-grid{flex:1;display:grid;grid-template-columns:repeat(12,1fr);grid-template-rows:repeat(7,1fr);grid-auto-flow:column;gap:3px}
.heat-grid i{aspect-ratio:1;border-radius:3px;background:var(--heat)}.heat-grid i.on{background:var(--heaton)}
.heat-grid i.fut{opacity:.35}.heat-grid i.today{outline:2px solid var(--warn);outline-offset:-1px}
.heat-legend{margin-bottom:8px}
.visits{display:flex;flex-direction:column;gap:8px;margin-top:8px}
.visit{display:flex;gap:12px;padding:10px;border:1px solid var(--line);border-radius:12px}
.date{width:46px;flex:none;text-align:center;line-height:1.1;border-radius:10px;background:var(--soft);padding:6px 0;color:var(--brand)}
.date b{display:block;font-size:20px}.date small{display:block;font-size:11px}
.vbody{flex:1;min-width:0}.times{font-weight:600;display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.dur{font-size:12px;font-weight:700;border-radius:99px;padding:1px 8px;background:var(--okbg);color:var(--ok)}.dur.live{animation:p 1.4s infinite}
@keyframes p{50%{opacity:.3}}
.review{margin-top:4px;font-size:13px}.star{color:#f59e0b;letter-spacing:1px}.star s{color:var(--line);text-decoration:none}
details{margin-top:8px}summary{cursor:pointer;color:var(--brand);font-weight:600;padding:6px 0}
.spark{width:100%;height:auto;margin:6px 0}.spark polyline{fill:none;stroke:var(--brand);stroke-width:2.5;stroke-linejoin:round}
.spark circle{fill:var(--card);stroke:var(--brand);stroke-width:2}.spark text{font-size:10px;fill:var(--muted)}
.rings{margin-top:8px;font-size:14px}
.goal,.note{margin-top:10px;padding:10px 12px;border-radius:12px;background:var(--bg);font-size:14px}.goal span,.note span{display:block;font-size:12px;color:var(--muted);font-weight:600}
.tbl{overflow-x:auto}table{width:100%;border-collapse:collapse;font-size:14px}td,th{padding:6px 4px;border-top:1px solid var(--line);text-align:left;white-space:nowrap}
th{color:var(--muted);font-weight:600;font-size:12px}
.plan{border:1px solid var(--line);border-radius:12px;padding:4px 12px 10px;margin-top:10px}
.plan summary{color:var(--ink)}.plan summary .muted{font-weight:400}
.plan-body h3{font-size:15px;margin:14px 0 2px;color:var(--brand)}.plan-body .focus{font-weight:600}
.plan-body ul{margin:6px 0;padding-left:20px}.plan-body li{margin:3px 0}
.plan-body p{margin:6px 0}.plan-body .tip{background:var(--bg);border-radius:10px;padding:8px 10px}
.pack{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:10px 0;border-top:1px solid var(--line)}.pack:first-of-type{border-top:0}
footer{text-align:center;margin-top:24px;font-size:14px}footer div{margin-top:2px}
@media print{.tabs,.cta{display:none}.hero{background:#0e7490 !important;-webkit-print-color-adjust:exact;print-color-adjust:exact}}
</style>
""";

    ContentResult NotFoundPage() => new()
    {
        StatusCode = 404,
        ContentType = "text/html; charset=utf-8",
        Content = "<!doctype html><html lang=\"vi\"><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\">"
            + "<meta name=\"robots\" content=\"noindex\"><title>Link không còn hiệu lực</title>"
            + "<body style=\"margin:0;font-family:system-ui;background:#eef3f7;color:#334155;display:grid;place-items:center;min-height:100vh;padding:24px\">"
            + "<div style=\"background:#fff;border-radius:16px;padding:28px;max-width:420px;text-align:center;box-shadow:0 10px 30px rgba(15,23,42,.1)\">"
            + "<div style=\"font-size:40px\">🔗</div><h2 style=\"margin:8px 0\">Link không còn hiệu lực</h2>"
            + "<p>Phòng tập đã đổi link mới. Vui lòng liên hệ lễ tân hoặc PT để nhận link xem thẻ tập.</p>"
            + "<p style=\"font-size:12px;color:#94a3b8\">SBOX HRM</p></div></body></html>",
    };
}
