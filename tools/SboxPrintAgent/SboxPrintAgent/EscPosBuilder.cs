using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace SboxPrintAgent;

public static class EscPosBuilder
{
    public static byte[] TestSlip(string title, int paperDots = 576)
    {
        var text =
            $"SBOX Print Agent\n{title}\n{DateTime.Now:dd/MM/yyyy HH:mm:ss}\n\n--- OK ---\n";
        return EscPosRaster.FromText(text, paperDots);
    }

    public static byte[] FromPlainText(string text, int paperDots = 576)
        => EscPosRaster.FromText(text, paperDots);

    public static byte[] FromKitchenSlipJson(string payload, int paperDots = 576)
    {
        try
        {
            using var doc = JsonDocument.Parse(payload);
            var root = doc.RootElement;
            var cancel = root.TryGetProperty("isCancel", out var c) && c.ValueKind == JsonValueKind.True;
            var table = root.TryGetProperty("tableName", out var t) ? t.GetString() : "Bàn";
            var sender = root.TryGetProperty("senderName", out var s) ? s.GetString() : "";
            var orderNo = root.TryGetProperty("orderNo", out var o) ? o.GetString() : "";
            var when = root.TryGetProperty("sentAt", out var sa) && DateTime.TryParse(sa.GetString(), out var dt)
                ? dt.ToLocalTime().ToString("dd/MM/yyyy HH:mm")
                : DateTime.Now.ToString("dd/MM/yyyy HH:mm");

            var sb = new StringBuilder();
            sb.AppendLine(cancel ? "*** PHIẾU HỦY ***" : "*** BÁO CHẾ BIẾN ***");
            if (root.TryGetProperty("title", out var titleEl))
            {
                var title = titleEl.GetString();
                if (!string.IsNullOrWhiteSpace(title))
                {
                    sb.Clear();
                    sb.AppendLine($"*** {title} ***");
                }
            }
            var kind = root.TryGetProperty("kind", out var kindEl) ? kindEl.GetString() : "";
            if (string.Equals(kind, "kdsReady", StringComparison.OrdinalIgnoreCase))
            {
                // Phiếu trả món KDS — giống báo chế biến nhưng tối giản (ít dòng).
                var area = root.TryGetProperty("areaName", out var ar) ? ar.GetString() : "";
                var place = string.IsNullOrWhiteSpace(area)
                    ? (table ?? "Bàn")
                    : $"{table} · {area}";
                var ready = root.TryGetProperty("readyAt", out var ra) && DateTime.TryParse(ra.GetString(), out var rdt)
                    ? rdt.ToLocalTime().ToString("HH:mm")
                    : DateTime.Now.ToString("HH:mm");
                string? earliestCall = null;
                if (root.TryGetProperty("calledAt", out var ca) && DateTime.TryParse(ca.GetString(), out var cdt))
                    earliestCall = cdt.ToLocalTime().ToString("HH:mm");

                var itemLines = new List<string>();
                if (root.TryGetProperty("lines", out var readyLines) && readyLines.ValueKind == JsonValueKind.Array)
                {
                    foreach (var line in readyLines.EnumerateArray())
                    {
                        var name = line.TryGetProperty("productName", out var n) ? n.GetString() : "";
                        if (string.IsNullOrWhiteSpace(name)) continue;
                        var qty = line.TryGetProperty("qty", out var q) ? q.ToString() : "1";
                        itemLines.Add($"{qty} x {name}");
                        if (earliestCall == null &&
                            line.TryGetProperty("calledAt", out var lca) &&
                            DateTime.TryParse(lca.GetString(), out var lcdt))
                        {
                            earliestCall = lcdt.ToLocalTime().ToString("HH:mm");
                        }
                    }
                }
                if (itemLines.Count == 0)
                {
                    var product = root.TryGetProperty("productName", out var pn) ? pn.GetString() : "";
                    var qty = root.TryGetProperty("qty", out var qv) ? qv.ToString() : "1";
                    if (!string.IsNullOrWhiteSpace(product))
                        itemLines.Add($"{qty} x {product}");
                }

                sb.Clear();
                sb.AppendLine(place ?? "Bàn");
                sb.AppendLine("*** RA MÓN ***");
                foreach (var row in itemLines)
                    sb.AppendLine(row);
                if (!string.IsNullOrWhiteSpace(earliestCall))
                    sb.AppendLine($"Gọi {earliestCall} · Ra {ready}");
                else
                    sb.AppendLine($"Ra {ready}");
                return FromPlainText(sb.ToString().TrimEnd() + "\n", paperDots);
            }
            var cutPerItem = root.TryGetProperty("cutPerItem", out var cpi) && cpi.ValueKind == JsonValueKind.True;
            var header = new StringBuilder();
            header.AppendLine(table ?? "Bàn");
            header.AppendLine(cancel ? "*** PHIẾU HỦY ***" : "*** BÁO CHẾ BIẾN ***");
            header.AppendLine($"Mã HĐ: {(string.IsNullOrWhiteSpace(orderNo) ? "-" : orderNo)}");
            header.AppendLine($"NV: {sender}");
            header.AppendLine($"Gọi lúc: {when}");
            header.AppendLine("--------------------------------");
            var items = new List<(string Name, string Qty, string? Unit, string? Note)>();
            if (root.TryGetProperty("lines", out var lines) && lines.ValueKind == JsonValueKind.Array)
            {
                foreach (var line in lines.EnumerateArray())
                {
                    var name = line.TryGetProperty("productName", out var n) ? n.GetString() : "";
                    if (string.IsNullOrWhiteSpace(name)) continue;
                    var qty = line.TryGetProperty("qty", out var q) ? q.ToString() : "1";
                    var unit = line.TryGetProperty("unitName", out var u) ? u.GetString() : null;
                    var note = line.TryGetProperty("note", out var nt) ? nt.GetString() : null;
                    note = StripItemCallTime(note);
                    items.Add((name!, qty, unit, note));
                }
            }
            if (cutPerItem && items.Count > 1)
            {
                using var ms = new MemoryStream();
                var n = 1;
                foreach (var item in items)
                {
                    var one = new StringBuilder(header.ToString());
                    one.AppendLine($"{n}. {item.Name}");
                    var sl = string.IsNullOrWhiteSpace(item.Unit) ? item.Qty : $"{item.Qty} {item.Unit}";
                    one.AppendLine($"   SL: {sl}");
                    if (!string.IsNullOrWhiteSpace(item.Note))
                    {
                        foreach (var part in item.Note.Replace("\r\n", "\n").Split('\n'))
                        {
                            var p = part.Trim();
                            if (p.Length == 0) continue;
                            one.AppendLine(p.StartsWith('+') || p.StartsWith("Gọi") ? $"   {p}" : $"   * {p}");
                        }
                    }
                    one.AppendLine("--------------------------------");
                    var bytes = FromPlainText(one.ToString(), paperDots);
                    ms.Write(bytes);
                    n++;
                }
                return ms.ToArray();
            }
            var body = new StringBuilder(header.ToString());
            var i = 1;
            foreach (var item in items)
            {
                body.AppendLine($"{i}. {item.Name}");
                var sl = string.IsNullOrWhiteSpace(item.Unit) ? item.Qty : $"{item.Qty} {item.Unit}";
                body.AppendLine($"   SL: {sl}");
                if (!string.IsNullOrWhiteSpace(item.Note))
                {
                    foreach (var part in item.Note.Replace("\r\n", "\n").Split('\n'))
                    {
                        var p = part.Trim();
                        if (p.Length == 0) continue;
                        body.AppendLine(p.StartsWith('+') || p.StartsWith("Gọi") ? $"   {p}" : $"   * {p}");
                    }
                }
                i++;
            }
            return FromPlainText(body.ToString().TrimEnd() + "\n", paperDots);
        }
        catch
        {
            return FromPlainText(payload, paperDots);
        }
    }

