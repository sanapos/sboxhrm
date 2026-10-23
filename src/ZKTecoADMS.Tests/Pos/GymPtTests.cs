using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>
/// Tài khoản PT (quyền «PT · Khách của tôi», không có Check-in gym): chỉ thấy / thao tác hội viên mình phụ trách;
/// lịch tập lặp hàng tuần bỏ qua buổi trùng giờ của PT.
/// </summary>
[Collection("pos-pg")]
public class GymPtTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    /// <summary>PT: có PosGymTrainer, không có PosGymCheckIn. Lễ tân: có cả hai.</summary>
    sealed class Perms(bool desk) : IModulePermissionService
    {
        public Task<IReadOnlyDictionary<string, ModulePermissionDto>> GetEffectivePermissionsAsync(
            Guid userId, string role, Guid? storeId, CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyDictionary<string, ModulePermissionDto>>(new Dictionary<string, ModulePermissionDto>());

        public Task<bool> HasPermissionAsync(Guid userId, string role, Guid? storeId, string module,
            ModulePermissionAction action, CancellationToken cancellationToken = default) =>
            Task.FromResult(module == "PosGymTrainer" || desk);
    }

    static PosGymController Ctl(ZKTecoDbContext db, Guid store, Guid? employeeId, bool desk)
    {
        var ctl = PosPgFixture.As(new PosGymController(db, null!,
            new GymCheckInService(db, Microsoft.Extensions.Logging.Abstractions.NullLogger<GymCheckInService>.Instance,
                new ServiceCollection().BuildServiceProvider())), store, desk ? "Manager" : "Employee");
        var sc = new ServiceCollection();
        sc.AddSingleton<IModulePermissionService>(new Perms(desk));
        ctl.HttpContext.RequestServices = sc.BuildServiceProvider();
        if (employeeId is Guid e)
            ((ClaimsIdentity)ctl.HttpContext.User.Identity!).AddClaim(new Claim(ClaimTypeNames.EmployeeId, e.ToString()));
        return ctl;
    }

    static T Data<T>(ActionResult<AppResponse<T>> r) =>
        ((AppResponse<T>)((ObjectResult)r.Result!).Value!).Data!;

    static int Status<T>(ActionResult<AppResponse<T>> r) => ((ObjectResult)r.Result!).StatusCode ?? 200;

    async Task<(Guid Store, Guid PtA, Guid PtB, Guid ClientA, Guid ClientB)> SeedAsync()
    {
        var store = await Fx.NewStoreAsync();
        var ptA = Guid.NewGuid();
        var ptB = Guid.NewGuid();
        await using var db = Fx.NewDb();
        PosCustomer C(string name, Guid pt, string ptName) => new()
        {
            Id = Guid.NewGuid(), StoreId = store, CustomerCode = "HV" + Random.Shared.Next(100000, 999999),
            Name = name, IsActive = true, GymTrainerEmployeeId = pt, GymTrainerName = ptName,
        };
        var a = C("Khách của A", ptA, "PT A");
        var b = C("Khách của B", ptB, "PT B");
        db.PosCustomers.AddRange(a, b);
        await db.SaveChangesAsync();
        return (store, ptA, ptB, a.Id, b.Id);
    }

    [Fact]
    public async Task PT_chi_thay_va_thao_tac_hoi_vien_minh_phu_trach()
    {
        if (NoDb) return;
        var (store, ptA, _, clientA, clientB) = await SeedAsync();
        await using var db = Fx.NewDb();
        var pt = Ctl(db, store, ptA, desk: false);

        var me = await pt.PtMe();
        Assert.False((bool)Data(me).GetType().GetProperty("manageAll")!.GetValue(Data(me))!);

        // Danh sách: chỉ khách của PT A (dù xin xem PT khác).
        var clients = Data(await pt.PtClients(trainerId: Guid.NewGuid()));
        var names = ((System.Collections.IEnumerable)clients).Cast<object>()
            .Select(x => (string)x.GetType().GetProperty("name")!.GetValue(x)!).ToList();
        Assert.Equal(["Khách của A"], names);

        // Đọc / ghi phiếu đánh giá: được với khách mình, bị chặn với khách PT khác.
        Assert.Equal(200, Status(await pt.Assessments(clientA)));
        Assert.Equal(403, Status(await pt.Assessments(clientB)));
        Assert.Equal(200, Status(await pt.AddAssessment(clientA,
            new(null, null, 70m, 170m, null, null, null, "Bình thường", "Giảm mỡ"))));
        Assert.Equal(403, Status(await pt.AddAssessment(clientB,
            new(null, null, 70m, 170m, null, null, null, null, null))));
        Assert.Equal(403, Status(await pt.AddPlan(clientB, new("Tuần 1", "Thứ 2: Ngực", null))));
        Assert.Equal(403, Status(await pt.CustomerBalances(clientB)));
        Assert.Equal(403, Status(await pt.Visits(customerId: clientB)));
        Assert.Equal(403, Status(await pt.Visits()));          // cả quầy: chỉ lễ tân
        Assert.Equal(403, Status(await pt.AddPtSession(new(clientB, DateTime.UtcNow.AddDays(1)))));

        // Lễ tân / quản lý thấy cả 2 PT.
        var desk = Ctl(db, store, null, desk: true);
        var all = Data(await desk.PtClients());
        Assert.Equal(2, ((System.Collections.IEnumerable)all).Cast<object>().Count());
        Assert.Equal(200, Status(await desk.Assessments(clientB)));
    }

    [Fact]
    public async Task Tai_khoan_chua_gan_ho_so_nhan_vien_bao_loi_ro()
    {
        if (NoDb) return;
        var (store, _, _, clientA, _) = await SeedAsync();
        await using var db = Fx.NewDb();
        var pt = Ctl(db, store, null, desk: false);
        Assert.Equal(403, Status(await pt.PtClients()));
        Assert.Equal(403, Status(await pt.Assessments(clientA)));
    }

    [Fact]
    public async Task Dat_lich_lap_hang_tuan_bo_qua_buoi_trung_gio_va_PT_khong_sua_lich_nguoi_khac()
    {
        if (NoDb) return;
        var (store, ptA, ptB, clientA, clientB) = await SeedAsync();
        var start = DateTime.UtcNow.Date.AddDays(2).AddHours(11); // 18:00 VN
        await using (var db = Fx.NewDb())
        {
            var pt = Ctl(db, store, ptA, desk: false);
            // Buổi lẻ tuần thứ 2 có sẵn → đặt lặp 4 tuần thì bỏ qua đúng buổi đó.
            Assert.Equal(200, Status(await pt.AddPtSession(new(clientA, start.AddDays(7).AddMinutes(30), 60))));
            var r = Data(await pt.AddPtSession(new(clientA, start, 60, "Ngực – vai", RepeatWeeks: 3)));
            Assert.Equal(3, (int)r.GetType().GetProperty("created")!.GetValue(r)!);
            Assert.Single((List<string>)r.GetType().GetProperty("skipped")!.GetValue(r)!);
            // Trùng giờ hoàn toàn → 409.
            Assert.Equal(409, Status(await pt.AddPtSession(new(clientA, start, 60))));

            var week = Data(await pt.PtSessions(start.AddHours(7).Date, start.AddHours(7).Date.AddDays(30)));
            Assert.Equal(4, week.Count);
            Assert.All(week, s => Assert.Equal(ptA, s.TrainerEmployeeId));
        }
        await using (var db = Fx.NewDb())
        {
            // PT B (lịch của B) — PT A không sửa / xóa được.
            var deskCtl = Ctl(db, store, null, desk: true);
            var b = Data(await deskCtl.AddPtSession(new(clientB, start, 60)));
            var bId = await db.PosGymPtSessions.Where(s => s.CustomerId == clientB).Select(s => s.Id).SingleAsync();
            var ptA2 = Ctl(db, store, ptA, desk: false);
            Assert.Equal(403, Status(await ptA2.UpdatePtSession(bId, new(Status: 1))));
            Assert.Equal(403, Status(await ptA2.DeletePtSession(bId)));
            var ptB2 = Ctl(db, store, ptB, desk: false);
            Assert.Equal(200, Status(await ptB2.UpdatePtSession(bId, new(Status: 1))));
            Assert.Equal(1, (await db.PosGymPtSessions.AsNoTracking().SingleAsync(s => s.Id == bId)).Status);
            Assert.NotNull(b);
        }
    }
}
