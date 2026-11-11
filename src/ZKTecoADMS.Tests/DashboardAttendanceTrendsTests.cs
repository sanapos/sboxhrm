using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using MediatR;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Chuyên cần trên Tổng quan: không bỏ cuối tuần cố định, người nghỉ phép không tính vắng,
/// NV đã nghỉ việc không tính, ngày nghỉ theo thiết lập lương.
/// </summary>
public class DashboardAttendanceTrendsTests
{
    static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    readonly Guid _store = Guid.NewGuid();
    readonly ServiceProvider _sp;
    readonly ZKTecoDbContext _db;

    public DashboardAttendanceTrendsTests()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        _sp = services.BuildServiceProvider();
        _db = _sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
    }

    DashboardController Ctl() => new(null!, NullLogger<DashboardController>.Instance, _db)
    {
        ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                RequestServices = _sp,
                User = new ClaimsPrincipal(new ClaimsIdentity([
                    new Claim("id", Guid.NewGuid().ToString()),
                    new Claim(ClaimTypes.Role, "Admin"),
                    new Claim(ClaimTypeNames.StoreId, _store.ToString()),
                ], "test")),
            },
        },
    };

    [Fact]
    public async Task Hom_nay_tinh_ca_cuoi_tuan_nghi_phep_khong_tinh_vang()
    {
        var today = DateTime.UtcNow.AddHours(7).Date;
        var device = new Device { Id = Guid.NewGuid(), StoreId = _store, SerialNumber = "SN1", DeviceName = "Máy" };
        _db.Devices.Add(device);
        // Thiết lập lương «theo lịch phân ca» → không có thứ nghỉ cố định: hôm nay (kể cả thứ 7 / CN) phải đi làm.
        // Lương tháng: lương giờ (giá trị mặc định của RateType) không tính «phải đi làm» khi chưa xếp ca.
        var profile = new Benefit
        {
            Id = Guid.NewGuid(), StoreId = _store, Name = "Lương", PaidLeaveType = "schedule", RateType = SalaryRateType.Monthly,
        };
        _db.Benefits.Add(profile);
        Employee E(string code, EmployeeWorkStatus st = EmployeeWorkStatus.Active) => new()
        {
            Id = Guid.NewGuid(), StoreId = _store, EmployeeCode = code, FirstName = code, LastName = "NV",
            ApplicationUserId = Guid.NewGuid(), WorkStatus = st,
        };
        var present = E("NV1");
        var onLeave = E("NV2");
        var absent = E("NV3");
        var resigned = E("NV4", EmployeeWorkStatus.Resigned);
        _db.Employees.AddRange(present, onLeave, absent, resigned);
        foreach (var e in new[] { present, onLeave, absent, resigned })
            _db.EmployeeBenefits.Add(new EmployeeBenefit
            {
                Id = Guid.NewGuid(), EmployeeId = e.Id, BenefitId = profile.Id, EffectiveDate = today.AddDays(-60),
            });
        _db.AttendanceLogs.Add(new Attendance
        {
            Id = Guid.NewGuid(), DeviceId = device.Id, PIN = "NV1", AttendanceTime = today.AddHours(8),
            AttendanceState = AttendanceStates.CheckIn,
        });
        // Máy không ghi loại vào/ra: lần chấm cuối ngày = giờ ra.
        _db.AttendanceLogs.Add(new Attendance
        {
            Id = Guid.NewGuid(), DeviceId = device.Id, PIN = "NV1", AttendanceTime = today.AddHours(17).AddMinutes(5),
            AttendanceState = AttendanceStates.CheckIn,
        });
        _db.Leaves.Add(new Leave
        {
            Id = Guid.NewGuid(), StoreId = _store, EmployeeUserId = onLeave.ApplicationUserId!.Value,
            StartDate = today, EndDate = today, Status = LeaveStatus.Approved, Type = LeaveType.AnnualLeave,
        });
        await _db.SaveChangesAsync();

        var res = Assert.IsType<OkObjectResult>(await Ctl().GetAttendanceTrends(days: 3));
        var root = JsonDocument.Parse(JsonSerializer.Serialize(res.Value, Json)).RootElement;
        var row = root.GetProperty("data").EnumerateArray()
            .Single(d => d.GetProperty("date").GetString() == today.ToString("yyyy-MM-dd"));

        Assert.Equal(1, row.GetProperty("present").GetInt32());
        Assert.Equal(1, row.GetProperty("onTime").GetInt32());
        Assert.Equal(1, row.GetProperty("onLeave").GetInt32());   // nghỉ phép không tính vắng
        Assert.Equal(1, row.GetProperty("absent").GetInt32());    // NV3; NV4 đã nghỉ việc không tính
        Assert.Equal(3, row.GetProperty("total").GetInt32());

        // «Nhân viên hôm nay» theo chấm công thực tế (gồm NV không có ca kiểu cũ).
        var emps = row.GetProperty("employees").EnumerateArray()
            .ToDictionary(e => e.GetProperty("employeeCode").GetString()!);
        Assert.Equal(3, emps.Count);
        Assert.Equal("Present", emps["NV1"].GetProperty("status").GetString());
        Assert.Equal("08:00", emps["NV1"].GetProperty("checkIn").GetString());
        Assert.Equal("17:05", emps["NV1"].GetProperty("checkOut").GetString());
        Assert.Equal("On Leave", emps["NV2"].GetProperty("status").GetString());
        Assert.Equal("Absent", emps["NV3"].GetProperty("status").GetString());
        Assert.False(emps.ContainsKey("NV4"));
    }

    [Fact]
    public async Task Di_tre_chi_theo_ca_thiet_lap_luong_tinh_du_phut()
    {
        var today = DateTime.UtcNow.AddHours(7).Date;
        var device = new Device { Id = Guid.NewGuid(), StoreId = _store, SerialNumber = "SN2", DeviceName = "Máy" };
        _db.Devices.Add(device);
        var caSang = new ShiftTemplate
        {
            Id = Guid.NewGuid(), StoreId = _store, Name = "Ca sáng", StartTime = new TimeSpan(7, 0, 0),
            EndTime = new TimeSpan(16, 0, 0), LateGraceMinutes = 5, EarlyLeaveGraceMinutes = 5, IsActive = true,
        };
        _db.ShiftTemplates.Add(caSang);
        // NV1: mẫu lương gán «Ca sáng». NV2: mẫu lương không gán ca nhưng CÓ lịch xếp ca 07:00 — không tính trễ.
        var coCa = new Benefit { Id = Guid.NewGuid(), StoreId = _store, Name = "Có ca", Description = "shifts:Ca  SÁNG|x:1", WeeklyOffDays = "" };
        var khongCa = new Benefit { Id = Guid.NewGuid(), StoreId = _store, Name = "Không ca" };
        _db.Benefits.AddRange(coCa, khongCa);
        Employee E(string code) => new()
        {
            Id = Guid.NewGuid(), StoreId = _store, EmployeeCode = code, FirstName = code, LastName = "NV",
            ApplicationUserId = Guid.NewGuid(), WorkStatus = EmployeeWorkStatus.Active,
        };
        var nv1 = E("NV1");
        var nv2 = E("NV2");
        _db.Employees.AddRange(nv1, nv2);
        _db.EmployeeBenefits.AddRange(
            new EmployeeBenefit { Id = Guid.NewGuid(), EmployeeId = nv1.Id, BenefitId = coCa.Id, EffectiveDate = today.AddDays(-60) },
            new EmployeeBenefit { Id = Guid.NewGuid(), EmployeeId = nv2.Id, BenefitId = khongCa.Id, EffectiveDate = today.AddDays(-60) });
        _db.WorkSchedules.Add(new WorkSchedule
        {
            Id = Guid.NewGuid(), StoreId = _store, EmployeeUserId = nv2.Id, Date = today, ShiftId = caSang.Id,
            IsActive = true,
        });
        foreach (var (pin, at) in new[] { ("NV1", today.AddHours(7).AddMinutes(7)), ("NV2", today.AddHours(7).AddMinutes(30)) })
            _db.AttendanceLogs.Add(new Attendance
            {
                Id = Guid.NewGuid(), DeviceId = device.Id, PIN = pin, AttendanceTime = at,
                AttendanceState = AttendanceStates.CheckIn,
            });
        await _db.SaveChangesAsync();

        var res = Assert.IsType<OkObjectResult>(await Ctl().GetAttendanceTrends(days: 1));
        var row = JsonDocument.Parse(JsonSerializer.Serialize(res.Value, Json)).RootElement
            .GetProperty("data").EnumerateArray().Single();
        Assert.Equal(2, row.GetProperty("present").GetInt32());
        Assert.Equal(1, row.GetProperty("late").GetInt32());
        // Ca 7:00, ân hạn 5 phút, vào 7:07 → trễ 7 phút (không trừ ân hạn).
        var late = row.GetProperty("lateEmployees").EnumerateArray().Single();
        Assert.Equal("NV1", late.GetProperty("pin").GetString());
        Assert.Equal(7, late.GetProperty("lateMinutes").GetInt32());
        var emps = row.GetProperty("employees").EnumerateArray().ToDictionary(e => e.GetProperty("employeeCode").GetString()!);
        Assert.Equal("Late", emps["NV1"].GetProperty("status").GetString());
        Assert.Equal(7, emps["NV1"].GetProperty("lateMinutes").GetInt32());
        Assert.Equal("Present", emps["NV2"].GetProperty("status").GetString());
        Assert.Equal("Chưa gán ca", emps["NV2"].GetProperty("shiftName").GetString());
    }

    [Theory]
    [InlineData("Saturday,Sunday", null, new[] { DayOfWeek.Saturday, DayOfWeek.Sunday })]
    [InlineData(null, "sunday", new[] { DayOfWeek.Sunday })]
    [InlineData(null, "sat-sun", new[] { DayOfWeek.Saturday, DayOfWeek.Sunday })]
    [InlineData(null, "schedule", new DayOfWeek[0])]
    [InlineData(null, null, new[] { DayOfWeek.Sunday })]
    public void Ngay_nghi_tuan_tu_thiet_lap_luong(string? weekly, string? paidLeave, DayOfWeek[] expected)
    {
        Assert.Equal(expected.ToHashSet(), DashboardController.ParseWeeklyOff(weekly, paidLeave));
    }
}
