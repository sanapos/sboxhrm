using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Tests;

/// <summary>Ca mẫu v2: chỉ xóa ca chưa phát sinh dữ liệu, xóa thì gỡ ca khỏi thiết lập lương.</summary>
public class ShiftTemplateUsageTests
{
    static ZKTecoDbContext NewDb()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o.UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        return services.BuildServiceProvider().CreateScope().ServiceProvider.GetRequiredService<ZKTecoDbContext>();
    }

    static ShiftTemplate Tpl(Guid store, string name) => new()
    {
        Id = Guid.NewGuid(), StoreId = store, ManagerId = Guid.NewGuid(), Name = name,
        StartTime = new TimeSpan(8, 0, 0), EndTime = new TimeSpan(17, 0, 0), IsActive = true,
    };

    [Fact]
    public void Remove_shift_id_from_allowance_json()
    {
        var a = Guid.NewGuid();
        var b = Guid.NewGuid();
        var (changed, json) = ShiftTemplateUsageHelper.RemoveShiftId($"[\"{a}\",\"{b}\"]", a);
        Assert.True(changed);
        Assert.Equal(new[] { b.ToString() }, ShiftTemplateUsageHelper.ParseShiftIds(json));
        Assert.Equal((true, (string?)null), ShiftTemplateUsageHelper.RemoveShiftId($"[\"{a}\"]", a));
        Assert.False(ShiftTemplateUsageHelper.RemoveShiftId($"[\"{b}\"]", a).changed);
        Assert.False(ShiftTemplateUsageHelper.RemoveShiftId("hỏng", a).changed);
    }

    [Fact]
    public void Copy_name_is_unique()
    {
        Assert.Equal("Ca sáng (bản sao)", ShiftTemplateUsageHelper.CopyName("Ca sáng", ["Ca sáng"]));
        Assert.Equal("Ca sáng (bản sao 2)", ShiftTemplateUsageHelper.CopyName("Ca sáng", ["Ca sáng", "ca sáng (bản sao)"]));
    }

    [Fact]
    public async Task Unused_shift_is_deleted_and_removed_from_salary_settings()
    {
        var db = NewDb();
        var store = Guid.NewGuid();
        var shift = Tpl(store, "Ca tối");
        var other = Tpl(store, "Ca sáng");
        db.AddRange(shift, other);
        db.Add(new ShiftSalaryLevel { Id = Guid.NewGuid(), StoreId = store, ShiftTemplateId = shift.Id, LevelName = "Mức 1", FixedRate = 200000 });
        db.Add(new ShiftSalaryLevel { Id = Guid.NewGuid(), StoreId = store, ShiftTemplateId = other.Id, LevelName = "Mức A", FixedRate = 150000 });
        var allowance = new Allowance { Id = Guid.NewGuid(), StoreId = store, Name = "Phụ cấp ca", ShiftIds = $"[\"{shift.Id}\",\"{other.Id}\"]" };
        db.Add(allowance);
        await db.SaveChangesAsync();

        var usage = (await ShiftTemplateUsageHelper.ComputeAsync(db, store))[shift.Id];
        Assert.False(usage.HasData);
        Assert.Equal(1, usage.SalaryLevels);
        Assert.Equal(1, usage.Allowances);

        var (ok, error, _) = await ShiftTemplateUsageHelper.DeleteAsync(db, store, shift.Id);
        Assert.True(ok, error);
        Assert.False(await db.ShiftTemplates.AnyAsync(t => t.Id == shift.Id));
        Assert.False(await db.ShiftSalaryLevels.AnyAsync(l => l.ShiftTemplateId == shift.Id));
        Assert.True(await db.ShiftSalaryLevels.AnyAsync(l => l.ShiftTemplateId == other.Id));
        var a = await db.Allowances.FirstAsync(x => x.Id == allowance.Id);
        Assert.Equal(new[] { other.Id.ToString() }, ShiftTemplateUsageHelper.ParseShiftIds(a.ShiftIds));
    }

    [Fact]
    public async Task Shift_with_data_cannot_be_deleted()
    {
        var db = NewDb();
        var store = Guid.NewGuid();
        var shift = Tpl(store, "Ca hành chính");
        db.Add(shift);
        db.Add(new WorkSchedule { Id = Guid.NewGuid(), StoreId = store, EmployeeUserId = Guid.NewGuid(), Date = DateTime.UtcNow.Date.AddDays(-3), ShiftId = shift.Id });
        db.Add(new WorkSchedule { Id = Guid.NewGuid(), StoreId = store, EmployeeUserId = Guid.NewGuid(), Date = DateTime.UtcNow.Date.AddDays(5), ShiftId = shift.Id });
        db.Add(new ShiftSalaryLevel { Id = Guid.NewGuid(), StoreId = store, ShiftTemplateId = shift.Id, LevelName = "Mức 1" });
        await db.SaveChangesAsync();

        var usage = (await ShiftTemplateUsageHelper.ComputeAsync(db, store))[shift.Id];
        Assert.True(usage.HasData);
        Assert.Equal(2, usage.Schedules);
        Assert.Equal(1, usage.UpcomingSchedules);
        Assert.Equal(2, usage.Employees);

        var (ok, error, _) = await ShiftTemplateUsageHelper.DeleteAsync(db, store, shift.Id);
        Assert.False(ok);
        Assert.Contains("Ngừng dùng", error);
        Assert.True(await db.ShiftTemplates.AnyAsync(t => t.Id == shift.Id));
        Assert.True(await db.ShiftSalaryLevels.AnyAsync(l => l.ShiftTemplateId == shift.Id)); // lương ca giữ nguyên
        Assert.Equal(2, await db.WorkSchedules.CountAsync(s => s.ShiftId == shift.Id));
    }

    [Fact]
    public async Task Cannot_delete_shift_of_another_store()
    {
        var db = NewDb();
        var shift = Tpl(Guid.NewGuid(), "Ca khác");
        db.Add(shift);
        await db.SaveChangesAsync();
        var (ok, _, _) = await ShiftTemplateUsageHelper.DeleteAsync(db, Guid.NewGuid(), shift.Id);
        Assert.False(ok);
        Assert.True(await db.ShiftTemplates.AnyAsync(t => t.Id == shift.Id));
    }
}
