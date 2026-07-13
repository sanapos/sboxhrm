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
            ["travel_attendance"] = "Chấm đi đường",
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
            ["penalty"] = "Phiếu phạt",
            ["pos"] = "POS",
            ["business_trip"] = "Công tác",
        };

    /// <summary>
    /// Chỉ các title thật sự chung chung — khi có sender mới fallback sang category · tên.
    /// Không đưa tiêu đề sự kiện cụ thể vào đây (sẽ bị mất trên FCM).
    /// </summary>
    private static readonly HashSet<string> GenericTitles = new(StringComparer.OrdinalIgnoreCase)
    {
        "",
        "Thông báo",
        "Thông báo mới",
        "Thông báo hệ thống",
        "Chấm công",
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
            return FormatAttendanceDisplay(rawMessage, sender);
        }

        if (IsDevice(notification))
        {
            var deviceTitle = IsGenericTitle(rawTitle) ? category : rawTitle;
            return new($"{category} · {deviceTitle}", rawMessage, "Hệ thống", category);
        }

        // Ưu tiên tiêu đề sự kiện (VD: "Yêu cầu ứng công tác mới").
        // Chỉ dùng "{category} · {sender}" khi title quá chung chung.
        if (!string.IsNullOrEmpty(sender))
        {
            var title = IsGenericTitle(rawTitle)
                ? $"{category} · {sender}"
                : rawTitle;
            var body = BuildSenderBody(rawMessage, sender, rawTitle);
            return new(title, body, sender, category);
        }

        if (notification.Type == NotificationType.ApprovalRequired)
        {
            var title = IsGenericTitle(rawTitle)
                ? $"{category} · Phê duyệt"
                : rawTitle;
            return new(title, CleanApprovalBody(rawTitle, rawMessage), null, category);
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
            "PaymentTransaction" => "Thưởng/Phạt",
            "PenaltyTicket" => "Phiếu phạt",
            "Communication" => "Truyền thông",
            "BusinessTripCase" or "BusinessTripExpense" => "Công tác",
            "MealSession" or "MealMenu" or "MealRecord" => "Suất ăn",
            "PosSaleOrder" or "PosProduct" or "PosPurchaseReceipt" => "POS",
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

    private static string BuildSenderBody(string message, string sender, string rawTitle)
    {
        var cleaned = CleanBody(message, sender, rawTitle);
        if (string.IsNullOrWhiteSpace(cleaned))
            return sender;

        // Đưa tên người gửi vào body nếu title đã dùng cho sự kiện.
        if (!cleaned.Contains(sender, StringComparison.OrdinalIgnoreCase)
            && !string.Equals(cleaned, sender, StringComparison.OrdinalIgnoreCase))
        {
            return $"{sender}: {cleaned}";
        }

        return cleaned;
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

    /// <summary>
    /// DB message: dòng 1 = họ tên, dòng 2 = giờ - thiết bị [tại chi nhánh].
    /// </summary>
    public static string BuildAttendanceStoredMessage(
        string employeeName,
        DateTime attendanceTime,
        string deviceLabel,
        string? branchLabel = null)
    {
        var name = string.IsNullOrWhiteSpace(employeeName) ? "Nhân viên" : employeeName.Trim();
        return $"{name}\n{FormatAttendanceDetailLine(attendanceTime, deviceLabel, branchLabel)}";
    }

    public static string FormatAttendanceDetailLine(
        DateTime attendanceTime,
        string deviceLabel,
        string? branchLabel = null)
    {
        var device = string.IsNullOrWhiteSpace(deviceLabel) ? "Thiết bị" : deviceLabel.Trim();
        var timeStr = attendanceTime.ToString("HH:mm:ss");
        var branch = branchLabel?.Trim();
        if (!string.IsNullOrEmpty(branch))
            return $"{timeStr} - {device} tại {branch}";
        return $"{timeStr} - {device}";
    }

    private static NotificationPushDisplay FormatAttendanceDisplay(string rawMessage, string? sender)
    {
        var lines = rawMessage.Split('\n', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        string employeeName;
        string detail;

        if (lines.Length >= 2)
        {
            employeeName = lines[0];
            detail = string.Join('\n', lines.Skip(1));
        }
        else if (lines.Length == 1)
        {
            employeeName = sender ?? lines[0];
            detail = sender != null && !string.Equals(sender, lines[0], StringComparison.OrdinalIgnoreCase)
                ? lines[0]
                : string.Empty;
        }
        else
        {
            employeeName = sender ?? "Nhân viên";
            detail = string.Empty;
        }

        // Tên NV ở title — iOS cắt title ~1 dòng; prefix "Chấm công ·" làm mất phần họ tên.
        var body = CompactAttendanceDetailForPush(detail);

        return new(employeeName, body, employeeName, "Chấm công");
    }

    /// <summary>
    /// Rút gọn dòng chi tiết cho banner iOS/Android: "18:02:30 · Chi nhánh" thay vì
    /// "18:02:30 - SN123456789 tại Chi nhánh".
    /// </summary>
    private static string CompactAttendanceDetailForPush(string detail)
    {
        detail = detail.Replace('\n', ' ').Trim();
        if (string.IsNullOrWhiteSpace(detail))
            return "Chấm công";

        const string taiMarker = " tại ";
        var taiIdx = detail.IndexOf(taiMarker, StringComparison.Ordinal);
        if (taiIdx >= 0)
        {
            var dashIdx = detail.IndexOf(" - ", StringComparison.Ordinal);
            var timePart = dashIdx >= 0 ? detail[..dashIdx].Trim() : detail[..taiIdx].Trim();
            var branch = detail[(taiIdx + taiMarker.Length)..].Trim();
            if (!string.IsNullOrEmpty(branch))
                return $"{timePart} · {branch}";
        }

        var sepIdx = detail.IndexOf(" - ", StringComparison.Ordinal);
        if (sepIdx >= 0)
        {
            var timePart = detail[..sepIdx].Trim();
            var rest = detail[(sepIdx + 3)..].Trim();
            return string.IsNullOrEmpty(rest) ? timePart : $"{timePart} · {rest}";
        }

        return detail;
    }
}
