using System.Text;
using System.Text.Json;

namespace SboxPrintAgent;

public static class EscPosBuilder
{
    public static byte[] TestSlip(string title)
    {
        using var ms = new MemoryStream();
        ms.WriteByte(0x1B); ms.WriteByte(0x40);
        ms.WriteByte(0x1B); ms.WriteByte(0x61); ms.WriteByte(0x01);
        var line = Encoding.UTF8.GetBytes($"SBOX Print Agent\n{title}\n{DateTime.Now:dd/MM/yyyy HH:mm:ss}\n\n");
        ms.Write(line);
        ms.WriteByte(0x1B); ms.WriteByte(0x61); ms.WriteByte(0x00);
        ms.Write(Encoding.UTF8.GetBytes("--- OK ---\n\n\n"));
        ms.WriteByte(0x1D); ms.WriteByte(0x56); ms.WriteByte(0x00);
        return ms.ToArray();
    }

    public static byte[] FromPlainText(string text)
    {
        using var ms = new MemoryStream();
        ms.WriteByte(0x1B); ms.WriteByte(0x40);
        ms.WriteByte(0x1B); ms.WriteByte(0x61); ms.WriteByte(0x00);
        foreach (var line in text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n'))
            ms.Write(Encoding.UTF8.GetBytes(line + "\n"));
        ms.WriteByte(0x0A);
        ms.WriteByte(0x0A);
        ms.WriteByte(0x1D); ms.WriteByte(0x56); ms.WriteByte(0x00);
        return ms.ToArray();
    }

    public static byte[] FromKitchenSlipJson(string payload)
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
            sb.AppendLine(cancel ? "*** PHIEU HUY ***" : "*** BAO CHE BIEN ***");
            sb.AppendLine(table ?? "Ban");
            sb.AppendLine($"Ma HD: {(string.IsNullOrWhiteSpace(orderNo) ? "-" : orderNo)}");
            sb.AppendLine($"NV: {sender}");
            sb.AppendLine($"Ngay: {when}");
            sb.AppendLine("================================");
            if (root.TryGetProperty("lines", out var lines) && lines.ValueKind == JsonValueKind.Array)
            {
                var i = 1;
                foreach (var line in lines.EnumerateArray())
                {
                    var name = line.TryGetProperty("productName", out var n) ? n.GetString() : "";
                    if (string.IsNullOrWhiteSpace(name)) continue;
                    var qty = line.TryGetProperty("qty", out var q) ? q.ToString() : "1";
                    var unit = line.TryGetProperty("unitName", out var u) ? u.GetString() : null;
                    var note = line.TryGetProperty("note", out var nt) ? nt.GetString() : null;
                    sb.AppendLine($"{i}. {name}");
                    sb.AppendLine($"   SL: {qty}{(string.IsNullOrWhiteSpace(unit) ? "" : " " + unit)}");
                    if (!string.IsNullOrWhiteSpace(note))
                        sb.AppendLine($"   Ghi chu: {note}");
                    i++;
                }
            }
            sb.AppendLine("================================");
            return FromPlainText(sb.ToString());
        }
        catch
        {
            return FromPlainText(payload);
        }
    }

    public static byte[] FromSaleOrderJson(string payload)
    {
        try
        {
            using var doc = JsonDocument.Parse(payload);
            var root = doc.RootElement;
            var sb = new StringBuilder();
            sb.AppendLine(root.TryGetProperty("documentTitle", out var dt) ? dt.GetString() : "HOA DON");
            if (root.TryGetProperty("storeName", out var sn))
                sb.AppendLine(sn.GetString());
            if (root.TryGetProperty("order", out var order) && order.ValueKind == JsonValueKind.Object)
            {
                if (order.TryGetProperty("orderNo", out var on))
                    sb.AppendLine($"Ma: {on.GetString()}");
                if (order.TryGetProperty("totalAmount", out var ta))
                    sb.AppendLine($"Tong: {ta}");
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
            return FromPlainText(sb.ToString());
        }
        catch
        {
            return FromPlainText(ExtractPrintableText(payload, "SaleInvoice"));
        }
    }

    public static byte[] BuildFromJob(ClaimJob job)
    {
        var format = job.PayloadFormat ?? "";
        var payload = job.Payload ?? "";

        if (format.Equals("EscPosBase64", StringComparison.OrdinalIgnoreCase))
        {
            try { return Convert.FromBase64String(payload.Trim()); }
            catch { /* fall through */ }
        }

        if (format.Equals("KitchenSlipJson", StringComparison.OrdinalIgnoreCase))
            return FromKitchenSlipJson(payload);
        if (format.Equals("TestPrintJson", StringComparison.OrdinalIgnoreCase))
            return TestSlip(job.ReferenceNo ?? "TestPrint");
        if (format.Equals("SaleOrderJson", StringComparison.OrdinalIgnoreCase))
            return FromSaleOrderJson(payload);

        return FromPlainText(ExtractPrintableText(payload, job.DocumentType));
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
