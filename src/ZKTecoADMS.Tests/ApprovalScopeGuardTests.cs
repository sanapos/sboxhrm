using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests;

/// <summary>API duyệt đơn chỉ cho duyệt đơn của nhân viên trong phạm vi quản lý, không tự duyệt đơn của mình.</summary>
public class ApprovalScopeGuardTests
{
    static readonly Guid Store = Guid.NewGuid();
    static readonly Guid DeptA = Guid.NewGuid();
    static readonly Guid DeptB = Guid.NewGuid();

    // Trưởng phòng A + một nhân viên phòng A + một nhân viên phòng B.
    static readonly Guid HeadUser = Guid.NewGuid(), HeadEmp = Guid.NewGuid();
    static readonly Guid AUser = Guid.NewGuid(), AEmp = Guid.NewGuid();
    static readonly Guid BUser = Guid.NewGuid(), BEmp = Guid.NewGuid();
    static readonly Guid LoneUser = Guid.NewGuid(), LoneEmp = Guid.NewGuid();

    static readonly Guid LeaveA = Guid.NewGuid(), LeaveB = Guid.NewGuid(), LeaveHead = Guid.NewGuid(), LeaveBAssigned = Guid.NewGuid();
    static readonly Guid PenaltyA = Guid.NewGuid(), PenaltyB = Guid.NewGuid();
    static readonly Guid OvertimeB = Guid.NewGuid(), OvertimeBManagedByHead = Guid.NewGuid();

