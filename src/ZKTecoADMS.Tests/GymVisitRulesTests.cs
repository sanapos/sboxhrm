using Xunit;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using static ZKTecoADMS.Application.Interfaces.GymVisitRules;

namespace ZKTecoADMS.Tests;

public class GymVisitRulesTests
{
    static readonly DateTime In = new(2026, 9, 26, 1, 0, 0, DateTimeKind.Utc); // 08:00 VN

    [Fact]
    public void Quet_lan_dau_la_vao() =>
        Assert.Equal(PunchAction.CheckIn, Decide(In, null, null));

    [Fact]
    public void Quet_lai_trong_3_phut_bo_qua() =>
        Assert.Equal(PunchAction.Ignore, Decide(In.AddMinutes(2), In, In));

    [Fact]
    public void Quet_sau_khi_tap_la_ra() =>
        Assert.Equal(PunchAction.CheckOut, Decide(In.AddMinutes(75), In, In));

    [Fact]
    public void Quen_quet_ra_qua_8_gio_thi_tinh_luot_moi() =>
        Assert.Equal(PunchAction.CheckIn, Decide(In.AddHours(9), In, In));

    [Fact]
    public void Log_gui_trung_bo_qua() =>
        Assert.Equal(PunchAction.Ignore, Decide(In.AddMinutes(75), null, In.AddMinutes(75)));

    [Fact]
    public void Ngay_viet_nam_tinh_theo_gio_7()
    {
        var (from, to) = VnDayUtc(new DateTime(2026, 9, 25, 18, 30, 0, DateTimeKind.Utc)); // 01:30 VN ngày 26
        Assert.Equal(new DateTime(2026, 9, 25, 17, 0, 0), from);
        Assert.Equal(new DateTime(2026, 9, 26, 17, 0, 0), to);
    }

    [Fact]
    public void Pin_hoi_vien_tach_dai_nhan_vien()
    {
        var used = new HashSet<string> { "1", "2", "90000001" };
        Assert.Equal("3", DeviceUserPinAllocator.AllocateSequential(used));
        Assert.Equal("90000002", DeviceUserPinAllocator.AllocateMember(used));
        Assert.True(PosGymMemberDevice.IsMemberPin("90000002"));
        Assert.False(PosGymMemberDevice.IsMemberPin("123"));
    }

    [Theory]
    [InlineData("0973024042", "973024042")]
    [InlineData("097 302 4042", "973024042")]
    [InlineData("+84 973 024 042", "973024042")]
    [InlineData("84973024042", "973024042")]
    [InlineData("02363123456", null)] // máy bàn 11 số
    [InlineData("0012345678", null)]
    [InlineData("12345", null)]
    [InlineData(null, null)]
    public void Pin_hoi_vien_theo_so_dien_thoai(string? phone, string? pin) =>
        Assert.Equal(pin, PinFromPhone(phone));

    [Fact]
    public void Quyet_dinh_mo_cua()
    {
        var t = In.AddHours(1);
        var ok = new PosGymVisit { CheckInAt = t, Status = "Ok" };
        var expired = new PosGymVisit { CheckInAt = t, Status = "Expired" };
        var leaving = new PosGymVisit { CheckInAt = In, CheckOutAt = t, Status = "OutOfSessions" };
        Assert.True(ShouldOpenDoor(ok, t, ok));
        Assert.False(ShouldOpenDoor(expired, t, expired));
        Assert.True(ShouldOpenDoor(leaving, t, leaving));          // ra: luôn cho khách ra
        Assert.True(ShouldOpenDoor(null, t.AddMinutes(1), ok));     // quét lại vì cửa chưa mở kịp
        Assert.False(ShouldOpenDoor(null, t.AddMinutes(1), expired));
        Assert.True(IsRealtime(t, t.AddSeconds(90)));
        Assert.False(IsRealtime(t, t.AddMinutes(10)));             // log cũ gửi bù: không mở cửa
        Assert.Equal(973024042, MessageUid("973024042"));
    }
}
