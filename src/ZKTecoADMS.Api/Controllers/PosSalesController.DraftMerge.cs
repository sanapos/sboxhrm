using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Controllers;

public partial class PosSalesController
{
    /// <summary>Một dòng trong bản giỏ máy bán nhận từ server lần đồng bộ gần nhất (nền để gộp 3 chiều).</summary>
    /// <param name="KitchenSentQty">Số đã báo bếp máy thấy lúc đồng bộ (null = app cũ không gửi).</param>
    public record BaseLineDto(
        Guid? Id, Guid ProductId, Guid? VariantId, string? ToppingsJson, string? LineNote, decimal Qty,
        decimal? KitchenSentQty = null);

    public record DraftMergeResult(List<SaleLineDto> Lines, int MergedKeys);

    public const string StaleCartBeforePayMessage =
        "Món trên bàn vừa thay đổi ở máy khác — kiểm tra lại giỏ trước khi thanh toán";

    /// <summary>
    /// Gộp 3 chiều giỏ máy bán với đơn trên server, theo nhóm món (SP + biến thể + topping + ghi chú):
    /// B = giỏ lúc máy đồng bộ gần nhất, C = giỏ máy gửi lên, S = đơn hiện trên server.
    /// S == B (không ai khác sửa) hoặc S == C (lần lưu trước của chính máy này đã vào, chỉ mất phản hồi)
    /// → lấy C như cũ. Còn lại → S + (C − B): giữ phần máy khác / báo bếp vừa thêm, cộng phần máy này
    /// đổi. Trước đây luôn lấy C → máy cầm giỏ cũ lưu đè làm mất món máy khác vừa gọi.
    /// baseLines null (app cũ) → không gộp.
    /// </summary>
    public static DraftMergeResult MergeDraftLines(
        List<SaleLineDto> client, List<BaseLineDto>? baseLines, IReadOnlyList<PosSaleOrderLine> server)
    {
        if (baseLines == null) return new(client, 0);

        static string Key(Guid productId, Guid? variantId, string? toppingsJson, string? lineNote) =>
            KitchenMergeKey(productId, variantId, toppingsJson, lineNote);

        var serverById = server.ToDictionary(l => l.Id);
        var b = new Dictionary<string, decimal>();
        foreach (var l in baseLines)
        {
            // Ưu tiên khóa của dòng trên server (cùng Id) — chuỗi topping máy gửi lại có thể lệch định dạng.
            var key = l.Id is Guid id && serverById.TryGetValue(id, out var row)
                ? Key(row.ProductId, row.VariantId, row.ToppingsJson, row.LineNote)
                : Key(l.ProductId, l.VariantId, l.ToppingsJson, l.LineNote);
            b[key] = b.GetValueOrDefault(key) + l.Qty;
        }
        var c = new Dictionary<string, decimal>();
        foreach (var l in client)
        {
            var key = Key(l.ProductId, l.VariantId, l.ToppingsJson, l.LineNote);
            c[key] = c.GetValueOrDefault(key) + l.Qty;
        }
        var s = new Dictionary<string, decimal>();
        foreach (var l in server)
        {
            var key = Key(l.ProductId, l.VariantId, l.ToppingsJson, l.LineNote);
            s[key] = s.GetValueOrDefault(key) + l.Qty;
        }

        var result = client.ToList();
        var merged = 0;
        foreach (var key in s.Keys.Union(c.Keys).Union(b.Keys).ToList())
        {
            var bq = b.GetValueOrDefault(key);
            var cq = c.GetValueOrDefault(key);
            var sq = s.GetValueOrDefault(key);
            if (sq == bq || sq == cq) continue;
            var target = Math.Max(0, sq + cq - bq);
            if (target == cq) continue;
            merged++;
            var delta = target - cq;
            var idx = result
                .Select((l, i) => (l, i))
                .Where(x => Key(x.l.ProductId, x.l.VariantId, x.l.ToppingsJson, x.l.LineNote) == key)
                .Select(x => x.i)
                .ToList();
            if (delta > 0 && idx.Count > 0)
            {
                var last = idx[^1];
                result[last] = result[last] with { Qty = result[last].Qty + delta };
            }
            else if (delta > 0)
            {
                // Máy này chưa có món đó → chép dòng server (giữ giá, đã báo bếp, nhân viên…).
                foreach (var row in server.Where(l =>
                             Key(l.ProductId, l.VariantId, l.ToppingsJson, l.LineNote) == key))
                {
                    if (delta <= 0) break;
                    var take = Math.Min(delta, row.Qty);
                    delta -= take;
                    result.Add(LineDtoFromRow(row, take));
                }
            }
            else
            {
                var cut = -delta;
                for (var j = idx.Count - 1; j >= 0 && cut > 0; j--)
                {
                    var i = idx[j];
                    var take = Math.Min(cut, result[i].Qty);
                    cut -= take;
                    result[i] = result[i] with { Qty = result[i].Qty - take };
                }
                result.RemoveAll(l => l.Qty <= 0);
            }
        }
        return new(result, merged);
    }

    static SaleLineDto LineDtoFromRow(PosSaleOrderLine row, decimal qty) => new(
        row.ProductId, qty, row.UnitId, row.UnitPrice, row.VariantId,
        DiscountAmount: row.Qty > 0 ? Math.Round(row.DiscountAmount * qty / row.Qty, 0) : 0,
        LineNote: row.LineNote,
        DurationMinutes: row.DurationMinutes,
        BillableMinutes: row.BillableMinutes,
        ServiceStartedAt: row.ServiceStartedAt,
        ServiceEndedAt: row.ServiceEndedAt,
        AssignedEmployeeId: row.AssignedEmployeeId,
        KitchenSentQty: Math.Min(row.KitchenSentQty, qty),
        ToppingsJson: row.ToppingsJson,
        StaffAssignments: PosStaffCommissionHelper.ParseAssignments(row.StaffAssignmentsJson) is { Count: > 0 } staff
            ? staff
            : null,
        ServicePausedAt: row.ServicePausedAt,
        ServicePauseMinutes: row.ServicePauseMinutes,
        KitchenRound: row.KitchenRound);
}
