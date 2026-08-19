using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services.PaymentGateway;

/// <summary>Xác thực & parse webhook Tingee (Payment Callback + Payment Gateway IPN).</summary>
public sealed class TingeePaymentWebhookProvider : IPaymentWebhookProvider
{
    public PosPaymentNotifyProvider Provider => PosPaymentNotifyProvider.Tingee;

    public bool VerifySignature(
        string? signature,
        string? timestamp,
        string rawBody,
        string secretKey)
    {
        if (string.IsNullOrWhiteSpace(signature) ||
            string.IsNullOrWhiteSpace(timestamp) ||
            string.IsNullOrWhiteSpace(secretKey) ||
            string.IsNullOrWhiteSpace(rawBody))
            return false;

        using var doc = JsonDocument.Parse(rawBody);
        var canonical = JsonSerializer.Serialize(doc.RootElement);
        var message = $"{timestamp}:{canonical}";
        var computed = ComputeHmacSha512Hex(message, secretKey);
        return string.Equals(computed, signature.Trim(), StringComparison.OrdinalIgnoreCase);
    }

    public PaymentWebhookPayload Parse(string rawBody)
    {
        try
        {
            using var doc = JsonDocument.Parse(rawBody);
            var root = doc.RootElement;

            // Payment Gateway IPN format
            if (root.TryGetProperty("orderId", out var orderIdEl) ||
                root.TryGetProperty("OrderId", out orderIdEl))
            {
                var status = GetString(root, "status", "Status") ?? "";
                var statusCode = GetString(root, "statusCode", "StatusCode") ?? "";
                var ok = status.Equals("success", StringComparison.OrdinalIgnoreCase) ||
                         statusCode == "00";
                return new PaymentWebhookPayload(
                    IsSuccess: ok,
                    TransactionCode: GetString(root, "providerTransactionCode", "ProviderTransactionCode")
                        ?? GetString(root, "billId", "BillId")
                        ?? GetString(root, "requestId", "RequestId"),
                    ExternalOrderId: orderIdEl.GetString(),
                    ClientId: GetString(root, "clientId", "ClientId"),
                    VaAccountNumber: GetString(root, "vaAccountNumber", "VaAccountNumber"),
                    TransferContent: GetString(root, "description", "Description"),
                    Amount: GetDecimal(root, "paidAmount", "PaidAmount")
                        ?? GetDecimal(root, "amount", "Amount"),
                    TransactionAt: ParseDate(GetString(root, "paidAt", "PaidAt"))
                        ?? ParseTxnDate(GetString(root, "transactionDate", "TransactionDate")),
                    RawJson: rawBody,
                    ErrorMessage: ok ? null : (GetString(root, "message", "Message") ?? status));
            }

            // Banking Payment Callback format
            var txnCode = GetString(root, "transactionCode", "TransactionCode");
            var amount = GetDecimal(root, "amount", "Amount");
            var content = GetString(root, "content", "Content");
            var externalOrderId = ExtractOrderIdFromContent(content)
                ?? GetAdditionalData(root, "billId")
                ?? GetAdditionalData(root, "orderId");

            return new PaymentWebhookPayload(
                IsSuccess: !string.IsNullOrWhiteSpace(txnCode),
                TransactionCode: txnCode,
                ExternalOrderId: externalOrderId,
                ClientId: GetString(root, "clientId", "ClientId"),
                VaAccountNumber: GetString(root, "vaAccountNumber", "VaAccountNumber"),
                TransferContent: content,
                Amount: amount,
                TransactionAt: ParseTxnDate(GetString(root, "transactionDate", "TransactionDate")),
                RawJson: rawBody,
                ErrorMessage: string.IsNullOrWhiteSpace(txnCode) ? "Missing transactionCode" : null);
        }
        catch (Exception ex)
        {
            return new PaymentWebhookPayload(
                false, null, null, null, null, null, null, null, rawBody, ex.Message);
        }
    }

    private static string? ExtractOrderIdFromContent(string? content)
    {
        if (string.IsNullOrWhiteSpace(content)) return null;
        // POS TMP123 / HD123 / POS 123
        var parts = content.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        foreach (var p in parts)
        {
            if (p.StartsWith("TMP", StringComparison.OrdinalIgnoreCase) ||
                p.StartsWith("HD", StringComparison.OrdinalIgnoreCase))
                return p;
        }
        return null;
    }

    private static string? GetAdditionalData(JsonElement root, string name)
    {
        if (!root.TryGetProperty("additionalData", out var arr) &&
            !root.TryGetProperty("AdditionalData", out arr))
            return null;
        if (arr.ValueKind != JsonValueKind.Array) return null;
        foreach (var item in arr.EnumerateArray())
        {
            var n = GetString(item, "name", "Name");
            if (!string.Equals(n, name, StringComparison.OrdinalIgnoreCase)) continue;
            return GetString(item, "value", "Value");
        }
        return null;
    }

    private static string? GetString(JsonElement el, params string[] names)
    {
        foreach (var n in names)
        {
            if (el.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.String)
                return v.GetString();
        }
        return null;
    }

    private static decimal? GetDecimal(JsonElement el, params string[] names)
    {
        foreach (var n in names)
        {
            if (!el.TryGetProperty(n, out var v)) continue;
            if (v.ValueKind == JsonValueKind.Number && v.TryGetDecimal(out var d)) return d;
            if (v.ValueKind == JsonValueKind.String &&
                decimal.TryParse(v.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out d))
                return d;
        }
        return null;
    }

    private static DateTime? ParseDate(string? iso)
    {
        if (string.IsNullOrWhiteSpace(iso)) return null;
        if (DateTime.TryParse(iso, CultureInfo.InvariantCulture, DateTimeStyles.AdjustToUniversal, out var dt))
            return dt;
        return null;
    }

    private static DateTime? ParseTxnDate(string? yyyyMMddHHmmss)
    {
        if (string.IsNullOrWhiteSpace(yyyyMMddHHmmss)) return null;
        var s = yyyyMMddHHmmss.Trim();
        if (s.Length >= 14 &&
            DateTime.TryParseExact(s[..14], "yyyyMMddHHmmss", CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeLocal, out var dt))
            return dt;
        return null;
    }

    private static string ComputeHmacSha512Hex(string message, string secret)
    {
        var key = Encoding.UTF8.GetBytes(secret);
        var data = Encoding.UTF8.GetBytes(message);
        var hash = HMACSHA512.HashData(key, data);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}