    /// Giờ gọi chỉ in ở header phiếu — gỡ dòng «Gọi lúc HH:mm» khỏi ghi chú món.
    static string? StripItemCallTime(string? note)
    {
        if (string.IsNullOrWhiteSpace(note)) return note;
        var kept = new List<string>();
        foreach (var raw in note.Replace("\r\n", "\n").Split('\n'))
        {
            var t = raw.Trim();
            if (t.Length == 0) continue;
            if (Regex.IsMatch(t, @"^Gọi lúc\s+\d{1,2}:\d{2}"))
                continue;
            kept.Add(t);
        }
        return kept.Count == 0 ? null : string.Join("\n", kept);
    }

    public static byte[] FromSaleOrderJson(string payload, int paperDots = 576)
    {
        try
        {
            using var doc = JsonDocument.Parse(payload);
            var root = doc.RootElement;
            var sb = new StringBuilder();
            sb.AppendLine(root.TryGetProperty("documentTitle", out var dt) ? dt.GetString() : "HÓA ĐƠN");
            if (root.TryGetProperty("storeName", out var sn))
                sb.AppendLine(sn.GetString());
            if (root.TryGetProperty("order", out var order) && order.ValueKind == JsonValueKind.Object)
            {
                if (order.TryGetProperty("orderNo", out var on))
                    sb.AppendLine($"Mã: {on.GetString()}");
                if (order.TryGetProperty("totalAmount", out var ta))
                    sb.AppendLine($"Tổng: {ta}");
                if (order.TryGetProperty("lines", out var lines) && lines.ValueKind == JsonValueKind.Array)
                {
                    sb.AppendLine("--------------------------------");
                    foreach (var line in lines.EnumerateArray().Take(40))
                    {
                        var name = line.TryGetProperty("productName", out var n) ? n.GetString()
                            : line.TryGetProperty("name", out var n2) ? n2.GetString() : "?";
                        var qty = line.TryGetProperty("qty", out var q) ? q.ToString() : "1";
                        sb.AppendLine($"{qty} x {name}");
                    }
                }
            }
            sb.AppendLine("--------------------------------");
            sb.AppendLine("(SBOX Windows Agent)");
            return FromPlainText(sb.ToString(), paperDots);
        }
        catch
        {
            return FromPlainText(ExtractPrintableText(payload, "SaleInvoice"), paperDots);
        }
    }

