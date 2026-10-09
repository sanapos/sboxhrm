using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>Mẫu việc trong gói ngành.</summary>
public record TaskPackTemplate(
    string Name,
    TaskType Type,
    string? StageKey,
    decimal? Hours,
    string[] Checklist,
    TaskPriority Priority = TaskPriority.Medium,
    TaskRecurrenceType Recurrence = TaskRecurrenceType.None,
    string? RecurrenceDays = null,
    string? RecurrenceTime = null,
    int? DueAfterHours = null,
    string? Description = null,
    TaskFormField[]? Form = null,
    decimal? PieceRate = null,
    bool AssignOnShift = false,
    bool RequireCheckIn = false);

/// <summary>Gói ngành: quy trình giai đoạn + mẫu việc + checklist + biểu mẫu, cài 1 chạm.</summary>
public record TaskIndustryPack(
    string Key,
    string Name,
    string Icon,
    string Description,
    string ProjectLabel,
    string Color,
    TaskStage[] Stages,
    TaskPackTemplate[] Templates,
    string TaskLabel = "Công việc",
    bool Featured = false);

/// <summary>
/// Gói ngành dựng sẵn. 5 gói ưu tiên (Featured): F&amp;B, Xây dựng, Bán lẻ, Dịch vụ, Quản lý sale.
/// Mục checklist bắt đầu bằng "📷 " = bắt buộc chụp ảnh khi đánh dấu xong (ký tự này bị bỏ khi cài).
/// </summary>
public static class TaskIndustryPacks
{
    private const string P = "📷 ";

    private static TaskStage S(string key, string name, string color, bool done = false) =>
        new() { Key = key, Name = name, Color = color, Done = done };

    /// <summary>Trường biểu mẫu: F("Nhiệt độ tủ mát", "number", true, unit: "°C").</summary>
    private static TaskFormField F(string label, string type = "text", bool required = false,
        string[]? options = null, string? unit = null, string? hint = null, string? key = null) =>
        new() { Key = key ?? "", Label = label, Type = type, Required = required, Options = options?.ToList(), Unit = unit, Hint = hint };

    private static readonly TaskStage[] SimpleBoard =
    {
        S("todo", "Cần làm", "#64748B"),
        S("doing", "Đang làm", "#158DC0"),
        S("check", "Chờ kiểm tra", "#D97706"),
        S("done", "Hoàn thành", "#16A34A", true),
    };

