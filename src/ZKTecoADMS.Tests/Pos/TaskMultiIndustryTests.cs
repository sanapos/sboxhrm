using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Công việc đa ngành: biểu mẫu riêng, gói ngành ưu tiên, việc theo ca.</summary>
[Collection("pos-pg")]
public class TaskMultiIndustryTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    [Fact]
    public void Bieu_mau_kiem_tra_kieu_va_truong_bat_buoc()
    {
        var schema = TaskFormHelper.NormalizeSchema("""
            [{"label":"Nhiệt độ tủ mát","type":"number","required":true,"unit":"°C"},
             {"label":"Khu vực","type":"select","options":["Bếp","Sảnh"]},
             {"label":"Khu vực","type":"text"},
             {"label":"Chữ ký khách","type":"signature","required":true},
             {"label":"","type":"text"},
             {"label":"Lạ","type":"weird"}]
            """);
        var fields = TaskFormHelper.ParseSchema(schema);
        Assert.Equal(["nhiet_do_tu_mat", "khu_vuc", "khu_vuc_2", "chu_ky_khach", "la"], fields.Select(f => f.Key).ToArray());
        Assert.Equal("text", fields[^1].Type);

        var (bad, err) = TaskFormHelper.Merge(schema, null, new Dictionary<string, string?> { ["nhiet_do_tu_mat"] = "lạnh" });
        Assert.Null(bad);
        Assert.Contains("phải là số", err);
        var (_, err2) = TaskFormHelper.Merge(schema, null, new Dictionary<string, string?> { ["khu_vuc"] = "Kho" });
        Assert.Contains("không hợp lệ", err2);

        var (json, ok) = TaskFormHelper.Merge(schema, null, new Dictionary<string, string?>
        {
            ["nhiet_do_tu_mat"] = "3.5", ["khu_vuc"] = "Bếp", ["khong_co"] = "x",
        });
        Assert.Null(ok);
        Assert.Equal(["Chữ ký khách"], TaskFormHelper.MissingRequired(schema, json));
        var (json2, _) = TaskFormHelper.Merge(schema, json, new Dictionary<string, string?> { ["chu_ky_khach"] = "/uploads/sig.png" });
        Assert.Empty(TaskFormHelper.MissingRequired(schema, json2));
        Assert.DoesNotContain("khong_co", json2);
    }

    [Fact]
    public void Goi_nganh_uu_tien_day_du_va_bieu_mau_hop_le()
    {
        var featured = TaskIndustryPacks.All.Where(p => p.Featured).Select(p => p.Key).ToArray();
        Assert.Equal(["fnb", "construction", "retail", "service", "sales"], featured);
        Assert.Equal(TaskIndustryPacks.All.Length, TaskIndustryPacks.All.Select(p => p.Key).Distinct().Count());
        Assert.Equal("construction", TaskIndustryPacks.Find("interior")!.Key);
        foreach (var p in TaskIndustryPacks.All)
        {
            var stageKeys = p.Stages.Select(s => s.Key).ToHashSet();
            foreach (var t in p.Templates)
            {
                Assert.True(t.StageKey == null || stageKeys.Contains(t.StageKey), $"{p.Key}/{t.Name}: giai đoạn {t.StageKey}");
                if (t.Form == null) continue;
                var fields = TaskFormHelper.ParseSchema(TaskIndustryPacks.FormJson(t));
                Assert.Equal(t.Form.Length, fields.Count);
                Assert.All(fields, f => Assert.True(f.Type != "select" || f.Options?.Count > 0, $"{p.Key}/{t.Name}/{f.Label}"));
            }
        }
        // Mỗi gói ưu tiên có biểu mẫu; xây dựng / dịch vụ có chữ ký khách và check-in.
        foreach (var key in featured)
            Assert.Contains(TaskIndustryPacks.Find(key)!.Templates, t => t.Form is { Length: > 0 });
        Assert.Contains(TaskIndustryPacks.Find("construction")!.Templates, t => t.RequireCheckIn && t.Form!.Any(f => f.Type == "signature"));
        Assert.Contains(TaskIndustryPacks.Find("service")!.Templates, t => t.RequireCheckIn && t.Form!.Any(f => f.Type == "signature"));
        Assert.Contains(TaskIndustryPacks.Find("fnb")!.Templates, t => t.AssignOnShift && t.Recurrence == TaskRecurrenceType.Daily);
    }

    [Fact]
    public async Task Viec_theo_ca_giao_chung_cho_nguoi_co_ca()
    {
        if (NoDb) return;
        var store = await Fx.NewStoreAsync();
        await using var db = Fx.NewDb();
        var manager = await db.Users.Where(u => u.StoreId == store).Select(u => u.Id).FirstAsync();
        Employee E(string name) => new() { Id = Guid.NewGuid(), StoreId = store, ManagerId = manager, EmployeeCode = name, CompanyEmail = name + "@t.vn", FirstName = name, LastName = "NV" };
        var morning1 = E("Sang1");
        var morning2 = E("Sang2");
        var evening = E("Toi");
        db.Employees.AddRange(morning1, morning2, evening);
        var day = new DateTime(2026, 10, 9);
        db.WorkSchedules.AddRange(
            new WorkSchedule { Id = Guid.NewGuid(), EmployeeUserId = morning1.Id, Date = day, StartTime = new TimeSpan(6, 0, 0), EndTime = new TimeSpan(14, 0, 0), StoreId = store, IsActive = true },
            new WorkSchedule { Id = Guid.NewGuid(), EmployeeUserId = morning2.Id, Date = day, StartTime = new TimeSpan(6, 30, 0), EndTime = new TimeSpan(14, 30, 0), StoreId = store, IsActive = true },
            new WorkSchedule { Id = Guid.NewGuid(), EmployeeUserId = evening.Id, Date = day, StartTime = new TimeSpan(14, 0, 0), EndTime = new TimeSpan(22, 0, 0), StoreId = store, IsActive = true });
        var pack = TaskIndustryPacks.Find("fnb")!;
        var open = pack.Templates.First(t => t.Name == "Checklist mở ca");
        var tpl = new TaskTemplate
        {
            Id = Guid.NewGuid(), StoreId = store, Name = open.Name, Title = open.Name, TaskType = open.Type,
            Checklist = TaskIndustryPacks.ChecklistJson(open), FormSchema = TaskIndustryPacks.FormJson(open),
            AssignOnShift = true, RecurrenceType = TaskRecurrenceType.Daily, RecurrenceTime = "06:30", DueAfterHours = 2, IsActive = true,
        };
        db.TaskTemplates.Add(tpl);
        await db.SaveChangesAsync();

        await using var db2 = Fx.NewDb();
        var t2 = await db2.TaskTemplates.AsTracking().FirstAsync(x => x.Id == tpl.Id);
        var n = await TaskRecurrenceRunner.CreateTasksFromTemplateAsync(db2, t2, day.AddHours(6).AddMinutes(30), manager, null);
        await db2.SaveChangesAsync();
        Assert.Equal(1, n);

        await using var db3 = Fx.NewDb();
        var task = await db3.WorkTasks.Include(x => x.TaskAssignees).SingleAsync(x => x.TemplateId == tpl.Id);
        Assert.Equal([morning1.Id, morning2.Id], task.TaskAssignees!.Select(a => a.EmployeeId).OrderBy(x => x == morning1.Id ? 0 : 1).ToArray());
        Assert.NotNull(task.FormSchema);
        Assert.Contains("Nhiệt độ tủ mát", TaskFormHelper.MissingRequired(task.FormSchema, task.FormValues));
    }
}
