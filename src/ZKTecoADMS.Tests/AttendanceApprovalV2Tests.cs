using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests;

/// <summary>Duyệt chấm công v2: chấm điểm rủi ro, tự duyệt tin cậy, hạn giữ ảnh bằng chứng.</summary>
public class AttendanceApprovalV2Tests
{
    [Fact]
    public void Near_location_with_good_face_is_trusted_and_auto_approvable()
    {
        var r = MobilePunchRiskScorer.Score(new MobilePunchRiskInput
        {
            Distance = 160, Radius = 100, GpsAccuracy = 12, FaceScore = 93, HasSitePhoto = true, HasReason = true,
        });
        Assert.Equal(MobilePunchRiskScorer.Trusted, r.Level);
        Assert.True(MobilePunchRiskScorer.CanAutoApprove(r, autoApproveTrusted: true, isTravel: false));
        Assert.False(MobilePunchRiskScorer.CanAutoApprove(r, autoApproveTrusted: false, isTravel: false));
        Assert.False(MobilePunchRiskScorer.CanAutoApprove(r, autoApproveTrusted: true, isTravel: true)); // đi đường luôn duyệt tay
    }

    [Fact]
    public void Far_or_weak_signals_need_review_or_are_high_risk()
    {
        var far = MobilePunchRiskScorer.Score(new MobilePunchRiskInput { Distance = 7200, Radius = 100, FaceScore = 90, HasSitePhoto = true });
        Assert.Equal(MobilePunchRiskScorer.High, far.Level);
        Assert.Contains(far.Flags, f => f.Contains("7,2 km"));

        var mid = MobilePunchRiskScorer.Score(new MobilePunchRiskInput { Distance = 800, Radius = 100, FaceScore = 90, HasSitePhoto = true, HasReason = true });
        Assert.Equal(MobilePunchRiskScorer.Review, mid.Level);

        // Gần nhưng GPS sai số lớn + mặt khớp thấp → không còn tin cậy
        var weak = MobilePunchRiskScorer.Score(new MobilePunchRiskInput { Distance = 150, Radius = 100, GpsAccuracy = 180, FaceScore = 70 });
        Assert.NotEqual(MobilePunchRiskScorer.Trusted, weak.Level);
        Assert.Contains(weak.Flags, f => f.Contains("GPS"));
        Assert.Contains(weak.Flags, f => f.Contains("khuôn mặt"));

        var noGps = MobilePunchRiskScorer.Score(new MobilePunchRiskInput { Distance = null, FaceScore = 95 });
        Assert.NotEqual(MobilePunchRiskScorer.Trusted, noGps.Level);

        // Lệch ca nhiều + chấm ngoài quá nhiều lần
        var odd = MobilePunchRiskScorer.Score(new MobilePunchRiskInput
        {
            Distance = 200, Radius = 100, FaceScore = 95, HasSitePhoto = true, HasReason = true, MinutesFromShift = 150, OutsideCountThisMonth = 20,
        });
        Assert.NotEqual(MobilePunchRiskScorer.Trusted, odd.Level);
        Assert.Contains(odd.Flags, f => f.Contains("Lệch ca"));
    }

    [Fact]
    public void Custom_trusted_distance_is_respected()
    {
        var input = new MobilePunchRiskInput { Distance = 450, Radius = 100, FaceScore = 95, HasSitePhoto = true, HasReason = true };
        Assert.NotEqual(MobilePunchRiskScorer.Trusted, MobilePunchRiskScorer.Score(input).Level);
        Assert.Equal(MobilePunchRiskScorer.Trusted, MobilePunchRiskScorer.Score(input, trustedMaxDistance: 500).Level);
    }

    [Fact]
    public async Task Evidence_is_kept_for_retention_then_purged()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        using var provider = services.BuildServiceProvider();
        var db = provider.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var storeA = Guid.NewGuid();
        var storeB = Guid.NewGuid();
        db.Add(new MobileAttendanceSetting { Id = Guid.NewGuid(), StoreId = storeB, EvidenceRetentionDays = 7 });
        var now = new DateTime(2026, 10, 10, 12, 0, 0, DateTimeKind.Utc);
        MobileAttendanceRecord Rec(Guid store, string status, int daysAgo) => new()
        {
            Id = Guid.NewGuid(), StoreId = store, OdooEmployeeId = "x", EmployeeName = "NV", PunchTime = now.AddDays(-daysAgo),
            Status = status, ApprovedAt = status == "pending" ? null : now.AddDays(-daysAgo), CreatedAt = now.AddDays(-daysAgo),
            SitePhotoUrl = $"site/{Guid.NewGuid()}.jpg", IsOutside = true,
        };
        var old = Rec(storeA, "approved", 31);        // quá 30 ngày mặc định → xóa
        var fresh = Rec(storeA, "rejected", 20);      // còn hạn → giữ
        var pendingOld = Rec(storeA, "pending", 60);  // chưa xử lý → giữ
        var shortStore = Rec(storeB, "approved", 8);  // cửa hàng giữ 7 ngày → xóa
        db.AddRange(old, fresh, pendingOld, shortStore);
        await db.SaveChangesAsync();

        var deleted = new List<string>();
        var n = await AttendanceEvidencePurgeBackgroundService.PurgeAsync(db, p => { deleted.Add(p); return Task.CompletedTask; }, now, default);

        Assert.Equal(2, n);
        Assert.Equal(2, deleted.Count);
        var after = await db.MobileAttendanceRecords.ToDictionaryAsync(r => r.Id);
        Assert.Null(after[old.Id].SitePhotoUrl);
        Assert.NotNull(after[old.Id].EvidencePurgedAt);
        Assert.NotNull(after[fresh.Id].SitePhotoUrl);
        Assert.NotNull(after[pendingOld.Id].SitePhotoUrl);
        Assert.Null(after[shortStore.Id].SitePhotoUrl);

        // Chạy lại không xóa thêm
        Assert.Equal(0, await AttendanceEvidencePurgeBackgroundService.PurgeAsync(db, _ => Task.CompletedTask, now, default));
    }
}
