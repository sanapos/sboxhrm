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
/// Nghỉ phép, báo giá, đặt chỗ, thêm nhân viên bằng lời: đúng quyền, ca nghỉ lấy theo lịch, giá / khách lấy từ danh mục,
/// giờ đặt chỗ đổi sang UTC, mã nhân viên tự nhảy.
/// </summary>
public class AiAssistantMoreTests
{
    static readonly AiAssistantActions Catalog = new(null!, null!, null!, NullLogger<AiAssistantActions>.Instance);

    static string Json(object o) => JsonSerializer.Serialize(o,
        new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });

    static ModulePermissionDto P(string m, bool create = false) => new() { Module = m, CanView = true, CanCreate = create };

    static readonly Guid Store = Guid.NewGuid();
    static readonly Guid HeadUser = Guid.NewGuid(), HeadEmp = Guid.NewGuid();
    static readonly Guid AUser = Guid.NewGuid(), AEmp = Guid.NewGuid();
    static readonly Guid Morning = Guid.NewGuid(), Evening = Guid.NewGuid();
    static readonly Guid Coca = Guid.NewGuid(), Cut = Guid.NewGuid(), Table5 = Guid.NewGuid(), Lan = Guid.NewGuid();
    static readonly DateTime Tomorrow = DateTime.UtcNow.AddHours(7).Date.AddDays(1);

    static AiAssistantScope Team => AiAssistantScope.Of(HeadEmp, [(HeadEmp, HeadUser), (AEmp, AUser)], selfOnly: false);

    static AiAssistantActions.Ctx Ctx(AiAssistantScope scope, Guid user, params ModulePermissionDto[] perms) =>
        new(Store, user, "Custom", perms.ToDictionary(p => p.Module), false, null, scope);

    static ZKTecoDbContext Seed()
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking).Options);
        db.Employees.AddRange(
            new Employee { Id = HeadEmp, StoreId = Store, ApplicationUserId = HeadUser, FirstName = "Head", LastName = "", EmployeeCode = "NV009", WorkStatus = EmployeeWorkStatus.Active, IsActive = true },
            new Employee { Id = AEmp, StoreId = Store, ApplicationUserId = AUser, FirstName = "An", LastName = "", EmployeeCode = "NV010", WorkStatus = EmployeeWorkStatus.Active, IsActive = true, PhoneNumber = "0901234567" });
        foreach (var (id, name, h) in new[] { (Morning, "Ca sáng", 8), (Evening, "Ca tối", 17) })
            db.ShiftTemplates.Add(new ShiftTemplate
            {
                Id = id, StoreId = Store, ManagerId = HeadUser, Name = name, StartTime = new TimeSpan(h, 0, 0),
                EndTime = new TimeSpan(h + 5, 0, 0), IsActive = true,
            });
        // An làm ca tối ngày mai.
        db.WorkSchedules.Add(new WorkSchedule { Id = Guid.NewGuid(), StoreId = Store, EmployeeUserId = AUser, ShiftId = Evening, Date = Tomorrow });
        db.PosProducts.AddRange(
            new PosProduct { Id = Coca, StoreId = Store, ProductCode = "HH001", Name = "Coca", BasePrice = 10000, BaseUnitName = "Lon", IsActive = true },
            new PosProduct { Id = Cut, StoreId = Store, ProductCode = "DV001", Name = "Cắt tóc", BasePrice = 80000, ProductType = PosProductType.Service, IsActive = true });
        db.PosCustomers.Add(new PosCustomer { Id = Lan, StoreId = Store, Name = "Chị Lan", Phone = "0988000111", Address = "Q1" });
        var area = new PosServiceArea { Id = Guid.NewGuid(), StoreId = Store, Name = "Tầng 1" };
        db.PosServiceAreas.Add(area);
        db.PosServiceResources.Add(new PosServiceResource
        {
            Id = Table5, StoreId = Store, AreaId = area.Id, Name = "Bàn 5", Code = "B5", Capacity = 4, IsActive = true,
        });
        db.SaveChanges();
        return db;
    }

    static AiAssistantActions Actions(ZKTecoDbContext db) =>
        new(db, new MemoryCache(new MemoryCacheOptions()), null!, NullLogger<AiAssistantActions>.Instance);

    /// <summary>Body gửi API mã hóa dấu tiếng Việt (\uXXXX) — so theo giá trị.</summary>
    static string? Field(AiAssistantActions.Pending p, string k) =>
        System.Text.Json.Nodes.JsonNode.Parse(p.Body!)![k]?.GetValue<string>();

    static async Task<(string Res, List<AiAssistantActions.Pending> Proposed)> Run(ZKTecoDbContext db, string tool, object args,
        AiAssistantActions.Ctx c)
    {
        var proposed = new List<AiAssistantActions.Pending>();
        var res = Json(await Actions(db).HandleAsync(tool, JsonSerializer.SerializeToElement(args), c, proposed, CancellationToken.None));
        return (res, proposed);
    }

    // ─── Quyền ─────────────────────────────────────────────────────

    [Fact]
    public void Cong_cu_moi_theo_dung_quyen()
    {
        var all = Catalog.AllowedToolNames(Ctx(Team, HeadUser, P("Leave", true), P("PosQuotes", true), P("PosBooking", true),
            P("Employee", true)));
        foreach (var t in new[] { "propose_leave", "propose_quote", "propose_reservation", "propose_employee" })
            Assert.Contains(t, all);
        Assert.Empty(Catalog.AllowedToolNames(Ctx(Team, HeadUser, P("Leave"), P("PosQuotes"), P("PosBooking"), P("Employee"))));

        // Nhân viên tự phục vụ: xin nghỉ được, thêm nhân viên thì không.
        var self = AiAssistantScope.Of(AEmp, [(AEmp, AUser)], selfOnly: true);
        var mine = Catalog.AllowedToolNames(Ctx(self, AUser, P("Leave", true), P("Employee", true)));
        Assert.Contains("propose_leave", mine);
        Assert.DoesNotContain("propose_employee", mine);

        var decl = Json(Catalog.ToolDeclarations(Ctx(Team, HeadUser, P("PosBooking", true))));
        Assert.Contains("find_resources", decl);
        Assert.Contains("find_customers", decl);
        Assert.Contains("find_shift_templates", Json(Catalog.ToolDeclarations(Ctx(self, AUser, P("Leave", true)))));
    }

    [Theory]
    [InlineData("Cho An nghỉ phép ngày mai", "hr")]
    [InlineData("Tôi xin nghỉ thứ 6 tuần này", "hr")]
    [InlineData("Báo giá cho chị Lan 10 thùng Coca", "sale")]
    [InlineData("Đặt bàn 5 tối nay 7 giờ cho anh Nam", "sale")]
    [InlineData("Thêm nhân viên mới tên Trần Thị Mai", "hr")]
    public void Doan_nhom(string q, string group) => Assert.Contains(group, AiAssistantIntent.Groups([q])!);

    [Theory]
    [InlineData("Mai tôi nghỉ, ca tối", true)]
    [InlineData("Lập báo giá cho anh Tùng", true)]
    [InlineData("Đặt lịch cắt tóc 3 giờ chiều cho chị Hoa", true)]
    [InlineData("Thêm nhân viên mới Nguyễn Văn Bình", true)]
    [InlineData("Tôi còn bao nhiêu ngày nghỉ phép?", false)]
    // Gõ không dấu (thử trên C20 03/11/2026: «Tao phieu chi 50k tien nuoc da» chỉ được chỉ đường, không lập phiếu).
    [InlineData("Tao phieu chi 50k tien nuoc da", true)]
    [InlineData("phat An 50k di tre", true)]
    [InlineData("Doanh thu hom nay bao nhieu", false)]
    // Có dấu vẫn so nguyên văn — «phát», «bình thường» không phải «phạt», «thưởng».
    [InlineData("Bình thường mấy giờ phát loa mở cửa?", false)]
    public void Nhan_lenh(string q, bool expected) => Assert.Equal(expected, AiAssistantIntent.LooksLikeAction(q));

    [Theory]
    [InlineData("Top 5 mon ban chay nhat tuan nay", true)]
    [InlineData("doanh thu thang nay so voi thang truoc", true)]
    [InlineData("may in bi loi", false)]
    public void Phan_tich_khong_dau(string q, bool expected) => Assert.Equal(expected, AiAssistantAgent.LooksAnalytical(q));

    [Fact]
    public void Nhom_cong_cu_khong_dau() => Assert.Contains("cash", AiAssistantIntent.Groups(["tao phieu chi 50k tien nuoc da"])!);

    [Fact]
    public void Huong_dan_nhac_cong_cu_moi_va_van_gon()
    {
        var text = AiAssistantActions.Instructions(true);
        foreach (var t in new[] { "propose_leave", "propose_quote", "propose_reservation", "propose_employee", "find_resources" })
            Assert.Contains(t, text);
        Assert.True(text.Length < 5200, $"Instructions dài {text.Length} ký tự");
    }

    // ─── Nghỉ phép ─────────────────────────────────────────────────

    [Fact]
    public async Task Nghi_phep_lay_ca_theo_lich_lam_viec()
    {
        await using var db = Seed();
        var (res, proposed) = await Run(db, "propose_leave", new { from = Tomorrow.ToString("yyyy-MM-dd"), type = "sick", reason = "Sốt" },
            Ctx(AiAssistantScope.Of(AEmp, [(AEmp, AUser)], selfOnly: true), AUser, P("Leave", true)));
        Assert.Contains("cho_xac_nhan", res);
        var p = Assert.Single(proposed);
        Assert.Equal("/api/Leaves", p.Path);
        Assert.Contains($"\"shiftId\":\"{Evening}\"", p.Body);
        Assert.Contains("\"type\":\"SickLeave\"", p.Body);
        // Xin cho chính mình → không gửi employeeUserId.
        Assert.DoesNotContain("employeeUserId", p.Body);
    }

    [Fact]
    public async Task Nghi_phep_nhieu_ca_chua_xep_lich_thi_hoi_ca()
    {
        await using var db = Seed();
        var (res, proposed) = await Run(db, "propose_leave",
            new { employee_id = HeadEmp.ToString(), from = Tomorrow.AddDays(3).ToString("yyyy-MM-dd") },
            Ctx(Team, HeadUser, P("Leave", true)));
        Assert.Contains("shift_id", res);
        Assert.Empty(proposed);

        (res, proposed) = await Run(db, "propose_leave",
            new { employee_id = AEmp.ToString(), from = Tomorrow.AddDays(3).ToString("yyyy-MM-dd"), shift_id = Morning.ToString() },
            Ctx(Team, HeadUser, P("Leave", true)));
        var p = Assert.Single(proposed);
        Assert.Contains($"\"employeeUserId\":\"{AUser}\"", p.Body);
        Assert.Contains($"\"shiftId\":\"{Morning}\"", p.Body);
    }

    // ─── Báo giá ───────────────────────────────────────────────────

    [Fact]
    public async Task Bao_gia_lay_gia_va_thong_tin_khach()
    {
        await using var db = Seed();
        var (_, proposed) = await Run(db, "propose_quote",
            new { items = new[] { new { product_id = Coca.ToString(), qty = 24 } }, customer_id = Lan.ToString(), valid_days = 10 },
            Ctx(Team, HeadUser, P("PosQuotes", true)));
        var p = Assert.Single(proposed);
        Assert.Equal("/api/pos/quotes", p.Path);
        Assert.Contains("\"productCode\":\"HH001\"", p.Body);
        Assert.Contains("\"unitPrice\":10000", p.Body);
        Assert.Equal("Chị Lan", Field(p, "customerName"));
        Assert.Equal("0988000111", Field(p, "customerPhone"));
        Assert.Contains(p.Lines, l => l.Value.Contains("240.000"));
    }

    // ─── Đặt chỗ ───────────────────────────────────────────────────

    [Fact]
    public async Task Dat_ban_doi_gio_sang_utc()
    {
        await using var db = Seed();
        var (_, proposed) = await Run(db, "propose_reservation",
            new { resource_id = Table5.ToString(), customer_name = "Anh Nam", phone = "0911", date = Tomorrow.ToString("yyyy-MM-dd"), time = "19:00", guests = 6 },
            Ctx(Team, HeadUser, P("PosBooking", true)));
        var p = Assert.Single(proposed);
        Assert.Equal("/api/pos/resource-reservations", p.Path);
        // 19:00 giờ VN = 12:00 UTC.
        Assert.Contains($"\"reservedUntil\":\"{Tomorrow:yyyy-MM-dd}T12:00:00.0000000Z\"", p.Body);
        Assert.DoesNotContain("slotStart", p.Body);
        Assert.Contains(p.Warnings, w => w.Contains("4 khách"));
    }

    [Fact]
    public async Task Dat_lich_dich_vu_tu_xep_tho()
    {
        await using var db = Seed();
        var (_, proposed) = await Run(db, "propose_reservation",
            new { resource_id = Table5.ToString(), customer_id = Lan.ToString(), date = Tomorrow.ToString("yyyy-MM-dd"), time = "15:00", service_id = Cut.ToString() },
            Ctx(Team, HeadUser, P("PosBooking", true)));
        var p = Assert.Single(proposed);
        Assert.Contains("\"slotStart\"", p.Body);
        Assert.Contains("\"autoAssignStaff\":true", p.Body);
        Assert.Equal("Chị Lan", Field(p, "customerName"));
    }

    [Fact]
    public async Task Tim_ban_theo_ten()
    {
        await using var db = Seed();
        var (res, _) = await Run(db, "find_resources", new { query = "ban 5" }, Ctx(Team, HeadUser, P("PosBooking", true)));
        Assert.Contains(Table5.ToString(), res);
        Assert.Contains("Tầng 1", res);
    }

    // ─── Nhân viên ─────────────────────────────────────────────────

    [Fact]
    public async Task Them_nhan_vien_tu_sinh_ma_va_tach_ten()
    {
        await using var db = Seed();
        var (_, proposed) = await Run(db, "propose_employee",
            new { full_name = "Trần  Thị Mai", phone = "0901234567", department = "Bếp", probation = true },
            Ctx(AiAssistantScope.Whole(), HeadUser, P("Employee", true)));
        var p = Assert.Single(proposed);
        Assert.Contains("\"employeeCode\":\"NV011\"", p.Body);
        Assert.Contains("\"firstName\":\"Mai\"", p.Body);
        Assert.Equal("Trần Thị", Field(p, "lastName"));
        Assert.Contains("\"workStatus\":\"Probation\"", p.Body);
        Assert.Contains(p.Warnings, w => w.Contains("trùng"));
    }

    [Theory]
    [InlineData(new string[0], "NV001")]
    [InlineData(new[] { "NV009", "NV010", "ADMIN" }, "NV011")]
    [InlineData(new[] { "A1", "B07", "B12" }, "B13")]
    public void Ma_nhan_vien_ke_tiep(string[] codes, string expected) =>
        Assert.Equal(expected, AiAssistantActions.NextEmployeeCode(codes));
}
