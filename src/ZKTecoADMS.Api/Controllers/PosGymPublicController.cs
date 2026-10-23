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
/// Trang công khai của hội viên gym (link gửi qua Zalo, không cần đăng nhập): thẻ / gói còn hạn, số buổi,
/// lượt tập (giờ vào – ra, thời gian tập), thể trạng do PT đo và phác đồ tập PT giao.
/// Mã link ngẫu nhiên 20 ký tự; đổi mã ở app làm link cũ hết hiệu lực.
/// </summary>
[ApiController]
[AllowAnonymous]
public class PosGymPublicController(ZKTecoDbContext db) : ControllerBase
{
    static string H(string? s) => WebUtility.HtmlEncode(s ?? "");
    static DateTime Vn(DateTime utc) => utc.AddHours(7);

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

        var storeName = await db.Stores.IgnoreQueryFilters().AsNoTracking()
            .Where(s => s.Id == c.StoreId).Select(s => s.Name).FirstOrDefaultAsync() ?? "";
        var now = DateTime.UtcNow;
        var balances = await db.PosCustomerSessionBalances.IgnoreQueryFilters().AsNoTracking()
            .Where(b => b.StoreId == c.StoreId && b.CustomerId == c.Id && b.Deleted == null)
            .OrderByDescending(b => b.ExpiresAt ?? b.CreatedAt)
            .Take(30)
            .ToListAsync();
        var since = now.AddDays(-60);
        var visits = await db.PosGymVisits.IgnoreQueryFilters().AsNoTracking()
            .Where(v => v.StoreId == c.StoreId && v.CustomerId == c.Id && v.Deleted == null && v.CheckInAt >= since)
            .OrderByDescending(v => v.CheckInAt)
            .Take(100)
            .Select(v => new { v.CheckInAt, v.CheckOutAt, v.DurationMinutes, v.Status })
            .ToListAsync();
        var assessments = await db.PosGymAssessments.IgnoreQueryFilters().AsNoTracking()
            .Where(a => a.StoreId == c.StoreId && a.CustomerId == c.Id && a.Deleted == null)
            .OrderByDescending(a => a.AssessedAt)
            .Take(10)
            .ToListAsync();
        var plans = await db.PosGymWorkoutPlans.IgnoreQueryFilters().AsNoTracking()
            .Where(p => p.StoreId == c.StoreId && p.CustomerId == c.Id && p.Deleted == null)
            .OrderByDescending(p => p.StartDate ?? p.CreatedAt)
            .Take(20)
            .ToListAsync();

        var sb = new StringBuilder();
        sb.Append("""
<!doctype html><html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>
""").Append(H(c.Name)).Append(" · ").Append(H(storeName)).Append("""
</title>
<style>
:root{--bg:#f3f6f9;--card:#fff;--ink:#0f172a;--muted:#64748b;--brand:#0e7490;--ok:#15803d;--warn:#b45309;--bad:#b91c1c;--line:#e2e8f0}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
header{background:var(--brand);color:#fff;padding:20px 16px 18px}header .store{opacity:.85;font-size:13px}header h1{margin:4px 0 0;font-size:22px}
main{max-width:720px;margin:0 auto;padding:12px 16px 32px}
section{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 16px;margin-top:12px}
h2{font-size:16px;margin:0 0 8px}.muted{color:var(--muted);font-size:13px}
.pack{display:flex;justify-content:space-between;gap:12px;padding:8px 0;border-top:1px solid var(--line)}.pack:first-of-type{border-top:0}
.pill{display:inline-block;font-size:12px;font-weight:600;border-radius:999px;padding:2px 8px;background:#e0f2fe;color:var(--brand)}
.pill.ok{background:#dcfce7;color:var(--ok)}.pill.warn{background:#fef3c7;color:var(--warn)}.pill.bad{background:#fee2e2;color:var(--bad)}
.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}.stat{background:var(--bg);border-radius:10px;padding:8px 10px}
.stat b{display:block;font-size:20px}table{width:100%;border-collapse:collapse;font-size:14px}
td,th{padding:6px 4px;border-top:1px solid var(--line);text-align:left}th{color:var(--muted);font-weight:600;font-size:12px}
.plan{border-top:1px solid var(--line);padding:10px 0}.plan:first-of-type{border-top:0}.plan pre{white-space:pre-wrap;font:inherit;margin:6px 0 0}
</style></head><body>
""");
        sb.Append("<header><div class=\"store\">").Append(H(storeName)).Append("</div><h1>").Append(H(c.Name)).Append("</h1>");
        if (!string.IsNullOrWhiteSpace(c.GymTrainerName))
            sb.Append("<div class=\"store\">PT phụ trách: ").Append(H(c.GymTrainerName)).Append("</div>");
        sb.Append("</header><main>");

