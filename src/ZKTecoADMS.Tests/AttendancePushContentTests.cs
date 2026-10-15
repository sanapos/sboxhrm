using MessagingErrorCode = FirebaseAdmin.Messaging.MessagingErrorCode;
using Xunit;
using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure.Services.Push;

namespace ZKTecoADMS.Tests;

/// <summary>Nội dung push chấm công + quy tắc tắt token FCM.</summary>
public class AttendancePushContentTests
{
    private static Notification AttendanceRow(string message, DateTime? ts = null) => new()
    {
        Id = Guid.NewGuid(),
        Title = "Chấm công",
        Message = message,
        CategoryCode = "attendance",
        RelatedEntityType = "Attendance",
        Timestamp = ts ?? DateTime.UtcNow,
    };

    [Fact]
    public void Single_punch_with_branch_has_no_double_separator()
    {
        var msg = NotificationPushFormatter.BuildAttendanceStoredMessage(
            "Nguyễn Văn A", new DateTime(2026, 10, 15, 8, 1, 2), "Máy A", "Chi nhánh 1", "Sáng", 3);

        var display = NotificationPushFormatter.Format(AttendanceRow(msg));

        Assert.Equal("Nguyễn Văn A", display.Title);
        Assert.Equal("08:01:02 · Ca Sáng · Trễ 3 phút · Máy A · tại Chi nhánh 1", display.Body);
        Assert.DoesNotContain("· ·", display.Body);
    }

    [Fact]
    public void Legacy_message_format_still_compacted()
    {
        var display = NotificationPushFormatter.Format(
            AttendanceRow("Nguyễn Văn A\n18:02:30 - SN123 tại Chi nhánh"));

        Assert.Equal("18:02:30 · Chi nhánh", display.Body);
    }

    [Fact]
    public void Utc_punch_time_is_shown_in_vietnam_time()
    {
        var line = NotificationPushFormatter.FormatAttendanceDetailLine(
            new DateTime(2026, 10, 15, 1, 0, 0, DateTimeKind.Utc), "Máy A");

        Assert.StartsWith("08:00:00", line);
    }

    [Fact]
    public void Batch_push_lists_every_employee_newest_first()
    {
        var t = DateTime.UtcNow;
        var rows = new[]
        {
            AttendanceRow(NotificationPushFormatter.BuildAttendanceStoredMessage(
                "Trần B", new DateTime(2026, 10, 15, 8, 0, 5), "Máy A"), t.AddSeconds(-5)),
            AttendanceRow(NotificationPushFormatter.BuildAttendanceStoredMessage(
                "Lê C", new DateTime(2026, 10, 15, 8, 0, 9), "Máy A", "CN1", "Sáng"), t),
        };

        var display = NotificationPushFormatter.FormatAttendanceBatch(rows, "Máy A");

        Assert.Equal("Chấm công · 2 lượt mới · Máy A", display.Title);
        Assert.Equal("Lê C · 08:00:09\nTrần B · 08:00:05", display.Body);
    }

    [Fact]
    public void Batch_of_one_uses_single_format()
    {
        var row = AttendanceRow(NotificationPushFormatter.BuildAttendanceStoredMessage(
            "Trần B", new DateTime(2026, 10, 15, 8, 0, 5), "Máy A"));

        var display = NotificationPushFormatter.FormatAttendanceBatch(new[] { row }, "Máy A");

        Assert.Equal("Trần B", display.Title);
        Assert.Equal("08:00:05 · Máy A", display.Body);
    }

    [Theory]
    [InlineData(MessagingErrorCode.Unregistered, 0, true)]
    [InlineData(MessagingErrorCode.InvalidArgument, 1, true)]
    // Cả lô đều InvalidArgument → nghi payload lỗi, không được tắt token của người dùng.
    [InlineData(MessagingErrorCode.InvalidArgument, 0, false)]
    [InlineData(MessagingErrorCode.Unavailable, 0, false)]
    [InlineData(MessagingErrorCode.Internal, 3, false)]
    public void Dead_token_rule(MessagingErrorCode code, int successInBatch, bool expected)
    {
        Assert.Equal(expected, PushNotificationService.IsDeadToken(code, successInBatch));
    }
}
