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

/// <summary>Phòng ban v2: đếm nhân viên (kể cả chỉ có tên chữ), chuyển nhân viên, sắp xếp chống vòng lặp, xóa kèm chuyển.</summary>
public class DepartmentsV2Tests
{
    readonly Guid _store = Guid.NewGuid();
    readonly ZKTecoDbContext _db;
    readonly IServiceProvider _sp;
    static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public DepartmentsV2Tests()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        _sp = services.BuildServiceProvider();
        _db = _sp.CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
    }

    DepartmentsV2Controller Ctl() => new(_db)
    {
        ControllerContext = new ControllerContext
        {
            HttpContext = new DefaultHttpContext
            {
                RequestServices = _sp,
                User = new ClaimsPrincipal(new ClaimsIdentity([
                    new Claim("id", Guid.NewGuid().ToString()),
                    new Claim(ClaimTypeNames.StoreId, _store.ToString()),
                ], "test")),
            },
        },
    };

    static JsonElement Ok(object? result, bool success = true)
    {
        var ok = Assert.IsType<OkObjectResult>(result);
        var root = JsonDocument.Parse(JsonSerializer.Serialize(ok.Value, Json)).RootElement;
        Assert.Equal(success, root.GetProperty("isSuccess").GetBoolean());
        return root;
    }

    Department Dept(string name, Guid? parent = null, int order = 0) => new()
    {
        Id = Guid.NewGuid(), StoreId = _store, Code = name.ToUpperInvariant()[..2] + order, Name = name, ParentDepartmentId = parent,
        SortOrder = order, IsActive = true,
    };

    Employee Emp(string first, Guid? deptId = null, string? deptText = null, EmployeeWorkStatus status = EmployeeWorkStatus.Active) => new()
    {
        Id = Guid.NewGuid(), StoreId = _store, EmployeeCode = "NV" + first, FirstName = first, LastName = "Lê",
        DepartmentId = deptId, Department = deptText, WorkStatus = status,
    };

    [Fact]
    public async Task Overview_counts_employees_including_text_only_and_children()
    {
        var kd = Dept("Kinh doanh");
        var kd1 = Dept("Bán lẻ", kd.Id, 1);
        var kho = Dept("Kho");
        _db.AddRange(kd, kd1, kho);
        _db.AddRange(
            Emp("A", kd.Id, "Kinh doanh"),
            Emp("B", kd1.Id, "Bán lẻ"),
            Emp("C", null, "Kho"),              // chỉ có tên chữ
            Emp("D"),                            // chưa có phòng ban
            Emp("E", kd.Id, "Kinh doanh", EmployeeWorkStatus.Resigned));
        await _db.SaveChangesAsync();

        var data = Ok((await Ctl().Overview()).Result).GetProperty("data");
        Assert.Equal(4, data.GetProperty("totalEmployees").GetInt32());
        Assert.Equal(1, data.GetProperty("unassigned").GetInt32());
        var items = data.GetProperty("items").EnumerateArray().ToDictionary(i => i.GetProperty("name").GetString()!);
        Assert.Equal(1, items["Kinh doanh"].GetProperty("directCount").GetInt32());
        Assert.Equal(2, items["Kinh doanh"].GetProperty("totalCount").GetInt32());
        Assert.Equal(1, items["Kho"].GetProperty("directCount").GetInt32());

        var members = Ok((await Ctl().Members(kd.Id.ToString(), includeChildren: true)).Result).GetProperty("data");
        Assert.Equal(2, members.GetArrayLength());
        var none = Ok((await Ctl().Members("none")).Result).GetProperty("data");
        Assert.Equal("Lê D", none[0].GetProperty("name").GetString());
    }

    [Fact]
    public async Task Move_employees_updates_id_and_text()
    {
        var kho = Dept("Kho");
        var e = Emp("A", null, "Phòng cũ");
        _db.AddRange(kho, e);
        await _db.SaveChangesAsync();
        Ok((await Ctl().MoveEmployees(new() { EmployeeIds = [e.Id], TargetDepartmentId = kho.Id })).Result);
        var after = await _db.Employees.FirstAsync(x => x.Id == e.Id);
        Assert.Equal(kho.Id, after.DepartmentId);
        Assert.Equal("Kho", after.Department);
    }

    [Fact]
    public async Task Reorder_rejects_cycle_and_recomputes_hierarchy()
    {
        var a = Dept("Khối A");
        var b = Dept("Phòng B", a.Id);
        var c = Dept("Tổ C", b.Id);
        _db.AddRange(a, b, c);
        await _db.SaveChangesAsync();

        // A vào trong C (cháu của A) → vòng lặp
        var bad = Ok((await Ctl().Reorder(new() { Items = [new() { Id = a.Id, ParentId = c.Id }] })).Result, success: false);
        Assert.Contains("phòng con", bad.ToString());

        // Đưa C lên làm phòng gốc, thứ tự 5
        Ok((await Ctl().Reorder(new() { Items = [new() { Id = c.Id, ParentId = null, SortOrder = 5 }] })).Result);
        var all = await _db.Departments.ToDictionaryAsync(d => d.Id);
        Assert.Null(all[c.Id].ParentDepartmentId);
        Assert.Equal(0, all[c.Id].Level);
        Assert.Equal(5, all[c.Id].SortOrder);
        Assert.Equal(1, all[b.Id].Level);
        Assert.Equal($"/{a.Id}/", all[b.Id].HierarchyPath);
    }

    [Fact]
    public async Task Delete_requires_target_when_employees_remain_then_moves_them()
    {
        var old = Dept("Phòng cũ");
        var target = Dept("Phòng mới");
        var e1 = Emp("A", old.Id, "Phòng cũ");
        var e2 = Emp("B", null, "Phòng cũ");
        _db.AddRange(old, target, e1, e2);
        await _db.SaveChangesAsync();

        var refused = Ok((await Ctl().Delete(old.Id, new())).Result, success: false);
        Assert.Contains("2 nhân viên", refused.ToString());

        var done = Ok((await Ctl().Delete(old.Id, new() { TargetDepartmentId = target.Id })).Result).GetProperty("data");
        Assert.Equal(2, done.GetProperty("moved").GetInt32());
        Assert.False(await _db.Departments.AnyAsync(d => d.Id == old.Id));
        Assert.All(await _db.Employees.ToListAsync(), e => Assert.Equal(target.Id, e.DepartmentId));
    }

    [Fact]
    public void Cycle_detection()
    {
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        var parents = new Dictionary<Guid, Guid?> { [a] = null, [b] = a };
        Assert.True(DepartmentOrgHelper.CreatesCycle(parents, a, b));
        Assert.True(DepartmentOrgHelper.CreatesCycle(parents, a, a));
        Assert.False(DepartmentOrgHelper.CreatesCycle(parents, b, null));
    }
}
