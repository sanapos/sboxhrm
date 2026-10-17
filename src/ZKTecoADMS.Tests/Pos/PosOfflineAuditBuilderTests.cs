using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Kiểm soát bán offline (không cần CSDL): kết luận, cảnh báo + cách xử lý, tổng đủ, đồ thị, giờ gửi.</summary>
public class PosOfflineAuditBuilderTests
{
    static readonly DateTime Now = new(2026, 10, 17, 5, 0, 0, DateTimeKind.Utc); // 12:00 giờ VN
    static readonly PosOfflineSaleRules.Settings On = new(true, 8);

    static PosDeviceInstall Inst(string inst, DateTime first, int pending = 0, int? lastSeq = null) => new()
    {
        Id = Guid.NewGuid(), DeviceKey = "a:dev-1", InstallId = inst, DeviceName = "Quầy 1", Platform = "android",
        FirstSeenAt = first, LastSeenAt = first.AddHours(1), PendingOfflineSales = pending, LastOfflineSeq = lastSeq,
        LastUserName = "thungan@x.vn",
    };

    static PosOfflineSerialBlock Block(int from, int to, string inst = "i1") => new()
    {
        Id = Guid.NewGuid(), DeviceKey = "a:dev-1", InstallId = inst, DeviceName = "Quầy 1", FromSeq = from, ToSeq = to,
        CreatedAt = Now.AddDays(-5),
    };

    static PosOfflineAuditBuilder.OrderRow Order(int seq, DateTime soldAt, decimal total = 10000,
        DateTime? createdAt = null, DateTime? updatedAt = null) => new(
        Guid.NewGuid(), $"HD{seq:D4}", PosOfflineSaleRules.Format(seq), soldAt, "a:dev-1",
        createdAt ?? soldAt.AddMinutes(3), updatedAt, "thungan@x.vn", total, PosSaleOrderStatus.Completed);

    static PosOfflineAuditBuilder.Report Build(
        List<PosDeviceInstall> installs, List<PosOfflineSerialBlock> blocks, List<PosOfflineAuditBuilder.OrderRow> orders,
        PosOfflineSaleRules.Settings? settings = null, int days = 30) =>
        PosOfflineAuditBuilder.Build(settings ?? On, installs, blocks, orders, Now.AddDays(-days), Now);

    [Fact]
    public void Off_store_without_data_says_not_enabled()
    {
        var r = Build([], [], [], new PosOfflineSaleRules.Settings(false, 8));
        Assert.Equal("off", r.Verdict);
        Assert.Empty(r.Alerts);
    }

    [Fact]
    public void All_synced_is_green()
    {
        var r = Build([Inst("i1", Now.AddDays(-6))], [Block(1, 50)],
            [Order(1, Now.AddDays(-1)), Order(2, Now.AddDays(-1))]);
        Assert.Equal("green", r.Verdict);
        Assert.Equal(2, r.Summary.SerialsUsed);
        Assert.Equal(50, r.Summary.SerialsIssued);
        Assert.Equal(0, r.Summary.Gaps);
    }

    [Fact]
    public void Gap_is_red_with_action_and_device_user()
    {
        var r = Build([Inst("i1", Now.AddDays(-6))], [Block(1, 50)],
            [Order(1, Now.AddDays(-1)), Order(3, Now.AddDays(-1))]);
        Assert.Equal("red", r.Verdict);
        var a = Assert.Single(r.Alerts, x => x.Kind == "GAP");
        Assert.Equal("high", a.Level);
        Assert.Contains("OFF-000002", a.Action);
        Assert.Contains("thungan@x.vn", a.Action);
        Assert.Equal(1, r.Summary.Gaps);
        Assert.Equal(["OFF-000002"], r.Blocks[0].Gaps);
    }

    [Fact]
    public void Reinstall_with_pending_is_flagged()
    {
        var r = Build([Inst("i1", Now.AddDays(-6), pending: 2, lastSeq: 4), Inst("i2", Now.AddDays(-1))],
            [Block(1, 10)], [Order(1, Now.AddDays(-2))]);
        Assert.Contains(r.Alerts, x => x.Kind == "REINSTALL_PENDING");
        Assert.Contains(r.Alerts, x => x.Kind == "REINSTALL" && x.Level == "info");
        Assert.Equal(1, r.Devices.Single().Reinstalls);
        Assert.Equal("high", r.Alerts[0].Level); // nghiêm trọng xếp đầu
    }

    [Fact]
    public void Pending_on_device_without_gap_is_yellow()
    {
        var r = Build([Inst("i1", Now.AddDays(-6), pending: 3)], [Block(1, 50)], [Order(1, Now.AddDays(-1))]);
        Assert.Equal("yellow", r.Verdict);
        Assert.Equal(3, r.Summary.PendingOnDevices);
    }

    [Fact]
    public void Out_of_range_number_is_medium()
    {
        var r = Build([Inst("i1", Now.AddDays(-6))], [Block(1, 10)], [Order(1, Now.AddDays(-1)), Order(99, Now.AddDays(-1))]);
        Assert.Contains(r.Alerts, x => x.Kind == "OUT_OF_RANGE" && x.Level == "medium");
        Assert.Equal("yellow", r.Verdict);
    }

    [Fact]
    public void Summary_counts_all_sales_not_only_listed_rows()
    {
        // 600 đơn — danh sách chỉ trả 500 dòng nhưng tổng phải đủ 600.
        var orders = Enumerable.Range(1, 600).Select(i => Order(i, Now.AddHours(-i / 30.0), 1000)).ToList();
        var r = Build([Inst("i1", Now.AddDays(-30))], [Block(1, 600)], orders);
        Assert.Equal(500, r.Sales.Count);
        Assert.Equal(600, r.Summary.OfflineSales);
        Assert.Equal(600_000m, r.Summary.OfflineTotal);
    }

    [Fact]
    public void Daily_series_covers_every_day_in_vn_time()
    {
        // 23:30 giờ VN ngày 15/10 = 16:30 UTC ngày 15/10.
        var r = Build([Inst("i1", Now.AddDays(-6))], [Block(1, 50)],
            [Order(1, new DateTime(2026, 10, 15, 16, 30, 0, DateTimeKind.Utc), 5000)], days: 7);
        Assert.Equal(8, r.Daily.Count); // 10/10 … 17/10
        var d = Assert.Single(r.Daily, x => x.Count > 0);
        Assert.Equal(new DateTime(2026, 10, 15), d.DateVn.Date);
        Assert.Equal(5000m, d.Total);
    }

    [Fact]
    public void Sale_on_table_opened_before_uses_update_time_for_delay()
    {
        var sold = Now.AddHours(-3);
        // Đơn bàn tạo trên máy chủ trước khi mất mạng; bán offline lúc [sold]; về máy chủ 2 giờ sau.
        var o = Order(1, sold, createdAt: sold.AddHours(-1), updatedAt: sold.AddHours(2));
        var r = Build([Inst("i1", Now.AddDays(-6))], [Block(1, 50)], [o]);
        Assert.Equal(120, r.Sales.Single().DelayMinutes);
        Assert.Equal(1, r.DelayBuckets.Single(b => b.Label == "1 – 24 giờ").Count);
        Assert.Equal(120, r.Summary.MaxDelayMinutes);
    }
}
