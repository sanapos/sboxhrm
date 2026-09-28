using Xunit;
using ZKTecoADMS.Application.Services;

namespace ZKTecoADMS.Tests;

/// <summary>Kiến nghị / khiếu nại: quyền xem, hạn xử lý, luồng trạng thái.</summary>
public class FeedbackRulesTests
{
    [Fact]
    public void Nhan_vien_khong_doc_duoc_hom_thu_chung_cua_nguoi_khac() =>
        Assert.False(FeedbackRules.CanView(fullAccess: false, isHandler: false, isSender: false,
            isRecipient: false, isAssignee: false, generalMailbox: true));

    [Fact]
    public void Quan_ly_khong_doc_duoc_phieu_gui_rieng_cho_nguoi_khac()
    {
        Assert.False(FeedbackRules.CanView(false, true, false, false, false, generalMailbox: false));
        Assert.True(FeedbackRules.CanView(false, true, false, false, false, generalMailbox: true));
        Assert.True(FeedbackRules.CanView(false, true, false, false, isAssignee: true, generalMailbox: false));
        Assert.True(FeedbackRules.CanView(fullAccess: true, false, false, false, false, false));
    }

    [Fact]
    public void Nguoi_gui_xem_duoc_nhung_khong_tu_xu_ly_phieu_cua_minh()
    {
        Assert.True(FeedbackRules.CanView(false, true, isSender: true, false, false, true));
        Assert.False(FeedbackRules.CanManage(true, true, isSender: true, false, false, true));
    }

    [Theory]
    [InlineData(FeedbackRules.PriorityUrgent, 24)]
    [InlineData(FeedbackRules.PriorityHigh, 48)]
    [InlineData(FeedbackRules.PriorityNormal, 72)]
    [InlineData(FeedbackRules.PriorityLow, 168)]
    public void Han_xu_ly_theo_muc_do(int priority, int hours) =>
        Assert.Equal(TimeSpan.FromHours(hours), FeedbackRules.SlaFor(priority));

    [Fact]
    public void Khieu_nai_mac_dinh_muc_cao_va_qua_han_chi_tinh_khi_dang_mo()
    {
        Assert.Equal(FeedbackRules.PriorityHigh, FeedbackRules.DefaultPriority("Complaint"));
        var now = new DateTime(2026, 9, 28, 10, 0, 0);
        Assert.True(FeedbackRules.IsOverdue(FeedbackRules.InProgress, now.AddHours(-1), now));
        Assert.False(FeedbackRules.IsOverdue(FeedbackRules.Resolved, now.AddHours(-1), now));
    }

    [Theory]
    [InlineData(FeedbackRules.Pending, FeedbackRules.InProgress, true)]
    [InlineData(FeedbackRules.InProgress, FeedbackRules.Resolved, true)]
    [InlineData(FeedbackRules.Resolved, FeedbackRules.Closed, true)]
    [InlineData(FeedbackRules.Closed, FeedbackRules.Pending, false)]
    [InlineData(FeedbackRules.Resolved, FeedbackRules.Resolved, false)]
    public void Luong_trang_thai(string from, string to, bool ok) =>
        Assert.Equal(ok, FeedbackRules.CanHandlerMove(from, to));

    [Fact]
    public void Mo_lai_trong_30_ngay_va_danh_gia_mot_lan()
    {
        var now = new DateTime(2026, 9, 28);
        Assert.True(FeedbackRules.CanSenderReopen(FeedbackRules.Resolved, now.AddDays(-10), now));
        Assert.False(FeedbackRules.CanSenderReopen(FeedbackRules.Resolved, now.AddDays(-40), now));
        Assert.False(FeedbackRules.CanSenderReopen(FeedbackRules.InProgress, null, now));
        Assert.True(FeedbackRules.CanSenderRate(FeedbackRules.Resolved, null));
        Assert.False(FeedbackRules.CanSenderRate(FeedbackRules.Resolved, 4));
        Assert.Equal("KN-2609-0012", FeedbackRules.MakeCode(now, 12));
    }
}