        // Thẻ / gói
        sb.Append("<section><h2>Thẻ &amp; gói tập</h2>");
        if (balances.Count == 0) sb.Append("<div class=\"muted\">Chưa có thẻ / gói tập.</div>");
        foreach (var b in balances)
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
            sb.Append("</div></div><div><span class=\"pill ").Append(cls).Append("\">").Append(label).Append("</span></div></div>");
        }
        sb.Append("</section>");

        // Lượt tập
        var entered = visits.Where(v => !GymVisitRules.IsDenied(v.Status, v.CheckInAt, v.CheckOutAt)).ToList();
        var mins = entered.Where(v => v.DurationMinutes is > 0).Select(v => v.DurationMinutes!.Value).ToList();
        var days30 = entered.Where(v => v.CheckInAt >= now.AddDays(-30)).Select(v => Vn(v.CheckInAt).Date).Distinct().Count();
        sb.Append("<section><h2>Lịch sử tập (60 ngày)</h2><div class=\"stats\">")
          .Append("<div class=\"stat\"><span class=\"muted\">Lượt tập</span><b>").Append(entered.Count).Append("</b></div>")
          .Append("<div class=\"stat\"><span class=\"muted\">Ngày tập / 30 ngày</span><b>").Append(days30).Append("</b></div>")
          .Append("<div class=\"stat\"><span class=\"muted\">TB mỗi buổi</span><b>")
          .Append(mins.Count == 0 ? "—" : $"{(int)Math.Round(mins.Average())}′").Append("</b></div></div>");
        if (entered.Count > 0)
        {
            sb.Append("<table><tr><th>Ngày</th><th>Vào</th><th>Ra</th><th>Thời gian</th></tr>");
            foreach (var v in entered.Take(40))
            {
                var inVn = Vn(v.CheckInAt);
                sb.Append("<tr><td>").Append(inVn.ToString("dd/MM")).Append("</td><td>").Append(inVn.ToString("HH:mm"))
                  .Append("</td><td>").Append(v.CheckOutAt is DateTime o ? Vn(o).ToString("HH:mm") : "—")
                  .Append("</td><td>").Append(v.DurationMinutes is int d && d > 0 ? $"{d / 60}h{d % 60:00}" : "—").Append("</td></tr>");
            }
            sb.Append("</table>");
        }
        sb.Append("</section>");

        // Thể trạng
        if (assessments.Count > 0)
        {
            sb.Append("<section><h2>Thể trạng</h2><table><tr><th>Ngày</th><th>Cân nặng</th><th>% mỡ</th><th>Cơ</th><th>Eo</th></tr>");
            static string N(decimal? x, string u) => x is decimal d ? $"{d:0.#}{u}" : "—";
            foreach (var a in assessments)
                sb.Append("<tr><td>").Append(Vn(a.AssessedAt).ToString("dd/MM/yy")).Append("</td><td>").Append(N(a.WeightKg, "kg"))
                  .Append("</td><td>").Append(N(a.BodyFatPercent, "%")).Append("</td><td>").Append(N(a.MuscleKg, "kg"))
                  .Append("</td><td>").Append(N(a.WaistCm, "cm")).Append("</td></tr>");
            sb.Append("</table>");
            var last = assessments[0];
            if (!string.IsNullOrWhiteSpace(last.Goal)) sb.Append("<p><b>Mục tiêu:</b> ").Append(H(last.Goal)).Append("</p>");
            if (!string.IsNullOrWhiteSpace(last.Condition)) sb.Append("<p class=\"muted\">PT ghi chú: ").Append(H(last.Condition)).Append("</p>");
            sb.Append("</section>");
        }

        // Phác đồ
        sb.Append("<section><h2>Phác đồ tập</h2>");
        if (plans.Count == 0) sb.Append("<div class=\"muted\">PT chưa giao phác đồ.</div>");
        foreach (var p in plans)
        {
            sb.Append("<div class=\"plan\"><b>").Append(H(p.Title)).Append("</b><div class=\"muted\">");
            var meta = new List<string>();
            if (p.StartDate is DateTime sd) meta.Add("áp dụng từ " + sd.ToString("dd/MM/yyyy"));
            if (!string.IsNullOrWhiteSpace(p.TrainerName)) meta.Add(p.TrainerName.StartsWith("PT", StringComparison.OrdinalIgnoreCase) ? p.TrainerName : "PT " + p.TrainerName);
            sb.Append(H(string.Join(" · ", meta))).Append("</div>");
            if (!string.IsNullOrWhiteSpace(p.Content)) sb.Append("<pre>").Append(H(p.Content)).Append("</pre>");
            sb.Append("</div>");
        }
        sb.Append("</section><p class=\"muted\" style=\"text-align:center;margin-top:16px\">Cập nhật ")
          .Append(Vn(now).ToString("HH:mm dd/MM/yyyy")).Append(" · SBOX</p></main></body></html>");

        Response.Headers.CacheControl = "no-store";
        return Content(sb.ToString(), "text/html; charset=utf-8");
    }

    ContentResult NotFoundPage() => new()
    {
        StatusCode = 404,
        ContentType = "text/html; charset=utf-8",
        Content = "<!doctype html><meta charset=utf-8><meta name=viewport content=\"width=device-width,initial-scale=1\">"
            + "<body style=\"font-family:system-ui;padding:32px;text-align:center;color:#334155\">"
            + "<h2>Link không còn hiệu lực</h2><p>Vui lòng liên hệ phòng tập để nhận link mới.</p></body>",
    };
}
