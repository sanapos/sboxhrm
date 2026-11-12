using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Application.Commands.WorkSchedules;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Repositories;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Một nhân viên làm nhiều ca trong ngày: thêm ca không được chồng giờ; đăng ký «đổi sang ca khác» thay ca cũ
/// (không cộng thêm ca); hoàn duyệt / xóa phiếu đổi ca trả lại ca cũ.
/// </summary>
public class MultiShiftScheduleTests
{
    sealed class NoTenant : ITenantProvider
    {
        public Guid? StoreId => null;
        public bool IsSuperAccess => true;
    }

    static EfRepository<T> Repo<T>(ZKTecoDbContext db) where T : Entity<Guid> =>
        new(db, NullLogger<EfRepository<T>>.Instance, new NoTenant());

    static readonly Guid Store = Guid.NewGuid();

    static ShiftTemplate Tpl(string name, int sh, int sm, int eh, int em) => new()
    {
        Id = Guid.NewGuid(), StoreId = Store, Name = name, ManagerId = Guid.NewGuid(),
        StartTime = new TimeSpan(sh, sm, 0), EndTime = new TimeSpan(eh, em, 0), IsActive = true,
    };

    [Fact]
    public void Ca_trung_gio_tinh_ca_ca_qua_dem()
    {
        var sang = Tpl("Ca Sáng", 7, 0, 11, 0);
        var chieu = Tpl("Ca Chiều", 13, 0, 21, 0);
        var trua = Tpl("Ca Trưa", 10, 30, 14, 0);
        var dem = Tpl("Ca Đêm", 22, 0, 6, 0);
        var som = Tpl("Ca Sớm", 5, 0, 8, 0);
        var linhHoat = Tpl("Ca Linh hoạt", 0, 0, 0, 0);
        var ketNoi = Tpl("Ca Nối", 11, 0, 13, 0);

        Assert.False(WorkScheduleDuplicateHelper.Overlaps(sang, chieu));
        Assert.True(WorkScheduleDuplicateHelper.Overlaps(sang, trua));
        Assert.True(WorkScheduleDuplicateHelper.Overlaps(dem, som));
        Assert.False(WorkScheduleDuplicateHelper.Overlaps(dem, sang));
        Assert.False(WorkScheduleDuplicateHelper.Overlaps(linhHoat, sang));
        // Ca nối liền (11:00 hết ca sáng, 11:00 vào ca nối) không tính trùng.
        Assert.False(WorkScheduleDuplicateHelper.Overlaps(sang, ketNoi));

        var tpls = new[] { sang, chieu, trua }.ToDictionary(t => t.Id);
        Assert.Null(WorkScheduleDuplicateHelper.OverlapError([sang.Id], chieu, tpls));
        Assert.Contains("trùng giờ với Ca Sáng", WorkScheduleDuplicateHelper.OverlapError([sang.Id], trua, tpls));
    }

