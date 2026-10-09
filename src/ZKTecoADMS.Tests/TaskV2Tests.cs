using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests;

/// <summary>Công việc v2: checklist, tiến độ tự tính, lịch lặp, gói ngành, tạo việc lặp.</summary>
public class TaskV2Tests
{
    [Fact]
    public void Checklist_reads_legacy_formats_and_keeps_proof_fields()
    {
        var strings = TaskV2Helper.ParseChecklist("[\"Lau kính\",\"Bật đèn\"]");
        Assert.Equal(2, strings.Count);
        Assert.Equal("Lau kính", strings[0].Text);
        Assert.False(strings[0].Done);

        var legacy = TaskV2Helper.ParseChecklist("[{\"title\":\"A\",\"isDone\":true},{\"text\":\"B\",\"requirePhoto\":true}]");
        Assert.True(legacy[0].Done);
        Assert.True(legacy[1].RequirePhoto);

        var text = TaskV2Helper.ParseChecklist("- Mở cửa\n- Kiểm két");
        Assert.Equal(new[] { "Mở cửa", "Kiểm két" }, text.Select(x => x.Text));

        // Id trùng được đánh lại để thao tác theo id không nhầm.
        var dup = TaskV2Helper.ParseChecklist("[{\"id\":\"x\",\"text\":\"1\"},{\"id\":\"x\",\"text\":\"2\"}]");
        Assert.NotEqual(dup[0].Id, dup[1].Id);

        var roundTrip = TaskV2Helper.ParseChecklist(TaskV2Helper.SerializeChecklist(legacy));
        Assert.Equal("A", roundTrip[0].Text);
        Assert.True(roundTrip[0].Done);
    }

    [Fact]
    public void Progress_follows_mode()
    {
        var task = new WorkTask
        {
            ProgressMode = TaskProgressMode.Checklist,
            Checklist = "[{\"text\":\"a\",\"done\":true},{\"text\":\"b\"},{\"text\":\"c\"},{\"text\":\"d\",\"done\":true}]",
        };
        Assert.Equal(50, TaskV2Helper.AutoProgress(task));
        task.ProgressMode = TaskProgressMode.Manual;
        Assert.Null(TaskV2Helper.AutoProgress(task));
        task.ProgressMode = TaskProgressMode.SubTasks;
        Assert.Equal(33, TaskV2Helper.AutoProgress(task, 3, 1));
        Assert.Null(TaskV2Helper.AutoProgress(task, 0, 0));
    }

    [Fact]
    public void Next_run_daily_weekly_monthly()
    {
        var mon = new DateTime(2026, 9, 28, 9, 0, 0); // Thứ 2
        Assert.Equal(new DateTime(2026, 9, 29, 8, 0, 0), TaskV2Helper.NextRun(TaskRecurrenceType.Daily, null, "08:00", mon));
        Assert.Equal(new DateTime(2026, 9, 28, 17, 0, 0), TaskV2Helper.NextRun(TaskRecurrenceType.Daily, null, "17:00", mon));
        // Thứ 2,4,6 — sau 9h thứ 2 → thứ 4 lúc 08:00
        Assert.Equal(new DateTime(2026, 9, 30, 8, 0, 0), TaskV2Helper.NextRun(TaskRecurrenceType.Weekly, "1,3,5", "08:00", mon));
        // Chủ nhật = 7
        Assert.Equal(new DateTime(2026, 10, 4, 21, 0, 0), TaskV2Helper.NextRun(TaskRecurrenceType.Weekly, "7", "21:00", mon));
        // Ngày cuối tháng (0)
        Assert.Equal(new DateTime(2026, 9, 30, 20, 0, 0), TaskV2Helper.NextRun(TaskRecurrenceType.Monthly, "0", "20:00", mon));
        Assert.Equal(new DateTime(2026, 10, 1, 8, 0, 0), TaskV2Helper.NextRun(TaskRecurrenceType.Monthly, "1", "08:00", mon));
        Assert.Null(TaskV2Helper.NextRun(TaskRecurrenceType.None, null, null, mon));
    }

