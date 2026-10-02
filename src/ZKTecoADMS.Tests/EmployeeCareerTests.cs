using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Tests;

/// <summary>Quá trình công tác: dòng thời gian gộp, khen thưởng không cần tài khoản, điều chuyển cập nhật hồ sơ.</summary>
public class EmployeeCareerTests
{
    readonly Guid _store = Guid.NewGuid();
    readonly ZKTecoDbContext _db;
    readonly IServiceProvider _sp;
    static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public EmployeeCareerTests()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        _sp = services.BuildServiceProvider();
        _db = _sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
    }

    EmployeeCareerController Ctl(string role = "Manager", Guid? userId = null) => new(_db)
    {
        ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                RequestServices = _sp,
                User = new ClaimsPrincipal(new ClaimsIdentity([
                    new Claim("id", (userId ?? Guid.NewGuid()).ToString()),
                    new Claim(ClaimTypeNames.StoreId, _store.ToString()),
                    new Claim(ClaimTypes.Role, role),
                    new Claim(ClaimTypes.Email, "ql@test.vn"),
                ], "test")),
            },
        },
    };

    static JsonElement Ok(object? result, bool success = true)
    {
        var ok = Assert.IsType<OkObjectResult>(result);
        var root = JsonDocument.Parse(JsonSerializer.Serialize(ok.Value, Json)).RootElement;
        Assert.True(success == root.GetProperty("isSuccess").GetBoolean(), root.ToString());
        return root;
    }

    (Employee emp, Department sales, Department wh) Seed(Guid? userId = null)
    {
        var sales = new Department { Id = Guid.NewGuid(), StoreId = _store, Code = "KD", Name = "Kinh doanh", IsActive = true };
        var wh = new Department { Id = Guid.NewGuid(), StoreId = _store, Code = "KHO", Name = "Kho", IsActive = true };
        var emp = new Employee
        {
            Id = Guid.NewGuid(), StoreId = _store, EmployeeCode = "NV01", FirstName = "An", LastName = "Nguyễn",
            DepartmentId = sales.Id, Department = "Kinh doanh", Position = "Nhân viên", JoinDate = new DateTime(2023, 3, 1),
            ApplicationUserId = userId,
        };
        _db.AddRange(sales, wh, emp);
        _db.SaveChanges();
        return (emp, sales, wh);
    }

    [Fact]
    public async Task Award_is_saved_without_login_account_and_shows_in_timeline()
    {
        var (emp, _, _) = Seed();   // nhân viên chưa có tài khoản
        Ok((await Ctl().AddRecord(emp.Id, new()
        {
            Kind = "award", Title = "Hoàn thành xuất sắc quý 3", Form = "Giấy khen", Amount = 2_000_000,
            EffectiveDate = new DateTime(2026, 9, 30), DecisionNumber = "QĐ-15/2026",
        })).Result);
        _db.Add(new PaymentTransaction { Id = Guid.NewGuid(), EmployeeId = emp.Id, Type = "Penalty", Amount = 100_000, Description = "Đi trễ", TransactionDate = new DateTime(2026, 8, 5) });
        await _db.SaveChangesAsync();

        var data = Ok((await Ctl().Get(emp.Id)).Result).GetProperty("data");
        var kinds = data.GetProperty("events").EnumerateArray().Select(e => e.GetProperty("kind").GetString()).ToList();
        Assert.Equal(new[] { "award", "penalty", "join" }, kinds);
        var s = data.GetProperty("summary");
        Assert.Equal(1, s.GetProperty("awards").GetInt32());
        Assert.Equal(2_000_000, s.GetProperty("bonusTotal").GetDecimal());
        Assert.Equal(100_000, s.GetProperty("penaltyTotal").GetDecimal());
    }

    [Fact]
    public async Task Transfer_ends_old_assignment_creates_position_and_updates_profile()
    {
        var (emp, _, wh) = Seed();
        var data = Ok((await Ctl().Move(emp.Id, new()
        {
            Kind = "transfer", DepartmentId = wh.Id, Position = "Thủ kho", EffectiveDate = DateTime.UtcNow.Date.AddDays(-1),
            DecisionNumber = "QĐ-20",
        })).Result).GetProperty("data");
        Assert.True(data.GetProperty("appliedNow").GetBoolean());

        var after = await _db.Employees.FirstAsync(e => e.Id == emp.Id);
        Assert.Equal(wh.Id, after.DepartmentId);
        Assert.Equal("Kho", after.Department);
        Assert.Equal("Thủ kho", after.Position);
        Assert.True(await _db.OrgPositions.AnyAsync(p => p.Name == "Thủ kho"));
        var rec = await _db.EmployeeCareerRecords.SingleAsync();
        Assert.Equal("Kinh doanh", rec.FromDepartment);
        Assert.Equal("Nhân viên", rec.FromPosition);
        Assert.Equal("Thủ kho", rec.ToPosition);

        // Không đổi gì → báo lỗi
        Ok((await Ctl().Move(emp.Id, new() { DepartmentId = wh.Id, Position = "thủ kho" })).Result, success: false);

        // Điều chuyển có hiệu lực tương lai: chưa đổi hồ sơ
        var later = Ok((await Ctl().Move(emp.Id, new() { Kind = "promotion", Position = "Trưởng kho", EffectiveDate = DateTime.UtcNow.Date.AddDays(10) })).Result);
        Assert.False(later.GetProperty("data").GetProperty("appliedNow").GetBoolean());
        Assert.Equal("Thủ kho", (await _db.Employees.FirstAsync(e => e.Id == emp.Id)).Position);
        var asg = await _db.OrgAssignments.Where(a => a.EmployeeId == emp.Id).ToListAsync();
        Assert.Single(asg, a => a.IsPrimary && a.EndDate == null);

        // Tới ngày hiệu lực: tự cập nhật hồ sơ, chạy lại không đổi thêm
        Assert.Equal(0, await CareerMoveApplier.ApplyDueAsync(_db, DateTime.UtcNow.Date.AddDays(5)));
        Assert.Equal(1, await CareerMoveApplier.ApplyDueAsync(_db, DateTime.UtcNow.Date.AddDays(10)));
        Assert.Equal("Trưởng kho", (await _db.Employees.FirstAsync(e => e.Id == emp.Id)).Position);
        Assert.Equal(0, await CareerMoveApplier.ApplyDueAsync(_db, DateTime.UtcNow.Date.AddDays(10)));
    }

    [Fact]
    public async Task Employee_sees_only_own_career()
    {
        var me = Guid.NewGuid();
        var (emp, _, _) = Seed(me);
        Ok((await Ctl("Employee", me).Get(emp.Id)).Result);
        Ok((await Ctl("Employee", Guid.NewGuid()).Get(emp.Id)).Result, success: false);
    }

    [Fact]
    public async Task Legacy_award_documents_are_included()
    {
        var user = Guid.NewGuid();
        var (emp, _, _) = Seed(user);
        _db.Add(new HrDocument { Id = Guid.NewGuid(), StoreId = _store, EmployeeUserId = user, Name = "Bằng khen 2024", DocumentType = HrDocumentType.Award, FilePath = "manual_entry", FileName = "entry.txt", EffectiveDate = new DateTime(2024, 12, 1) });
        _db.Add(new HrDocument { Id = Guid.NewGuid(), StoreId = _store, EmployeeUserId = user, Name = "CCCD", DocumentType = HrDocumentType.IdCard, FilePath = "/uploads/x.jpg", FileName = "x.jpg" });
        await _db.SaveChangesAsync();
        var events = Ok((await Ctl().Get(emp.Id)).Result).GetProperty("data").GetProperty("events").EnumerateArray().ToList();
        Assert.Contains(events, e => e.GetProperty("title").GetString() == "Bằng khen 2024" && e.GetProperty("source").GetString() == "document");
        Assert.DoesNotContain(events, e => e.GetProperty("title").GetString() == "CCCD");
    }
}
