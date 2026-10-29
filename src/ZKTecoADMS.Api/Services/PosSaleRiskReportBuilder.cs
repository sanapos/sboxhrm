using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Báo cáo «Nguy cơ gian lận» cho chủ quán: đơn bị giảm / hủy món / hủy đơn SAU KHI ĐÃ IN TẠM TÍNH, «đá bill»
/// (xóa / hủy đơn đang có món, hủy đơn đã thu tiền), «đá món» (hủy nhiều món), không in hóa đơn, in lại nhiều lần,
/// giảm giá tay lớn, trả hàng ngay sau bán. Mỗi dấu hiệu có mức (high / medium / low), số tiền, cách kiểm tra;
/// gom theo nhân viên để thấy ai bất thường so với cả quán. Thuần tính toán (không DB) để test.
/// </summary>
/// <remarks>Đây là DẤU HIỆU cần kiểm tra, không phải kết luận gian lận — nhiều trường hợp có lý do chính đáng.</remarks>
public static class PosSaleRiskReportBuilder
{
    static readonly TimeSpan Vn = TimeSpan.FromHours(7);

    // Ngưỡng — chỉnh ở một chỗ.
    public const decimal ReduceTolerance = 1000m;        // lệch dưới 1.000đ coi như làm tròn
    public const double BigDiscountRatio = 0.2;          // giảm giá tay ≥ 20% tiền hàng
    public const decimal BigDiscountMin = 50_000m;
    public const int ReprintMin = 3;                     // in hóa đơn ≥ 3 lần
    public const int ManyVoidLines = 3;                  // hủy ≥ 3 món trên một đơn
    public const decimal ManyVoidAmount = 200_000m;
    public static readonly TimeSpan QuickReturn = TimeSpan.FromHours(24);
    const int MaxOrders = 300;

    public record OrderRow(
        Guid Id, string OrderNo, PosSaleOrderStatus Status, DateTime SoldAtUtc, decimal SubTotal, decimal Discount,
        decimal Total, string? PaymentMethod, int PrintCount, string? Cashier, string? SoldBy,
        Guid? ResourceSessionId, string? ResourceName, string? EInvoiceStatus);

    public record SessionRow(
        Guid Id, string? ResourceName, PosResourceSessionStatus Status, DateTime? BillRequestedAt,
        decimal? BillRequestedTotal, string? BillRequestedBy, int BillRequestCount);

    public record Flag(string Code, string Level, string Title, string Detail, decimal Amount);

    public record RiskOrder(
        string Key, Guid? OrderId, string? OrderNo, DateTime AtUtc, string? ResourceName, string? Staff,
        string? PaymentMethod, decimal Total, decimal? ProvisionalTotal, decimal AmountAtRisk, string Level,
        List<Flag> Flags, string HowToCheck);

    public record StaffRow(
        string Key, string Name, int Orders, int HighSignals, int MediumSignals, int LowSignals, decimal AmountAtRisk,
        int VoidsAfterBill, int ReducedAfterBill, int DroppedBills, int PaidCancels, int KitchenVoids,
        int NoReceipt, int CashOrders, double NoReceiptPct, string Level, List<string> Notes);

    public record CodeStat(string Code, string Label, string Level, int Count, decimal Amount);

    public record DayRow(DateTime DateVn, int Count, decimal Amount);

    public record Recommendation(string Level, string Title, string Detail);

    public record Summary(
        int OrdersChecked, int RiskOrders, int HighOrders, decimal AmountAtRisk, decimal ReducedAfterBillAmount,
        int VoidsAfterBill, int DroppedBills, int PaidCancels, int NoReceipt, double NoReceiptPct,
        int ProvisionalBills);

    public record Report(
        string Verdict, string VerdictText, string VerdictDetail, Summary Summary, List<CodeStat> ByCode,
        List<RiskOrder> Orders, List<StaffRow> Staff, List<DayRow> Daily, List<Recommendation> Recommendations);