    static async Task<ZKTecoDbContext> SeedAsync()
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        db.Departments.AddRange(
            new Department { Id = DeptA, StoreId = Store, Name = "Bếp", Code = "A", ManagerId = HeadEmp, IsActive = true },
            new Department { Id = DeptB, StoreId = Store, Name = "Phục vụ", Code = "B", IsActive = true });
        Employee Emp(Guid id, Guid user, Guid? dept, string name) => new()
        {
            Id = id, StoreId = Store, ApplicationUserId = user, DepartmentId = dept, FirstName = name, LastName = "",
            EmployeeCode = name, WorkStatus = EmployeeWorkStatus.Active, IsActive = true,
        };
        db.Employees.AddRange(Emp(HeadEmp, HeadUser, DeptA, "Head"), Emp(AEmp, AUser, DeptA, "An"),
            Emp(BEmp, BUser, DeptB, "Binh"), Emp(LoneEmp, LoneUser, null, "Lone"));
        Leave L(Guid id, Guid user, Guid emp, Guid manager) => new()
        {
            Id = id, StoreId = Store, EmployeeUserId = user, EmployeeId = emp, ManagerId = manager, Reason = "x",
            StartDate = DateTime.UtcNow.Date, EndDate = DateTime.UtcNow.Date, Status = LeaveStatus.Pending, IsActive = true,
        };
        db.Leaves.AddRange(L(LeaveA, AUser, AEmp, Guid.NewGuid()), L(LeaveB, BUser, BEmp, Guid.NewGuid()),
            L(LeaveHead, HeadUser, HeadEmp, Guid.NewGuid()), L(LeaveBAssigned, BUser, BEmp, Guid.NewGuid()));
        // Đơn phòng B nhưng bước duyệt gán cho trưởng phòng A → vẫn được duyệt.
        db.LeaveApprovalRecords.Add(new LeaveApprovalRecord
        {
            Id = Guid.NewGuid(), LeaveId = LeaveBAssigned, StepOrder = 1, AssignedUserId = HeadUser, StoreId = Store,
        });
        PenaltyTicket P(Guid id, Guid emp) => new()
        {
            Id = id, StoreId = Store, EmployeeId = emp, TicketCode = "PP-" + id.ToString("N")[..6], Amount = 50000,
            ViolationDate = DateTime.UtcNow.Date, Status = PenaltyTicketStatus.Pending, IsActive = true,
        };
        db.PenaltyTickets.AddRange(P(PenaltyA, AEmp), P(PenaltyB, BEmp));
        Overtime O(Guid id, Guid user, Guid manager) => new()
        {
            Id = id, StoreId = Store, EmployeeUserId = user, ManagerId = manager, Date = DateTime.UtcNow.Date,
            StartTime = new TimeSpan(18, 0, 0), EndTime = new TimeSpan(20, 0, 0), Reason = "x", Status = OvertimeStatus.Pending, IsActive = true,
        };
        db.Overtimes.AddRange(O(OvertimeB, BUser, Guid.NewGuid()), O(OvertimeBManagedByHead, BUser, HeadUser));
        await db.SaveChangesAsync();
        return db;
    }

    static ApprovalScopeGuard Guard(ZKTecoDbContext db) => new(db, new DataScopeService(db), new HttpContextAccessor());

    [Fact]
    public async Task Truong_phong_chi_duyet_duoc_don_phong_minh()
    {
        await using var db = await SeedAsync();
        var g = Guard(db);
        Assert.Null(await g.DenyAsync(ApprovalScopeGuard.Kind.Leave, LeaveA, HeadUser, Store, "DepartmentHead"));
        Assert.Equal(ApprovalScopeGuard.OutOfScopeMessage,
            await g.DenyAsync(ApprovalScopeGuard.Kind.Leave, LeaveB, HeadUser, Store, "DepartmentHead"));
        Assert.Null(await g.DenyAsync(ApprovalScopeGuard.Kind.Penalty, PenaltyA, HeadUser, Store, "DepartmentHead"));
        Assert.Equal(ApprovalScopeGuard.OutOfScopeMessage,
            await g.DenyAsync(ApprovalScopeGuard.Kind.Penalty, PenaltyB, HeadUser, Store, "DepartmentHead"));
    }

    [Fact]
    public async Task Nguoi_duoc_giao_duyet_van_duyet_duoc_don_ngoai_phong()
    {
        await using var db = await SeedAsync();
        var g = Guard(db);
        Assert.Null(await g.DenyAsync(ApprovalScopeGuard.Kind.Leave, LeaveBAssigned, HeadUser, Store, "DepartmentHead"));
        Assert.Null(await g.DenyAsync(ApprovalScopeGuard.Kind.Overtime, OvertimeBManagedByHead, HeadUser, Store, "DepartmentHead"));
        Assert.Equal(ApprovalScopeGuard.OutOfScopeMessage,
            await g.DenyAsync(ApprovalScopeGuard.Kind.Overtime, OvertimeB, HeadUser, Store, "DepartmentHead"));
    }

    [Fact]
    public async Task Khong_tu_duyet_don_cua_minh_tru_tai_khoan_toan_quyen()
    {
        await using var db = await SeedAsync();
        Assert.Equal(ApprovalScopeGuard.OwnRequestMessage,
            await Guard(db).DenyAsync(ApprovalScopeGuard.Kind.Leave, LeaveHead, HeadUser, Store, "DepartmentHead"));
        Assert.Equal(ApprovalScopeGuard.OwnRequestMessage,
            await Guard(db).DenyAsync(ApprovalScopeGuard.Kind.Leave, LeaveHead, HeadUser, Store, "Director"));
        Assert.Null(await Guard(db).DenyAsync(ApprovalScopeGuard.Kind.Leave, LeaveHead, HeadUser, Store, "Admin"));
    }

    [Fact]
    public async Task Giam_doc_ke_toan_va_quan_ly_chua_phan_pham_vi_duyet_ca_cua_hang()
    {
        await using var db = await SeedAsync();
        Assert.Null(await Guard(db).DenyAsync(ApprovalScopeGuard.Kind.Leave, LeaveB, LoneUser, Store, "Director"));
        Assert.Null(await Guard(db).DenyAsync(ApprovalScopeGuard.Kind.Leave, LeaveB, LoneUser, Store, "Accountant"));
        // Quản lý chưa được giao cấp dưới / phòng ban / chi nhánh nào → như trước (cửa hàng nhỏ không bị khóa duyệt).
        Assert.Null(await Guard(db).DenyAsync(ApprovalScopeGuard.Kind.Leave, LeaveB, LoneUser, Store, "Manager"));
    }

    [Fact]
    public async Task Cham_cong_mobile_theo_pham_vi_va_khong_tu_duyet()
    {
        await using var db = await SeedAsync();
        // Mã NV mobile lưu dạng chuỗi: userId / Employee.Id / mã NV.
        Guid punchA = Guid.NewGuid(), punchB = Guid.NewGuid(), deviceHead = Guid.NewGuid(), changeB = Guid.NewGuid();
        db.MobileAttendanceRecords.AddRange(
            new MobileAttendanceRecord { Id = punchA, StoreId = Store, OdooEmployeeId = AUser.ToString(), PunchTime = DateTime.UtcNow },
            new MobileAttendanceRecord { Id = punchB, StoreId = Store, OdooEmployeeId = BEmp.ToString(), PunchTime = DateTime.UtcNow });
        db.AuthorizedMobileDevices.Add(new AuthorizedMobileDevice { Id = deviceHead, StoreId = Store, EmployeeId = "Head", DeviceId = "d1" });
        db.DeviceChangeRequests.Add(new DeviceChangeRequest { Id = changeB, StoreId = Store, EmployeeId = "Binh" });
        await db.SaveChangesAsync();
        var g = Guard(db);

        Assert.Null(await g.DenyAsync(ApprovalScopeGuard.Kind.MobilePunch, punchA, HeadUser, Store, "DepartmentHead"));
        Assert.Equal(ApprovalScopeGuard.OutOfScopeMessage,
            await g.DenyAsync(ApprovalScopeGuard.Kind.MobilePunch, punchB, HeadUser, Store, "DepartmentHead"));
        Assert.Equal(ApprovalScopeGuard.OutOfScopeMessage,
            await g.DenyAsync(ApprovalScopeGuard.Kind.MobileDeviceChange, changeB, HeadUser, Store, "DepartmentHead"));
        Assert.Equal(ApprovalScopeGuard.OwnRequestMessage,
            await g.DenyAsync(ApprovalScopeGuard.Kind.MobileDevice, deviceHead, HeadUser, Store, "DepartmentHead"));
        Assert.Equal(ApprovalScopeGuard.OwnRequestMessage,
            await g.DenyForMobileEmployeeAsync(HeadEmp.ToString(), HeadUser, Store, "DepartmentHead"));
        Assert.Null(await Guard(db).DenyAsync(ApprovalScopeGuard.Kind.MobileDevice, deviceHead, HeadUser, Store, "Admin"));
    }

    [Fact]
    public async Task Khong_tim_thay_don_de_api_bao_loi_nhu_cu()
    {
        await using var db = await SeedAsync();
        Assert.Null(await Guard(db).DenyAsync(ApprovalScopeGuard.Kind.Advance, Guid.NewGuid(), HeadUser, Store, "DepartmentHead"));
    }
}
