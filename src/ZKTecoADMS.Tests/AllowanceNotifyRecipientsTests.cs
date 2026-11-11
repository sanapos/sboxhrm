using System.Reflection;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Application.Commands.Allowances;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Entities.Base;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Repositories;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Phụ cấp lưu mã nhân viên (Employee.Id) — thông báo phải tới tài khoản của nhân viên đó; phụ cấp «tất cả
/// nhân viên» (không chọn ai) báo mọi nhân viên đang làm có tài khoản. Trước đây đọc nhầm là mã tài khoản → không ai nhận.
/// </summary>
public class AllowanceNotifyRecipientsTests
{
    sealed class NoTenant : ITenantProvider
    {
        public Guid? StoreId => null;
        public bool IsSuperAccess => true;
    }

    public class Capture : DispatchProxy
    {
        public static readonly List<(List<Guid> To, string Title)> Sent = [];

        protected override object? Invoke(MethodInfo? m, object?[]? args)
        {
            if (m?.Name == nameof(ISystemNotificationService.CreateAndSendToUsersAsync) && args != null)
                lock (Sent) Sent.Add((((IEnumerable<Guid>)args[0]!).ToList(), (string)args[2]!));
            return Task.CompletedTask;
        }
    }

    static EfRepository<T> Repo<T>(ZKTecoDbContext db) where T : Entity<Guid> =>
        new(db, NullLogger<EfRepository<T>>.Instance, new NoTenant());

    [Fact]
    public async Task Bao_dung_tai_khoan_nhan_vien_va_tat_ca_nhan_vien()
    {
        // Cấu hình Mapster (EmployeeIds JSON → List) như lúc app khởi động.
        Mapster.TypeAdapterConfig.GlobalSettings.Scan(typeof(CreateAllowanceHandler).Assembly);
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString()).Options);
        var store = Guid.NewGuid();
        Employee E(string code, Guid? user, EmployeeWorkStatus st = EmployeeWorkStatus.Active) => new()
        {
            Id = Guid.NewGuid(), StoreId = store, EmployeeCode = code, FirstName = code, LastName = "NV",
            ApplicationUserId = user, WorkStatus = st,
        };
        var u1 = Guid.NewGuid();
        var u2 = Guid.NewGuid();
        var nv1 = E("NV1", u1);
        var nv2 = E("NV2", u2);
        var noAccount = E("NV3", null);
        var resigned = E("NV4", Guid.NewGuid(), EmployeeWorkStatus.Resigned);
        db.Employees.AddRange(nv1, nv2, noAccount, resigned);
        await db.SaveChangesAsync();

        var notify = DispatchProxy.Create<ISystemNotificationService, Capture>();
        var handler = new CreateAllowanceHandler(Repo<Allowance>(db), Repo<Employee>(db), notify);
        CreateAllowanceCommand Cmd(string name, List<string>? emps) => new(
            store, name, null, null, AllowanceType.Fixed, 500_000, "VND", false, false, null, null, emps, null);

        lock (Capture.Sent) Capture.Sent.Clear();
        var r1 = await handler.Handle(Cmd("Xăng xe", [nv1.Id.ToString()]), default);
        Assert.True(r1.IsSuccess, r1.Message);
        var r2 = await handler.Handle(Cmd("Ăn trưa", null), default);
        Assert.True(r2.IsSuccess, r2.Message);

        List<(List<Guid> To, string Title)> sent;
        lock (Capture.Sent) sent = [.. Capture.Sent];
        var xang = Assert.Single(sent, s => s.Title.Contains("Xăng xe"));
        Assert.Equal([u1], xang.To);
        var an = Assert.Single(sent, s => s.Title.Contains("Ăn trưa"));
        Assert.Equal(new HashSet<Guid> { u1, u2 }, an.To.ToHashSet());
    }
}
