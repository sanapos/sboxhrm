using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// SBOX BOSS «Nhân viên hôm nay» / ô «Đã chấm công» ở Tổng quan: đi trễ chỉ theo ca trong thiết lập lương, trễ quá
/// «Giới hạn đi trễ» vẫn tính đủ phút; lịch xếp ca chỉ để biết ai nghỉ / ai phải làm.
/// </summary>
public class BossStaffTodayBuilderTests
{
    [Fact]
    public async Task Tre_theo_ca_thiet_lap_luong_khong_theo_lich()
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var store = Guid.NewGuid();
        // Giờ chấm lưu giờ tường VN không nhãn (như cột timestamp của Postgres).
        var today = DateTime.SpecifyKind(VnTimeHelper.NowVn().Date, DateTimeKind.Unspecified);
        var caHc = new ShiftTemplate
        {
            Id = Guid.NewGuid(), StoreId = store, Name = "Ca hành chính", StartTime = new TimeSpan(8, 0, 0),
            EndTime = new TimeSpan(17, 0, 0), LateGraceMinutes = 5, MaximumAllowedLateMinutes = 15, IsActive = true,
        };
        var caSang = new ShiftTemplate
        {
            Id = Guid.NewGuid(), StoreId = store, Name = "Ca sáng", StartTime = new TimeSpan(6, 0, 0),
            EndTime = new TimeSpan(14, 0, 0), LateGraceMinutes = 5, IsActive = true,
        };
        db.ShiftTemplates.AddRange(caHc, caSang);
        var coCa = new Benefit { Id = Guid.NewGuid(), StoreId = store, Name = "VP", Description = "shifts:Ca hành chính", WeeklyOffDays = "" };
        var khongCa = new Benefit { Id = Guid.NewGuid(), StoreId = store, Name = "Khác", WeeklyOffDays = "" };
        db.Benefits.AddRange(coCa, khongCa);
        Employee E(string code) => new()
        {
            Id = Guid.NewGuid(), StoreId = store, EmployeeCode = code, FirstName = code, LastName = "NV",
            WorkStatus = EmployeeWorkStatus.Active,
        };
        var nv1 = E("NV1"); // ca hành chính trong thiết lập lương, vào 08:19
        var nv2 = E("NV2"); // không gán ca, có lịch Ca sáng 06:00, vào 08:30 → không tính trễ
        var nv3 = E("NV3"); // ca hành chính, chưa chấm
        db.Employees.AddRange(nv1, nv2, nv3);
        db.EmployeeBenefits.AddRange(
            new EmployeeBenefit { Id = Guid.NewGuid(), EmployeeId = nv1.Id, BenefitId = coCa.Id, EffectiveDate = today.AddDays(-30) },
            new EmployeeBenefit { Id = Guid.NewGuid(), EmployeeId = nv2.Id, BenefitId = khongCa.Id, EffectiveDate = today.AddDays(-30) },
            new EmployeeBenefit { Id = Guid.NewGuid(), EmployeeId = nv3.Id, BenefitId = coCa.Id, EffectiveDate = today.AddDays(-30) });
        db.WorkSchedules.Add(new WorkSchedule
        {
            Id = Guid.NewGuid(), StoreId = store, EmployeeUserId = nv2.Id, Date = today, ShiftId = caSang.Id, IsActive = true,
        });
        var device = new Device { Id = Guid.NewGuid(), StoreId = store, SerialNumber = "SNB", DeviceName = "Máy" };
        db.Devices.Add(device);
        foreach (var (emp, h, m) in new[] { (nv1, 8, 19), (nv2, 8, 30) })
        {
            var du = new DeviceUser { Id = Guid.NewGuid(), DeviceId = device.Id, Pin = emp.EmployeeCode!, Name = emp.EmployeeCode!, EmployeeId = emp.Id };
            db.DeviceUsers.Add(du);
            db.AttendanceLogs.Add(new Attendance
            {
                Id = Guid.NewGuid(), DeviceId = device.Id, EmployeeId = du.Id, PIN = du.Pin,
                AttendanceTime = today.AddHours(h).AddMinutes(m), AttendanceState = AttendanceStates.CheckIn,
            });
        }
        await db.SaveChangesAsync();

        var result = await BossStaffTodayBuilder.BuildAsync(db, store, db.Employees.Where(e => e.StoreId == store), default);
        var rows = result.Staff.ToDictionary(r => r.Code!);

        Assert.True(result.HasSchedules);
        Assert.Equal(19, rows["NV1"].LateMinutes);          // trễ quá giới hạn 15 phút vẫn tính đủ phút
        Assert.Equal("Ca hành chính", rows["NV1"].ShiftName);
        Assert.Equal(0, rows["NV2"].LateMinutes);           // chỉ có lịch xếp ca → không tính trễ
        Assert.True(rows["NV2"].HasShift);                  // lịch vẫn cho biết hôm nay phải làm
        Assert.Null(rows["NV3"].FirstPunch);
        Assert.True(rows["NV3"].HasShift);
        Assert.Equal("08:00", rows["NV3"].ShiftStart);      // chưa chấm: giờ ca từ thiết lập lương
    }
}
