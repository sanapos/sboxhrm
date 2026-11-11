using MessagingErrorCode = FirebaseAdmin.Messaging.MessagingErrorCode;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
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
        Assert.Equal("08:01:02 · Ca Sáng · Trễ 3 phút · Máy A (Chi nhánh 1)", display.Body);
        Assert.DoesNotContain("· ·", display.Body);
    }

    [Theory]
    [InlineData("SBOX Cafe", "SBOX Cafe", "SBOX Cafe")]
    [InlineData("sbox  cafe", "SBOX Cafe", "sbox  cafe")]
    [InlineData("Máy SBOX Cafe", "SBOX Cafe", "Máy SBOX Cafe")]
    [InlineData("Cafe", "SBOX Cafe", "SBOX Cafe")]
    [InlineData("Máy A", "Chi nhánh 1", "Máy A (Chi nhánh 1)")]
    [InlineData("Máy A", null, "Máy A")]
    public void Ten_may_trung_ten_cua_hang_chi_hien_mot_lan(string device, string? branch, string expected)
        => Assert.Equal(expected, NotificationPushFormatter.FormatPunchPlace(device, branch));

    [Fact]
    public void Luot_vao_ghi_vao_va_tre_luot_ra_ghi_ra_va_ve_som()
    {
        var vao = NotificationPushFormatter.Format(AttendanceRow(NotificationPushFormatter.BuildAttendanceStoredMessage(
            "Nguyễn Văn A", new DateTime(2026, 11, 11, 8, 7, 0), "SBOX Cafe", "SBOX Cafe", "Ca hành chính", 7, "Vào")));
        Assert.Equal("Vào 08:07:00 · Ca hành chính · Trễ 7 phút · SBOX Cafe", vao.Body);

        var ra = NotificationPushFormatter.Format(AttendanceRow(NotificationPushFormatter.BuildAttendanceStoredMessage(
            "Nguyễn Văn A", new DateTime(2026, 11, 11, 16, 50, 0), "SBOX Cafe", "SBOX Cafe", "Ca hành chính",
            lateMinutes: 520, direction: "Ra", earlyMinutes: 10)));
        Assert.Equal("Ra 16:50:00 · Ca hành chính · Về sớm 10 phút · SBOX Cafe", ra.Body);

        var raDungGio = NotificationPushFormatter.FormatAttendanceDetailLine(
            new DateTime(2026, 11, 11, 17, 2, 0), "Máy A", shiftName: "Ca hành chính", direction: "Ra");
        Assert.Equal("Ra 17:02:00 · Ca hành chính · Máy A", raDungGio);
    }

    [Fact]
    public void Lo_nhieu_luot_hien_vao_ra_tung_dong()
    {
        var t = DateTime.UtcNow;
        var rows = new[]
        {
            AttendanceRow(NotificationPushFormatter.BuildAttendanceStoredMessage(
                "Trần B", new DateTime(2026, 10, 15, 8, 0, 5), "Máy A", direction: "Vào"), t.AddSeconds(-5)),
            AttendanceRow(NotificationPushFormatter.BuildAttendanceStoredMessage(
                "Lê C", new DateTime(2026, 10, 15, 17, 0, 9), "Máy A", direction: "Ra"), t),
        };
        var display = NotificationPushFormatter.FormatAttendanceBatch(rows, "Máy A");
        Assert.Equal("Lê C · Ra 17:00:09\nTrần B · Vào 08:00:05", display.Body);
    }

    static readonly DateTime D = new(2026, 11, 11);

    [Fact]
    public void Huong_cham_theo_thu_tu_trong_ngay_khi_may_khong_phan_biet()
    {
        // Lượt đầu ngày → vào; lượt thứ 2 → ra; thứ 3 → vào.
        Assert.Equal("Vào", AttendanceNotificationService.PunchDirection(AttendanceStates.CheckIn, [], D.AddHours(8)));
        Assert.Equal("Ra", AttendanceNotificationService.PunchDirection(
            AttendanceStates.CheckIn, [D.AddHours(8)], D.AddHours(12)));
        Assert.Equal("Vào", AttendanceNotificationService.PunchDirection(
            AttendanceStates.CheckIn, [D.AddHours(8), D.AddHours(12)], D.AddHours(13)));
        // Quẹt trùng trong 3 phút: vẫn là lượt vào, lượt sau đó mới là ra.
        Assert.Equal("Vào", AttendanceNotificationService.PunchDirection(
            AttendanceStates.CheckIn, [D.AddHours(8)], D.AddHours(8).AddMinutes(1)));
        Assert.Equal("Ra", AttendanceNotificationService.PunchDirection(
            AttendanceStates.CheckIn, [D.AddHours(8), D.AddHours(8).AddMinutes(1)], D.AddHours(17)));
        // Máy / app ghi rõ chấm ra.
        Assert.Equal("Ra", AttendanceNotificationService.PunchDirection(AttendanceStates.CheckOut, [], D.AddHours(17)));
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

    [Theory]
    [InlineData("Ca đêm", "Ca đêm")]
    [InlineData("Sáng", "Ca Sáng")]
    public void Shift_name_does_not_repeat_the_word_ca(string shiftName, string expected)
    {
        var line = NotificationPushFormatter.FormatAttendanceDetailLine(
            new DateTime(2026, 10, 15, 1, 0, 0, DateTimeKind.Utc), "Máy A", shiftName: shiftName);

        Assert.Contains($" · {expected} · ", line);
        Assert.DoesNotContain("Ca Ca", line);
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
