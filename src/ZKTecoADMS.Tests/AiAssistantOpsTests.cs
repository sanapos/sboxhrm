using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Công cụ vận hành của trợ lý (xếp ca, chuyển kho, thu nợ, thông báo, giao việc, chốt ca, phạt hàng loạt, gợi ý nhập):
/// đúng quyền + gói, chỉ nhân viên trong phạm vi, phạt hàng loạt bỏ người đã có phiếu.
/// </summary>
public class AiAssistantOpsTests
{
    // Danh mục công cụ không đụng CSDL — dựng không cần DbContext.
    static readonly AiAssistantActions Catalog = new(null!, null!, null!, NullLogger<AiAssistantActions>.Instance);

    static string Json(object o) => JsonSerializer.Serialize(o,
        new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });

    static ModulePermissionDto P(string m, bool create = false, bool edit = false, bool delete = false, bool approve = false, bool view = true) =>
        new() { Module = m, CanView = view, CanCreate = create, CanEdit = edit, CanDelete = delete, CanApprove = approve };

    static readonly Guid Store = Guid.NewGuid();
    static readonly Guid HeadUser = Guid.NewGuid(), HeadEmp = Guid.NewGuid();
    static readonly Guid AUser = Guid.NewGuid(), AEmp = Guid.NewGuid();
    static readonly Guid BUser = Guid.NewGuid(), BEmp = Guid.NewGuid();
    static readonly Guid OutUser = Guid.NewGuid(), OutEmp = Guid.NewGuid();
    static readonly Guid Shift = Guid.NewGuid();

    /// <summary>Trưởng nhóm quản lý An + Bình; «Ngoài» thuộc nhóm khác.</summary>
    static AiAssistantScope Team => AiAssistantScope.Of(HeadEmp, [(HeadEmp, HeadUser), (AEmp, AUser), (BEmp, BUser)], selfOnly: false);

    static AiAssistantActions.Ctx Ctx(AiAssistantScope scope, params ModulePermissionDto[] perms) =>
        new(Store, HeadUser, "Custom", perms.ToDictionary(p => p.Module), false, null, scope);

    // ─── Quyền + gói ───────────────────────────────────────────────

    [Fact]
    public void Khong_co_quyen_chuc_nang_thi_khong_co_cong_cu()
    {
        var c = Ctx(Team, P("PenaltyTickets", create: true));
        var tools = Catalog.AllowedToolNames(c);
        Assert.Contains("propose_penalties_for_late", tools);
        foreach (var t in new[] { "propose_assign_shift", "propose_shift_swap", "propose_stock_transfer", "propose_collect_debt",
                     "propose_announcement", "propose_task", "propose_close_cashier_shift" })
            Assert.DoesNotContain(t, tools);

        // Xếp ca cần quyền Thêm lịch; đổi ca thẳng trên lịch cần quyền Sửa lịch (hoặc Thêm yêu cầu đổi ca).
        var sched = Catalog.AllowedToolNames(Ctx(Team, P("WorkSchedule", create: true)));
        Assert.Contains("propose_assign_shift", sched);
        Assert.DoesNotContain("propose_shift_swap", sched);
        Assert.Contains("propose_shift_swap", Catalog.AllowedToolNames(Ctx(Team, P("WorkSchedule", edit: true))));
        Assert.Contains("propose_shift_swap", Catalog.AllowedToolNames(Ctx(Team, P("ShiftSwap", create: true))));

        var ops = Catalog.AllowedToolNames(Ctx(Team, P("PosProducts", create: true), P("PosCustomers", edit: true),
            P("Notification", create: true), P("Task", create: true), P("PosCashierShift", create: true)));
        foreach (var t in new[] { "propose_stock_transfer", "propose_collect_debt", "propose_announcement", "propose_task", "propose_close_cashier_shift" })
            Assert.Contains(t, ops);
        // Thu nợ cần quyền Sửa khách (như API), không phải Thêm.
        Assert.DoesNotContain("propose_collect_debt", Catalog.AllowedToolNames(Ctx(Team, P("PosCustomers", create: true))));
    }

    [Fact]
    public void Nhan_vien_tu_phuc_vu_khong_co_cong_cu_quan_ly()
    {
        var selfOnly = AiAssistantScope.Of(AEmp, [(AEmp, AUser)], selfOnly: true);
        var tools = Catalog.AllowedToolNames(Ctx(selfOnly, P("PenaltyTickets", create: true), P("Task", create: true),
            P("Notification", create: true), P("WorkSchedule", create: true, edit: true), P("PosCashierShift", create: true)));
        foreach (var t in new[] { "propose_penalties_for_late", "propose_task", "propose_announcement", "propose_assign_shift", "propose_shift_swap" })
            Assert.DoesNotContain(t, tools);
        // Thu ngân vẫn tự chốt ca của mình.
        Assert.Contains("propose_close_cashier_shift", tools);
    }

    [Fact]
    public void Goi_dich_vu_chan_ca_tai_khoan_toan_quyen()
    {
        var c = Ctx(AiAssistantScope.Whole()) with { IsSuper = true, Package = ["PenaltyTickets", "PosSell"] };
        var tools = Catalog.AllowedToolNames(c);
        Assert.Contains("propose_penalties_for_late", tools);
        foreach (var t in new[] { "propose_announcement", "propose_task", "propose_assign_shift", "propose_stock_transfer", "propose_close_cashier_shift" })
            Assert.DoesNotContain(t, tools);
    }

    [Fact]
    public void Cong_cu_tra_cuu_kem_theo_dung_quyen()
    {
        var noReport = Json(Catalog.ToolDeclarations(Ctx(Team, P("PosPurchaseReceipts", edit: true))));
        Assert.DoesNotContain("find_reorder_suggestions", noReport);
        var withReport = Json(Catalog.ToolDeclarations(Ctx(Team, P("PosPurchaseReceipts", edit: true), P("PosReportStock"))));
        Assert.Contains("find_reorder_suggestions", withReport);
        // Có quyền Xem báo cáo nhưng gói không có → không khai báo.
        var pkg = Json(Catalog.ToolDeclarations(Ctx(Team, P("PosPurchaseReceipts", edit: true), P("PosReportStock"))
            with { Package = ["PosPurchaseReceipts"] }));
        Assert.DoesNotContain("find_reorder_suggestions", pkg);

        var shift = Json(Catalog.ToolDeclarations(Ctx(Team, P("WorkSchedule", create: true))));
        Assert.Contains("find_shift_templates", shift);
        Assert.Contains("find_employees", shift);
        var transfer = Json(Catalog.ToolDeclarations(Ctx(Team, P("PosProducts", create: true))));
        Assert.Contains("find_branches", transfer);
        Assert.Single(System.Text.RegularExpressions.Regex.Matches(transfer, "\"find_products\""));
        Assert.Contains("find_customers", Json(Catalog.ToolDeclarations(Ctx(Team, P("PosCustomers", edit: true)))));
    }

    // ─── Đoán nhóm công cụ ─────────────────────────────────────────

    [Theory]
    [InlineData("Xếp ca sáng cho Lan thứ 2 tới", "shift")]
    [InlineData("Đổi ca của An với Bình ngày mai", "shift")]
    [InlineData("Chuyển kho 10 thùng bia sang chi nhánh Quận 3", "stock")]
    [InlineData("Thu nợ chị Hoa 500k", "sale")]
    [InlineData("Gửi thông báo họp toàn thể 8h sáng mai", "comms")]
    [InlineData("Giao việc kiểm kho cho An hạn thứ 6", "comms")]
    [InlineData("Chốt ca thu ngân, két có 2 triệu", "cash")]
    [InlineData("Phạt tất cả ai đi trễ hôm nay theo nội quy", "hr")]
    [InlineData("Nhập hàng theo gợi ý", "stock")]
    public void Doan_nhom_cong_cu_moi(string q, string group) =>
        Assert.Contains(group, AiAssistantIntent.Groups([q])!);

    [Theory]
    [InlineData("propose_assign_shift", "shift")]
    [InlineData("propose_shift_swap", "shift")]
    [InlineData("propose_stock_transfer", "stock")]
    [InlineData("propose_collect_debt", "sale")]
    [InlineData("propose_announcement", "comms")]
    [InlineData("propose_task", "comms")]
    [InlineData("propose_close_cashier_shift", "cash")]
    [InlineData("propose_penalties_for_late", "hr")]
    public void Nhom_cua_cong_cu_moi(string tool, string group) => Assert.Equal(group, AiAssistantIntent.GroupOf(tool));

    [Theory]
    [InlineData("Xếp ca chiều cho Bình tuần sau", true)]
    [InlineData("Chuyển kho 5 thùng nước sang chi nhánh 2", true)]
    [InlineData("Thu nợ anh Tùng hết", true)]
    [InlineData("Gửi thông báo nghỉ lễ cho cả cửa hàng", true)]
    [InlineData("Chốt ca giúp tôi", true)]
    [InlineData("Hôm nay ai đi trễ?", false)]
    public void Nhan_lenh_van_hanh(string q, bool expected) => Assert.Equal(expected, AiAssistantIntent.LooksLikeAction(q));

    [Fact]
    public void Huong_dan_gon_va_du_cong_cu_moi()
    {
        Assert.Equal("", AiAssistantActions.Instructions(false));
        var text = AiAssistantActions.Instructions(true);
        foreach (var t in new[] { "propose_assign_shift", "propose_stock_transfer", "propose_collect_debt", "propose_announcement",
                     "propose_task", "propose_close_cashier_shift", "propose_penalties_for_late", "find_reorder_suggestions" })
            Assert.Contains(t, text);
        // Gửi lại ở mọi vòng gọi AI — giữ gọn.
        Assert.True(text.Length < 4500, $"Instructions dài {text.Length} ký tự");
    }

    // ─── CSDL: phạm vi + phạt hàng loạt ────────────────────────────

    // Giờ tường VN như đọc từ CSDL (Kind Unspecified) — chấm công không bị cộng thêm 7 giờ.
    static readonly DateTime Day = DateTime.SpecifyKind(DateTime.UtcNow.AddHours(7).Date.AddDays(-3), DateTimeKind.Unspecified);

    static ZKTecoDbContext Seed()
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking).Options);
        Employee Emp(Guid id, Guid user, string name) => new()
        {
            Id = id, StoreId = Store, ApplicationUserId = user, FirstName = name, LastName = "", EmployeeCode = name.ToUpperInvariant(),
            WorkStatus = EmployeeWorkStatus.Active, IsActive = true,
        };
        db.Employees.AddRange(Emp(HeadEmp, HeadUser, "Head"), Emp(AEmp, AUser, "An"), Emp(BEmp, BUser, "Binh"), Emp(OutEmp, OutUser, "Ngoai"));
        db.ShiftTemplates.Add(new ShiftTemplate
        {
            Id = Shift, StoreId = Store, ManagerId = HeadUser, Name = "Ca sáng", StartTime = new TimeSpan(8, 0, 0),
            EndTime = new TimeSpan(17, 0, 0), LateGraceMinutes = 5, IsActive = true,
        });
        var device = Guid.NewGuid();
        // An, Bình, Ngoài cùng có ca và cùng vào trễ 35 phút.
        foreach (var e in new[] { AEmp, BEmp, OutEmp })
        {
            db.WorkSchedules.Add(new WorkSchedule { Id = Guid.NewGuid(), StoreId = Store, EmployeeUserId = e, ShiftId = Shift, Date = Day });
            var du = Guid.NewGuid();
            db.DeviceUsers.Add(new DeviceUser { Id = du, DeviceId = device, EmployeeId = e, Pin = e.ToString("N")[..6], Name = "x" });
            db.AttendanceLogs.Add(new Attendance
            {
                Id = Guid.NewGuid(), DeviceId = device, EmployeeId = du, PIN = e.ToString("N")[..6],
                AttendanceState = AttendanceStates.CheckIn, AttendanceTime = Day.AddHours(8).AddMinutes(35),
            });
        }
        // Bình đã có phiếu phạt đi trễ ngày đó (vd phiếu tự động) → không lập trùng.
        db.PenaltyTickets.Add(new PenaltyTicket
        {
            Id = Guid.NewGuid(), StoreId = Store, EmployeeId = BEmp, TicketCode = "PP-1", Type = PenaltyTicketType.Late,
            Status = PenaltyTicketStatus.Pending, Amount = 50000, ViolationDate = Day, IsActive = true,
        });
        db.PenaltySettings.Add(new PenaltySetting { Id = Guid.NewGuid(), StoreId = Store });
        db.SaveChanges();
        return db;
    }

    static AiAssistantActions Actions(ZKTecoDbContext db) =>
        new(db, new MemoryCache(new MemoryCacheOptions()), null!, NullLogger<AiAssistantActions>.Instance);

    static JsonElement Args(object o) => JsonSerializer.SerializeToElement(o);

    [Fact]
    public async Task Phat_hang_loat_bo_nguoi_da_co_phieu_va_ngoai_pham_vi()
    {
        await using var db = Seed();
        var proposed = new List<AiAssistantActions.Pending>();
        var res = Json(await Actions(db).HandleAsync("propose_penalties_for_late",
            Args(new { date = Day.ToString("yyyy-MM-dd"), type = "Late" }),
            Ctx(Team, P("PenaltyTickets", create: true)), proposed, CancellationToken.None));
        Assert.Contains("cho_xac_nhan", res);
        var p = Assert.Single(proposed);
        Assert.Equal("penalty_batch", p.Kind);
        Assert.True(p.Batch);
        var step = Assert.Single(p.Steps!);
        Assert.Equal("An", step.Label);
        Assert.Contains(AEmp.ToString(), step.Body);
        // Trễ 35 phút → mức 2 của Thiết lập phạt mặc định (100.000đ).
        Assert.Contains("\"amount\":100000", step.Body);
        Assert.Contains(p.Warnings, w => w.Contains("Binh"));
        Assert.DoesNotContain(p.Lines, l => l.Label == "Ngoai");
        Assert.Equal("normal", p.Risk);
    }

    [Fact]
    public async Task Phat_hang_loat_theo_muc_nguoi_dung_dua()
    {
        await using var db = Seed();
        var proposed = new List<AiAssistantActions.Pending>();
        await Actions(db).HandleAsync("propose_penalties_for_late",
            Args(new { date = Day.ToString("yyyy-MM-dd"), amount = 30000 }),
            Ctx(AiAssistantScope.Whole(), P("PenaltyTickets", create: true)), proposed, CancellationToken.None);
        var p = Assert.Single(proposed);
        // Cả cửa hàng: An + Ngoài (Bình đã có phiếu).
        Assert.Equal(2, p.Steps!.Count);
        Assert.All(p.Steps!, s => Assert.Contains("\"amount\":30000", s.Body));
    }

    [Fact]
    public async Task Nhan_vien_ngoai_pham_vi_bi_tu_choi()
    {
        await using var db = Seed();
        var actions = Actions(db);
        var c = Ctx(Team, P("WorkSchedule", create: true), P("Task", create: true), P("Notification", create: true),
            P("PenaltyTickets", create: true));
        var proposed = new List<AiAssistantActions.Pending>();

        var shift = Json(await actions.HandleAsync("propose_assign_shift",
            Args(new { employee_ids = OutEmp.ToString(), shift_id = Shift.ToString(), dates = Day.AddDays(5).ToString("yyyy-MM-dd") }),
            c, proposed, CancellationToken.None));
        Assert.Contains("error", shift);
        Assert.Contains("phạm vi", shift);

        var task = Json(await actions.HandleAsync("propose_task",
            Args(new { title = "Kiểm kho", employee_ids = $"{AEmp},{OutEmp}" }), c, proposed, CancellationToken.None));
        Assert.Contains("error", task);

        var pen = Json(await actions.HandleAsync("propose_penalties_for_late",
            Args(new { date = Day.ToString("yyyy-MM-dd"), employee_ids = OutEmp.ToString(), amount = 50000 }), c, proposed, CancellationToken.None));
        Assert.Contains("error", pen);
        Assert.Empty(proposed);

        // Thông báo «mọi người» chỉ tới nhân viên trong phạm vi (không gửi cho chính mình).
        await actions.HandleAsync("propose_announcement",
            Args(new { title = "Họp", body = "Họp toàn thể 8h sáng mai", everyone = true }), c, proposed, CancellationToken.None);
        var ann = Assert.Single(proposed);
        Assert.Contains(AUser.ToString(), ann.Body);
        Assert.Contains(BUser.ToString(), ann.Body);
        Assert.DoesNotContain(OutUser.ToString(), ann.Body);
        Assert.DoesNotContain(HeadUser.ToString(), ann.Body);
    }

    [Fact]
    public async Task Xep_ca_nhieu_ngay_mot_the_bo_luot_trung()
    {
        await using var db = Seed();
        var proposed = new List<AiAssistantActions.Pending>();
        // Ngày Day An và Bình đã có «Ca sáng» → bỏ; ngày hôm sau xếp mới → 2 lượt.
        await Actions(db).HandleAsync("propose_assign_shift",
            Args(new
            {
                employee_ids = $"{AEmp},{BEmp}", shift_id = Shift.ToString(),
                from = Day.ToString("yyyy-MM-dd"), to = Day.AddDays(1).ToString("yyyy-MM-dd"),
            }),
            Ctx(Team, P("WorkSchedule", create: true)), proposed, CancellationToken.None);
        var p = Assert.Single(proposed);
        Assert.Equal("assign_shift", p.Kind);
        Assert.True(p.Batch);
        Assert.Equal(2, p.Steps!.Count);
        Assert.All(p.Steps!, s => Assert.Equal("/api/WorkSchedules", s.Path));
        Assert.Contains(p.Warnings, w => w.Contains("đã có ca này"));
    }
}