    public static readonly IReadOnlyDictionary<string, (string Label, string Level)> Codes =
        new Dictionary<string, (string, string)>
        {
            ["REDUCED_AFTER_BILL"] = ("Tiền thu ít hơn tạm tính", "high"),
            ["VOID_AFTER_BILL"] = ("Hủy món / hủy đơn sau tạm tính", "high"),
            ["UNPAID_AFTER_BILL"] = ("Đã tạm tính nhưng không thu tiền", "high"),
            ["CANCEL_PAID"] = ("Hủy đơn đã thanh toán", "medium"),
            ["DROPPED_BILL"] = ("Xóa / hủy đơn đang có món (đá bill)", "medium"),
            ["MANY_VOIDS"] = ("Hủy nhiều món trên một đơn (đá món)", "medium"),
            ["QUICK_RETURN"] = ("Trả hàng ngay sau khi bán", "medium"),
            ["BIG_DISCOUNT"] = ("Giảm giá tay lớn", "medium"),
            ["REPRINT"] = ("In lại hóa đơn nhiều lần", "medium"),
            ["NO_RECEIPT"] = ("Thu tiền mặt không in hóa đơn", "low"),
        };

    sealed class Case
    {
        public List<Flag> Flags { get; } = [];
        public Guid? OrderId { get; set; }
        public string? OrderNo { get; set; }
        public DateTime At { get; set; }
        public string? Resource { get; set; }
        public HashSet<string> Staff { get; } = [];
        public decimal? Provisional { get; set; }
    }

    static string Name(string? key, IReadOnlyDictionary<string, string> names) =>
        string.IsNullOrWhiteSpace(key) ? "Không rõ"
        : names.TryGetValue(key.Trim().ToLowerInvariant(), out var n) && !string.IsNullOrWhiteSpace(n) ? n
        : key.Trim();

    static string StaffKey(string? s) => string.IsNullOrWhiteSpace(s) ? "?" : s.Trim().ToLowerInvariant();

    static bool IsCash(string? pm) => string.IsNullOrWhiteSpace(pm) || pm.Contains("mặt", StringComparison.OrdinalIgnoreCase)
        || pm.Contains("cash", StringComparison.OrdinalIgnoreCase);

    static string Money(decimal v) => $"{v:#,##0} đ".Replace(',', '.');

    static int Rank(string level) => level switch { "high" => 0, "medium" => 1, _ => 2 };

