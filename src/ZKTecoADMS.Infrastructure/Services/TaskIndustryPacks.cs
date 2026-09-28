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
    string? Description = null);

/// <summary>Gói ngành: quy trình giai đoạn + mẫu việc + checklist, cài 1 chạm.</summary>
public record TaskIndustryPack(
    string Key,
    string Name,
    string Icon,
    string Description,
    string ProjectLabel,
    string Color,
    TaskStage[] Stages,
    TaskPackTemplate[] Templates);

/// <summary>
/// 9 gói ngành dựng sẵn. Mục checklist bắt đầu bằng "📷 " = bắt buộc chụp ảnh khi đánh dấu xong
/// (ký tự này bị bỏ khi cài, chỉ dùng để khai báo gọn).
/// </summary>
public static class TaskIndustryPacks
{
    private const string P = "📷 ";

    private static TaskStage S(string key, string name, string color, bool done = false) =>
        new() { Key = key, Name = name, Color = color, Done = done };

    private static readonly TaskStage[] SimpleBoard =
    {
        S("todo", "Cần làm", "#64748B"),
        S("doing", "Đang làm", "#158DC0"),
        S("check", "Chờ kiểm tra", "#D97706"),
        S("done", "Hoàn thành", "#16A34A", true),
    };

    public static readonly TaskIndustryPack[] All =
    {
        new("interior", "Nội thất / Thi công", "construction",
            "Công trình nội thất, xây dựng, sửa nhà: khảo sát → thiết kế → sản xuất → thi công → nghiệm thu → bảo hành.",
            "Công trình", "#B45309",
            new[]
            {
                S("survey", "Khảo sát", "#64748B"),
                S("design", "Thiết kế & báo giá", "#7C3AED"),
                S("production", "Sản xuất / đặt hàng", "#0891B2"),
                S("construction", "Thi công", "#158DC0"),
                S("handover", "Nghiệm thu & bàn giao", "#16A34A", true),
                S("warranty", "Bảo hành", "#94A3B8", true),
            },
            new TaskPackTemplate[]
            {
                new("Khảo sát, đo đạc hiện trạng", TaskType.Survey, "survey", 3, new[]
                {
                    "Hẹn lịch với khách", P + "Chụp ảnh hiện trạng từng phòng", P + "Đo kích thước, vị trí điện nước",
                    "Ghi nhu cầu, phong cách, ngân sách của khách", "Gửi biên bản khảo sát cho khách",
                }),
                new("Thiết kế 3D và báo giá", TaskType.Task, "design", 16, new[]
                {
                    "Lên mặt bằng bố trí", "Dựng phối cảnh 3D", "Bóc khối lượng vật tư", "Lập báo giá", "Khách duyệt thiết kế và báo giá", "Ký hợp đồng, thu tạm ứng",
                }, TaskPriority.High),
                new("Đặt vật tư / sản xuất tại xưởng", TaskType.Procurement, "production", 8, new[]
                {
                    "Chốt mã màu, vật liệu với khách", "Đặt ván, phụ kiện, thiết bị", "Theo dõi tiến độ xưởng", P + "Kiểm tra hàng về (số lượng, lỗi)",
                }),
                new("Thi công lắp đặt", TaskType.Installation, "construction", 16, new[]
                {
                    P + "Che chắn, bảo vệ mặt bằng", "Lắp khung, thùng tủ", "Lắp cánh, ray, bản lề, phụ kiện", "Căn chỉnh, kiểm tra đóng mở", P + "Vệ sinh sau thi công",
                }, TaskPriority.High),
                new("Nghiệm thu, bàn giao công trình", TaskType.Inspection, "handover", 2, new[]
                {
                    "Kiểm tra đối chiếu bản vẽ", "Kiểm tra vận hành thiết bị", P + "Biên bản nghiệm thu có chữ ký khách",
                    "Hướng dẫn sử dụng, bảo quản", "Thu tiền đợt cuối", "Kích hoạt phiếu bảo hành",
                }, TaskPriority.High),
                new("Chăm sóc, bảo hành sau bàn giao", TaskType.Maintenance, "warranty", 1, new[]
                {
                    "Gọi hỏi thăm khách", "Kiểm tra bản lề, ray, silicon", "Ghi nhận lỗi và hẹn xử lý",
                }, TaskPriority.Low),
                new("Báo cáo công trường cuối ngày", TaskType.Routine, "construction", 0.5m, new[]
                {
                    P + "Ảnh tiến độ trong ngày", "Khối lượng đã làm", "Vật tư còn thiếu", "Kế hoạch ngày mai",
                }, TaskPriority.Medium, TaskRecurrenceType.Weekly, "1,2,3,4,5,6", "17:00", 3),
            }),

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

        new("fnb", "Nhà hàng / Cafe", "tools-kitchen-2",
            "Quán ăn, nhà hàng, cafe, trà sữa: checklist mở/đóng cửa, nhận hàng, vệ sinh, an toàn thực phẩm.",
            "Sự kiện / chiến dịch", "#EA580C",
            SimpleBoard,
            new TaskPackTemplate[]
            {
                new("Checklist mở cửa", TaskType.Routine, "doing", 0.75m, new[]
                {
                    P + "Vệ sinh khu bar / bếp", P + "Nhiệt độ tủ mát, tủ đông", "Nhận hàng đầu ngày", "Sơ chế nguyên liệu", "Kiểm tra tiền két đầu ca",
                }, TaskPriority.High, TaskRecurrenceType.Daily, null, "06:30", 1),
                new("Checklist đóng cửa", TaskType.Routine, "doing", 0.75m, new[]
                {
                    "Bảo quản nguyên liệu thừa", P + "Vệ sinh bếp, sàn, bàn ghế", "Đổ rác, tắt gas, điện", "Chốt két, bàn giao",
                }, TaskPriority.High, TaskRecurrenceType.Daily, null, "22:00", 1),
                new("Vệ sinh nhà vệ sinh", TaskType.Routine, "doing", 0.25m, new[]
                {
                    P + "Lau sàn, bồn rửa", "Bổ sung giấy, xà phòng", "Ký sổ vệ sinh",
                }, TaskPriority.Medium, TaskRecurrenceType.Daily, null, "11:00", 1),
                new("Nhận hàng nhà cung cấp", TaskType.Procurement, "doing", 0.5m, new[]
                {
                    "Đối chiếu số lượng với đơn", "Kiểm tra hạn dùng, cảm quan", "Kiểm tra nhiệt độ hàng lạnh", P + "Ảnh hóa đơn giao hàng",
                }),
                new("Kiểm kê nguyên liệu", TaskType.Inspection, "check", 1.5m, new[]
                {
                    "Đếm tồn kho nguyên liệu", "Ghi hao hụt", "Lập đơn đặt hàng tuần",
                }, TaskPriority.Medium, TaskRecurrenceType.Weekly, "7", "21:00", 12),
                new("Tổng vệ sinh, an toàn thực phẩm", TaskType.Inspection, "check", 3, new[]
                {
                    P + "Vệ sinh hút mùi, cống thoát", "Kiểm tra hạn dùng toàn kho", "Kiểm tra bình chữa cháy", "Cập nhật sổ ATTP",
                }, TaskPriority.High, TaskRecurrenceType.Monthly, "1", "14:00", 48),
            }),

        new("retail", "Bán lẻ / Cửa hàng", "building-store",
            "Shop, siêu thị mini, cửa hàng tiện lợi, nhà thuốc: mở/đóng cửa, trưng bày, kiểm hạn dùng, kiểm kê.",
            "Chiến dịch / đợt khuyến mãi", "#158DC0",
            SimpleBoard,
            new TaskPackTemplate[]
            {
                new("Mở cửa hàng", TaskType.Routine, "doing", 0.5m, new[]
                {
                    "Bật đèn, biển hiệu, máy tính tiền", "Lau kính, quầy kệ", P + "Kệ trưng bày đầy hàng", "Kiểm tra tiền lẻ két",
                }, TaskPriority.High, TaskRecurrenceType.Daily, null, "07:30", 1),
                new("Đóng cửa hàng", TaskType.Routine, "doing", 0.5m, new[]
                {
                    "Chốt ca, đối chiếu doanh thu", "Châm hàng lên kệ", "Tắt thiết bị, khóa cửa",
                }, TaskPriority.High, TaskRecurrenceType.Daily, null, "22:00", 1),
                new("Kiểm tra hạn dùng, hàng sắp hết", TaskType.Inspection, "check", 1, new[]
                {
                    "Lọc hàng cận date", "Đưa hàng cận date ra khu giảm giá", "Lập danh sách hàng sắp hết",
                }, TaskPriority.Medium, TaskRecurrenceType.Weekly, "1,4", "09:00", 8),
                new("Trưng bày chương trình khuyến mãi", TaskType.Task, "doing", 2, new[]
                {
                    "In, dán bảng giá khuyến mãi", "Sắp xếp khu trưng bày", P + "Ảnh sau khi trưng bày",
                }),
                new("Nhận hàng nhập", TaskType.Procurement, "doing", 1, new[]
                {
                    "Đối chiếu phiếu giao", "Kiểm tra hàng lỗi, hạn dùng", P + "Ảnh phiếu nhập có chữ ký", "Nhập kho trên phần mềm",
                }),
                new("Kiểm kê định kỳ", TaskType.Inspection, "check", 4, new[]
                {
                    "Chia khu kiểm đếm", "Nhập số kiểm trên phần mềm", "Giải trình chênh lệch",
                }, TaskPriority.High, TaskRecurrenceType.Monthly, "0", "20:00", 24),
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

    public static TaskIndustryPack? Find(string? key) =>
        All.FirstOrDefault(p => string.Equals(p.Key, key, StringComparison.OrdinalIgnoreCase));

    /// <summary>Checklist JSON của mẫu (mục "📷 " → bắt buộc ảnh).</summary>
    public static string ChecklistJson(TaskPackTemplate t) =>
        TaskV2Helper.SerializeChecklist(t.Checklist.Select((text, i) => new TaskChecklistItem
        {
            Id = $"c{i + 1}",
            Text = text.StartsWith(P) ? text[P.Length..] : text,
            RequirePhoto = text.StartsWith(P),
        }));
}
