using System.Text.Json;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Nội dung (topping + ghi chú) của dòng lúc báo bếp gần nhất. Thêm topping cho món đã báo chỉ là phần bổ sung:
/// số đã báo, số đã xong và Id dòng giữ nguyên, phiếu bếp chỉ in phần chênh lệch. Trước đây đổi topping là dòng
/// mới với bếp — in lại cả món, bếp làm thêm một phần.
/// </summary>
public static class PosKitchenContent
{
    /// <summary>Đầu tên món trên phiếu bổ sung — cùng chuỗi với posKitchenAddOnPrefix của app.</summary>
    public const string AddOnPrefix = "BỔ SUNG: ";

    record Topping(string Key, string Name, int Qty);

    public static string Serialize(string? toppingsJson, string? lineNote) =>
        JsonSerializer.Serialize(new { t = toppingsJson ?? "", n = (lineNote ?? "").Trim() });

    static (string Toppings, string Note)? TryRead(string? content)
    {
        if (string.IsNullOrWhiteSpace(content)) return null;
        try
        {
            using var doc = JsonDocument.Parse(content);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return null;
            var t = doc.RootElement.TryGetProperty("t", out var tv) && tv.ValueKind == JsonValueKind.String
                ? tv.GetString() ?? ""
                : "";
            var n = doc.RootElement.TryGetProperty("n", out var nv) && nv.ValueKind == JsonValueKind.String
                ? nv.GetString() ?? ""
                : "";
            return (t, n.Trim());
        }
        catch (JsonException)
        {
            return null;
        }
    }

    static List<Topping> ParseToppings(string? json)
    {
        var list = new List<Topping>();
        if (string.IsNullOrWhiteSpace(json)) return list;
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.ValueKind != JsonValueKind.Array) return list;
            foreach (var e in doc.RootElement.EnumerateArray())
            {
                if (e.ValueKind != JsonValueKind.Object) continue;
                var id = Text(e, "id", "Id");
                var name = Text(e, "name", "Name");
                if (id.Length == 0 && name.Length == 0) continue;
                list.Add(new Topping(id.Length > 0 ? id.ToLowerInvariant() : name, name, Qty(e)));
            }
        }
        catch (JsonException)
        {
            // JSON topping hỏng coi như không có topping — không chặn lưu đơn.
        }
        return list;
    }

    static string Text(JsonElement e, string a, string b)
    {
        if (e.TryGetProperty(a, out var v) || e.TryGetProperty(b, out v))
            return v.ValueKind == JsonValueKind.String ? (v.GetString() ?? "").Trim() : v.ToString().Trim();
        return "";
    }

    /// <summary>Thiếu / nhỏ hơn 1 → 1, khớp posToppingQty của app.</summary>
    static int Qty(JsonElement e)
    {
        if (!e.TryGetProperty("qty", out var v) && !e.TryGetProperty("Qty", out v)) return 1;
        var n = v.ValueKind == JsonValueKind.Number && v.TryGetDecimal(out var d) ? (int)d : 1;
        return n < 1 ? 1 : n;
    }

    /// <summary>Không phụ thuộc thứ tự / định dạng chuỗi JSON (giá, hoa thường Id).</summary>
    static string Signature(string? toppingsJson, string? lineNote)
    {
        var picks = ParseToppings(toppingsJson)
            .GroupBy(t => t.Key)
            .Select(g => $"{g.Key}x{g.Sum(x => x.Qty)}")
            .OrderBy(s => s, StringComparer.Ordinal);
        return $"{string.Join(",", picks)}|{(lineNote ?? "").Trim()}";
    }

    /// <summary>
    /// Khóa ghép dòng khi autosave dựng lại đơn: dòng đã báo ghép theo nội dung lúc báo, dòng khác theo nội dung hiện tại.
    /// </summary>
    public static string CarryKey(
        Guid productId, Guid? variantId, string? toppingsJson, string? lineNote, string? sentContent)
    {
        var sent = TryRead(sentContent);
        var signature = sent is { } s ? Signature(s.Toppings, s.Note) : Signature(toppingsJson, lineNote);
        return $"{productId}|{variantId}|{signature}";
    }

    /// <summary>Đã đổi so với lúc báo bếp? Chưa có mốc (dòng cũ) → coi như chưa đổi.</summary>
    public static bool Changed(string? sentContent, string? toppingsJson, string? lineNote) =>
        TryRead(sentContent) is { } s && Signature(s.Toppings, s.Note) != Signature(toppingsJson, lineNote);

    /// <summary>Chốt trạng thái bếp của dòng sau khi đã ghép số đã báo.</summary>
    public static void Settle(PosSaleOrderLine line)
    {
        if (line.KitchenSentQty <= 0)
        {
            line.KitchenSentContent = null;
            line.KitchenContentPending = false;
            line.KitchenAddOnNote = null;
            return;
        }
        line.KitchenSentContent ??= Serialize(line.ToppingsJson, line.LineNote);
        line.KitchenContentPending = Changed(line.KitchenSentContent, line.ToppingsJson, line.LineNote);
    }

    /// <summary>Phần chênh lệch để in phiếu bổ sung: <c>+ Trân châu x2</c>, <c>- Bỏ thạch</c>, ghi chú mới. Không đổi → null.</summary>
    public static string? ChangeNote(string? sentContent, string? toppingsJson, string? lineNote)
    {
        if (TryRead(sentContent) is not { } sent) return null;
        var before = ParseToppings(sent.Toppings);
        var after = ParseToppings(toppingsJson);
        var lines = new List<string>();
        foreach (var g in after.GroupBy(t => t.Key))
        {
            var diff = g.Sum(x => x.Qty) - before.Where(t => t.Key == g.Key).Sum(x => x.Qty);
            if (diff > 0) lines.Add($"+ {WithQty(g.First().Name, diff)}");
        }
        foreach (var g in before.GroupBy(t => t.Key))
        {
            var diff = g.Sum(x => x.Qty) - after.Where(t => t.Key == g.Key).Sum(x => x.Qty);
            if (diff > 0) lines.Add($"- Bỏ {WithQty(g.First().Name, diff)}");
        }
        var note = (lineNote ?? "").Trim();
        if (note != sent.Note)
            lines.Add(note.Length > 0 ? note : $"Bỏ ghi chú: {sent.Note}");
        return lines.Count == 0 ? null : string.Join("\n", lines);
    }

    static string WithQty(string name, int qty) => qty > 1 ? $"{name} x{qty}" : name;

    /// <summary>Ghi chú trên KDS: phần bổ sung lên đầu để bếp thấy ngay, rồi nội dung đầy đủ của món.</summary>
    public static string? KdsNote(string? addOnNote, string? note)
    {
        if (string.IsNullOrWhiteSpace(addOnNote)) return note;
        var head = $"Bổ sung:\n{addOnNote.Trim()}";
        return string.IsNullOrWhiteSpace(note) ? head : $"{head}\n---\n{note.Trim()}";
    }
}
