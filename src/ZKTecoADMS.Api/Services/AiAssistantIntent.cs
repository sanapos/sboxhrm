namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Đoán ý định câu hỏi để chỉ gửi cho Gemini những công cụ cần dùng. Mỗi khai báo công cụ tốn vài trăm token và bị gửi
/// lại ở MỌI vòng gọi — câu hỏi kho không cần khai báo phạt / thưởng / duyệt đơn. Không đoán được nhóm nào → gửi đủ
/// (thà tốn token còn hơn trả lời "không có quyền" sai).
/// </summary>
public static class AiAssistantIntent
{
    public const string Hr = "hr", Cash = "cash", Sale = "sale", Stock = "stock", Promo = "promo", Review = "review", Manage = "manage",
        Shift = "shift", Comms = "comms";

    public static readonly IReadOnlyList<string> AllGroups = [Hr, Cash, Sale, Stock, Promo, Review, Manage, Shift, Comms];

    /// <summary>Nhóm của một công cụ propose_*.</summary>
    public static string GroupOf(string tool) => tool switch
    {
        "propose_advance" or "propose_penalty" or "propose_update_penalty" or "propose_reward" or "propose_update_reward"
            or "propose_overtime" or "propose_attendance_fix" or "propose_penalties_for_late" => Hr,
        "propose_cash_voucher" or "propose_update_cash_voucher" or "propose_close_cashier_shift" => Cash,
        "propose_sale_order" or "propose_customer_return" or "propose_collect_debt" => Sale,
        "propose_product" or "propose_purchase_receipt" or "propose_stock_count" or "propose_damage_issue"
            or "propose_internal_use" or "propose_purchase_return" or "propose_update_product" or "propose_stock_transfer" => Stock,
        "propose_assign_shift" or "propose_shift_swap" => Shift,
        "propose_announcement" or "propose_task" => Comms,
        "propose_voucher" or "propose_promotion" => Promo,
        "propose_review_requests" => Review,
        _ => Manage,
    };

    static readonly Dictionary<string, string[]> Keywords = new()
    {
        [Hr] =
        [
            "phạt", "thưởng", " ứng", "ứng lương", "tăng ca", "làm thêm", "chấm công", "quên chấm", "chấm bù", "bổ sung công",
            "đi trễ", "đi muộn", "về sớm", "lương", "nhân viên", "vắng", "nghỉ không phép", "nội quy",
        ],
        [Cash] = ["phiếu thu", "phiếu chi", "thu tiền", "chi tiền", "sổ quỹ", "quỹ", "tiền điện", "tiền nước", "chi phí", "thu chi", "tiền nhà",
            "chốt ca", "đóng ca", "kết ca", "đóng sổ", "chốt sổ", "két"],
        [Sale] = ["bán", "hóa đơn", "hoá đơn", "đơn hàng", "lên đơn", "tạo đơn", "khách", "trả hàng", "ghi nợ", "trả lại", "thu nợ", "công nợ", "đòi nợ", "trả nợ"],
        [Stock] =
        [
            "hàng", "kho", "nhập", "kiểm kê", "xuất hủy", "hủy hàng", "nội bộ", "nhà cung cấp", "ncc", "giá bán", "giá vốn",
            "đổi giá", "sửa giá", "ngừng bán", "món", "sản phẩm", "mặt hàng", "dịch vụ",
            "chuyển kho", "chi nhánh", "đặt hàng", "gợi ý nhập", "sắp hết",
        ],
        [Promo] = ["voucher", "mã giảm", "khuyến mãi", "khuyến mại", "giảm giá", "combo", "tặng", "giờ vàng", "đồng giá"],
        [Review] = ["duyệt", "từ chối", "phê duyệt", "đơn chờ", "đơn phép", "đơn nghỉ", "xin nghỉ"],
        [Manage] =
        [
            "xóa", "xoá", "hủy", "huỷ", "bỏ phiếu", "ngừng theo dõi", "sửa thông tin", "đổi số", "đổi sđt", "sửa sđt",
            "đổi tên", "sửa tên", "địa chỉ", "số điện thoại",
        ],
        [Shift] = ["xếp ca", "đổi ca", "xếp lịch", "đổi lịch", "lịch làm", "ca sáng", "ca chiều", "ca tối", "ca đêm", "ngày nghỉ"],
        [Comms] = ["thông báo", "nhắn", "giao việc", "công việc", "nhiệm vụ", "hạn chót", "deadline"],
    };

    /// <summary>
    /// Nhóm công cụ cần cho đoạn hội thoại (câu cuối + vài câu trước của người dùng — câu trả lời ngắn kiểu «ừ, 500k»
    /// vẫn thuộc việc đang làm). null = không đoán được → gửi mọi nhóm.
    /// </summary>
    public static IReadOnlySet<string>? Groups(IEnumerable<string> recentUserMessages)
    {
        var text = " " + string.Join(" ", recentUserMessages).ToLowerInvariant() + " ";
        var hit = Keywords.Where(kv => kv.Value.Any(text.Contains)).Select(kv => kv.Key).ToHashSet();
        if (hit.Count == 0) return null;
        // Xóa / hủy / sửa thông tin cần cả công cụ tìm của nhóm chứng từ đó — công cụ quản lý đã kèm sẵn find_*.
        // Duyệt đơn nhân sự hay đi kèm lập phiếu phạt / tăng ca → thêm nhóm nhân sự.
        if (hit.Contains(Review)) hit.Add(Hr);
        return hit;
    }

    static readonly string[] ActionKeys =
    [
        " tạo ", " thêm ", " lập ", " ghi ", " sửa ", " đổi ", "cập nhật", "điều chỉnh", "phạt", "thưởng", " ứng ",
        "tăng ca", "làm thêm giờ", "quên chấm", "bổ sung công", "chấm bù", "phiếu thu", "phiếu chi", "chi tiền", "thu tiền",
        "bán cho", "lên đơn", "tạo đơn", "xuất hóa đơn", "lập hóa đơn", "ghi nợ",
        "nhập kho", "nhập hàng", "kiểm kho", "kiểm kê", "xuất hủy", "hủy hàng", "dùng nội bộ", "xuất dùng",
        "trả hàng", "trả lại", "voucher", "mã giảm", "khuyến mãi", "khuyến mại", "giảm giá", "mua 1 tặng", "tặng 1",
        " xóa ", " xoá ", " hủy ", " huỷ ", "duyệt", "từ chối", "ngừng bán", "mở bán lại", "ngừng theo dõi", "hoàn tác",
        "xếp ca", "đổi ca", "xếp lịch", "chuyển kho", "thu nợ", "gửi thông báo", "thông báo cho", "nhắn cho", "giao việc",
        "chốt ca", "đóng ca", "kết ca", "đóng sổ", "đặt hàng", "nhập hàng theo",
    ];

    /// <summary>Câu muốn thêm / sửa / xóa / hủy / duyệt — cần công cụ đề xuất (bot rule chỉ mở form).</summary>
    public static bool LooksLikeAction(string query)
    {
        var q = " " + (query ?? "").ToLowerInvariant().Replace(',', ' ').Replace('.', ' ').Replace('?', ' ') + " ";
        // «Bán 2 Coca cho…», «Bán cho chị Lan…» — câu mở đầu bằng «bán» là lệnh lập hóa đơn.
        return ActionKeys.Any(q.Contains) || q.StartsWith(" bán ", StringComparison.Ordinal);
    }
}
