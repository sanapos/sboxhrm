using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Notifications;

/// <summary>
/// Chuẩn hóa tiêu đề/nội dung thông báo push (FCM + SignalR) để người dùng
/// luôn thấy: loại thông báo, tên người gửi/yêu cầu, và nội dung chi tiết.
/// </summary>
public sealed record NotificationPushDisplay(
    string Title,
    string Body,
    string? SenderName,
    string CategoryLabel);

public static class NotificationPushFormatter
{
    private static readonly Dictionary<string, string> CategoryLabels =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["attendance"] = "Chấm công",
            ["leave"] = "Nghỉ phép",
            ["overtime"] = "Tăng ca",
            ["payroll"] = "Lương",
            ["task"] = "Công việc",
            ["approval"] = "Phê duyệt",
            ["device"] = "Thiết bị",
            ["hr"] = "Nhân sự",
            ["employee"] = "Nhân sự",
            ["system"] = "Hệ thống",
            ["kpi"] = "KPI",
            ["internal_comm"] = "Truyền thông",
            ["transaction"] = "Thu chi",
            ["production"] = "Sản lượng",
            ["feedback"] = "Phản hồi",
            ["meal"] = "Suất ăn",
            ["allowance"] = "Phụ cấp",
            ["shift"] = "Ca làm việc",
            ["store"] = "Cửa hàng",
        };

    private static readonly HashSet<string> GenericTitles = new(StringComparer.OrdinalIgnoreCase)
    {
        "",
        "Thông báo",
        "Thông báo mới",
        "Thông báo hệ thống",
        "Chấm công",
        "Đơn nghỉ phép mới",
        "Đơn tăng ca mới",
        "Yêu cầu chỉnh công mới",
        "Yêu cầu ứng lương mới",
        "Đăng ký lịch làm việc mới",
        "Phản hồi mới",
        "Phản ánh mới",
        "Phiếu thu/chi mới",
        "Công việc mới",
        "Công việc mới được giao",
    };

    public static NotificationPushDisplay Format(
        Notification notification,
        string? senderDisplayName = null,
        string? categoryDisplayName = null)
    {
        var category = ResolveCategoryLabel(notification, categoryDisplayName);
        var sender = NormalizeName(senderDisplayName);
        var rawTitle = (notification.Title ?? string.Empty).Trim();
        var rawMessage = (notification.Message ?? string.Empty).Trim();

        if (IsAttendance(notification))
        {
            var lines = rawMessage.Split('\n', 2, StringSplitOptions.TrimEntries);
            var employeeName = lines.Length > 0 && !string.IsNullOrWhiteSpace(lines[0])
                ? lines[0]
                : (sender ?? "Nhân viên");
            var detail = lines.Length > 1 ? lines[1] : rawMessage;
            return new($"Chấm công · {employeeName}", detail, employeeName, "Chấm công");
        }

        if (IsDevice(notification))
        {
            var deviceTitle = IsGenericTitle(rawTitle) ? category : rawTitle;
            return new($"{category} · {deviceTitle}", rawMessage, "Hệ thống", category);
        }

        if (!string.IsNullOrEmpty(sender))
        {
            var title = $"{category} · {sender}";
            var body = CleanBody(rawMessage, sender, rawTitle);
            return new(title, body, sender, category);
        }

        if (notification.Type == NotificationType.ApprovalRequired)
        {
            return new(
                $"{category} · Phê duyệt",
                CleanApprovalBody(rawTitle, rawMessage),
                null,
                category);
        }

        var displayTitle = IsGenericTitle(rawTitle) ? category : rawTitle;
        return new(displayTitle, rawMessage, null, category);
    }

    public static string ResolveCategoryLabel(
        Notification notification,
        string? categoryDisplayName = null)
    {
        if (!string.IsNullOrWhiteSpace(categoryDisplayName))
            return categoryDisplayName.Trim();

        var code = notification.CategoryCode?.Trim();
        if (!string.IsNullOrEmpty(code) &&
            CategoryLabels.TryGetValue(code, out var label))
        {
            return label;
        }

        return notification.RelatedEntityType switch
        {
            "Leave" => "Nghỉ phép",
            "Overtime" => "Tăng ca",
            "AdvanceRequest" => "Ứng lương",
            "AttendanceCorrection" => "Chỉnh công",
            "ScheduleRegistration" => "Đăng ký lịch",
            "WorkTask" => "Công việc",
            "Attendance" or "NewAttendance" => "Chấm công",
            "Device" or "DeviceStatus" => "Thiết bị",
            "Feedback" => "Phản hồi",
            "CashTransaction" => "Thu chi",
            "Communication" => "Truyền thông",
            _ => notification.Type switch
            {
                NotificationType.ApprovalRequired => "Phê duyệt",
                NotificationType.Warning => "Cảnh báo",
                NotificationType.Error => "Lỗi",
                NotificationType.Success => "Thành công",
                NotificationType.Reminder => "Nhắc nhở",
                _ => "Thông báo",
            },
        };
    }

    private static bool IsAttendance(Notification notification) =>
        string.Equals(notification.CategoryCode, "attendance", StringComparison.OrdinalIgnoreCase)
        || string.Equals(notification.RelatedEntityType, "Attendance", StringComparison.OrdinalIgnoreCase)
        || string.Equals(notification.RelatedEntityType, "NewAttendance", StringComparison.OrdinalIgnoreCase);

    private static bool IsDevice(Notification notification) =>
        string.Equals(notification.CategoryCode, "device", StringComparison.OrdinalIgnoreCase)
        || string.Equals(notification.RelatedEntityType, "Device", StringComparison.OrdinalIgnoreCase)
        || string.Equals(notification.RelatedEntityType, "DeviceStatus", StringComparison.OrdinalIgnoreCase);

    private static bool IsGenericTitle(string title) => GenericTitles.Contains(title.Trim());

    private static string? NormalizeName(string? name)
    {
        var trimmed = name?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? null : trimmed;
    }

    private static string CleanBody(string message, string sender, string rawTitle)
    {
        if (string.IsNullOrWhiteSpace(message))
            return rawTitle;

        if (message.StartsWith(sender, StringComparison.OrdinalIgnoreCase))
        {
            var rest = message[sender.Length..].TrimStart(':', ' ', '-', '·', '\n', '\r');
            if (!string.IsNullOrWhiteSpace(rest)) return rest;
        }

        if (message.StartsWith("Có ", StringComparison.OrdinalIgnoreCase)
            && message.Contains("cần phê duyệt", StringComparison.OrdinalIgnoreCase))
        {
            return CleanApprovalBody(rawTitle, message);
        }

        return message;
    }

    private static string CleanApprovalBody(string rawTitle, string rawMessage)
    {
        if (string.IsNullOrWhiteSpace(rawMessage))
            return rawTitle;

        var msg = rawMessage;
        msg = msg.Replace("Có đơn nghỉ phép mới cần phê duyệt", "Xin nghỉ", StringComparison.OrdinalIgnoreCase);
        msg = msg.Replace("Có đơn tăng ca mới", "Đăng ký tăng ca", StringComparison.OrdinalIgnoreCase);
        msg = msg.Replace(" cần phê duyệt", string.Empty, StringComparison.OrdinalIgnoreCase);
        return msg.Trim();
    }

    public static string FormatUserDisplayName(ApplicationUser? user) =>
        FormatUserDisplayName(
            user?.LastName,
            user?.FirstName,
            user?.UserName,
            user?.Email);

    public static string FormatUserDisplayName(
        string? lastName,
        string? firstName,
        string? userName,
        string? email)
    {
        var name = $"{lastName} {firstName}".Trim();
        if (!string.IsNullOrWhiteSpace(name)) return name;
        return userName ?? email ?? string.Empty;
    }
}