    /// <summary>
    /// EscPosBase64: gửi nguyên nếu đã có ảnh (GS v 0).
    /// Web/A7 cũ hay gửi UTF-8 text → XP-80C lỗi font → Agent vẽ lại tiếng Việt.
    /// KitchenSlipJson / SaleOrderJson / Test / plain: luôn raster.
    /// </summary>
    public static byte[] BuildFromJob(ClaimJob job, PrinterItem? printer = null)
    {
        var format = job.PayloadFormat ?? "";
        var payload = job.Payload ?? "";
        var paperDots = EscPosRaster.PaperDots(printer?.PaperSize);

        if (format.Equals("EscPosBase64", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var raw = Convert.FromBase64String(payload.Trim());
                if (raw.Length == 0) return raw;
                // Đã có ảnh (mẫu V2) → gửi nguyên. Không vẽ lại layout thô.
                if (ContainsRaster(raw))
                    return raw;
                // EscPos chữ UTF-8 cũ (lỗi font XP) → raster lại để đọc được.
                var text = ExtractTextFromEscPos(raw);
                if (!string.IsNullOrWhiteSpace(text))
                    return FromPlainText(text, paperDots);
                return raw;
            }
            catch { /* fall through */ }
        }

        if (format.Equals("KitchenSlipJson", StringComparison.OrdinalIgnoreCase))
            return FromKitchenSlipJson(payload, paperDots);
        if (format.Equals("TestPrintJson", StringComparison.OrdinalIgnoreCase))
            return TestSlip(job.ReferenceNo ?? "TestPrint", paperDots);
        if (format.Equals("SaleOrderJson", StringComparison.OrdinalIgnoreCase))
            return FromSaleOrderJson(payload, paperDots);

        return FromPlainText(ExtractPrintableText(payload, job.DocumentType), paperDots);
    }

    static bool ContainsRaster(byte[] raw)
    {
        // GS v 0 = 1D 76 30
        for (var i = 0; i + 2 < raw.Length; i++)
        {
            if (raw[i] == 0x1D && raw[i + 1] == 0x76 && raw[i + 2] == 0x30)
                return true;
        }
        return false;
    }