    public static readonly TaskIndustryPack[] All =
    {
        // ─── F&B: nhà hàng, cafe, trà sữa, bếp ───
        new("fnb", "F&B — Nhà hàng / Cafe", "tools-kitchen-2",
            "Checklist mở / đóng ca theo người có ca, vệ sinh, nhiệt độ tủ, nhận hàng, kiểm kê nguyên liệu, an toàn thực phẩm, phản ánh khách.",
            "Nhóm việc", "#EA580C", SimpleBoard,
            new TaskPackTemplate[]
            {
                new("Checklist mở ca", TaskType.Routine, "doing", 0.75m, new[]
                {
                    "Bật đèn, điều hoà, nhạc", P + "Quầy bar / khu bán gọn sạch", "Kiểm tra máy pha, máy POS, máy in bill",
                    "Rã đông, sơ chế nguyên liệu theo định mức", P + "Nhiệt kế tủ mát / tủ đông",
                }, TaskPriority.High, TaskRecurrenceType.Daily, null, "06:30", 2,
                    Form: new[]
                    {
                        F("Nhiệt độ tủ mát", "number", true, unit: "°C", hint: "Chuẩn 0–5°C"),
                        F("Nhiệt độ tủ đông", "number", unit: "°C", hint: "Chuẩn ≤ -18°C"),
                        F("Tiền đầu ca trong két", "money", true),
                    }, AssignOnShift: true),
                new("Checklist đóng ca", TaskType.Routine, "doing", 0.75m, new[]
                {
                    "Vệ sinh máy pha, quầy bar", "Bảo quản nguyên liệu dư, dán nhãn ngày", P + "Bếp sạch, đã khoá gas",
                    "Đổ rác, lau sàn", P + "Tắt điện, khoá cửa",
                }, TaskPriority.High, TaskRecurrenceType.Daily, null, "21:30", 2,
                    Form: new[]
                    {
                        F("Tiền mặt cuối ca", "money", true),
                        F("Chênh lệch so với máy", "money", hint: "Thừa ghi số dương, thiếu ghi số âm"),
                        F("Ghi chú bàn giao ca sau", "textarea"),
                    }, AssignOnShift: true),
                new("Vệ sinh khu vực theo giờ", TaskType.Routine, "doing", 0.25m, new[]
                {
                    "Lau bề mặt, thay khăn", "Bổ sung giấy, xà phòng", P + "Ảnh khu vực sau vệ sinh",
                }, TaskPriority.Medium, TaskRecurrenceType.Daily, null, "10:00", 1,
                    Form: new[] { F("Khu vực", "select", true, new[] { "Nhà vệ sinh", "Sảnh khách", "Bếp", "Quầy bar", "Kho" }) },
                    AssignOnShift: true),
                new("Nhận hàng nhà cung cấp", TaskType.Procurement, "doing", 0.5m, new[]
                {
                    "Đối chiếu số lượng với đơn đặt", "Kiểm tra hạn dùng, bao bì", "Đo nhiệt độ hàng lạnh", P + "Hoá đơn / phiếu giao",
                }, Form: new[]
                {
                    F("Nhà cung cấp", "text", true),
                    F("Số hoá đơn", "text"),
                    F("Tổng tiền", "money"),
                    F("Nhiệt độ hàng lạnh", "number", unit: "°C"),
                    F("Kết quả", "select", true, new[] { "Đạt — nhập kho", "Thiếu hàng", "Không đạt — trả lại" }),
                }),
                new("Kiểm kê nguyên liệu cuối ngày", TaskType.Inspection, "check", 1, new[]
                {
                    "Đếm nguyên liệu chính", "Ghi hao hụt, hư hỏng", "Đề xuất đặt hàng ngày mai",
                }, TaskPriority.Medium, TaskRecurrenceType.Daily, null, "22:00", 2,
                    Form: new[]
                    {
                        F("Giá trị hao hụt", "money"),
                        F("Nguyên liệu cần đặt thêm", "textarea"),
                    }, AssignOnShift: true),
                new("Kiểm tra an toàn thực phẩm", TaskType.Inspection, "check", 2, new[]
                {
                    "Nhãn ngày sơ chế đầy đủ", "Thực phẩm sống / chín để riêng", "Nhân viên đội mũ, đeo găng", P + "Ảnh kho lạnh",
                }, TaskPriority.High, TaskRecurrenceType.Weekly, "1", "14:00", 24,
                    Form: new[]
                    {
                        F("Điểm đánh giá", "rating", true),
                        F("Vấn đề phát hiện", "textarea"),
                    }),
                new("Bảo trì thiết bị bếp / quầy", TaskType.Maintenance, "doing", 2, new[]
                {
                    "Vệ sinh lưới lọc, ống xả", "Kiểm tra gioăng tủ, quạt", "Ghi tình trạng thiết bị",
                }, TaskPriority.Medium, TaskRecurrenceType.Monthly, "1", "15:00", 72,
                    Form: new[]
                    {
                        F("Thiết bị", "select", true, new[] { "Máy pha cà phê", "Tủ mát", "Tủ đông", "Bếp gas", "Máy lạnh", "Máy làm đá", "Khác" }),
                        F("Tình trạng", "select", true, new[] { "Tốt", "Cần theo dõi", "Cần sửa" }),
                        F("Chi phí", "money"),
                    }),
                new("Xử lý phản ánh khách", TaskType.CustomerService, "doing", 0.5m, new[]
                {
                    "Liên hệ xin lỗi khách", "Tìm nguyên nhân", "Báo quản lý cách khắc phục",
                }, TaskPriority.Urgent, DueAfterHours: 4, Form: new[]
                {
                    F("Kênh", "select", true, new[] { "Tại quán", "Điện thoại", "Google Maps", "Facebook", "GrabFood / ShopeeFood" }),
                    F("Nội dung phản ánh", "textarea", true),
                    F("Cách xử lý", "textarea", true),
                    F("Khách hài lòng sau xử lý", "rating"),
                }),
            }, "Công việc", true),

        // ─── Xây dựng / thi công / nội thất ───
        new("construction", "Xây dựng / Thi công / Nội thất", "construction",
            "Công trình xây dựng, sửa nhà, nội thất: khảo sát → dự toán → hợp đồng → vật tư → thi công → nghiệm thu → bàn giao, nhật ký công trường có ảnh và GPS.",
            "Công trình", "#B45309",
            new[]
            {
                S("survey", "Khảo sát", "#64748B"),
                S("design", "Thiết kế & dự toán", "#7C3AED"),
                S("contract", "Ký hợp đồng", "#4F46E5"),
                S("material", "Vật tư / sản xuất", "#0891B2"),
                S("construction", "Thi công", "#158DC0"),
                S("inspection", "Nghiệm thu", "#D97706"),
                S("handover", "Bàn giao", "#16A34A", true),
                S("warranty", "Bảo hành", "#94A3B8", true),
            },
            new TaskPackTemplate[]
            {
                new("Khảo sát hiện trạng", TaskType.Survey, "survey", 3, new[]
                {
                    "Hẹn lịch với chủ nhà", P + "Ảnh hiện trạng từng khu vực", "Đo kích thước, cao độ", "Vị trí điện, nước, thoát nước",
                }, Form: new[]
                {
                    F("Diện tích", "number", true, unit: "m²"),
                    F("Hạng mục khách cần", "textarea", true),
                    F("Ngân sách dự kiến", "money"),
                    F("Thời gian mong muốn hoàn thành", "date"),
                }, RequireCheckIn: true),
                new("Thiết kế & dự toán", TaskType.Task, "design", 16, new[]
                {
                    "Bản vẽ mặt bằng", "Phối cảnh 3D (nếu có)", "Bóc khối lượng", "Lập dự toán / báo giá", "Khách duyệt",
                }, TaskPriority.High, Form: new[]
                {
                    F("Giá trị dự toán", "money", true),
                    F("Số bản vẽ", "number"),
                }),
                new("Ký hợp đồng & tạm ứng", TaskType.Task, "contract", 1, new[]
                {
                    "Chốt phạm vi, tiến độ, đợt thanh toán", P + "Hợp đồng đã ký", "Thu tạm ứng đợt 1",
                }, TaskPriority.High, Form: new[]
                {
                    F("Số hợp đồng", "text", true),
                    F("Giá trị hợp đồng", "money", true),
                    F("Tạm ứng đã thu", "money"),
                }),
                new("Đặt vật tư", TaskType.Procurement, "material", 4, new[]
                {
                    "Chốt chủng loại, màu với khách", "Đặt hàng nhà cung cấp", P + "Kiểm tra vật tư về công trình",
                }, Form: new[]
                {
                    F("Nhà cung cấp", "text"),
                    F("Giá trị vật tư", "money"),
                    F("Ngày giao", "date"),
                }),
                new("Thi công hạng mục", TaskType.Installation, "construction", 8, new[]
                {
                    P + "Ảnh trước khi làm", "Che chắn bảo vệ mặt bằng", "Thi công đúng bản vẽ", P + "Ảnh sau khi làm", "Dọn vệ sinh khu vực",
                }, TaskPriority.High, Form: new[]
                {
                    F("Hạng mục", "text", true, hint: "VD: Ốp lát nhà tắm tầng 2"),
                    F("Khối lượng", "number", true),
                    F("Đơn vị", "select", true, new[] { "m²", "m³", "md", "bộ", "cái", "điểm" }),
                }, RequireCheckIn: true),
                new("Nhật ký công trường cuối ngày", TaskType.Routine, "construction", 0.5m, new[]
                {
                    P + "Ảnh tiến độ trong ngày", "Vật tư còn thiếu", "Kế hoạch ngày mai",
                }, TaskPriority.Medium, TaskRecurrenceType.Weekly, "1,2,3,4,5,6", "17:00", 3,
                    Form: new[]
                    {
                        F("Số công nhân", "number", true),
                        F("Thời tiết", "select", true, new[] { "Nắng", "Mưa", "Âm u", "Mưa — nghỉ" }),
                        F("Khối lượng làm được hôm nay", "textarea", true),
                        F("Sự cố / vướng mắc", "textarea"),
                    }, RequireCheckIn: true),
                new("Kiểm tra an toàn lao động", TaskType.Inspection, "construction", 1, new[]
                {
                    "Mũ, giày, dây an toàn", "Giàn giáo, lan can", "Điện thi công có aptomat", P + "Ảnh khu vực nguy hiểm",
                }, TaskPriority.High, TaskRecurrenceType.Weekly, "1", "07:30", 8,
                    Form: new[]
                    {
                        F("Kết quả", "select", true, new[] { "Đạt", "Đạt — có nhắc nhở", "Không đạt" }),
                        F("Vi phạm ghi nhận", "textarea"),
                    }, RequireCheckIn: true),
                new("Nghiệm thu hạng mục", TaskType.Inspection, "inspection", 2, new[]
                {
                    "Đối chiếu bản vẽ, dự toán", "Kiểm tra chất lượng hoàn thiện", P + "Ảnh hạng mục nghiệm thu",
                }, TaskPriority.High, Form: new[]
                {
                    F("Kết quả", "select", true, new[] { "Đạt", "Đạt — cần sửa nhỏ", "Không đạt" }),
                    F("Tồn tại cần khắc phục", "textarea"),
                    F("Chữ ký đại diện chủ nhà", "signature", true),
                }, RequireCheckIn: true),
                new("Bàn giao & thanh toán đợt cuối", TaskType.Inspection, "handover", 2, new[]
                {
                    "Hướng dẫn sử dụng, bảo quản", "Bàn giao chìa khoá, hồ sơ", "Thu tiền đợt cuối", "Kích hoạt bảo hành",
                }, TaskPriority.High, Form: new[]
                {
                    F("Số tiền đã thu", "money", true),
                    F("Chữ ký khách nhận bàn giao", "signature", true),
                    F("Khách đánh giá", "rating"),
                }, RequireCheckIn: true),
                new("Bảo hành công trình", TaskType.Maintenance, "warranty", 2, new[]
                {
                    P + "Ảnh lỗi trước sửa", "Khắc phục", P + "Ảnh sau sửa",
                }, TaskPriority.Medium, Form: new[]
                {
                    F("Mô tả lỗi", "textarea", true),
                    F("Nguyên nhân", "select", true, new[] { "Lỗi vật tư", "Lỗi thi công", "Do sử dụng", "Khác" }),
                    F("Chi phí phát sinh", "money"),
                }, RequireCheckIn: true),
            }, "Hạng mục", true),

        // ─── Bán lẻ ───
        new("retail", "Bán lẻ / Cửa hàng", "building-store",
            "Mở / đóng cửa theo ca, đối soát tiền, trưng bày khuyến mãi, hàng cận date, nhận hàng, kiểm kê, đổi trả.",
            "Nhóm việc", "#0284C7", SimpleBoard,
            new TaskPackTemplate[]
            {
                new("Mở cửa hàng", TaskType.Routine, "doing", 0.5m, new[]
                {
                    P + "Mặt tiền, biển hiệu sạch", "Bật đèn, máy lạnh, nhạc", "Kệ hàng đầy, ngay ngắn", "Máy POS, máy quét, máy in sẵn sàng",
                }, TaskPriority.High, TaskRecurrenceType.Daily, null, "07:45", 1,
                    Form: new[] { F("Tiền đầu ca", "money", true) }, AssignOnShift: true),
                new("Đóng cửa & đối soát tiền", TaskType.Routine, "doing", 0.5m, new[]
                {
                    "In báo cáo cuối ca trên máy", "Đếm tiền, đối chiếu", "Tắt thiết bị", P + "Khoá cửa",
                }, TaskPriority.High, TaskRecurrenceType.Daily, null, "21:45", 1,
                    Form: new[]
                    {
                        F("Doanh thu theo máy", "money", true),
                        F("Tiền mặt đếm được", "money", true),
                        F("Chênh lệch", "money", hint: "Thừa ghi số dương, thiếu ghi số âm"),
                    }, AssignOnShift: true),
                new("Trưng bày khuyến mãi", TaskType.Task, "doing", 2, new[]
                {
                    "Lấy hàng theo danh sách", "Gắn giá / bảng khuyến mãi", P + "Ảnh khu trưng bày",
                }, Form: new[]
                {
                    F("Chương trình", "text", true),
                    F("Vị trí trưng bày", "text"),
                    F("Ảnh trưng bày hoàn thiện", "photo", true),
                }),
                new("Kiểm hàng cận date", TaskType.Inspection, "check", 1, new[]
                {
                    "Lọc hàng còn dưới 30 ngày", "Dán nhãn giảm giá / tách riêng", "Báo quản lý danh sách",
                }, TaskPriority.Medium, TaskRecurrenceType.Weekly, "1", "09:00", 8,
                    Form: new[]
                    {
                        F("Số mặt hàng cận date", "number", true),
                        F("Cách xử lý", "select", true, new[] { "Giảm giá", "Trả nhà cung cấp", "Huỷ", "Chưa xử lý" }),
                    }),
                new("Nhận hàng nhà cung cấp", TaskType.Procurement, "doing", 0.5m, new[]
                {
                    "Đối chiếu số lượng, mã hàng", "Kiểm tra hạn dùng, móp méo", P + "Phiếu giao hàng",
                }, Form: new[]
                {
                    F("Nhà cung cấp", "text", true),
                    F("Số phiếu", "text"),
                    F("Giá trị", "money"),
                    F("Thiếu / lỗi", "textarea"),
                }),
                new("Kiểm kê định kỳ", TaskType.Inspection, "check", 4, new[]
                {
                    "Chốt sổ, ngừng nhập xuất", "Đếm theo khu vực", "Đối chiếu tồn máy", "Giải trình chênh lệch",
                }, TaskPriority.High, TaskRecurrenceType.Monthly, "0", "20:00", 24,
                    Form: new[]
                    {
                        F("Số mã chênh lệch", "number", true),
                        F("Giá trị chênh lệch", "money"),
                    }),
                new("Xử lý đổi trả / khiếu nại", TaskType.CustomerService, "doing", 0.5m, new[]
                {
                    "Kiểm tra hoá đơn, tình trạng hàng", "Xử lý theo chính sách", "Ghi nhận vào hệ thống",
                }, TaskPriority.High, DueAfterHours: 24, Form: new[]
                {
                    F("Mã hoá đơn", "text", true),
                    F("Lý do", "select", true, new[] { "Lỗi sản phẩm", "Không vừa / đổi mẫu", "Giao nhầm", "Khác" }),
                    F("Cách xử lý", "select", true, new[] { "Đổi hàng", "Hoàn tiền", "Bảo hành", "Từ chối" }),
                }),
                new("Vệ sinh cửa hàng", TaskType.Routine, "doing", 0.5m, new[]
                {
                    "Lau kệ, quầy", "Lau sàn, cửa kính", P + "Ảnh sau vệ sinh",
                }, TaskPriority.Low, TaskRecurrenceType.Daily, null, "14:00", 2, AssignOnShift: true),
            }, "Công việc", true),

        // ─── Dịch vụ: sửa chữa, lắp đặt, bảo trì, vệ sinh tại nhà ───
        new("service", "Dịch vụ — Sửa chữa / Lắp đặt / Bảo trì", "tool",
            "Đơn dịch vụ tại nhà khách: tiếp nhận → hẹn lịch → check-in GPS → ảnh trước / sau → chữ ký khách → chăm sóc sau dịch vụ, tính khoán cho thợ.",
            "Đơn dịch vụ", "#0D9488",
            new[]
            {
                S("receive", "Tiếp nhận", "#64748B"),
                S("schedule", "Đã hẹn lịch", "#7C3AED"),
                S("onsite", "Đang thực hiện", "#158DC0"),
                S("quality", "Kiểm tra chất lượng", "#D97706"),
                S("done", "Hoàn thành", "#16A34A", true),
                S("followup", "Đã chăm sóc", "#94A3B8", true),
            },
            new TaskPackTemplate[]
            {
                new("Tiếp nhận yêu cầu", TaskType.CustomerService, "receive", 0.25m, new[]
                {
                    "Ghi rõ địa chỉ, SĐT", "Báo giá sơ bộ", "Hẹn giờ với khách",
                }, TaskPriority.High, DueAfterHours: 4, Form: new[]
                {
                    F("Loại dịch vụ", "select", true, new[] { "Sửa chữa", "Lắp đặt", "Bảo trì", "Vệ sinh", "Tư vấn / khảo sát" }),
                    F("Địa chỉ", "text", true),
                    F("Hẹn lúc", "date", true),
                    F("Mô tả của khách", "textarea"),
                }),
                new("Thực hiện dịch vụ tại nhà khách", TaskType.Installation, "onsite", 2, new[]
                {
                    P + "Ảnh trước khi làm", "Kiểm tra, báo khách phương án", "Thực hiện", P + "Ảnh sau khi làm", "Hướng dẫn khách sử dụng",
                }, TaskPriority.High, Form: new[]
                {
                    F("Thiết bị / hạng mục", "text", true),
                    F("Số serial", "text"),
                    F("Vật tư sử dụng", "textarea"),
                    F("Tiền vật tư", "money"),
                    F("Tiền công", "money"),
                    F("Tổng thu của khách", "money", true),
                    F("Chữ ký khách", "signature", true),
                    F("Khách đánh giá", "rating"),
                }, RequireCheckIn: true),
                new("Bảo trì định kỳ khách hợp đồng", TaskType.Maintenance, "onsite", 2, new[]
                {
                    P + "Ảnh thiết bị trước bảo trì", "Vệ sinh, kiểm tra", "Đo thông số vận hành", P + "Ảnh sau bảo trì",
                }, TaskPriority.Medium, TaskRecurrenceType.Monthly, "5", "08:00", 72,
                    Form: new[]
                    {
                        F("Thông số đo được", "text"),
                        F("Tình trạng", "select", true, new[] { "Tốt", "Cần theo dõi", "Cần thay thế" }),
                        F("Chữ ký khách", "signature", true),
                    }, RequireCheckIn: true),
                new("Gọi chăm sóc sau dịch vụ", TaskType.CustomerService, "followup", 0.25m, new[]
                {
                    "Hỏi thăm tình trạng", "Ghi nhận góp ý", "Mời đánh giá Google / Facebook",
                }, TaskPriority.Low, DueAfterHours: 72, Form: new[]
                {
                    F("Mức hài lòng", "rating", true),
                    F("Phản hồi của khách", "textarea"),
                }),
                new("Bảo hành / làm lại", TaskType.Maintenance, "onsite", 1, new[]
                {
                    P + "Ảnh lỗi", "Khắc phục", P + "Ảnh sau xử lý",
                }, TaskPriority.Urgent, DueAfterHours: 24, Form: new[]
                {
                    F("Nguyên nhân", "select", true, new[] { "Lỗi vật tư", "Lỗi tay nghề", "Khách dùng sai", "Khác" }),
                    F("Chi phí", "money"),
                    F("Chữ ký khách", "signature"),
                }, RequireCheckIn: true),
            }, "Phiếu dịch vụ", true),

        // ─── Quản lý sale ───
        new("sales", "Quản lý sale / Kinh doanh", "chart-line",
            "Theo dõi khách tiềm năng: khách mới → liên hệ → tư vấn / demo → báo giá → thương lượng → chốt, kèm báo cáo sale cuối ngày và chăm sóc sau bán.",
            "Chiến dịch", "#9333EA",
            new[]
            {
                S("lead", "Khách mới", "#64748B"),
                S("contacted", "Đã liên hệ", "#0EA5E9"),
                S("consult", "Tư vấn / demo", "#7C3AED"),
                S("quote", "Đã báo giá", "#D97706"),
                S("negotiate", "Thương lượng", "#EA580C"),
                S("won", "Chốt đơn", "#16A34A", true),
                S("lost", "Không thành", "#94A3B8", true),
            },
            new TaskPackTemplate[]
            {
                new("Gọi khách mới", TaskType.CustomerService, "lead", 0.25m, new[]
                {
                    "Gọi trong 1 giờ kể từ khi có số", "Tìm hiểu nhu cầu, ngân sách", "Hẹn tư vấn / gửi tài liệu",
                }, TaskPriority.High, DueAfterHours: 24, Form: new[]
                {
                    F("Nguồn khách", "select", true, new[] { "Facebook", "Zalo", "TikTok", "Website", "Giới thiệu", "Khách vãng lai", "Hội chợ / sự kiện" }),
                    F("Kết quả cuộc gọi", "select", true, new[] { "Quan tâm", "Chưa có nhu cầu", "Không nghe máy", "Sai số" }),
                    F("Nhu cầu", "textarea"),
                    F("Hẹn gọi lại", "date"),
                }),
                new("Gặp khách / demo", TaskType.Meeting, "consult", 1.5m, new[]
                {
                    "Chuẩn bị tài liệu, mẫu", "Trình bày giải pháp", P + "Ảnh buổi gặp / mẫu đã xem",
                }, TaskPriority.High, Form: new[]
                {
                    F("Kết quả buổi gặp", "textarea", true),
                    F("Giá trị dự kiến", "money"),
                    F("Khả năng chốt", "select", true, new[] { "Cao", "Trung bình", "Thấp" }),
                }, RequireCheckIn: true),
                new("Gửi báo giá", TaskType.Task, "quote", 1, new[]
                {
                    "Lập báo giá", "Gửi khách qua Zalo / email", "Xác nhận khách đã nhận",
                }, TaskPriority.High, DueAfterHours: 24, Form: new[]
                {
                    F("Số báo giá", "text"),
                    F("Giá trị báo giá", "money", true),
                    F("Hạn báo giá", "date"),
                }),
                new("Theo dõi báo giá / thương lượng", TaskType.CustomerService, "negotiate", 0.5m, new[]
                {
                    "Gọi hỏi phản hồi", "Ghi nhận yêu cầu điều chỉnh", "Trình quản lý nếu cần giảm giá",
                }, TaskPriority.Medium, DueAfterHours: 48, Form: new[]
                {
                    F("Phản hồi của khách", "textarea", true),
                    F("Bước tiếp theo", "select", true, new[] { "Gửi báo giá mới", "Hẹn gặp lại", "Chờ khách quyết", "Khách từ chối" }),
                }),
                new("Chốt đơn", TaskType.Task, "won", 0.5m, new[]
                {
                    "Xác nhận đơn / hợp đồng", "Thu cọc", "Chuyển bộ phận giao hàng / thi công",
                }, TaskPriority.High, Form: new[]
                {
                    F("Giá trị chốt", "money", true),
                    F("Mã đơn / hợp đồng", "text"),
                    F("Đã thu cọc", "money"),
                }),
                new("Chăm sóc sau bán", TaskType.CustomerService, "won", 0.25m, new[]
                {
                    "Hỏi thăm sau 7 ngày", "Giới thiệu sản phẩm liên quan", "Xin giới thiệu khách mới",
                }, TaskPriority.Low, DueAfterHours: 168, Form: new[]
                {
                    F("Mức hài lòng", "rating", true),
                    F("Có nhu cầu mua thêm", "select", false, new[] { "Có", "Chưa" }),
                    F("Khách được giới thiệu", "text"),
                }),
                new("Báo cáo sale cuối ngày", TaskType.Routine, "lead", 0.25m, new[]
                {
                    "Cập nhật trạng thái khách trên hệ thống", "Kế hoạch ngày mai",
                }, TaskPriority.Medium, TaskRecurrenceType.Weekly, "1,2,3,4,5,6", "17:30", 3,
                    Form: new[]
                    {
                        F("Số cuộc gọi", "number", true),
                        F("Khách mới", "number", true),
                        F("Báo giá đã gửi", "number"),
                        F("Doanh số chốt hôm nay", "money"),
                        F("Khó khăn / đề xuất", "textarea"),
                    }),
                new("Họp sale tuần", TaskType.Meeting, "lead", 1, new[]
                {
                    "Doanh số tuần so với mục tiêu", "Khách nóng cần hỗ trợ", "Mục tiêu tuần này",
                }, TaskPriority.Medium, TaskRecurrenceType.Weekly, "1", "08:30", 4,
                    Form: new[] { F("Mục tiêu doanh số tuần", "money", true) }),
            }, "Cơ hội / việc sale", true),

        // ─── Các ngành khác ───
        new("repair", "Sửa chữa / Bảo hành", "tool",
            "Tiệm sửa điện thoại, điện máy, xe, máy tính; trung tâm bảo hành: tiếp nhận → chẩn đoán → báo giá → sửa → chạy thử → trả máy.",
            "Phiếu sửa chữa", "#0891B2",
            new[]
            {
                S("receive", "Tiếp nhận", "#64748B"),
                S("diagnose", "Kiểm tra lỗi", "#7C3AED"),
                S("quote", "Báo giá / chờ khách", "#D97706"),
                S("repairing", "Đang sửa", "#158DC0"),
                S("testing", "Chạy thử", "#0891B2"),
                S("returned", "Đã trả máy", "#16A34A", true),
            },
            new TaskPackTemplate[]
            {
                new("Tiếp nhận thiết bị", TaskType.CustomerService, "receive", 0.25m, new[]
                {
                    "Ghi thông tin khách, số điện thoại", P + "Chụp ngoại quan, trầy xước", "Ghi phụ kiện kèm theo, mật khẩu", "Hẹn ngày trả",
                }),
                new("Kiểm tra, chẩn đoán lỗi", TaskType.Inspection, "diagnose", 1, new[]
                {
                    "Kiểm tra theo mô tả của khách", "Xác định linh kiện hỏng", "Ghi kết quả kiểm tra",
                }),
                new("Báo giá và chờ khách duyệt", TaskType.CustomerService, "quote", 0.25m, new[]
                {
                    "Báo giá linh kiện và công", "Khách đồng ý / từ chối", "Đặt linh kiện nếu thiếu",
                }, TaskPriority.High),
                new("Sửa chữa / thay linh kiện", TaskType.Maintenance, "repairing", 2, new[]
                {
                    "Xuất linh kiện khỏi kho", P + "Ảnh linh kiện cũ và mới", "Ghi serial linh kiện thay",
                }),
                new("Chạy thử, kiểm tra chất lượng", TaskType.Inspection, "testing", 0.5m, new[]
                {
                    "Chạy thử đủ thời gian", "Kiểm tra các chức năng khác", "Vệ sinh máy",
                }),
                new("Trả máy cho khách", TaskType.CustomerService, "returned", 0.25m, new[]
                {
                    "Khách kiểm tra lại máy", "Thu tiền", P + "Phiếu trả máy có chữ ký", "Kích hoạt bảo hành",
                }),
                new("Bảo trì định kỳ khách hợp đồng", TaskType.Maintenance, "receive", 4, new[]
                {
                    "Gọi xác nhận lịch với khách", P + "Ảnh thiết bị trước / sau bảo trì", "Ghi biên bản bảo trì",
                }, TaskPriority.Medium, TaskRecurrenceType.Monthly, "1", "08:00", 72),
            }),

        new("spa", "Spa / Salon / Thẩm mỹ", "sparkles",
            "Spa, salon tóc, nail, thẩm mỹ: mở/đóng ca, tiệt trùng dụng cụ, chăm sóc khách sau liệu trình.",
            "Liệu trình / chiến dịch", "#DB2777",
            new[]
            {
                S("booked", "Đã hẹn", "#64748B"),
                S("prepare", "Chuẩn bị", "#7C3AED"),
                S("serving", "Đang phục vụ", "#158DC0"),
                S("followup", "Chăm sóc sau", "#D97706"),
                S("done", "Hoàn tất", "#16A34A", true),
            },
            new TaskPackTemplate[]
            {
                new("Mở ca", TaskType.Routine, "prepare", 0.5m, new[]
                {
                    "Bật đèn, điều hòa, nhạc, máy xông", P + "Khăn, dụng cụ đã tiệt trùng", "Xem lịch hẹn trong ngày", "Kiểm tra mỹ phẩm sắp hết",
                }, TaskPriority.High, TaskRecurrenceType.Daily, null, "08:00", 1),
                new("Đóng ca", TaskType.Routine, "done", 0.5m, new[]
                {
                    P + "Vệ sinh phòng dịch vụ", "Giặt, phơi khăn", "Chốt két, bàn giao tiền", "Tắt thiết bị, khóa cửa",
                }, TaskPriority.High, TaskRecurrenceType.Daily, null, "21:00", 1),
                new("Tiệt trùng dụng cụ", TaskType.Routine, "prepare", 0.5m, new[]
                {
                    "Rửa sạch dụng cụ", P + "Hấp / sấy tiệt trùng", "Ghi sổ tiệt trùng",
                }, TaskPriority.Medium, TaskRecurrenceType.Daily, null, "13:00", 2),
                new("Chăm sóc khách sau liệu trình", TaskType.CustomerService, "followup", 0.25m, new[]
                {
                    "Gọi / nhắn hỏi thăm sau 24 giờ", "Ghi phản hồi, tình trạng da / tóc", "Hẹn buổi tiếp theo",
                }),
                new("Kiểm kê mỹ phẩm, vật tư", TaskType.Inspection, "prepare", 1, new[]
                {
                    "Đếm tồn mỹ phẩm", "Kiểm tra hạn dùng", "Lập danh sách cần nhập",
                }, TaskPriority.Medium, TaskRecurrenceType.Weekly, "1", "09:00", 8),
            }),

        new("logistics", "Kho / Giao hàng", "truck-delivery",
            "Kho hàng, giao nhận, shop online: soạn → đóng gói → xuất kho → giao → xác nhận.",
            "Chuyến / đơn giao", "#0F766E",
            new[]
            {
                S("pick", "Soạn hàng", "#64748B"),
                S("pack", "Đóng gói", "#7C3AED"),
                S("dispatch", "Xuất kho", "#0891B2"),
                S("delivering", "Đang giao", "#158DC0"),
                S("delivered", "Đã giao", "#16A34A", true),
            },
            new TaskPackTemplate[]
            {
                new("Soạn và đóng gói đơn", TaskType.Delivery, "pack", 0.5m, new[]
                {
                    "Đối chiếu mã hàng, số lượng", "Đóng gói, chèn chống sốc", P + "Ảnh kiện hàng trước khi dán", "Dán nhãn vận đơn",
                }),
                new("Giao hàng cho khách", TaskType.Delivery, "delivering", 1, new[]
                {
                    "Gọi khách trước khi đến", "Giao hàng, khách kiểm tra", P + "Ảnh xác nhận giao hàng", "Thu COD",
                }, TaskPriority.High),
                new("Nhập hàng vào kho", TaskType.Procurement, "pick", 1, new[]
                {
                    "Đối chiếu số lượng", P + "Ảnh hàng lỗi / móp méo (nếu có)", "Xếp đúng vị trí kệ",
                }),
                new("Kiểm tra xe đầu ngày", TaskType.Routine, "pick", 0.25m, new[]
                {
                    "Xăng / pin, lốp, đèn", "Giấy tờ xe", P + "Ảnh công-tơ-mét",
                }, TaskPriority.Medium, TaskRecurrenceType.Weekly, "1,2,3,4,5,6", "07:00", 1),
                new("Kiểm kê kho", TaskType.Inspection, "pick", 3, new[]
                {
                    "Kiểm đếm theo khu", "Ghi chênh lệch", "Sắp xếp lại vị trí",
                }, TaskPriority.Medium, TaskRecurrenceType.Weekly, "6", "15:00", 24),
            }),

        new("manufacturing", "Sản xuất / Xưởng", "building-factory-2",
            "Xưởng gỗ, may, cơ khí, thực phẩm: kế hoạch → vật tư → sản xuất → QC → nhập kho; bảo dưỡng máy, 5S.",
            "Lệnh sản xuất", "#4F46E5",
            new[]
            {
                S("plan", "Kế hoạch", "#64748B"),
                S("material", "Chuẩn bị vật tư", "#7C3AED"),
                S("producing", "Sản xuất", "#158DC0"),
                S("qc", "Kiểm tra chất lượng", "#D97706"),
                S("stocked", "Nhập kho", "#16A34A", true),
            },
            new TaskPackTemplate[]
            {
                new("Lập kế hoạch sản xuất", TaskType.Task, "plan", 2, new[]
                {
                    "Xác nhận số lượng, hạn giao", "Tính định mức vật tư", "Phân công tổ / máy",
                }),
                new("Xuất vật tư cho sản xuất", TaskType.Procurement, "material", 1, new[]
                {
                    "Xuất theo định mức", "Kiểm tra vật tư lỗi", "Ký phiếu xuất",
                }),
                new("Gia công / lắp ráp", TaskType.Installation, "producing", 8, new[]
                {
                    "Chạy mẫu đầu tiên", "Sản xuất hàng loạt", "Ghi số lượng đạt / hỏng",
                }),
                new("Kiểm tra chất lượng thành phẩm", TaskType.Inspection, "qc", 2, new[]
                {
                    P + "Đo kiểm theo tiêu chuẩn", "Ghi lỗi, phân loại", "Dán tem QC",
                }, TaskPriority.High),
                new("Nhập kho thành phẩm", TaskType.Procurement, "stocked", 1, new[]
                {
                    "Đếm, đóng thùng", P + "Ảnh lô hàng nhập kho", "Nhập kho trên phần mềm",
                }),
                new("Bảo dưỡng máy móc", TaskType.Maintenance, "plan", 2, new[]
                {
                    "Vệ sinh máy", "Tra dầu mỡ, kiểm tra dây curoa", P + "Ảnh sổ bảo dưỡng",
                }, TaskPriority.Medium, TaskRecurrenceType.Weekly, "6", "14:00", 8),
                new("5S cuối ca", TaskType.Routine, "producing", 0.25m, new[]
                {
                    P + "Dọn sạch khu làm việc", "Sắp xếp dụng cụ đúng chỗ", "Tắt máy, điện",
                }, TaskPriority.Medium, TaskRecurrenceType.Weekly, "1,2,3,4,5,6", "17:00", 1),
            }),

        new("hotel", "Khách sạn / Homestay", "bed",
            "Khách sạn, homestay, nhà nghỉ: dọn phòng, kiểm tra phòng, bảo trì, giao ca lễ tân, PCCC.",
            "Đợt / chiến dịch", "#9333EA",
            new[]
            {
                S("todo", "Cần làm", "#64748B"),
                S("cleaning", "Đang dọn / sửa", "#158DC0"),
                S("inspect", "Chờ kiểm tra", "#D97706"),
                S("ready", "Sẵn sàng", "#16A34A", true),
            },
            new TaskPackTemplate[]
            {
                new("Dọn phòng khách trả", TaskType.Routine, "cleaning", 0.75m, new[]
                {
                    "Thay ga, gối, khăn", "Vệ sinh nhà tắm", "Bổ sung amenity, nước", "Kiểm tra minibar, đồ thất lạc", P + "Ảnh phòng sau khi dọn",
                }, TaskPriority.High),
                new("Kiểm tra phòng trước khi nhận khách", TaskType.Inspection, "inspect", 0.25m, new[]
                {
                    "Điều hòa, TV, nước nóng", "Độ sạch sàn, gương, nhà tắm", "Chuyển trạng thái phòng sẵn sàng",
                }),
                new("Bảo trì, sửa chữa phòng", TaskType.Maintenance, "cleaning", 1, new[]
                {
                    "Kiểm tra sự cố", P + "Ảnh sau khi sửa", "Ghi vật tư đã dùng",
                }),
                new("Giao ca lễ tân", TaskType.Routine, "todo", 0.25m, new[]
                {
                    "Bàn giao tiền, két", "Danh sách khách đến / đi", "Yêu cầu đặc biệt của khách",
                }, TaskPriority.Medium, TaskRecurrenceType.Daily, null, "14:00", 1),
                new("Kiểm tra PCCC, an ninh", TaskType.Inspection, "inspect", 1, new[]
                {
                    P + "Bình chữa cháy còn hạn", "Đèn thoát hiểm, lối thoát", "Camera, khóa từ",
                }, TaskPriority.High, TaskRecurrenceType.Monthly, "1", "10:00", 48),
            }),

        new("office", "Văn phòng / Dịch vụ", "briefcase",
            "Công ty dịch vụ, agency, văn phòng: dự án, họp giao ban, báo cáo tuần/tháng, chăm sóc khách hàng.",
            "Dự án", "#475569",
            new[]
            {
                S("backlog", "Kế hoạch", "#94A3B8"),
                S("todo", "Cần làm", "#64748B"),
                S("doing", "Đang làm", "#158DC0"),
                S("review", "Chờ duyệt", "#D97706"),
                S("done", "Hoàn thành", "#16A34A", true),
            },
            new TaskPackTemplate[]
            {
                new("Họp giao ban tuần", TaskType.Meeting, "todo", 1, new[]
                {
                    "Tổng kết việc tuần trước", "Việc trễ hạn và nguyên nhân", "Kế hoạch tuần này", "Gửi biên bản họp",
                }, TaskPriority.Medium, TaskRecurrenceType.Weekly, "1", "08:30", 4),
                new("Báo cáo tuần", TaskType.Routine, "doing", 1, new[]
                {
                    "Kết quả tuần", "Khó khăn, đề xuất", "Kế hoạch tuần sau",
                }, TaskPriority.Medium, TaskRecurrenceType.Weekly, "5", "15:00", 3),
                new("Chuẩn bị hồ sơ / hợp đồng", TaskType.Task, "doing", 3, new[]
                {
                    "Soạn hồ sơ theo mẫu", "Trình duyệt nội bộ", "Gửi khách ký", P + "Bản scan đã ký",
                }),
                new("Chăm sóc khách hàng", TaskType.CustomerService, "doing", 0.5m, new[]
                {
                    "Gọi / gửi email hỏi thăm", "Ghi nhận phản hồi", "Tạo việc xử lý nếu có vấn đề",
                }),
                new("Báo cáo tháng", TaskType.Routine, "review", 4, new[]
                {
                    "Tổng hợp số liệu", "Phân tích so với kế hoạch", "Trình ban giám đốc",
                }, TaskPriority.High, TaskRecurrenceType.Monthly, "0", "09:00", 48),
            }),
    };

    /// <summary>Khoá cũ «interior» (Nội thất) → gói «construction».</summary>
    public static TaskIndustryPack? Find(string? key)
    {
        if (string.Equals(key, "interior", StringComparison.OrdinalIgnoreCase)) key = "construction";
        return All.FirstOrDefault(p => string.Equals(p.Key, key, StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>Biểu mẫu JSON của mẫu việc trong gói (đã chuẩn hoá khoá).</summary>
    public static string? FormJson(TaskPackTemplate t) =>
        t.Form == null ? null : TaskFormHelper.SerializeSchema(TaskFormHelper.Normalize(t.Form));

    /// <summary>Checklist JSON của mẫu (mục "📷 " → bắt buộc ảnh).</summary>
    public static string ChecklistJson(TaskPackTemplate t) =>
        TaskV2Helper.SerializeChecklist(t.Checklist.Select((text, i) => new TaskChecklistItem
        {
            Id = $"c{i + 1}",
            Text = text.StartsWith(P) ? text[P.Length..] : text,
            RequirePhoto = text.StartsWith(P),
        }));
}