    [Fact]
    public void Nine_industry_packs_are_consistent()
    {
        Assert.Equal(11, TaskIndustryPacks.All.Length);
        Assert.Equal(TaskIndustryPacks.All.Length, TaskIndustryPacks.All.Select(p => p.Key).Distinct().Count());
        foreach (var pack in TaskIndustryPacks.All)
        {
            // Mỗi ngành đủ mẫu để giao việc ngay sau khi chọn mô hình (không phải tự nhập từ đầu).
            Assert.True(pack.Templates.Length >= 4, $"{pack.Key}: chỉ {pack.Templates.Length} mẫu");
            var keys = pack.Stages.Select(s => s.Key).ToList();
            Assert.Equal(keys.Count, keys.Distinct().Count());
            Assert.Contains(pack.Stages, s => s.Done);
            Assert.Equal(pack.Templates.Length, pack.Templates.Select(t => t.Name).Distinct().Count());
            foreach (var t in pack.Templates)
            {
                Assert.True(t.StageKey == null || keys.Contains(t.StageKey), $"{pack.Key}/{t.Name} stage {t.StageKey}");
                Assert.NotEmpty(t.Checklist);
                var items = TaskV2Helper.ParseChecklist(TaskIndustryPacks.ChecklistJson(t));
                Assert.Equal(t.Checklist.Length, items.Count);
                Assert.DoesNotContain(items, i => i.Text.Contains("📷"));
                if (t.Recurrence != TaskRecurrenceType.None)
                    Assert.NotNull(TaskV2Helper.NextRun(t.Recurrence, t.RecurrenceDays, t.RecurrenceTime, DateTime.Now));
            }
        }
        Assert.Contains(TaskIndustryPacks.Find("construction")!.Templates, t => t.Checklist.Any(c => c.StartsWith("📷")));
    }

    [Fact]
    public async Task Recurring_template_creates_one_task_per_assignee_with_unique_codes()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        using var provider = services.BuildServiceProvider();
        using var scope = provider.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();

        var storeId = Guid.NewGuid();
        var otherStore = Guid.NewGuid();
        var owner = new ApplicationUser { Id = Guid.NewGuid(), UserName = "owner", FirstName = "O", LastName = "W", StoreId = storeId };
        var e1 = new Employee { Id = Guid.NewGuid(), StoreId = storeId, FirstName = "An", LastName = "Lê" };
        var e2 = new Employee { Id = Guid.NewGuid(), StoreId = storeId, FirstName = "Bình", LastName = "Trần" };
        var foreign = new Employee { Id = Guid.NewGuid(), StoreId = otherStore, FirstName = "X", LastName = "Y" };
        db.AddRange(owner, e1, e2, foreign);
        // Cửa hàng khác đã có mã hôm nay → mã mới không được trùng (chỉ mục duy nhất toàn hệ thống).
        var today = DateTime.UtcNow.ToString("yyyyMMdd");
        db.Add(new WorkTask { Id = Guid.NewGuid(), TaskCode = $"TASK-{today}-0001", Title = "cũ", StoreId = otherStore, AssignedById = owner.Id, IsActive = true });
        var project = new TaskProject
        {
            Id = Guid.NewGuid(), StoreId = storeId, Code = "DA-0001", Name = "Quán 1", Status = TaskProjectStatus.Active,
            Stages = TaskV2Helper.SerializeStages(TaskIndustryPacks.Find("fnb")!.Stages),
        };
        db.Add(project);
        var pack = TaskIndustryPacks.Find("fnb")!.Templates.First(t => t.Recurrence == TaskRecurrenceType.Daily);
        var template = new TaskTemplate
        {
            Id = Guid.NewGuid(), StoreId = storeId, Name = pack.Name, Title = pack.Name,
            Checklist = TaskIndustryPacks.ChecklistJson(pack), ProgressMode = TaskProgressMode.Checklist,
            RecurrenceType = pack.Recurrence, RecurrenceTime = pack.RecurrenceTime, DueAfterHours = pack.DueAfterHours,
            StageKey = pack.StageKey, ProjectId = project.Id,
            DefaultAssigneeIds = System.Text.Json.JsonSerializer.Serialize(new[] { e1.Id, e2.Id, foreign.Id }),
        };
        db.Add(template);
        await db.SaveChangesAsync();

        var runAt = new DateTime(2026, 9, 28, 6, 30, 0);
        var n = await TaskRecurrenceRunner.CreateTasksFromTemplateAsync(db, template, runAt, owner.Id, null);
        await db.SaveChangesAsync();

        Assert.Equal(2, n); // nhân viên cửa hàng khác bị bỏ qua
        var tasks = await db.WorkTasks.Where(t => t.TemplateId == template.Id).ToListAsync();
        Assert.Equal(2, tasks.Count);
        Assert.All(tasks, t =>
        {
            Assert.Equal(project.Id, t.ProjectId);
            Assert.Equal(pack.StageKey, t.StageKey);
            Assert.Equal(runAt.AddHours(pack.DueAfterHours!.Value), t.DueDate);
            Assert.Equal(pack.Checklist.Length, TaskV2Helper.ParseChecklist(t.Checklist).Count);
        });
        var codes = await db.WorkTasks.Select(t => t.TaskCode).ToListAsync();
        Assert.Equal(codes.Count, codes.Distinct().Count());
        Assert.Equal(2, await db.TaskAssignees.CountAsync(a => tasks.Select(t => t.Id).Contains(a.TaskId)));
    }
}