    /// <summary>Bóc chữ UTF-8 từ ESC/POS text (bỏ lệnh ESC/GS), giữ tiếng Việt.</summary>
    static string ExtractTextFromEscPos(byte[] raw)
    {
        var sb = new StringBuilder();
        var i = 0;
        while (i < raw.Length)
        {
            var b = raw[i];
            if (b == 0x1B) // ESC
            {
                i++;
                if (i >= raw.Length) break;
                var cmd = raw[i++];
                // ESC @ init — no args
                if (cmd == 0x40) continue;
                // ESC a n, ESC d n, ESC e n, ESC 3 n, ESC 2, ESC ! n, ESC E n, ESC - n, ESC M n…
                if (cmd is 0x61 or 0x64 or 0x65 or 0x33 or 0x21 or 0x45 or 0x2D or 0x4D or 0x56 or 0x74 or 0x52)
                {
                    if (i < raw.Length) i++;
                    continue;
                }
                if (cmd == 0x32) continue; // ESC 2
                continue;
            }
            if (b == 0x1D) // GS
            {
                i++;
                if (i >= raw.Length) break;
                var cmd = raw[i++];
                if (cmd == 0x56 && i < raw.Length) { i++; continue; } // cut
                if (cmd == 0x21 && i < raw.Length) { i++; continue; } // size
                if (cmd == 0x42 && i < raw.Length) { i++; continue; } // beep-ish
                // skip unknown GS payload conservatively
                continue;
            }
            if (b == 0x0A || b == 0x0D)
            {
                sb.Append('\n');
                i++;
                continue;
            }
            if (b >= 0x20)
            {
                // Collect UTF-8 run
                var start = i;
                while (i < raw.Length && raw[i] != 0x1B && raw[i] != 0x1D && raw[i] != 0x0A && raw[i] != 0x0D)
                    i++;
                try
                {
                    sb.Append(Encoding.UTF8.GetString(raw, start, i - start));
                }
                catch
                {
                    sb.Append(Encoding.Latin1.GetString(raw, start, i - start));
                }
                continue;
            }
            i++;
        }
        var text = sb.ToString();
        // Gọn dòng trống
        var lines = text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        var cleaned = new StringBuilder();
        foreach (var line in lines)
        {
            var t = line.TrimEnd();
            if (t.Length == 0 && cleaned.Length == 0) continue;
            cleaned.AppendLine(t);
        }
        return cleaned.ToString().Trim();
    }

    public static string ExtractPrintableText(string? payloadJson, string? documentType)
    {
        if (string.IsNullOrWhiteSpace(payloadJson))
            return $"[SBOX] {documentType}\n(empty payload)\n";

        var trim = payloadJson.Trim();
        if (!trim.StartsWith('{') && !trim.StartsWith('['))
            return trim;

        try
        {
            using var doc = JsonDocument.Parse(trim);
            var root = doc.RootElement;
            if (root.TryGetProperty("text", out var t) && t.ValueKind == JsonValueKind.String)
                return t.GetString() ?? trim;
            if (root.TryGetProperty("content", out var c) && c.ValueKind == JsonValueKind.String)
                return c.GetString() ?? trim;
            if (root.TryGetProperty("lines", out var lines) && lines.ValueKind == JsonValueKind.Array)
            {
                var sb = new StringBuilder();
                foreach (var line in lines.EnumerateArray())
                {
                    if (line.ValueKind == JsonValueKind.String)
                        sb.AppendLine(line.GetString());
                    else if (line.TryGetProperty("text", out var lt))
                        sb.AppendLine(lt.GetString());
                    else if (line.TryGetProperty("productName", out var pn))
                        sb.AppendLine(pn.GetString());
                }
                if (sb.Length > 0) return sb.ToString();
            }
            var dump = new StringBuilder();
            dump.AppendLine($"=== SBOX {documentType} ===");
            foreach (var prop in root.EnumerateObject().Take(40))
            {
                dump.Append(prop.Name).Append(": ");
                dump.AppendLine(prop.Value.ValueKind == JsonValueKind.String
                    ? prop.Value.GetString()
                    : prop.Value.ToString());
            }
            return dump.ToString();
        }
        catch
        {
            return trim;
        }
    }
}