    public static Report Build(
        IReadOnlyList<OrderRow> orders,
        IReadOnlyList<SessionRow> sessions,
        IReadOnlyList<PosCancelReturnAudit> audits,
        IReadOnlyDictionary<string, string> staffNames,
        DateTime fromUtc,
        DateTime toUtc)
    {
        var byId = orders.GroupBy(o => o.Id).ToDictionary(g => g.Key, g => g.First());
        var inPeriod = orders.Where(o => o.SoldAtUtc >= fromUtc && o.SoldAtUtc < toUtc).ToList();
        var completed = inPeriod.Where(o => o.Status == PosSaleOrderStatus.Completed).ToList();
        var periodAudits = audits.Where(a => a.OccurredAt >= fromUtc && a.OccurredAt < toUtc).ToList();

        // Mỗi «vụ» gom theo đơn (hoặc theo phiên bàn khi đơn đã bị xóa / chưa có mã).
        var cases = new Dictionary<string, Case>();
        // Dấu hiệu theo nhân viên: (mã, mức, tiền).
        var staffSignals = new List<(string Staff, string Code, string Level, decimal Amount)>();

        void AddFlag(string key, Guid? orderId, string? orderNo, DateTime at, string? resource, string? staff,
            string code, string detail, decimal amount, decimal? provisional = null, string? level = null)
        {
            var (label, lv) = Codes[code];
            lv = level ?? lv;
            if (!cases.TryGetValue(key, out var c)) cases[key] = c = new Case { At = at, Resource = resource };
            c.Provisional ??= provisional;
            c.Resource ??= resource;
            if (orderNo != null && c.OrderNo == null)
            {
                c.OrderNo = orderNo;
                c.OrderId = orderId;
            }
            c.OrderId ??= orderId;
            c.Flags.Add(new Flag(code, lv, label, detail, amount));
            if (!string.IsNullOrWhiteSpace(staff)) c.Staff.Add(StaffKey(staff));
            staffSignals.Add((StaffKey(staff), code, lv, amount));
        }

        string KeyOf(Guid? orderId, Guid? sessionId, string? fallback) =>
            orderId is Guid o ? "o:" + o : sessionId is Guid s ? "s:" + s : "x:" + (fallback ?? Guid.NewGuid().ToString());

        // ── 1. Sau tạm tính: hủy món / hủy đơn ──────────────────────────────────
        foreach (var g in periodAudits.Where(a => a.AfterProvisionalBill
                     && a.ActionType is PosCancelAuditHelper.KitchenVoid or PosCancelAuditHelper.DraftCancel
                         or PosCancelAuditHelper.OrderDelete or PosCancelAuditHelper.SaleCancel)
                     .GroupBy(a => (KeyOf(a.SaleOrderId, a.ResourceSessionId, a.Id.ToString()), StaffKey(a.Actor))))
        {
            var list = g.OrderBy(a => a.OccurredAt).ToList();
            var first = list[0];
            var amount = list.Sum(a => a.Amount);
            var what = list.All(a => a.ActionType == PosCancelAuditHelper.KitchenVoid)
                ? $"hủy {list.Count} món ({PosCancelAuditHelper.ProductSummary(list.Select(a => a.ProductName ?? "").ToList()) ?? "—"})"
                : "hủy / xóa cả đơn";
            AddFlag(g.Key.Item1, first.SaleOrderId, first.OrderNo, first.OccurredAt, first.ResourceName, first.Actor,
                "VOID_AFTER_BILL",
                $"Khách đã được đưa phiếu tạm tính, sau đó {what} — {Money(amount)}"
                + (string.IsNullOrWhiteSpace(first.Reason) ? "" : $". Lý do ghi: «{first.Reason}»"),
                amount);
        }

        // ── 2. Tạm tính rồi thu ít hơn / không thu ──────────────────────────────
        var completedBySession = completed.Where(o => o.ResourceSessionId != null)
            .GroupBy(o => o.ResourceSessionId!.Value).ToDictionary(g => g.Key, g => g.ToList());
        var allBySession = orders.Where(o => o.ResourceSessionId != null)
            .GroupBy(o => o.ResourceSessionId!.Value).ToDictionary(g => g.Key, g => g.ToList());
        var provisionalBills = 0;
        foreach (var s in sessions.Where(s => s.BillRequestedTotal is > 0 && s.BillRequestedAt != null
                     && s.BillRequestedAt >= fromUtc && s.BillRequestedAt < toUtc))
        {
            provisionalBills++;
            var printed = s.BillRequestedTotal!.Value;
            completedBySession.TryGetValue(s.Id, out var paid);
            paid ??= [];
            var paidTotal = paid.Sum(o => o.Total);
            var main = paid.OrderByDescending(o => o.Total).FirstOrDefault();
            var key = main != null ? KeyOf(main.Id, null, null) : KeyOf(null, s.Id, null);
            if (paid.Count > 0 && paidTotal < printed - ReduceTolerance)
            {
                var diff = printed - paidTotal;
                AddFlag(key, main!.Id, main.OrderNo, s.BillRequestedAt!.Value, s.ResourceName ?? main.ResourceName,
                    main.Cashier, "REDUCED_AFTER_BILL",
                    $"Phiếu tạm tính in {Money(printed)} (in {s.BillRequestCount} lần) nhưng chỉ thu {Money(paidTotal)} "
                    + $"— thiếu {Money(diff)}", diff, printed);
                // Người in tạm tính khác người thu → ghi cho cả hai.
                if (!string.IsNullOrWhiteSpace(s.BillRequestedBy) && StaffKey(s.BillRequestedBy) != StaffKey(main.Cashier))
                    cases[key].Staff.Add(StaffKey(s.BillRequestedBy));
            }
            else if (paid.Count == 0 && s.Status == PosResourceSessionStatus.Closed)
            {
                // Bàn đóng mà không có hóa đơn nào được thanh toán. Có thể do gộp / chuyển bàn → mức vừa nếu đơn
                // vẫn còn (đã chuyển đi), cao nếu đơn đã bị hủy / xóa.
                allBySession.TryGetValue(s.Id, out var any);
                var stillAlive = (any ?? []).Any(o => o.Status != PosSaleOrderStatus.Cancelled);
                AddFlag(key, null, null, s.BillRequestedAt!.Value, s.ResourceName, s.BillRequestedBy,
                    "UNPAID_AFTER_BILL",
                    $"Bàn đã in tạm tính {Money(printed)} rồi đóng mà không có hóa đơn thanh toán"
                    + (stillAlive ? " (có thể do gộp / chuyển bàn — kiểm tra)" : ""),
                    printed, printed, stillAlive ? "medium" : null);
            }
        }

        // ── 3. Đá bill: hủy / xóa đơn đang có món (trước tạm tính), hủy đơn đã thu tiền ─────
        foreach (var a in periodAudits.Where(a => !a.AfterProvisionalBill && a.Amount > 0))
        {
            var key = KeyOf(a.SaleOrderId, a.ResourceSessionId, a.Id.ToString());
            switch (a.ActionType)
            {
                case PosCancelAuditHelper.DraftCancel:
                case PosCancelAuditHelper.OrderDelete:
                    AddFlag(key, a.SaleOrderId, a.OrderNo, a.OccurredAt, a.ResourceName, a.Actor, "DROPPED_BILL",
                        $"Đơn đang có món ({a.ProductName ?? "—"}) bị {(a.ActionType == PosCancelAuditHelper.OrderDelete ? "xóa" : "hủy")} "
                        + $"— {Money(a.Amount)}" + (string.IsNullOrWhiteSpace(a.Reason) ? ", không ghi lý do" : $". Lý do: «{a.Reason}»"),
                        a.Amount);
                    break;
                case PosCancelAuditHelper.SaleCancel:
                    var o = a.SaleOrderId is Guid id && byId.TryGetValue(id, out var x) ? x : null;
                    var cash = o == null || IsCash(o.PaymentMethod);
                    AddFlag(key, a.SaleOrderId, a.OrderNo, a.OccurredAt, a.ResourceName ?? o?.ResourceName, a.Actor,
                        "CANCEL_PAID",
                        $"Hủy hóa đơn đã thanh toán {Money(a.Amount)}{(o == null ? "" : $" ({o.PaymentMethod})")}"
                        + (o == null ? "" : $", {(int)Math.Max(0, (a.OccurredAt - o.SoldAtUtc).TotalMinutes)} phút sau khi bán")
                        + (string.IsNullOrWhiteSpace(a.Reason) ? "" : $". Lý do: «{a.Reason}»"),
                        a.Amount, level: cash ? "high" : null);
                    break;
                case PosCancelAuditHelper.SaleReturn:
                    var so = a.SaleOrderId is Guid rid && byId.TryGetValue(rid, out var y) ? y : null;
                    if (so != null && a.OccurredAt - so.SoldAtUtc <= QuickReturn)
                        AddFlag(key, a.SaleOrderId, a.OrderNo, a.OccurredAt, a.ResourceName ?? so.ResourceName, a.Actor,
                            "QUICK_RETURN",
                            $"Trả {a.ProductName ?? "hàng"} {Money(a.Amount)} chỉ {(int)Math.Max(0, (a.OccurredAt - so.SoldAtUtc).TotalMinutes)} phút sau khi bán"
                            + (StaffKey(a.Actor) == StaffKey(so.Cashier) ? " — cùng người bán và người trả" : ""),
                            a.Amount);
                    break;
            }
        }

        // ── 4. Đá món: nhiều món bị hủy (trước tạm tính) trên một đơn ───────────
        foreach (var g in periodAudits.Where(a => !a.AfterProvisionalBill && a.ActionType == PosCancelAuditHelper.KitchenVoid)
                     .GroupBy(a => KeyOf(a.SaleOrderId, a.ResourceSessionId, a.Id.ToString())))
        {
            var list = g.ToList();
            var amount = list.Sum(a => a.Amount);
            var first = list.OrderBy(a => a.OccurredAt).First();
            foreach (var a in list) staffSignals.Add((StaffKey(a.Actor), "KITCHEN_VOID", "low", a.Amount));
            if (list.Count < ManyVoidLines && amount < ManyVoidAmount) continue;
            AddFlag(g.Key, first.SaleOrderId, first.OrderNo, first.OccurredAt, first.ResourceName, first.Actor, "MANY_VOIDS",
                $"Hủy {list.Count} món đã báo bếp ({PosCancelAuditHelper.ProductSummary(list.Select(a => a.ProductName ?? "").ToList()) ?? "—"}) "
                + $"— {Money(amount)}", amount);
        }

        // ── 5. Hóa đơn: giảm giá tay lớn, in lại nhiều lần, không in ────────────
        var cashOrders = completed.Where(o => IsCash(o.PaymentMethod) && o.Total > 0).ToList();
        bool NotPrinted(OrderRow o) => o.PrintCount == 0 && !string.Equals(o.EInvoiceStatus, "Issued", StringComparison.OrdinalIgnoreCase);
        var noReceipt = cashOrders.Where(NotPrinted).ToList();
        var noReceiptPct = cashOrders.Count == 0 ? 0 : Math.Round(100.0 * noReceipt.Count / cashOrders.Count, 1);
        // Quán vẫn in hóa đơn cho đa số đơn → đơn không in mới đáng chú ý (quán không in thì bỏ qua).
        var storePrints = cashOrders.Count >= 10 && noReceiptPct <= 50;
        foreach (var o in completed)
        {
            var key = KeyOf(o.Id, null, null);
            if (o.Discount >= BigDiscountMin && o.SubTotal > 0 && (double)(o.Discount / o.SubTotal) >= BigDiscountRatio)
                AddFlag(key, o.Id, o.OrderNo, o.SoldAtUtc, o.ResourceName, o.Cashier, "BIG_DISCOUNT",
                    $"Giảm tay {Money(o.Discount)} trên {Money(o.SubTotal)} ({Math.Round(100 * o.Discount / o.SubTotal)}%)",
                    o.Discount);
            if (o.PrintCount >= ReprintMin)
                AddFlag(key, o.Id, o.OrderNo, o.SoldAtUtc, o.ResourceName, o.Cashier, "REPRINT",
                    $"Hóa đơn {Money(o.Total)} được in {o.PrintCount} lần — có thể dùng lại hóa đơn cũ đưa khách khác",
                    0);
        }
        foreach (var o in noReceipt)
        {
            staffSignals.Add((StaffKey(o.Cashier), "NO_RECEIPT_RAW", "low", o.Total));
            if (storePrints)
                AddFlag(KeyOf(o.Id, null, null), o.Id, o.OrderNo, o.SoldAtUtc, o.ResourceName, o.Cashier, "NO_RECEIPT",
                    $"Thu tiền mặt {Money(o.Total)} mà không in hóa đơn (quán thường in {100 - noReceiptPct:0}% đơn)",
                    0);
        }

        // ── Danh sách vụ ────────────────────────────────────────────────────────
        string HowTo(List<Flag> flags)
        {
            var codes = flags.Select(f => f.Code).ToHashSet();
            var steps = new List<string>();
            if (codes.Overlaps(["REDUCED_AFTER_BILL", "VOID_AFTER_BILL", "UNPAID_AFTER_BILL"]))
                steps.Add("Xem camera quầy / bàn đúng giờ này: khách có trả theo phiếu tạm tính không");
            if (codes.Overlaps(["DROPPED_BILL", "UNPAID_AFTER_BILL", "MANY_VOIDS"]))
                steps.Add("Hỏi bếp / bar món đã làm chưa, đối chiếu phiếu bếp");
            if (codes.Overlaps(["CANCEL_PAID", "QUICK_RETURN"]))
                steps.Add("Hỏi khách / kiểm tra tiền đã hoàn thật chưa, đối chiếu két cuối ca");
            if (codes.Contains("BIG_DISCOUNT")) steps.Add("Hỏi ai cho phép giảm giá, khách là ai");
            if (codes.Overlaps(["REPRINT", "NO_RECEIPT"])) steps.Add("Đối chiếu tiền mặt két ca với doanh thu ca");
            steps.Add("Hỏi nhân viên lý do, ghi lại kết quả");
            return string.Join("  ", steps.Select((x, i) => $"{i + 1}) {x}."));
        }

        var riskOrders = cases.Select(kv =>
            {
                var c = kv.Value;
                var o = c.OrderId is Guid id && byId.TryGetValue(id, out var x) ? x : null;
                var level = c.Flags.MinBy(f => Rank(f.Level))!.Level;
                var staff = string.Join(", ", c.Staff.Where(s => s != "?").Select(s => Name(s, staffNames)).Distinct());
                return new RiskOrder(kv.Key, c.OrderId, c.OrderNo ?? o?.OrderNo, DateTime.SpecifyKind(c.At, DateTimeKind.Utc),
                    c.Resource ?? o?.ResourceName, staff.Length == 0 ? null : staff, o?.PaymentMethod, o?.Total ?? 0,
                    c.Provisional, c.Flags.Sum(f => f.Amount), level,
                    c.Flags.OrderBy(f => Rank(f.Level)).ToList(), HowTo(c.Flags));
            })
            .Where(r => r.Level != "low" || storePrints)
            .OrderBy(r => Rank(r.Level)).ThenByDescending(r => r.AmountAtRisk).ThenByDescending(r => r.AtUtc)
            .ToList();

        // ── Theo nhân viên ──────────────────────────────────────────────────────
        var ordersByStaff = completed.GroupBy(o => StaffKey(o.Cashier)).ToDictionary(g => g.Key, g => g.ToList());
        var staffKeys = staffSignals.Select(s => s.Staff).Concat(ordersByStaff.Keys).Where(k => k != "?").Distinct();
        var staff = staffKeys.Select(k =>
            {
                var sig = staffSignals.Where(s => s.Staff == k).ToList();
                ordersByStaff.TryGetValue(k, out var mine);
                mine ??= [];
                var cash = mine.Count(o => IsCash(o.PaymentMethod) && o.Total > 0);
                var nr = sig.Count(s => s.Code == "NO_RECEIPT_RAW");
                int C(string code) => sig.Count(s => s.Code == code);
                var real = sig.Where(s => s.Code is not ("NO_RECEIPT_RAW" or "KITCHEN_VOID")).ToList();
                var high = real.Count(s => s.Level == "high");
                var medium = real.Count(s => s.Level == "medium");
                var amount = real.Sum(s => s.Amount);
                var nrPct = cash == 0 ? 0 : Math.Round(100.0 * nr / cash, 1);
                var notes = new List<string>();
                if (C("VOID_AFTER_BILL") + C("REDUCED_AFTER_BILL") + C("UNPAID_AFTER_BILL") > 0)
                    notes.Add($"{C("VOID_AFTER_BILL") + C("REDUCED_AFTER_BILL") + C("UNPAID_AFTER_BILL")} lần giảm / hủy sau tạm tính");
                if (C("DROPPED_BILL") > 0) notes.Add($"{C("DROPPED_BILL")} đơn có món bị xóa / hủy");
                if (C("CANCEL_PAID") > 0) notes.Add($"{C("CANCEL_PAID")} hóa đơn đã thu bị hủy");
                if (C("KITCHEN_VOID") >= 5) notes.Add($"{C("KITCHEN_VOID")} món bị hủy");
                // Tỷ lệ không in cao hơn hẳn cả quán.
                var nrHigh = storePrints && cash >= 5 && nrPct >= Math.Max(30, noReceiptPct * 2);
                if (nrHigh) notes.Add($"Không in hóa đơn {nrPct:0}% đơn tiền mặt (cả quán {noReceiptPct:0}%)");
                var level = high >= 2 || amount >= 500_000 ? "red"
                    : high >= 1 || medium >= 3 || nrHigh ? "yellow"
                    : "green";
                return new StaffRow(k, Name(k, staffNames), mine.Count, high, medium, sig.Count(s => s.Level == "low"),
                    amount, C("VOID_AFTER_BILL"), C("REDUCED_AFTER_BILL"), C("DROPPED_BILL"), C("CANCEL_PAID"),
                    C("KITCHEN_VOID"), nr, cash, nrPct, level, notes);
            })
            .OrderBy(s => s.Level switch { "red" => 0, "yellow" => 1, _ => 2 })
            .ThenByDescending(s => s.AmountAtRisk).ThenByDescending(s => s.Orders)
            .ToList();

        // ── Tổng / đồ thị ───────────────────────────────────────────────────────
        var byCode = Codes.Select(kv =>
            {
                var flags = riskOrders.SelectMany(r => r.Flags).Where(f => f.Code == kv.Key).ToList();
                return new CodeStat(kv.Key, kv.Value.Label, kv.Value.Level, flags.Count, flags.Sum(f => f.Amount));
            })
            .Where(c => c.Count > 0)
            .OrderBy(c => Rank(c.Level)).ThenByDescending(c => c.Amount)
            .ToList();
        var daily = new List<DayRow>();
        var byDay = riskOrders.Where(r => r.Level != "low")
            .GroupBy(r => (r.AtUtc + Vn).Date).ToDictionary(g => g.Key, g => (g.Count(), g.Sum(r => r.AmountAtRisk)));
        for (var d = (fromUtc + Vn).Date; d < (toUtc + Vn).Date; d = d.AddDays(1))
        {
            byDay.TryGetValue(d, out var v);
            daily.Add(new DayRow(DateTime.SpecifyKind(d, DateTimeKind.Utc), v.Item1, v.Item2));
        }

        int CodeCount(string code) => byCode.FirstOrDefault(c => c.Code == code)?.Count ?? 0;
        var highOrders = riskOrders.Count(r => r.Level == "high");
        var summary = new Summary(
            inPeriod.Count, riskOrders.Count(r => r.Level != "low"), highOrders,
            riskOrders.Where(r => r.Level != "low").Sum(r => r.AmountAtRisk),
            riskOrders.SelectMany(r => r.Flags).Where(f => f.Code == "REDUCED_AFTER_BILL").Sum(f => f.Amount),
            CodeCount("VOID_AFTER_BILL"), CodeCount("DROPPED_BILL"), CodeCount("CANCEL_PAID"),
            noReceipt.Count, noReceiptPct, provisionalBills);

        string verdict, verdictText, verdictDetail;
        if (inPeriod.Count == 0 && periodAudits.Count == 0)
        {
            verdict = "none";
            verdictText = "Chưa có đơn trong kỳ này";
            verdictDetail = "Chọn kỳ khác để xem.";
        }
        else if (highOrders > 0)
        {
            verdict = "red";
            verdictText = $"{highOrders} đơn có dấu hiệu nghiêm trọng — cần kiểm tra";
            verdictDetail = $"Tổng tiền cần soát {Money(summary.AmountAtRisk)}. Phần lớn là giảm / hủy sau khi đã đưa khách " +
                            "phiếu tạm tính hoặc hủy hóa đơn đã thu tiền. Đây là dấu hiệu, chưa chắc là gian lận — xem «Cách kiểm tra».";
        }
        else if (summary.RiskOrders > 0)
        {
            verdict = "yellow";
            verdictText = $"{summary.RiskOrders} đơn cần xem lại";
            verdictDetail = "Không có dấu hiệu nghiêm trọng, nhưng có đơn bị xóa / hủy món / giảm giá lớn. Nên xem qua cuối ngày.";
        }
        else
        {
            verdict = "green";
            verdictText = "Không thấy dấu hiệu bất thường";
            verdictDetail = $"Đã soát {inPeriod.Count} đơn: không có giảm / hủy sau tạm tính, không hủy hóa đơn đã thu.";
        }

        // ── Nên làm ─────────────────────────────────────────────────────────────
        var recs = new List<Recommendation>();
        if (CodeCount("VOID_AFTER_BILL") + CodeCount("REDUCED_AFTER_BILL") + CodeCount("UNPAID_AFTER_BILL") > 0)
            recs.Add(new("high", "Siết hủy món / sửa đơn sau tạm tính",
                "Chỉ quản lý được hủy món, giảm giá hoặc hủy đơn sau khi đã in tạm tính (Phân quyền). " +
                "Dặn thu ngân: khách thanh toán đúng số trên phiếu tạm tính, có thay đổi phải in lại."));
        if (CodeCount("CANCEL_PAID") > 0)
            recs.Add(new("high", "Không cho nhân viên tự hủy hóa đơn đã thu tiền",
                "Chỉ chủ / quản lý được hủy hóa đơn đã thanh toán; cuối ca đếm két và so với «Tổng kết cuối ngày»."));
        if (CodeCount("DROPPED_BILL") + CodeCount("MANY_VOIDS") > 0)
            recs.Add(new("medium", "Đối chiếu món hủy với bếp mỗi ngày",
                "Bếp / bar giữ phiếu hủy món (KDS); cuối ngày so số món hủy với món đã làm. Bắt buộc ghi lý do khi hủy."));
        // Quán ít in hóa đơn (≥ 30% đơn tiền mặt không in) cũng gợi ý — ô chỉ số đã báo đỏ / vàng.
        if (staff.Any(s => s.Notes.Any(n => n.StartsWith("Không in"))) || (storePrints && noReceipt.Count > 0)
            || (cashOrders.Count >= 10 && noReceiptPct >= 30))
            recs.Add(new("medium", "Luôn in hóa đơn cho khách",
                "Bật tự in hóa đơn khi thanh toán; dán bảng «Không nhận hóa đơn — báo quản lý». " +
                "Thu tiền mặt không in hóa đơn là cách hay gặp để giữ tiền lại."));
        if (CodeCount("REPRINT") > 0)
            recs.Add(new("medium", "Kiểm tra hóa đơn in lại nhiều lần",
                "Chỉ quản lý được in lại hóa đơn; hóa đơn in lại có chữ «IN LẠI»."));
        if (CodeCount("BIG_DISCOUNT") > 0)
            recs.Add(new("medium", "Giới hạn giảm giá tay",
                "Đặt mức giảm tối đa cho thu ngân; giảm lớn hơn cần quản lý duyệt hoặc dùng voucher / khuyến mãi có sẵn."));
        if (recs.Count == 0)
            recs.Add(new("ok", "Tiếp tục theo dõi", "Xem báo cáo này mỗi tuần, nhất là sau ngày đông khách."));

        return new Report(verdict, verdictText, verdictDetail, summary, byCode,
            riskOrders.Take(MaxOrders).ToList(), staff, daily, recs);
    }
}
