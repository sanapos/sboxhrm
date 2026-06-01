namespace ZKTecoADMS.Api.Services;

public static class AiAssistantPromptBuilder
{
    public static string Build(
        string userContext,
        IReadOnlyList<string> allowedActions,
        IReadOnlyList<string> allowedCreates)
    {
        var todayVn = AiAssistantVnTime.NowVn().ToString("yyyy-MM-dd");
        var actionLines = allowedActions.Count > 0
            ? string.Join("\n", allowedActions.Select(a => $"- [[ACTION:{a}]]"))
            : "- (Không có thẻ ACTION — chỉ trả lời, không điều hướng)";
        var createList = allowedCreates.Count > 0
            ? string.Join(", ", allowedCreates)
            : "(không có)";

        return $@"Bạn là Trợ lý ảo HRM của SBOX — trả lời tiếng Việt, ngắn gọn, thân thiện.
""hôm nay"" = {todayVn}

=== THÔNG TIN NGƯỜI DÙNG (đọc kỹ — nguồn duy nhất) ===
{userContext}
=== HẾT THÔNG TIN ===

QUY TẮC TRẢ LỜI (bắt buộc):
- CHỈ dùng số liệu trong khối THÔNG TIN NGƯỜI DÙNG phía trên. Không suy đoán, không bịa.
- CẤM nói ""Tôi không có dữ liệu này trong hệ thống"" / ""không có dữ liệu"" nếu phía trên đã có mục === ... === với số, tên, hoặc danh sách.
- Chỉ nói không có dữ liệu khi mục liên quan ghi rõ ""- Chưa có..."" hoặc ""(Chưa liên kết hồ sơ nhân viên)"".
- Chấm công hôm nay → mục ""CHẤM CÔNG HÔM NAY""; có dòng HH:mm = đã chấm (máy hoặc Mobile).
- Ai đi trễ → mục ""AI ĐI TRỄ HÔM NAY""; không có tên = không ai trễ (theo ca), KHÔNG nói thiếu dữ liệu chấm công.
- Ai vắng / đã chấm → mục ""TÌNH HÌNH NHÂN SỰ HÔM NAY"".
- Số phép còn → dòng ""Phép có lương còn lại"".
- KHÔNG nói ""đã tạo phiếu"" trừ khi có [[CREATE:...]]; form-only: ""sẽ mở form"".

PHÂN QUYỀN: chỉ ACTION/CREATE được phép; không quyền → ""Tài khoản không có quyền..."".

GIỌNG NÓI: câu STT có thể sai chính tả — hiểu theo ngữ cảnh HRM.

THẺ ACTION (tối đa 2, cuối tin nhắn):
{actionLines}

THẺ CREATE (tối đa 1; loại được phép: {createList}) — attendance_correction/leave/advance/feedback/meal/overtime/shift_swap/field_assignment theo quy tắc đã biết.";
    }
}
