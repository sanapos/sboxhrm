using System.Text;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Helpers;

/// <summary>
/// Sửa chuỗi tiếng Việt bị lỗi encoding (UTF-8 hiển thị như Latin-1 / Windows-1252).
/// </summary>
public static class VietnameseEncodingFix
{
    private static readonly Encoding Latin1 = Encoding.GetEncoding("ISO-8859-1");

    public static string TryFix(string? input)
    {
        if (string.IsNullOrEmpty(input))
            return input ?? string.Empty;

        if (!LooksLikeMojibake(input))
            return input;

        try
        {
            var bytes = Latin1.GetBytes(input);
            var decoded = Encoding.UTF8.GetString(bytes);
            return LooksLikeMojibake(decoded) ? input : decoded;
        }
        catch
        {
            return input;
        }
    }

    public static bool LooksLikeMojibake(string input)
        => input.Contains('Ã')
           || input.Contains("áº")
           || input.Contains("Æ°")
           || input.Contains("Ä'")
           || input.Contains("á»");

    /// <summary>So khớp tên danh mục (kể cả bản mojibake trong DB).</summary>
    public static bool CategoryNamesMatch(string? a, string? b)
    {
        if (string.IsNullOrWhiteSpace(a) || string.IsNullOrWhiteSpace(b))
            return false;
        if (string.Equals(a, b, StringComparison.Ordinal))
            return true;
        var fa = TryFix(a);
        var fb = TryFix(b);
        return fa == b || fb == a || fa == fb;
    }

    /// <summary>Danh mục hệ thống mặc định (UTF-8 đúng).</summary>
    public static IReadOnlyList<(string Name, CashTransactionType Type, string Icon, string Color, int SortOrder)> DefaultTransactionCategories()
        => new List<(string, CashTransactionType, string, string, int)>
        {
            ("Bán hàng", CashTransactionType.Income, "shopping_cart", "#22C55E", 1),
            ("Dịch vụ", CashTransactionType.Income, "build", "#10B981", 2),
            ("Lãi vay/đầu tư", CashTransactionType.Income, "trending_up", "#14B8A6", 3),
            ("Cho thuê", CashTransactionType.Income, "home", "#06B6D4", 4),
            ("Hoàn tiền", CashTransactionType.Income, "replay", "#0EA5E9", 5),
            ("Thu khác", CashTransactionType.Income, "add_circle", "#3B82F6", 99),
            ("Nhập hàng", CashTransactionType.Expense, "inventory", "#EF4444", 1),
            ("Lương nhân viên", CashTransactionType.Expense, "people", "#F97316", 2),
            ("Điện/Nước/Internet", CashTransactionType.Expense, "bolt", "#F59E0B", 3),
            ("Thuê mặt bằng", CashTransactionType.Expense, "storefront", "#EAB308", 4),
            ("Vận chuyển", CashTransactionType.Expense, "local_shipping", "#84CC16", 5),
            ("Marketing", CashTransactionType.Expense, "campaign", "#EC4899", 6),
            ("Văn phòng phẩm", CashTransactionType.Expense, "edit_note", "#8B5CF6", 7),
            ("Bảo trì/Sửa chữa", CashTransactionType.Expense, "handyman", "#6366F1", 8),
            ("Thuế/Phí", CashTransactionType.Expense, "receipt_long", "#A855F7", 9),
            ("Chi khác", CashTransactionType.Expense, "remove_circle", "#6B7280", 99),
            ("Phạt nhân viên", CashTransactionType.Income, "gavel", "#DC2626", 10),
            ("Thưởng nhân viên", CashTransactionType.Expense, "emoji_events", "#F59E0B", 10),
            ("Ứng lương", CashTransactionType.Expense, "account_balance_wallet", "#F97316", 11),
        };
}
