using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Tests;

/// <summary>Heartbeat Agent (12s / máy) chỉ ghi DB khi đổi thông tin hoặc lần ghi trước đã quá 30s.</summary>
public class PosPrintAgentHeartbeatTests
{
    static readonly DateTime Now = new(2026, 10, 31, 10, 0, 0, DateTimeKind.Utc);

    static PosPrintAgent Agent(double ageSec, bool online = true) => new()
    {
        Id = Guid.NewGuid(),
        DeviceId = "dev",
        DeviceName = "C20",
        EmployeeName = "Thu ngân",
        UserId = "u1",
        AssignedPrinterIdsJson = "[\"a\"]",
        AppVersion = "1.0",
        IsOnline = online,
        // Đọc từ cột timestamp không múi giờ → Kind Unspecified.
        LastHeartbeatAt = DateTime.SpecifyKind(Now.AddSeconds(-ageSec), DateTimeKind.Unspecified),
    };

    static bool Changed(PosPrintAgent a, string json = "[\"a\"]", string? name = "C20") =>
        PosPrintDispatchService.HeartbeatChanged(a, name, "Thu ngân", "u1", json, "1.0", Now);

    [Fact]
    public void Khong_doi_va_vua_ghi_thi_bo_qua() => Assert.False(Changed(Agent(12)));

    [Fact]
    public void Qua_30s_thi_ghi_lai() => Assert.True(Changed(Agent(31)));

    [Fact]
    public void Doi_may_in_hoac_ten_thi_ghi_ngay()
    {
        Assert.True(Changed(Agent(5), json: "[\"a\",\"b\"]"));
        Assert.True(Changed(Agent(5), name: "C20 quầy"));
    }

    [Fact]
    public void Dang_offline_thi_ghi_ngay() => Assert.True(Changed(Agent(5, online: false)));
}
