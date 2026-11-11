using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Repositories;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Phạt tự động đi trễ chỉ theo ca trong thiết lập lương («shifts:» của mẫu lương, mức lương ca),
/// không theo lịch xếp ca; vào trễ quá «Giới hạn đi trễ» vẫn phạt đủ phút.
/// </summary>
public class AutoPenaltySalaryShiftOnlyTests
{
    sealed class NoTenant : ITenantProvider
    {
        public Guid? StoreId => null;
        public bool IsSuperAccess => true;
    }

    static EfRepository<T> Repo<T>(ZKTecoDbContext db) where T : Entity<Guid> =>
        new(db, NullLogger<EfRepository<T>>.Instance, new NoTenant());

    [Fact]
    public async Task Phat_tre_chi_theo_ca_thiet_lap_luong()
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var store = Guid.NewGuid();
        var day = new DateTime(2026, 11, 4); // thứ 4
        var device = new Device { Id = Guid.NewGuid(), StoreId = store, SerialNumber = "SNP", DeviceName = "Máy" };
        db.Devices.Add(device);
        var caHc = new ShiftTemplate
        {
            Id = Guid.NewGuid(), StoreId = store, Name = "Ca hành chính", StartTime = new TimeSpan(8, 0, 0),
            EndTime = new TimeSpan(17, 0, 0), LateGraceMinutes = 5, EarlyLeaveGraceMinutes = 5,
            MaximumAllowedLateMinutes = 15, IsActive = true,
        };
        var caSang = new ShiftTemplate
        {
            Id = Guid.NewGuid(), StoreId = store, Name = "Ca sáng", StartTime = new TimeSpan(6, 0, 0),
            EndTime = new TimeSpan(14, 0, 0), LateGraceMinutes = 5, EarlyLeaveGraceMinutes = 5, IsActive = true,
        };
        db.ShiftTemplates.AddRange(caHc, caSang);
        var coCa = new Benefit { Id = Guid.NewGuid(), StoreId = store, Name = "VP", Description = "shifts:Ca hành chính", RateType = SalaryRateType.Monthly };
        var khongCa = new Benefit { Id = Guid.NewGuid(), StoreId = store, Name = "Khác", RateType = SalaryRateType.Monthly };
        db.Benefits.AddRange(coCa, khongCa);
        db.PenaltySettings.Add(new PenaltySetting { Id = Guid.NewGuid(), StoreId = store });

        Employee E(string code) => new()
        {
            Id = Guid.NewGuid(), StoreId = store, EmployeeCode = code, FirstName = code, LastName = "NV",
            ApplicationUserId = Guid.NewGuid(), WorkStatus = EmployeeWorkStatus.Active,
        };
        var nv1 = E("NV1"); // mẫu lương gán Ca hành chính
        var nv2 = E("NV2"); // không gán ca, chỉ có lịch xếp Ca sáng 06:00 → không phạt
        var nv3 = E("NV3"); // gán qua mức lương ca
        db.Employees.AddRange(nv1, nv2, nv3);
        db.EmployeeBenefits.AddRange(
            new EmployeeBenefit { Id = Guid.NewGuid(), EmployeeId = nv1.Id, BenefitId = coCa.Id, EffectiveDate = day.AddDays(-30) },
            new EmployeeBenefit { Id = Guid.NewGuid(), EmployeeId = nv2.Id, BenefitId = khongCa.Id, EffectiveDate = day.AddDays(-30) },
            new EmployeeBenefit { Id = Guid.NewGuid(), EmployeeId = nv3.Id, BenefitId = khongCa.Id, EffectiveDate = day.AddDays(-30) });
        db.Set<ShiftSalaryLevel>().Add(new ShiftSalaryLevel
        {
            Id = Guid.NewGuid(), StoreId = store, ShiftTemplateId = caHc.Id, LevelName = "Mức 1",
            EmployeeIds = $"[\"{nv3.Id}\"]",
        });
        db.WorkSchedules.Add(new WorkSchedule
        {
            Id = Guid.NewGuid(), StoreId = store, EmployeeUserId = nv2.Id, Date = day, ShiftId = caSang.Id, IsActive = true,
        });
        var atts = new List<Attendance>();
        foreach (var (emp, pin, h, m) in new[] { (nv1, "1", 8, 19), (nv2, "2", 8, 19), (nv3, "3", 8, 20) })
        {
            var du = new DeviceUser { Id = Guid.NewGuid(), DeviceId = device.Id, Pin = pin, Name = pin, EmployeeId = emp.Id };
            db.DeviceUsers.Add(du);
            var a = new Attendance
            {
                Id = Guid.NewGuid(), DeviceId = device.Id, EmployeeId = du.Id, PIN = pin,
                AttendanceTime = day.AddHours(h).AddMinutes(m), AttendanceState = AttendanceStates.CheckIn,
            };
            db.AttendanceLogs.Add(a);
            atts.Add(a);
        }
        await db.SaveChangesAsync();

        var svc = new AttendanceService(
            Repo<Attendance>(db), Repo<Device>(db), Repo<DeviceUser>(db), Repo<Shift>(db), Repo<WorkSchedule>(db),
            Repo<PenaltySetting>(db), Repo<Employee>(db), Repo<PenaltyTicket>(db), Repo<EmployeeBenefit>(db),
            Repo<ShiftTemplate>(db), Repo<AppSettings>(db), Repo<Leave>(db), Repo<ShiftSalaryLevel>(db),
            NullLogger<AttendanceService>.Instance);
        await svc.UpdateShiftAttendancesAsync(atts, device);

        var late = await db.PenaltyTickets.AsNoTracking()
            .Where(t => t.Type == PenaltyTicketType.Late).ToListAsync();
        var byEmp = late.ToDictionary(t => t.EmployeeId);
        Assert.Equal(19, byEmp[nv1.Id].MinutesLateOrEarly);   // trễ quá giới hạn 15 phút vẫn phạt đủ phút
        Assert.Equal(20, byEmp[nv3.Id].MinutesLateOrEarly);   // ca từ mức lương ca
        Assert.False(byEmp.ContainsKey(nv2.Id));             // chỉ có lịch xếp ca → không phạt
    }
}