    static (ZKTecoDbContext Db, Guid EmpId, ShiftTemplate Sang, ShiftTemplate Chieu, ShiftTemplate Trua) Seed()
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var sang = Tpl("Ca Sáng", 7, 0, 11, 0);
        var chieu = Tpl("Ca Chiều", 13, 0, 21, 0);
        var trua = Tpl("Ca Trưa", 10, 30, 14, 0);
        db.Set<ShiftTemplate>().AddRange(sang, chieu, trua);
        db.SaveChanges();
        return (db, Guid.NewGuid(), sang, chieu, trua);
    }

    static WorkSchedule Row(Guid emp, DateTime day, Guid shiftId) => new()
    {
        Id = Guid.NewGuid(), StoreId = Store, EmployeeUserId = emp, Date = day, ShiftId = shiftId,
    };

    [Fact]
    public async Task Duyet_dang_ky_them_ca_giu_ca_cu_va_them_ca_moi()
    {
        var (db, emp, sang, chieu, _) = Seed();
        var day = new DateTime(2026, 11, 20);
        db.Set<WorkSchedule>().Add(Row(emp, day, sang.Id));
        db.SaveChanges();
        var reg = new ScheduleRegistration { Id = Guid.NewGuid(), StoreId = Store, EmployeeUserId = emp, Date = day, ShiftId = chieu.Id };

        await ApproveScheduleRegistrationHandler.ApplyApprovedScheduleAsync(
            reg, Store, Repo<WorkSchedule>(db), Repo<ShiftTemplate>(db), default);

        var shifts = db.Set<WorkSchedule>().Where(w => w.EmployeeUserId == emp).Select(w => w.ShiftId).ToList();
        Assert.Equal(2, shifts.Count);
        Assert.Contains(sang.Id, shifts);
        Assert.Contains(chieu.Id, shifts);
        Assert.True(reg.AppliedCreatedNewSchedule);
    }

    [Fact]
    public async Task Duyet_them_ca_chong_gio_bi_chan()
    {
        var (db, emp, sang, _, trua) = Seed();
        var day = new DateTime(2026, 11, 20);
        db.Set<WorkSchedule>().Add(Row(emp, day, sang.Id));
        db.SaveChanges();
        var reg = new ScheduleRegistration { Id = Guid.NewGuid(), StoreId = Store, EmployeeUserId = emp, Date = day, ShiftId = trua.Id };

        var ex = await Assert.ThrowsAsync<InvalidOperationException>(() =>
            ApproveScheduleRegistrationHandler.ApplyApprovedScheduleAsync(
                reg, Store, Repo<WorkSchedule>(db), Repo<ShiftTemplate>(db), default));
        Assert.Contains("trùng giờ", ex.Message);
        Assert.Single(db.Set<WorkSchedule>().Where(w => w.EmployeeUserId == emp));
    }

    [Fact]
    public async Task Duyet_doi_ca_thay_ca_cu_hoan_duyet_tra_lai_ca_cu()
    {
        var (db, emp, sang, chieu, trua) = Seed();
        var day = new DateTime(2026, 11, 20);
        var row = Row(emp, day, sang.Id);
        db.Set<WorkSchedule>().Add(row);
        db.SaveChanges();
        // Đổi Ca Sáng → Ca Trưa: ca trưa chồng giờ ca sáng nhưng ca sáng bị bỏ nên hợp lệ.
        var reg = new ScheduleRegistration
        {
            Id = Guid.NewGuid(), StoreId = Store, EmployeeUserId = emp, Date = day, ShiftId = trua.Id, ReplaceShiftId = sang.Id,
        };
        var repo = Repo<WorkSchedule>(db);

        await ApproveScheduleRegistrationHandler.ApplyApprovedScheduleAsync(reg, Store, repo, Repo<ShiftTemplate>(db), default);

        var rows = db.Set<WorkSchedule>().AsNoTracking().Where(w => w.EmployeeUserId == emp).ToList();
        Assert.Single(rows);
        Assert.Equal(trua.Id, rows[0].ShiftId);
        Assert.Equal(row.Id, reg.AppliedWorkScheduleId);
        Assert.False(reg.AppliedCreatedNewSchedule);

        await RegistrationScheduleCleanup.RemoveAppliedScheduleAsync(reg, Store, repo, default);

        rows = db.Set<WorkSchedule>().AsNoTracking().Where(w => w.EmployeeUserId == emp).ToList();
        Assert.Single(rows);
        Assert.Equal(sang.Id, rows[0].ShiftId);
        _ = chieu;
    }

    [Fact]
    public async Task Doi_ca_khi_ca_cu_da_bi_go_thi_them_ca_moi()
    {
        var (db, emp, sang, chieu, _) = Seed();
        var day = new DateTime(2026, 11, 20);
        var reg = new ScheduleRegistration
        {
            Id = Guid.NewGuid(), StoreId = Store, EmployeeUserId = emp, Date = day, ShiftId = chieu.Id, ReplaceShiftId = sang.Id,
        };

        await ApproveScheduleRegistrationHandler.ApplyApprovedScheduleAsync(
            reg, Store, Repo<WorkSchedule>(db), Repo<ShiftTemplate>(db), default);

        var rows = db.Set<WorkSchedule>().Where(w => w.EmployeeUserId == emp).ToList();
        Assert.Single(rows);
        Assert.Equal(chieu.Id, rows[0].ShiftId);
        Assert.True(reg.AppliedCreatedNewSchedule);
    }
}
