using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Cài đặt dữ liệu mẫu cho cửa hàng mới đăng ký
/// </summary>
[Route("api/[controller]")]
[ApiController]
public class SampleDataController(
    ZKTecoDbContext db,
    UserManager<ApplicationUser> userManager,
    ILogger<SampleDataController> logger) : ControllerBase
{
    /// <summary>
    /// Cài đặt dữ liệu mẫu: 10 nhân viên, 15 ngày dữ liệu đầy đủ các module
    /// </summary>
    [HttpPost("seed/{storeCode}")]
    [AllowAnonymous]
    public async Task<ActionResult<AppResponse<SampleDataResult>>> SeedSampleData(
        string storeCode, CancellationToken ct)
    {
        try
        {
            // 1. Tìm store
            var store = await db.Stores
                .FirstOrDefaultAsync(s => s.Code.ToLower() == storeCode.ToLower(), ct);
            if (store == null)
                return NotFound(AppResponse<SampleDataResult>.Error("Không tìm thấy cửa hàng."));

            var storeId = store.Id;

            // Kiểm tra đã có dữ liệu mẫu chưa
            var hasEmployees = await db.Employees
                .IgnoreQueryFilters()
                .AnyAsync(e => e.StoreId == storeId, ct);
            if (hasEmployees)
                return BadRequest(AppResponse<SampleDataResult>.Error("Cửa hàng đã có dữ liệu. Không thể cài mẫu."));

            // Tìm owner user
            var ownerUser = await db.Users
                .FirstOrDefaultAsync(u => u.StoreId == storeId && u.Role == nameof(Roles.Admin), ct);
            if (ownerUser == null)
                return BadRequest(AppResponse<SampleDataResult>.Error("Không tìm thấy tài khoản quản lý."));

            var ownerId = ownerUser.Id;
            var now = DateTime.UtcNow;
            var today = now.Date;

            // Sử dụng transaction để đảm bảo tính toàn vẹn dữ liệu
            await using var transaction = await db.Database.BeginTransactionAsync(ct);
            try
            {

            // ══════════════════════════════════════════════
            // 2. TẠO PHÒNG BAN
            // ══════════════════════════════════════════════
            var departments = new List<Department>
            {
                new() { Id = Guid.NewGuid(), Code = "BGD", Name = "Ban Giám Đốc", Description = "Ban lãnh đạo công ty", Level = 0, SortOrder = 1, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), Code = "KD", Name = "Phòng Kinh Doanh", Description = "Bán hàng và chăm sóc khách hàng", Level = 1, SortOrder = 2, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), Code = "KT", Name = "Phòng Kế Toán", Description = "Quản lý tài chính kế toán", Level = 1, SortOrder = 3, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), Code = "NS", Name = "Phòng Nhân Sự", Description = "Quản lý nhân sự và tuyển dụng", Level = 1, SortOrder = 4, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), Code = "SX", Name = "Phòng Sản Xuất", Description = "Sản xuất và gia công", Level = 1, SortOrder = 5, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
            };
            db.Departments.AddRange(departments);

            // ══════════════════════════════════════════════
            // 3. TẠO TÀI KHOẢN NHÂN VIÊN (10 người)
            // ══════════════════════════════════════════════
            var empData = new[]
            {
                ("An",    "Nguyễn Văn", "Nam",  "0901000001", "an",    "NV001", "Giám Đốc",      0, "1990-03-15"),
                ("Bình",  "Trần Thị",   "Nữ",   "0901000002", "binh",  "NV002", "Trưởng phòng KD",1, "1992-07-20"),
                ("Cường", "Lê Hoàng",   "Nam",  "0901000003", "cuong", "NV003", "Nhân viên KD",   1, "1995-01-10"),
                ("Dung",  "Phạm Thị",   "Nữ",   "0901000004", "dung",  "NV004", "Kế toán trưởng", 2, "1991-11-25"),
                ("Em",    "Hoàng Văn",   "Nam",  "0901000005", "em",    "NV005", "Nhân viên KT",   2, "1998-05-08"),
                ("Fương", "Võ Thị",      "Nữ",   "0901000006", "fuong", "NV006", "Trưởng phòng NS",3, "1993-09-12"),
                ("Giang", "Đặng Văn",    "Nam",  "0901000007", "giang", "NV007", "Nhân viên NS",   3, "1997-02-28"),
                ("Hạnh",  "Bùi Thị",     "Nữ",   "0901000008", "hanh",  "NV008", "Quản đốc SX",    4, "1994-06-17"),
                ("Khang", "Ngô Văn",     "Nam",  "0901000009", "khang", "NV009", "Công nhân SX",    4, "1996-08-03"),
                ("Lan",   "Mai Thị",     "Nữ",   "0901000010", "lan",   "NV010", "Công nhân SX",    4, "1999-12-22"),
            };

            var employees = new List<Employee>();
            var userIds = new List<Guid>();

            foreach (var (firstName, lastName, gender, phone, emailBase, code, position, deptIdx, dob) in empData)
            {
                var userId = Guid.NewGuid();
                var empId = Guid.NewGuid();
                userIds.Add(userId);

                var email = $"{emailBase}-{storeCode}@demo.local";
                var empCode = $"{code}-{storeCode}";
                // Tạo user account
                var user = new ApplicationUser
                {
                    Id = userId,
                    UserName = email,
                    Email = email,
                    PhoneNumber = phone,
                    FirstName = firstName,
                    LastName = lastName,
                    EmailConfirmed = true,
                    PhoneNumberConfirmed = true,
                    CreatedAt = now,
                    StoreId = storeId,
                    Role = deptIdx == 0 ? nameof(Roles.Manager) : nameof(Roles.Employee),
                };
                var createResult = await userManager.CreateAsync(user, "Demo@123");
                if (!createResult.Succeeded) continue;

                var roleName = deptIdx == 0 ? nameof(Roles.Manager) : nameof(Roles.Employee);
                await userManager.AddToRoleAsync(user, roleName);

                var emp = new Employee
                {
                    Id = empId,
                    EmployeeCode = empCode,
                    FirstName = firstName,
                    LastName = lastName,
                    Gender = gender,
                    DateOfBirth = DateTime.Parse(dob),
                    PhoneNumber = phone,
                    CompanyEmail = email,
                    Department = departments[deptIdx].Name,
                    DepartmentId = departments[deptIdx].Id,
                    Position = position,
                    Level = deptIdx == 0 ? "C-Level" : (position.Contains("Trưởng") || position.Contains("Quản đốc") ? "Senior" : "Junior"),
                    JoinDate = today.AddDays(-30),
                    WorkStatus = EmployeeWorkStatus.Active,
                    EmploymentType = EmploymentType.Monthly,
                    ApplicationUserId = userId,
                    ManagerId = ownerId,
                    StoreId = storeId,
                    IsActive = true,
                    CreatedAt = now,
                    CreatedBy = "SampleData",
                    BankName = "Vietcombank",
                    BankAccountNumber = $"10200{code[2..]}",
                    BankAccountName = $"{lastName} {firstName}".ToUpperInvariant(),
                };
                employees.Add(emp);
            }
            db.Employees.AddRange(employees);
            await db.SaveChangesAsync(ct);

            // ══════════════════════════════════════════════
            // 4. TẠO CA LÀM VIỆC (ShiftTemplate)
            // ══════════════════════════════════════════════
            var shifts = new List<ShiftTemplate>
            {
                new() { Id = Guid.NewGuid(), ManagerId = ownerId, Name = "Ca sáng", Code = "CS", StartTime = new TimeSpan(8,0,0), EndTime = new TimeSpan(17,0,0), MaximumAllowedLateMinutes = 15, MaximumAllowedEarlyLeaveMinutes = 15, BreakTimeMinutes = 60, ShiftType = "HanhChinh", IsActive = true, StoreId = storeId, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), ManagerId = ownerId, Name = "Ca chiều", Code = "CC", StartTime = new TimeSpan(13,0,0), EndTime = new TimeSpan(21,0,0), MaximumAllowedLateMinutes = 15, MaximumAllowedEarlyLeaveMinutes = 15, BreakTimeMinutes = 30, ShiftType = "HanhChinh", IsActive = true, StoreId = storeId, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), ManagerId = ownerId, Name = "Ca đêm", Code = "CD", StartTime = new TimeSpan(21,0,0), EndTime = new TimeSpan(5,0,0), MaximumAllowedLateMinutes = 15, MaximumAllowedEarlyLeaveMinutes = 15, BreakTimeMinutes = 30, ShiftType = "QuaDem", IsActive = true, StoreId = storeId, CreatedAt = now, CreatedBy = "SampleData" },
            };
            db.ShiftTemplates.AddRange(shifts);

            // ══════════════════════════════════════════════
            // 5. TẠO BẢNG LƯƠNG (Benefit / Salary Profile)
            // ══════════════════════════════════════════════
            var salaryProfiles = new List<Benefit>
            {
                new() { Id = Guid.NewGuid(), Name = "Lương quản lý", RateType = SalaryRateType.Monthly, Rate = 25_000_000, SalaryPerDay = 961_538, StandardWorkMode = StandardWorkMode.Fixed26, MealAllowance = 40_000, TransportAllowance = 500_000, OvertimeMultiplier = 1.5m, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), Name = "Lương nhân viên VP", RateType = SalaryRateType.Monthly, Rate = 12_000_000, SalaryPerDay = 461_538, StandardWorkMode = StandardWorkMode.Fixed26, MealAllowance = 30_000, TransportAllowance = 300_000, OvertimeMultiplier = 1.5m, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), Name = "Lương công nhân", RateType = SalaryRateType.Daily, Rate = 350_000, SalaryPerDay = 350_000, StandardWorkMode = StandardWorkMode.Fixed26, MealAllowance = 30_000, TransportAllowance = 200_000, OvertimeMultiplier = 1.5m, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
            };
            db.Benefits.AddRange(salaryProfiles);

            // Gán bảng lương cho nhân viên
            var empBenefits = new List<EmployeeBenefit>();
            for (int i = 0; i < employees.Count; i++)
            {
                var profileIdx = i == 0 ? 0 : (i < 8 ? 1 : 2); // Quản lý / VP / Công nhân
                empBenefits.Add(new EmployeeBenefit
                {
                    Id = Guid.NewGuid(),
                    EmployeeId = employees[i].Id,
                    BenefitId = salaryProfiles[profileIdx].Id,
                    EffectiveDate = today.AddDays(-30),
                    IsActive = true,
                    CreatedAt = now,
                    CreatedBy = "SampleData",
                });
            }
            db.EmployeeBenefits.AddRange(empBenefits);

            // ══════════════════════════════════════════════
            // 6. TẠO LỊCH LÀM VIỆC + CA + CHẤM CÔNG (15 ngày)
            // ══════════════════════════════════════════════
            var rng = new Random(42);
            var morningShiftId = shifts[0].Id;
            var allShifts = new List<Shift>();
            var allSchedules = new List<WorkSchedule>();
            var allAttendances = new List<Attendance>();

            // Tạo thiết bị mẫu (cần cho FK AttendanceLogs → Devices)
            var dummyDeviceId = Guid.NewGuid();
            var dummyDeviceInfoId = Guid.NewGuid();
            var dummyDeviceInfo = new DeviceInfo
            {
                Id = dummyDeviceInfoId,
                DeviceId = dummyDeviceId,
                FirmwareVersion = "Ver 6.60 Oct 29 2020",
                EnrolledUserCount = 10,
                FingerprintCount = 0,
                AttendanceCount = 0,
                DeviceIp = "192.168.1.100",
            };
            db.DeviceInfos.Add(dummyDeviceInfo);

            var dummyDevice = new Device
            {
                Id = dummyDeviceId,
                SerialNumber = $"DEMO-{storeCode}",
                DeviceName = "Máy chấm công Demo",
                Description = "Thiết bị mẫu cho dữ liệu demo",
                IpAddress = "192.168.1.100",
                Location = "Sảnh chính",
                DeviceStatus = "Online",
                ManagerId = ownerId,
                OwnerId = ownerId,
                IsClaimed = true,
                ClaimedAt = now,
                DeviceInfoId = dummyDeviceInfoId,
                StoreId = storeId,
                IsActive = true,
                CreatedAt = now,
                CreatedBy = "SampleData",
            };
            db.Devices.Add(dummyDevice);

            // Tạo DeviceUser cho mỗi nhân viên (cần cho FK AttendanceLogs → DeviceUsers)
            var deviceUsers = new List<DeviceUser>();
            var empToDeviceUserId = new Dictionary<Guid, Guid>(); // Employee.Id → DeviceUser.Id
            foreach (var emp in employees)
            {
                var du = new DeviceUser
                {
                    Id = Guid.NewGuid(),
                    Pin = emp.EmployeeCode,
                    Name = $"{emp.LastName} {emp.FirstName}",
                    DeviceId = dummyDeviceId,
                    EmployeeId = emp.Id,
                    GroupId = 1,
                    Privilege = 0,
                    VerifyMode = 15, // Face
                    IsActive = true,
                    CreatedAt = now,
                    CreatedBy = "SampleData",
                };
                deviceUsers.Add(du);
                empToDeviceUserId[emp.Id] = du.Id;
            }
            db.DeviceUsers.AddRange(deviceUsers);

            for (int dayOffset = -14; dayOffset <= 0; dayOffset++)
            {
                var date = today.AddDays(dayOffset);
                if (date.DayOfWeek == DayOfWeek.Sunday) continue; // Chủ nhật nghỉ

                foreach (var emp in employees)
                {
                    var userId = emp.ApplicationUserId!.Value;
                    var shiftId = Guid.NewGuid();
                    var shiftStart = date.Add(shifts[0].StartTime); // 8:00
                    var shiftEnd = date.Add(shifts[0].EndTime);     // 17:00

                    // Lịch làm việc
                    allSchedules.Add(new WorkSchedule
                    {
                        Id = Guid.NewGuid(),
                        EmployeeUserId = emp.Id,
                        Date = date,
                        ShiftId = morningShiftId,
                        StartTime = shifts[0].StartTime,
                        EndTime = shifts[0].EndTime,
                        IsDayOff = date.DayOfWeek == DayOfWeek.Saturday && rng.Next(3) == 0,
                        AssignedById = ownerId,
                        StoreId = storeId,
                        IsActive = true,
                        CreatedAt = now,
                        CreatedBy = "SampleData",
                    });

                    // Random chấm công: hầu hết đúng giờ, vài người muộn
                    var lateMinutes = rng.Next(10) < 7 ? 0 : rng.Next(1, 20);
                    var checkInTime = shiftStart.AddMinutes(lateMinutes);
                    var earlyLeave = rng.Next(10) < 8 ? 0 : rng.Next(1, 15);
                    var checkOutTime = shiftEnd.AddMinutes(-earlyLeave);

                    var deviceUserId = empToDeviceUserId[emp.Id];
                    var checkInAtt = new Attendance
                    {
                        Id = Guid.NewGuid(),
                        DeviceId = dummyDeviceId,
                        EmployeeId = deviceUserId, // FK → DeviceUsers.Id
                        PIN = emp.EmployeeCode,
                        VerifyMode = VerifyModes.Face,
                        AttendanceState = AttendanceStates.CheckIn,
                        AttendanceTime = checkInTime,
                        CreatedAt = checkInTime,
                        CreatedBy = "SampleData",
                    };
                    var checkOutAtt = new Attendance
                    {
                        Id = Guid.NewGuid(),
                        DeviceId = dummyDeviceId,
                        EmployeeId = deviceUserId, // FK → DeviceUsers.Id
                        PIN = emp.EmployeeCode,
                        VerifyMode = VerifyModes.Face,
                        AttendanceState = AttendanceStates.CheckOut,
                        AttendanceTime = checkOutTime,
                        CreatedAt = checkOutTime,
                        CreatedBy = "SampleData",
                    };
                    allAttendances.Add(checkInAtt);
                    allAttendances.Add(checkOutAtt);

                    // Tạo ca làm việc (Shift)
                    allShifts.Add(new Shift
                    {
                        Id = shiftId,
                        EmployeeUserId = userId,
                        StartTime = shiftStart,
                        EndTime = shiftEnd,
                        MaximumAllowedLateMinutes = 15,
                        MaximumAllowedEarlyLeaveMinutes = 15,
                        BreakTimeMinutes = 60,
                        Status = ShiftStatus.Approved,
                        CheckInAttendanceId = checkInAtt.Id,
                        CheckOutAttendanceId = checkOutAtt.Id,
                        StoreId = storeId,
                        IsActive = true,
                        CreatedAt = now,
                        CreatedBy = "SampleData",
                    });
                }
            }
            db.AttendanceLogs.AddRange(allAttendances);
            db.Shifts.AddRange(allShifts);
            db.WorkSchedules.AddRange(allSchedules);

            // ══════════════════════════════════════════════
            // 7. TẠO ĐƠN NGHỈ PHÉP
            // ══════════════════════════════════════════════
            var leaves = new List<Leave>();
            // Nhân viên 2 (Cường) xin nghỉ phép năm
            if (allShifts.Count > 25)
            {
                leaves.Add(new Leave
                {
                    Id = Guid.NewGuid(),
                    EmployeeUserId = userIds[2],
                    ManagerId = ownerId,
                    Type = LeaveType.AnnualLeave,
                    ShiftId = allShifts[25].Id,
                    StartDate = today.AddDays(-10),
                    EndDate = today.AddDays(-9),
                    IsHalfShift = false,
                    Reason = "Nghỉ phép đi du lịch gia đình",
                    Status = LeaveStatus.Approved,
                    StoreId = storeId,
                    EmployeeId = employees[2].Id,
                    IsActive = true,
                    CreatedAt = now,
                    CreatedBy = "SampleData",
                });
            }
            // Nhân viên 4 (Em) xin nghỉ ốm 
            if (allShifts.Count > 45)
            {
                leaves.Add(new Leave
                {
                    Id = Guid.NewGuid(),
                    EmployeeUserId = userIds[4],
                    ManagerId = ownerId,
                    Type = LeaveType.SickLeave,
                    ShiftId = allShifts[45].Id,
                    StartDate = today.AddDays(-5),
                    EndDate = today.AddDays(-5),
                    IsHalfShift = true,
                    Reason = "Bị cảm sốt, cần nghỉ ngơi",
                    Status = LeaveStatus.Approved,
                    StoreId = storeId,
                    EmployeeId = employees[4].Id,
                    IsActive = true,
                    CreatedAt = now,
                    CreatedBy = "SampleData",
                });
            }
            // Nhân viên 6 (Fương) nghỉ việc riêng
            if (allShifts.Count > 60)
            {
                leaves.Add(new Leave
                {
                    Id = Guid.NewGuid(),
                    EmployeeUserId = userIds[5],
                    ManagerId = ownerId,
                    Type = LeaveType.PersonalPaid,
                    ShiftId = allShifts[60].Id,
                    StartDate = today.AddDays(-3),
                    EndDate = today.AddDays(-3),
                    IsHalfShift = false,
                    Reason = "Có việc gia đình cần giải quyết",
                    Status = LeaveStatus.Pending,
                    StoreId = storeId,
                    EmployeeId = employees[5].Id,
                    IsActive = true,
                    CreatedAt = now,
                    CreatedBy = "SampleData",
                });
            }
            db.Leaves.AddRange(leaves);

            // ══════════════════════════════════════════════
            // 8. TĂNG CA (Overtime)
            // ══════════════════════════════════════════════
            var overtimes = new List<Overtime>
            {
                new() { Id = Guid.NewGuid(), EmployeeUserId = userIds[1], ManagerId = ownerId, Type = OvertimeType.Weekday, Date = today.AddDays(-7), StartTime = new TimeSpan(17,30,0), EndTime = new TimeSpan(20,0,0), PlannedHours = 2.5m, ActualHours = 2.5m, Multiplier = 1.5m, Reason = "Hoàn thành báo cáo doanh số tháng", Status = OvertimeStatus.Approved, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), EmployeeUserId = userIds[7], ManagerId = ownerId, Type = OvertimeType.Weekend, Date = today.AddDays(-6), StartTime = new TimeSpan(8,0,0), EndTime = new TimeSpan(12,0,0), PlannedHours = 4m, ActualHours = 4m, Multiplier = 2.0m, Reason = "Giao hàng gấp cho khách VIP", Status = OvertimeStatus.Completed, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), EmployeeUserId = userIds[8], ManagerId = ownerId, Type = OvertimeType.Weekday, Date = today.AddDays(-2), StartTime = new TimeSpan(17,0,0), EndTime = new TimeSpan(19,30,0), PlannedHours = 2.5m, Multiplier = 1.5m, Reason = "Gia công đơn hàng số 2024-156", Status = OvertimeStatus.Pending, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
            };
            db.Overtimes.AddRange(overtimes);

            // ══════════════════════════════════════════════
            // 9. PHẠT (PenaltyTicket)
            // ══════════════════════════════════════════════
            var penalties = new List<PenaltyTicket>
            {
                new() { Id = Guid.NewGuid(), TicketCode = $"PT-001-{storeCode}", EmployeeId = employees[2].Id, Type = PenaltyTicketType.Late, Status = PenaltyTicketStatus.Approved, Amount = 50_000, ViolationDate = today.AddDays(-12), MinutesLateOrEarly = 18, ShiftStartTime = new TimeSpan(8,0,0), ActualPunchTime = today.AddDays(-12).AddHours(8).AddMinutes(18), PenaltyTier = 1, Description = "Đi trễ 18 phút", StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), TicketCode = $"PT-002-{storeCode}", EmployeeId = employees[8].Id, Type = PenaltyTicketType.EarlyLeave, Status = PenaltyTicketStatus.Approved, Amount = 30_000, ViolationDate = today.AddDays(-8), MinutesLateOrEarly = 12, ShiftEndTime = new TimeSpan(17,0,0), PenaltyTier = 1, Description = "Về sớm 12 phút", StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), TicketCode = $"PT-003-{storeCode}", EmployeeId = employees[9].Id, Type = PenaltyTicketType.ForgotCheck, Status = PenaltyTicketStatus.Pending, Amount = 20_000, ViolationDate = today.AddDays(-4), Description = "Quên chấm công ra ca", StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
            };
            db.PenaltyTickets.AddRange(penalties);

            // ══════════════════════════════════════════════
            // 10. ỨNG LƯƠNG (AdvanceRequest)  
            // ══════════════════════════════════════════════
            var advances = new List<AdvanceRequest>
            {
                new() { Id = Guid.NewGuid(), EmployeeUserId = userIds[8], EmployeeId = employees[8].Id, Amount = 3_000_000, Reason = "Cần tiền gấp sửa xe", RequestDate = today.AddDays(-10), Status = AdvanceRequestStatus.Approved, ApprovedById = ownerId, ApprovedDate = today.AddDays(-9), ForMonth = now.Month, ForYear = now.Year, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), EmployeeUserId = userIds[6], EmployeeId = employees[6].Id, Amount = 2_000_000, Reason = "Đóng tiền học con", RequestDate = today.AddDays(-5), Status = AdvanceRequestStatus.Pending, ForMonth = now.Month, ForYear = now.Year, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
            };
            db.AdvanceRequests.AddRange(advances);

            // ══════════════════════════════════════════════
            // 11. THU CHI (CashTransaction)
            // ══════════════════════════════════════════════
            var incCat = new TransactionCategory { Id = Guid.NewGuid(), Name = "Doanh thu bán hàng", Type = CashTransactionType.Income, Icon = "💰", Color = "#4CAF50", SortOrder = 1, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" };
            var expCat = new TransactionCategory { Id = Guid.NewGuid(), Name = "Chi phí vận hành", Type = CashTransactionType.Expense, Icon = "🏢", Color = "#F44336", SortOrder = 2, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" };
            var salCat = new TransactionCategory { Id = Guid.NewGuid(), Name = "Lương nhân viên", Type = CashTransactionType.Expense, Icon = "👥", Color = "#2196F3", SortOrder = 3, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" };
            db.TransactionCategories.AddRange(incCat, expCat, salCat);

            var transactions = new List<CashTransaction>
            {
                new() { Id = Guid.NewGuid(), TransactionCode = $"TX-001-{storeCode}", Type = CashTransactionType.Income, CategoryId = incCat.Id, Amount = 45_000_000, TransactionDate = today.AddDays(-13), Description = "Thu tiền đơn hàng #2024-150", PaymentMethod = PaymentMethodType.BankTransfer, Status = CashTransactionStatus.Completed, ContactName = "Công ty ABC", StoreId = storeId, CreatedByUserId = ownerId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), TransactionCode = $"TX-002-{storeCode}", Type = CashTransactionType.Income, CategoryId = incCat.Id, Amount = 28_500_000, TransactionDate = today.AddDays(-8), Description = "Thu tiền đơn hàng #2024-155", PaymentMethod = PaymentMethodType.Cash, Status = CashTransactionStatus.Completed, ContactName = "Cửa hàng XYZ", StoreId = storeId, CreatedByUserId = ownerId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), TransactionCode = $"TX-003-{storeCode}", Type = CashTransactionType.Expense, CategoryId = expCat.Id, Amount = 8_500_000, TransactionDate = today.AddDays(-10), Description = "Tiền điện + nước tháng này", PaymentMethod = PaymentMethodType.BankTransfer, Status = CashTransactionStatus.Completed, StoreId = storeId, CreatedByUserId = ownerId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), TransactionCode = $"TX-004-{storeCode}", Type = CashTransactionType.Expense, CategoryId = expCat.Id, Amount = 3_200_000, TransactionDate = today.AddDays(-6), Description = "Mua văn phòng phẩm + mực in", PaymentMethod = PaymentMethodType.Cash, Status = CashTransactionStatus.Completed, StoreId = storeId, CreatedByUserId = ownerId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), TransactionCode = $"TX-005-{storeCode}", Type = CashTransactionType.Expense, CategoryId = salCat.Id, Amount = 65_000_000, TransactionDate = today.AddDays(-1), Description = "Thanh toán lương tháng này", PaymentMethod = PaymentMethodType.BankTransfer, Status = CashTransactionStatus.Pending, StoreId = storeId, CreatedByUserId = ownerId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
            };
            db.CashTransactions.AddRange(transactions);

            // ══════════════════════════════════════════════
            // 12. TRUYỀN THÔNG NỘI BỘ  
            // ══════════════════════════════════════════════
            var comms = new List<InternalCommunication>
            {
                new() { Id = Guid.NewGuid(), StoreId = storeId, Title = "Chào mừng thành viên mới!", Content = "Chào mừng tất cả thành viên gia nhập công ty. Hãy cùng nhau xây dựng môi trường làm việc tốt nhất!", Type = CommunicationType.Announcement, Priority = CommunicationPriority.High, Status = CommunicationStatus.Published, AuthorId = ownerId, AuthorName = $"{ownerUser.FirstName} {ownerUser.LastName}", PublishedAt = now.AddDays(-14), IsPinned = true, ViewCount = 10, LikeCount = 8, CreatedAt = now.AddDays(-14), CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), StoreId = storeId, Title = "Nội quy công ty áp dụng từ tháng này", Content = "Các nội quy mới:\n1. Giờ làm việc: 8:00 - 17:00\n2. Nghỉ trưa: 12:00 - 13:00\n3. Trang phục lịch sự\n4. Không sử dụng điện thoại trong giờ làm việc\n5. Báo cáo trước khi nghỉ phép ít nhất 1 ngày", Type = CommunicationType.Regulation, Priority = CommunicationPriority.Normal, Status = CommunicationStatus.Published, AuthorId = ownerId, AuthorName = $"{ownerUser.FirstName} {ownerUser.LastName}", PublishedAt = now.AddDays(-12), ViewCount = 9, LikeCount = 3, CreatedAt = now.AddDays(-12), CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), StoreId = storeId, Title = "Kế hoạch team building quý 2", Content = "Công ty tổ chức chuyến team building tại Vũng Tàu ngày 15-16 tháng tới. Chi phí do công ty chi trả 100%. Đăng ký tham gia trước ngày 10.", Type = CommunicationType.Event, Priority = CommunicationPriority.Normal, Status = CommunicationStatus.Published, AuthorId = ownerId, AuthorName = $"{ownerUser.FirstName} {ownerUser.LastName}", PublishedAt = now.AddDays(-5), ViewCount = 7, LikeCount = 6, CreatedAt = now.AddDays(-5), CreatedBy = "SampleData" },
            };
            db.InternalCommunications.AddRange(comms);

            // ══════════════════════════════════════════════
            // 13. FEEDBACK / GÓP Ý
            // ══════════════════════════════════════════════
            var feedbacks = new List<Feedback>
            {
                new() { Id = Guid.NewGuid(), SenderEmployeeId = employees[2].Id, IsAnonymous = false, Title = "Đề xuất cải thiện giờ nghỉ trưa", Content = "Em đề xuất kéo dài giờ nghỉ trưa thêm 15 phút để nhân viên có thời gian nghỉ ngơi tốt hơn.", Category = "Suggestion", Status = "Responded", Response = "Cảm ơn góp ý. Ban giám đốc sẽ xem xét áp dụng từ tháng sau.", RespondedByEmployeeId = employees[0].Id, RespondedAt = now.AddDays(-5), StoreId = storeId, IsActive = true, CreatedAt = now.AddDays(-8), CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), SenderEmployeeId = null, IsAnonymous = true, Title = "Máy lạnh phòng sản xuất bị hỏng", Content = "Máy lạnh tầng 2 khu sản xuất đã hỏng 3 ngày, rất nóng ảnh hưởng năng suất. Kính mong ban quản lý sớm sửa chữa.", Category = "Complaint", Status = "Pending", StoreId = storeId, IsActive = true, CreatedAt = now.AddDays(-2), CreatedBy = "SampleData" },
            };
            db.Feedbacks.AddRange(feedbacks);

            // ══════════════════════════════════════════════
            // 14. SẢN XUẤT (Production)
            // ══════════════════════════════════════════════
            var prodGroup = new ProductGroup { Id = Guid.NewGuid(), Name = "Sản phẩm may mặc", Description = "Các sản phẩm may gia công", SortOrder = 1, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" };
            db.ProductGroups.Add(prodGroup);

            var products = new List<ProductItem>
            {
                new() { Id = Guid.NewGuid(), Code = $"SP001-{storeCode}", Name = "Áo sơ mi nam", Unit = "Cái", ProductGroupId = prodGroup.Id, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), Code = $"SP002-{storeCode}", Name = "Quần tây nam", Unit = "Cái", ProductGroupId = prodGroup.Id, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), Code = $"SP003-{storeCode}", Name = "Áo vest nữ", Unit = "Cái", ProductGroupId = prodGroup.Id, StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
            };
            db.ProductItems.AddRange(products);

            // Sản lượng 15 ngày cho công nhân SX (emp 7, 8, 9)
            var prodEntries = new List<ProductionEntry>();
            for (int dayOffset = -14; dayOffset <= 0; dayOffset++)
            {
                var date = today.AddDays(dayOffset);
                if (date.DayOfWeek == DayOfWeek.Sunday) continue;

                for (int empIdx = 7; empIdx <= 9; empIdx++)
                {
                    var productIdx = rng.Next(products.Count);
                    var qty = 15 + rng.Next(20); // 15-34 sản phẩm/ngày
                    prodEntries.Add(new ProductionEntry
                    {
                        Id = Guid.NewGuid(),
                        EmployeeId = employees[empIdx].Id,
                        ProductItemId = products[productIdx].Id,
                        WorkDate = date,
                        Quantity = qty,
                        UnitPrice = 25_000,
                        Amount = qty * 25_000,
                        StoreId = storeId,
                        IsActive = true,
                        CreatedAt = now,
                        CreatedBy = "SampleData",
                    });
                }
            }
            db.ProductionEntries.AddRange(prodEntries);

            // ══════════════════════════════════════════════
            // 15. NGÀY LỄ
            // ══════════════════════════════════════════════
            var year = now.Year;
            var holidays = new List<Holiday>
            {
                new() { Id = Guid.NewGuid(), Name = "Tết Dương lịch", Date = new DateTime(year, 1, 1), IsRecurring = true, SalaryRate = 3.0, Category = "Ngày nghỉ chính thức", StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), Name = "Giỗ Tổ Hùng Vương", Date = new DateTime(year, 4, 18), IsRecurring = true, SalaryRate = 3.0, Category = "Ngày nghỉ chính thức", StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), Name = "Ngày Giải Phóng", Date = new DateTime(year, 4, 30), IsRecurring = true, SalaryRate = 3.0, Category = "Ngày nghỉ chính thức", StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), Name = "Quốc tế Lao động", Date = new DateTime(year, 5, 1), IsRecurring = true, SalaryRate = 3.0, Category = "Ngày nghỉ chính thức", StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), Name = "Quốc Khánh", Date = new DateTime(year, 9, 2), IsRecurring = true, SalaryRate = 3.0, Category = "Ngày nghỉ chính thức", StoreId = storeId, IsActive = true, CreatedAt = now, CreatedBy = "SampleData" },
            };
            db.Holidays.AddRange(holidays);

            // ══════════════════════════════════════════════
            // 16. GIAO VIỆC (WorkTask)
            // ══════════════════════════════════════════════
            var tasks = new List<WorkTask>
            {
                new() { Id = Guid.NewGuid(), TaskCode = $"TASK-001-{storeCode}", Title = "Lập báo cáo doanh số tháng 3", Description = "Tổng hợp doanh số bán hàng tháng 3, so sánh với KPI đề ra", TaskType = TaskType.Task, Priority = TaskPriority.High, Status = WorkTaskStatus.Completed, Progress = 100, StoreId = storeId, AssignedById = ownerId, IsActive = true, CreatedAt = now.AddDays(-10), CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), TaskCode = $"TASK-002-{storeCode}", Title = "Tuyển dụng 2 nhân viên kế toán", Description = "Đăng tin tuyển dụng, sàng lọc hồ sơ, phỏng vấn ứng viên", TaskType = TaskType.Task, Priority = TaskPriority.Medium, Status = WorkTaskStatus.InProgress, Progress = 40, StoreId = storeId, AssignedById = ownerId, IsActive = true, CreatedAt = now.AddDays(-7), CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), TaskCode = $"TASK-003-{storeCode}", Title = "Kiểm kê kho nguyên vật liệu", Description = "Kiểm tra số lượng tồn kho, đối chiếu sổ sách", TaskType = TaskType.Task, Priority = TaskPriority.Medium, Status = WorkTaskStatus.Todo, Progress = 0, StoreId = storeId, AssignedById = ownerId, IsActive = true, CreatedAt = now.AddDays(-3), CreatedBy = "SampleData" },
                new() { Id = Guid.NewGuid(), TaskCode = $"TASK-004-{storeCode}", Title = "Đào tạo quy trình mới cho nhân viên SX", Description = "Tổ chức buổi đào tạo quy trình may công nghiệp mới, áp dụng công nghệ lean manufacturing", TaskType = TaskType.Task, Priority = TaskPriority.High, Status = WorkTaskStatus.InProgress, Progress = 60, StoreId = storeId, AssignedById = ownerId, IsActive = true, CreatedAt = now.AddDays(-5), CreatedBy = "SampleData" },
            };
            db.WorkTasks.AddRange(tasks);

            // Gán task cho nhân viên
            var taskAssignees = new List<TaskAssignee>
            {
                new() { Id = Guid.NewGuid(), TaskId = tasks[0].Id, EmployeeId = employees[1].Id, AssignedAt = now.AddDays(-10), Role = "Assignee" },
                new() { Id = Guid.NewGuid(), TaskId = tasks[1].Id, EmployeeId = employees[5].Id, AssignedAt = now.AddDays(-7), Role = "Assignee" },
                new() { Id = Guid.NewGuid(), TaskId = tasks[2].Id, EmployeeId = employees[3].Id, AssignedAt = now.AddDays(-3), Role = "Assignee" },
                new() { Id = Guid.NewGuid(), TaskId = tasks[3].Id, EmployeeId = employees[7].Id, AssignedAt = now.AddDays(-5), Role = "Assignee" },
            };
            db.TaskAssignees.AddRange(taskAssignees);

            // ══════════════════════════════════════════════
            // 17. QUYỀN (RolePermissions)
            // ══════════════════════════════════════════════
            var existingRolePermIds = await db.RolePermissions
                .Where(rp => rp.StoreId == storeId)
                .Select(rp => rp.PermissionId + "_" + rp.RoleName)
                .ToListAsync(ct);
            var existingRolePermSet = new HashSet<string>(existingRolePermIds);
            var permissions = await db.Permissions.ToListAsync(ct);
            var rolePerms = new List<RolePermission>();
            foreach (var perm in permissions)
            {
                // Admin: full quyền
                if (!existingRolePermSet.Contains(perm.Id + "_" + nameof(Roles.Admin)))
                rolePerms.Add(new RolePermission
                {
                    Id = Guid.NewGuid(),
                    RoleName = nameof(Roles.Admin),
                    RoleDisplayName = "Quản trị viên",
                    PermissionId = perm.Id,
                    StoreId = storeId,
                    CanView = true,
                    CanCreate = true,
                    CanEdit = true,
                    CanDelete = true,
                    CanExport = true,
                    CanApprove = true,
                    IsActive = true,
                    CreatedAt = now,
                    CreatedBy = "SampleData",
                });
                // Manager: view + create + edit + approve
                if (!existingRolePermSet.Contains(perm.Id + "_" + nameof(Roles.Manager)))
                rolePerms.Add(new RolePermission
                {
                    Id = Guid.NewGuid(),
                    RoleName = nameof(Roles.Manager),
                    RoleDisplayName = "Quản lý",
                    PermissionId = perm.Id,
                    StoreId = storeId,
                    CanView = true,
                    CanCreate = true,
                    CanEdit = true,
                    CanDelete = false,
                    CanExport = true,
                    CanApprove = true,
                    IsActive = true,
                    CreatedAt = now,
                    CreatedBy = "SampleData",
                });
                // Employee: view only
                if (!existingRolePermSet.Contains(perm.Id + "_" + nameof(Roles.Employee)))
                rolePerms.Add(new RolePermission
                {
                    Id = Guid.NewGuid(),
                    RoleName = nameof(Roles.Employee),
                    RoleDisplayName = "Nhân viên",
                    PermissionId = perm.Id,
                    StoreId = storeId,
                    CanView = true,
                    CanCreate = false,
                    CanEdit = false,
                    CanDelete = false,
                    CanExport = false,
                    CanApprove = false,
                    IsActive = true,
                    CreatedAt = now,
                    CreatedBy = "SampleData",
                });
            }
            db.RolePermissions.AddRange(rolePerms);

            // ══════════════════════════════════════════════
            // SAVE ALL
            // ══════════════════════════════════════════════
            await db.SaveChangesAsync(ct);
            await transaction.CommitAsync(ct);

            var result = new SampleDataResult
            {
                EmployeesCreated = employees.Count,
                DepartmentsCreated = departments.Count,
                ShiftsCreated = allShifts.Count,
                AttendanceRecords = allAttendances.Count,
                LeavesCreated = leaves.Count,
                OvertimesCreated = overtimes.Count,
                PenaltiesCreated = penalties.Count,
                TransactionsCreated = transactions.Count,
                TasksCreated = tasks.Count,
                ProductionEntries = prodEntries.Count,
                Message = "Đã cài đặt dữ liệu mẫu thành công! 10 nhân viên, 15 ngày dữ liệu đầy đủ."
            };

            logger.LogInformation("Sample data seeded for store {StoreCode}: {Result}", storeCode, result.Message);
            return Ok(AppResponse<SampleDataResult>.Success(result));
            }
            catch
            {
                await transaction.RollbackAsync(ct);
                throw;
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error seeding sample data for store {StoreCode}", storeCode);
            var innerMsg = ex.InnerException?.Message ?? ex.Message;
            return StatusCode(500, AppResponse<SampleDataResult>.Error($"Lỗi cài dữ liệu mẫu: {innerMsg}"));
        }
    }

    /// <summary>
    /// Xóa toàn bộ dữ liệu mẫu (CreatedBy = "SampleData") của cửa hàng
    /// </summary>
    [HttpDelete("delete/{storeCode}")]
    [AllowAnonymous]
    public async Task<ActionResult<AppResponse<SampleDataDeleteResult>>> DeleteSampleData(
        string storeCode, CancellationToken ct)
    {
        try
        {
            // Support both storeCode and storeId (GUID)
            Store? store;
            if (Guid.TryParse(storeCode, out var storeGuid))
                store = await db.Stores.FirstOrDefaultAsync(s => s.Id == storeGuid, ct);
            else
                store = await db.Stores.FirstOrDefaultAsync(s => s.Code.ToLower() == storeCode.ToLower(), ct);

            if (store == null)
                return NotFound(AppResponse<SampleDataDeleteResult>.Error("Không tìm thấy cửa hàng."));

            var storeId = store.Id;
            var marker = "SampleData";

            // Kiểm tra có dữ liệu mẫu không
            var hasSampleData = await db.Employees
                .IgnoreQueryFilters()
                .AnyAsync(e => e.StoreId == storeId && e.CreatedBy == marker, ct);
            if (!hasSampleData)
                return BadRequest(AppResponse<SampleDataDeleteResult>.Error("Cửa hàng không có dữ liệu mẫu."));

            // Xóa theo thứ tự FK (con trước, cha sau)
            var taskAssignees = await db.TaskAssignees
                .IgnoreQueryFilters()
                .Where(x => db.WorkTasks.IgnoreQueryFilters()
                    .Where(t => t.StoreId == storeId && t.CreatedBy == marker)
                    .Select(t => t.Id).Contains(x.TaskId))
                .ToListAsync(ct);
            db.TaskAssignees.RemoveRange(taskAssignees);

            var tasks = await db.WorkTasks
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.WorkTasks.RemoveRange(tasks);

            var prodEntries = await db.ProductionEntries
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.ProductionEntries.RemoveRange(prodEntries);

            var products = await db.ProductItems
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.ProductItems.RemoveRange(products);

            var prodGroups = await db.ProductGroups
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.ProductGroups.RemoveRange(prodGroups);

            var feedbacks = await db.Feedbacks
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.Feedbacks.RemoveRange(feedbacks);

            var comms = await db.InternalCommunications
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.InternalCommunications.RemoveRange(comms);

            var transactions = await db.CashTransactions
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.CashTransactions.RemoveRange(transactions);

            var txCategories = await db.TransactionCategories
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.TransactionCategories.RemoveRange(txCategories);

            var advances = await db.AdvanceRequests
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.AdvanceRequests.RemoveRange(advances);

            var penalties = await db.PenaltyTickets
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.PenaltyTickets.RemoveRange(penalties);

            var overtimes = await db.Overtimes
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.Overtimes.RemoveRange(overtimes);

            var leaves = await db.Leaves
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.Leaves.RemoveRange(leaves);

            var shifts = await db.Shifts
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.Shifts.RemoveRange(shifts);

            var schedules = await db.WorkSchedules
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.WorkSchedules.RemoveRange(schedules);

            var attendances = await db.AttendanceLogs
                .IgnoreQueryFilters()
                .Where(x => x.CreatedBy == marker)
                .ToListAsync(ct);
            // Lọc theo employee IDs của store
            var sampleEmpIds = (await db.Employees
                .IgnoreQueryFilters()
                .Where(e => e.StoreId == storeId && e.CreatedBy == marker)
                .Select(e => e.Id)
                .ToListAsync(ct)).ToHashSet();
            attendances = attendances.Where(a => a.EmployeeId.HasValue && sampleEmpIds.Contains(a.EmployeeId.Value)).ToList();
            db.AttendanceLogs.RemoveRange(attendances);

            var empBenefits = await db.EmployeeBenefits
                .IgnoreQueryFilters()
                .Where(x => x.CreatedBy == marker)
                .ToListAsync(ct);
            empBenefits = empBenefits.Where(x => sampleEmpIds.Contains(x.EmployeeId)).ToList();
            db.EmployeeBenefits.RemoveRange(empBenefits);

            var benefits = await db.Benefits
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.Benefits.RemoveRange(benefits);

            var shiftTemplates = await db.ShiftTemplates
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.ShiftTemplates.RemoveRange(shiftTemplates);

            var holidays = await db.Holidays
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.Holidays.RemoveRange(holidays);

            var rolePerms = await db.RolePermissions
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.RolePermissions.RemoveRange(rolePerms);

            // Lấy danh sách employee sample để xóa user accounts
            var sampleEmployees = await db.Employees
                .IgnoreQueryFilters()
                .Where(e => e.StoreId == storeId && e.CreatedBy == marker)
                .ToListAsync(ct);

            var userIdsToDelete = sampleEmployees
                .Where(e => e.ApplicationUserId.HasValue)
                .Select(e => e.ApplicationUserId!.Value)
                .ToList();

            db.Employees.RemoveRange(sampleEmployees);

            var departments = await db.Departments
                .IgnoreQueryFilters()
                .Where(x => x.StoreId == storeId && x.CreatedBy == marker)
                .ToListAsync(ct);
            db.Departments.RemoveRange(departments);

            await db.SaveChangesAsync(ct);

            // Xóa user accounts (sau khi đã xóa employee FK)
            var deletedUsers = 0;
            foreach (var userId in userIdsToDelete)
            {
                var user = await userManager.FindByIdAsync(userId.ToString());
                if (user != null)
                {
                    await userManager.DeleteAsync(user);
                    deletedUsers++;
                }
            }

            var result = new SampleDataDeleteResult
            {
                EmployeesDeleted = sampleEmployees.Count,
                UsersDeleted = deletedUsers,
                DepartmentsDeleted = departments.Count,
                ShiftsDeleted = shifts.Count,
                AttendanceRecordsDeleted = attendances.Count,
                Message = $"Đã xóa toàn bộ dữ liệu mẫu thành công! ({sampleEmployees.Count} nhân viên, {departments.Count} phòng ban)"
            };

            logger.LogInformation("Sample data deleted for store {StoreCode}: {Msg}", storeCode, result.Message);
            return Ok(AppResponse<SampleDataDeleteResult>.Success(result));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error deleting sample data for store {StoreCode}", storeCode);
            return StatusCode(500, AppResponse<SampleDataDeleteResult>.Error($"Lỗi xóa dữ liệu mẫu: {ex.Message}"));
        }
    }
}

public class SampleDataResult
{
    public int EmployeesCreated { get; set; }
    public int DepartmentsCreated { get; set; }
    public int ShiftsCreated { get; set; }
    public int AttendanceRecords { get; set; }
    public int LeavesCreated { get; set; }
    public int OvertimesCreated { get; set; }
    public int PenaltiesCreated { get; set; }
    public int TransactionsCreated { get; set; }
    public int TasksCreated { get; set; }
    public int ProductionEntries { get; set; }
    public string Message { get; set; } = string.Empty;
}

public class SampleDataDeleteResult
{
    public int EmployeesDeleted { get; set; }
    public int UsersDeleted { get; set; }
    public int DepartmentsDeleted { get; set; }
    public int ShiftsDeleted { get; set; }
    public int AttendanceRecordsDeleted { get; set; }
    public string Message { get; set; } = string.Empty;
}
