using System.Text.RegularExpressions;
using ZKTecoADMS.Application.Helpers;

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
            or "propose_overtime" or "propose_attendance_fix" or "propose_penalties_for_late" or "propose_leave"
            or "propose_employee" or "propose_update_employee" or "propose_business_trip" or "propose_feedback"
            or "propose_meal" => Hr,
        "propose_cash_voucher" or "propose_update_cash_voucher" or "propose_close_cashier_shift" or "propose_supplier_payment" => Cash,
        "propose_sale_order" or "propose_customer_return" or "propose_collect_debt" or "propose_quote"
            or "propose_reservation" or "propose_einvoice" or "propose_warranty_claim" => Sale,
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
            "nghỉ phép", "xin nghỉ", "cho nghỉ", "nghỉ ốm", "nghỉ bù", "phép năm", "tuyển", "người mới",
            "công tác", "tạm ứng", "kiến nghị", "góp ý", "khiếu nại", "suất ăn", "đăng ký ăn", "cơm trưa", "hồ sơ",
            "phòng ban", "chức vụ", "nghỉ việc", "thôi việc", "chuyển phòng", "sang phòng", "số tài khoản",
        ],
        [Cash] = ["phiếu thu", "phiếu chi", "thu tiền", "chi tiền", "sổ quỹ", "quỹ", "tiền điện", "tiền nước", "chi phí", "thu chi", "tiền nhà",
            "chốt ca", "đóng ca", "kết ca", "đóng sổ", "chốt sổ", "két", "trả nợ ncc", "trả nợ nhà cung cấp", "trả tiền hàng"],
        [Sale] = ["bán", "hóa đơn", "hoá đơn", "đơn hàng", "lên đơn", "tạo đơn", "khách", "trả hàng", "ghi nợ", "trả lại", "thu nợ", "công nợ", "đòi nợ", "trả nợ",
            "báo giá", "bao gia", "đặt bàn", "đặt phòng", "đặt lịch", "đặt chỗ", "giữ bàn", "giữ phòng", "lịch hẹn", "hẹn khách",
            "đơn tạm", "gọi món", "mở bàn", "hóa đơn điện tử", "hđđt", "xuất vat", "mã số thuế", "bảo hành", "sửa máy", "seri", "imei"],
        [Stock] =
        [
            "hàng", "kho", "nhập", "kiểm kê", "xuất hủy", "hủy hàng", "nội bộ", "nhà cung cấp", "ncc", "giá bán", "giá vốn",
            "đổi giá", "sửa giá", "ngừng bán", "món", "sản phẩm", "mặt hàng", "dịch vụ",
            "chuyển kho", "chi nhánh", "đặt hàng", "gợi ý nhập", "sắp hết",
        ],
        [Promo] = ["voucher", "mã giảm", "khuyến mãi", "khuyến mại", "giảm giá", "combo", "tặng", "giờ vàng", "đồng giá"],
        [Review] = ["duyệt", "từ chối", "phê duyệt", "đơn chờ", "đơn phép", "đơn nghỉ", "xin nghỉ", "chấm công mobile", "chấm ngoài"],
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
        // «Còn bao nhiêu ngày nghỉ phép?» là câu hỏi — chỉ bắt cách nói xin / cho nghỉ.
        "xin nghỉ", "cho nghỉ", "xin phép nghỉ", "tôi nghỉ", "em nghỉ", "mai nghỉ", "muốn nghỉ", "báo giá", "bao gia",
        "đặt bàn", "đặt phòng", "đặt lịch", "đặt chỗ", "giữ bàn", "giữ phòng", "hẹn lịch",
        "nhân viên mới", "tuyển thêm", "nhận thêm",
        "công tác", "tạm ứng", "kiến nghị", "góp ý", "khiếu nại", "đăng ký ăn", "đăng ký suất", "hủy suất", "báo cơm",
        "chuyển phòng", "sang phòng", "lên chức", "cho nghỉ việc", "nghỉ việc từ", "thôi việc", "trả nợ", "xuất hđđt", "xuất vat",
        "hóa đơn điện tử", "nhận bảo hành", "tiếp nhận", "mở bàn", "gọi món", "đơn tạm",
    ];

    /// <summary>Câu muốn thêm / sửa / xóa / hủy / duyệt — cần công cụ đề xuất (bot rule chỉ mở form).</summary>
    public static bool LooksLikeAction(string query)
    {
        var q = " " + (query ?? "").ToLowerInvariant().Replace(',', ' ').Replace('.', ' ').Replace('?', ' ') + " ";
        // «Bán 2 Coca cho…», «Bán cho chị Lan…» — câu mở đầu bằng «bán» là lệnh lập hóa đơn.
        return ActionKeys.Any(q.Contains) || q.StartsWith(" bán ", StringComparison.Ordinal);
    }

    /// <summary>
    /// Dấu hiệu hỏi CÁCH DÙNG / gặp sự cố (so không dấu, nguyên từ). Không có «thế nào», «tại sao» — hay gặp trong câu hỏi
    /// số liệu («doanh thu tháng này thế nào», «tại sao lãi giảm») cần đọc báo cáo thật.
    /// </summary>
    static readonly string[] GuideMarkers =
    [
        "cach", "huong dan", "lam sao", "lam the nao", "o dau", "cho nao", "menu nao", "mo dau", "nut nao", "bam vao dau",
        "khong in", "khong in duoc", "khong duoc", "khong hien", "khong thay", "khong ket noi", "bi loi", "bao loi",
    ];

    /// <summary>Số tiền / số lượng («50k», «2 triệu», «10 thùng») — câu có số + động từ thao tác là lệnh cụ thể.</summary>
    static readonly Regex Amount = new(@"\d", RegexOptions.Compiled);

    /// <summary>«không … được» (đã bỏ dấu): «không chấm công được», «không in hóa đơn được».</summary>
    static readonly Regex CannotDo = new(@" khong (\S+ ){1,4}duoc ", RegexOptions.Compiled);

    /// <summary>
    /// Câu hỏi cách dùng trả lời được thẳng từ hướng dẫn sử dụng (không gọi AI): có dấu hiệu hỏi cách / sự cố, khớp rõ một
    /// bước hướng dẫn ([topHelpScore] ≥ <see cref="AiAssistantHelpCorpus.ConfidentScore"/>), và không phải lệnh cụ thể
    /// («hướng dẫn tạo phiếu phạt An 50k» → vẫn để agent dựng thẻ).
    /// </summary>
    public static bool IsGuideQuestion(string query, int topHelpScore)
    {
        if (topHelpScore < AiAssistantHelpCorpus.ConfidentScore) return false;
        var raw = (query ?? "").ToLowerInvariant();
        var f = " " + string.Join(' ', VnSearch.FoldText(raw).Split([' ', ',', '.', '?', '!', ':', ';'], StringSplitOptions.RemoveEmptyEntries)) + " ";
        if (!raw.Contains("lỗi") && !CannotDo.IsMatch(f) && !GuideMarkers.Any(k => f.Contains(" " + k + " "))) return false;
        return !(Amount.IsMatch(raw) && LooksLikeAction(raw));
    }
}
