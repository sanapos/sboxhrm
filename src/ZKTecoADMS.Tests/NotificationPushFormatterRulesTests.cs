using Xunit;
using ZKTecoADMS.Application.Notifications;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests;

/// <summary>Luật chung của bộ định dạng push (FCM / SignalR) — rà nội dung thông báo 11/2026.</summary>
public class NotificationPushFormatterRulesTests
{
    static Notification N(string title, string message, string? category = null, string? entity = null,
        NotificationType type = NotificationType.Info) => new()
    {
        Id = Guid.NewGuid(), Title = title, Message = message, CategoryCode = category,
        RelatedEntityType = entity, Type = type, Timestamp = DateTime.UtcNow,
    };

    [Fact]
    public void Thong_bao_ca_lich_nhom_attendance_giu_tieu_de()
    {
        var d = NotificationPushFormatter.Format(
            N("Lịch làm việc đã duyệt", "Tuần 10/11–16/11 · 6 ca", "attendance", "WorkSchedule"), "Trần Quản Lý");
        Assert.Equal("Lịch làm việc đã duyệt", d.Title);
        Assert.Equal("Trần Quản Lý: Tuần 10/11–16/11 · 6 ca", d.Body);
    }

    [Fact]
    public void Luot_cham_cong_van_theo_dinh_dang_cham_cong()
    {
        var d = NotificationPushFormatter.Format(
            N("Chấm công", "Nguyễn Văn A\nVào 08:01:02 · Máy A", "attendance", "Attendance"));
        Assert.Equal("Nguyễn Văn A", d.Title);
        Assert.Equal("Vào 08:01:02 · Máy A", d.Body);
    }

    [Fact]
    public void Thiet_bi_khong_lap_chu_thiet_bi()
    {
        var d = NotificationPushFormatter.Format(
            N("Máy chấm công mất kết nối", "Máy cửa chính · SBOX Cafe · từ 08:02", "device", "DeviceStatus"));
        Assert.Equal("Máy chấm công mất kết nối", d.Title);
        Assert.Equal("Máy cửa chính · SBOX Cafe · từ 08:02", d.Body);
    }

    [Fact]
    public void Tieu_de_da_co_ten_nguoi_gui_thi_khong_chen_lai()
    {
        var d = NotificationPushFormatter.Format(
            N("Bình luận mới · Lê Thị Hoa", "Đã xong phần báo giá", "task", "WorkTask"), "Lê Thị Hoa");
        Assert.Equal("Bình luận mới · Lê Thị Hoa", d.Title);
        Assert.Equal("Đã xong phần báo giá", d.Body);
    }

    [Fact]
    public void Tieu_de_chung_chung_co_nguoi_gui_khong_lap_ten_o_noi_dung()
    {
        var d = NotificationPushFormatter.Format(N("Thông báo", "Họp lúc 14:00", "internal_comm"), "Lê Thị Hoa");
        Assert.Equal("Truyền thông · Lê Thị Hoa", d.Title);
        Assert.Equal("Họp lúc 14:00", d.Body);
    }

    [Fact]
    public void Nguoi_gui_Unknown_bi_bo()
    {
        var d = NotificationPushFormatter.Format(N("Đơn nghỉ phép bị từ chối", "Nghỉ 12/11", "leave", "Leave"), "Unknown");
        Assert.Equal("Nghỉ 12/11", d.Body);
        Assert.Null(d.SenderName);
    }

    [Theory]
    [InlineData("Yêu cầu bị từ chối. Lý do: ", "Yêu cầu bị từ chối")]
    [InlineData("Yêu cầu bị từ chối · Lý do:", "Yêu cầu bị từ chối")]
    [InlineData("Đơn  nghỉ   phép · · 12/11", "Đơn nghỉ phép · 12/11")]
    [InlineData("Lý do: ốm", "Lý do: ốm")]
    [InlineData("Giờ vào: 08:00", "Giờ vào: 08:00")]
    public void Don_chu_thua(string input, string expected)
        => Assert.Equal(expected, NotificationPushFormatter.Tidy(input));
}
