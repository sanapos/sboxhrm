using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Controllers;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Máy POS báo lần cài nhiều lần: số đơn chờ / số offline cuối phải được cập nhật (DbContext mặc định NoTracking).</summary>
[Collection("pos-pg")]
public class PosOfflineInstallTests(PosPgFixture fx)
{
    [Fact]
    public async Task Lan_bao_sau_cap_nhat_so_don_cho_va_so_cuoi()
    {
        if (fx.ConnectionString == null) return;
        var store = await fx.NewStoreAsync();
        PosOfflineController Ctl(Infrastructure.ZKTecoDbContext db) =>
            PosPgFixture.As(new PosOfflineController(db, NullLogger<PosOfflineController>.Instance), store);
        PosOfflineController.InstallDto Dto(int pending, int? seq) => new()
        {
            DeviceKey = "a:dev-1", InstallId = "inst-1", DeviceName = "POS 1", Platform = "android",
            AppVersion = "1.0", PendingOfflineSales = pending, LastOfflineSeq = seq,
        };

        await using (var db = fx.NewDb()) await Ctl(db).Install(Dto(0, null), default);
        await using (var db = fx.NewDb()) await Ctl(db).Install(Dto(2, 7), default);

        await using var check = fx.NewDb();
        var row = await check.PosDeviceInstalls.SingleAsync(x => x.StoreId == store);
        Assert.Equal(2, row.PendingOfflineSales);   // trước đây vẫn 0
        Assert.Equal(7, row.LastOfflineSeq);        // trước đây null → không cảnh báo «chưa đồng bộ đủ»
        Assert.True(row.LastSeenAt > row.FirstSeenAt);
    }
}
