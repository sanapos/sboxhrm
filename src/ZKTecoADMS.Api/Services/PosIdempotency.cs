namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Mã chống trùng (idempotency key) do máy bán hàng sinh cho mỗi thao tác
/// (tạo đơn, báo bếp, tạo lệnh in). Máy gửi lại cùng mã khi mạng lỗi → server
/// trả lại kết quả lần trước thay vì tạo đơn / phiếu mới.
/// </summary>
public static class PosIdempotency
{
    public const int MaxLength = 64;

    /// <summary>Chuẩn hóa mã: 8–64 ký tự chữ, số, '-', '_', ':'. Sai định dạng → null (bỏ qua).</summary>
    public static string? Normalize(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var s = raw.Trim();
        if (s.Length < 8 || s.Length > MaxLength) return null;
        foreach (var c in s)
        {
            if (!(char.IsAsciiLetterOrDigit(c) || c == '-' || c == '_' || c == ':'))
                return null;
        }
        return s;
    }

    /// <summary>Lỗi trùng khóa duy nhất theo tên index (Postgres 23505 kèm tên constraint).</summary>
    public static bool IsUniqueViolation(Exception ex, string indexName)
    {
        for (var e = ex; e != null; e = e.InnerException)
        {
            if (e.Message.Contains(indexName, StringComparison.Ordinal))
                return true;
        }
        return false;
    }

    public const string SaleOrderIndex = "IX_PosSaleOrders_Store_ClientRequestId";
    public const string PrintJobIndex = "IX_PosPrintJobs_Store_ClientRequestId";
}
