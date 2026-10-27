using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Bản tin sáng tự động: số liệu (doanh thu so tuần trước, tồn thấp, chờ duyệt theo phạm vi), lịch gửi giờ VN + chống
/// gửi trùng, AI lỗi vẫn gửi bản số liệu, chọn người nhận, mỗi cửa hàng một lần gọi AI / ngày.
/// </summary>
public class AiMorningBriefTests
{
    // 01:30 UTC 28/10/2026 = 08:30 giờ VN (thứ Tư). Ngày dữ liệu = thứ Ba 27/10, tuần trước = 20/10.
    static readonly DateTime Now = new(2026, 10, 28, 1, 30, 0, DateTimeKind.Utc);
    static readonly DateTime BriefDay = new(2026, 10, 28);
    static readonly DateTime DataDay = new(2026, 10, 27);

    static ZKTecoDbContext NewDb(string name) => new(new DbContextOptionsBuilder<ZKTecoDbContext>()
        .UseInMemoryDatabase(name)
        .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking)
        .Options);

    /// <summary>Giờ VN → mặt số UTC lưu ở SaleDate.</summary>
    static DateTime Utc(DateTime vn) => vn.AddHours(-7);

    // ─── Giả lập ─────────────────────────────────────────────────

    sealed class FakePerms : IModulePermissionService
    {
        public readonly Dictionary<Guid, Dictionary<string, ModulePermissionDto>> Map = [];

        public void Grant(Guid user, string module, bool view = true, bool approve = false, bool edit = false)
        {
            if (!Map.TryGetValue(user, out var m)) Map[user] = m = new(StringComparer.OrdinalIgnoreCase);
            m[module] = new ModulePermissionDto { Module = module, CanView = view, CanApprove = approve, CanEdit = edit };
        }

        public Task<IReadOnlyDictionary<string, ModulePermissionDto>> GetEffectivePermissionsAsync(
            Guid userId, string role, Guid? storeId, CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyDictionary<string, ModulePermissionDto>>(
                Map.TryGetValue(userId, out var m) ? m : new Dictionary<string, ModulePermissionDto>());

        public Task<bool> HasPermissionAsync(Guid userId, string role, Guid? storeId, string module,
            Application.Constants.ModulePermissionAction action, CancellationToken cancellationToken = default) =>
            Task.FromResult(false);
    }

    sealed class FakeGemini(Func<string> respond) : IGeminiAiService
    {
        public int Calls;
        public string? LastPrompt;

        public Task<string> GenerateJsonAsync(string systemPrompt, string userPrompt, IReadOnlyList<AiFilePart>? files = null,
            int maxTokens = 16384, CancellationToken cancellationToken = default)
        {
            Calls++;
            LastPrompt = userPrompt;
            try { return Task.FromResult(respond()); }
            catch (Exception ex) { return Task.FromException<string>(ex); }
        }

        public bool IsConfigured => true;
        public bool IsEnabled => true;
        public Task<AiGeneratedContent> GenerateCommunicationContentAsync(string prompt, string typeLabel, string tone, string? context, int maxLength) => throw new NotSupportedException();
        public IAsyncEnumerable<string> StreamGenerateCommunicationContentAsync(string prompt, string typeLabel, string tone, string? context, int maxLength, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<string> GeneratePlainTextAsync(string systemPrompt, string userPrompt, int maxTokens = 1024) => throw new NotSupportedException();
        public Task<string> GenerateAssistantChatAsync(string systemPrompt, IReadOnlyList<(string Role, string Content)> messages, int maxTokens = 2048, CancellationToken cancellationToken = default) => throw new NotSupportedException();
        public Task<System.Text.Json.JsonElement> GenerateContentRawAsync(object requestBody, CancellationToken cancellationToken = default, string? model = null) => throw new NotSupportedException();
        public void UpdateConfig(string? apiKey, string? model = null, int? maxTokens = null, double? temperature = null, bool? enabled = null) { }
        public GeminiConfig GetCurrentConfig() => new();
    }

    sealed class FakeFactory(FakeGemini ai) : IAiMorningBriefGemini
    {
        public IGeminiAiService Create(ZKTecoDbContext db, Guid storeId) => ai;
    }

    sealed class FakeNotifier : IAiMorningBriefNotifier
    {
        public readonly List<(Guid User, BriefMessage Msg)> Sent = [];

        public Task<bool> SendAsync(Guid storeId, Guid userId, BriefMessage message, CancellationToken ct)
        {
            Sent.Add((userId, message));
            return Task.FromResult(true);
        }
    }

    sealed record Ctx(Guid Store, Guid Owner, Guid Manager, Guid Sub, Guid Other, Guid Cashier, Guid Accountant, FakePerms Perms);

    static AiMorningBriefService Service(ZKTecoDbContext db, FakePerms perms, FakeGemini ai, FakeNotifier notifier) =>
        new(db, perms, new DataScopeService(db), new FakeFactory(ai), notifier, new MemoryCache(new MemoryCacheOptions()),
            NullLogger<AiMorningBriefService>.Instance);

    static FakeGemini OkAi() => new(() => """{"suggestions":["Nhập thêm Cà phê trước giờ cao điểm","Nhắc ca sáng đến đúng giờ"]}""");

    /// <summary>Cửa hàng mẫu: chủ (Admin), quản lý có 1 cấp dưới, 1 NV ngoài phạm vi, thu ngân xem được báo cáo bán, kế toán.</summary>
    static async Task<Ctx> SeedAsync(string name, bool aiModule = true, bool enabled = true, int sendMinute = 420)
    {
        await using var db = NewDb(name);
        var store = Guid.NewGuid();
        var pkg = new ServicePackage
        {
            Id = Guid.NewGuid(), Name = "Gói thử", IsActive = true,
            AllowedModules = aiModule ? """["PosSell","AIAssistant"]""" : """["PosSell"]""",
        };
        db.ServicePackages.Add(pkg);
        Guid owner = Guid.NewGuid(), manager = Guid.NewGuid(), sub = Guid.NewGuid(), other = Guid.NewGuid(),
            cashier = Guid.NewGuid(), accountant = Guid.NewGuid();
        db.Stores.Add(new Store { Id = store, Name = "Quán Mẫu", Code = "mau", IsActive = true, OwnerId = owner, ServicePackageId = pkg.Id });
        void U(Guid id, string role, bool active = true) => db.Users.Add(new ApplicationUser
        {
            Id = id, UserName = id.ToString("N"), Email = $"{id:N}@t.local", FirstName = role, LastName = "TK", Role = role, StoreId = store, IsActive = active,
        });
        U(owner, "Admin");
        U(manager, "Manager");
        U(sub, "Employee");
        U(other, "Employee");
        U(cashier, "Cashier");
        U(accountant, "Accountant");
        U(Guid.NewGuid(), "Manager", active: false); // tài khoản đã khóa
        U(Guid.NewGuid(), "SuperAdmin");

        var empManager = new Employee { Id = Guid.NewGuid(), StoreId = store, ApplicationUserId = manager, FirstName = "Quản", LastName = "Lý", EmployeeCode = "QL" };
        var empSub = new Employee { Id = Guid.NewGuid(), StoreId = store, ApplicationUserId = sub, FirstName = "An", LastName = "Nguyễn", EmployeeCode = "NV1", DirectManagerEmployeeId = empManager.Id };
        var empOther = new Employee { Id = Guid.NewGuid(), StoreId = store, ApplicationUserId = other, FirstName = "Bình", LastName = "Trần", EmployeeCode = "NV2" };
        db.Employees.AddRange(empManager, empSub, empOther);

        // Bán hàng
        PosSaleOrder Order(DateTime vn, decimal total, decimal? paid = null, PosSaleOrderStatus st = PosSaleOrderStatus.Completed) => new()
        {
            Id = Guid.NewGuid(), StoreId = store, OrderNo = Guid.NewGuid().ToString("N")[..8], Status = st, Total = total,
            PaidAmount = paid ?? total, IsActive = true, SaleDate = Utc(vn),
        };
        var o1 = Order(DataDay.AddHours(10), 300_000);
        var o2 = Order(DataDay.AddMinutes(30), 200_000, paid: 150_000); // 00:30 VN hôm qua (= 17:30 UTC hôm kia) vẫn tính hôm qua
        var oToday = Order(BriefDay.AddHours(7), 999_000);
        db.PosSaleOrders.AddRange(o1, o2, oToday,
            Order(DataDay.AddDays(-7).AddHours(12), 400_000), // cùng thứ tuần trước
            Order(new DateTime(2026, 10, 5, 9, 0, 0), 1_000_000),
            Order(DataDay.AddMinutes(-30), 50_000), // 23:30 VN hôm kia → không phải hôm qua
            Order(DataDay.AddHours(15), 777_000, st: PosSaleOrderStatus.Cancelled));
        db.PosSaleOrderLines.AddRange(
            new PosSaleOrderLine { Id = Guid.NewGuid(), StoreId = store, SaleOrderId = o1.Id, ProductName = "Cà phê", Qty = 3, LineTotal = 300_000, IsActive = true },
            new PosSaleOrderLine { Id = Guid.NewGuid(), StoreId = store, SaleOrderId = o2.Id, ProductName = "Trà đào", Qty = 2, LineTotal = 200_000, IsActive = true },
            new PosSaleOrderLine { Id = Guid.NewGuid(), StoreId = store, SaleOrderId = oToday.Id, ProductName = "Bánh mì", Qty = 9, LineTotal = 999_000, IsActive = true });

        // Tồn kho
        PosProduct P(string n, decimal onHand, decimal min, PosProductType t = PosProductType.Goods, bool active = true) => new()
        {
            Id = Guid.NewGuid(), StoreId = store, Name = n, ProductCode = n, ProductType = t, OnHandQty = onHand, MinStockQty = min, IsActive = active,
        };
        db.PosProducts.AddRange(P("Sữa", 0, 5), P("Đường", 3, 5), P("Cà phê hạt", 10, 5),
            P("Dịch vụ giao", 0, 5, PosProductType.Service), P("Hàng ngừng bán", 0, 2, active: false), P("Không đặt tối thiểu", -1, 0));

        // Công nợ
        db.PosCustomers.AddRange(
            new PosCustomer { Id = Guid.NewGuid(), StoreId = store, Name = "Chị Lan", CustomerCode = "KH1", CurrentDebt = 2_000_000, DebtLimit = 1_000_000, IsActive = true },
            new PosCustomer { Id = Guid.NewGuid(), StoreId = store, Name = "Anh Tú", CustomerCode = "KH2", CurrentDebt = 500_000, IsActive = true });

        // Chờ duyệt: 1 đơn của cấp dưới, 1 đơn của NV ngoài phạm vi quản lý
        db.Leaves.AddRange(
            new Leave { Id = Guid.NewGuid(), StoreId = store, EmployeeUserId = sub, Status = LeaveStatus.Pending, StartDate = BriefDay, EndDate = BriefDay, IsActive = true },
            new Leave { Id = Guid.NewGuid(), StoreId = store, EmployeeUserId = other, Status = LeaveStatus.Pending, StartDate = BriefDay, EndDate = BriefDay, IsActive = true });
        db.PenaltyTickets.AddRange(
            new PenaltyTicket { Id = Guid.NewGuid(), StoreId = store, EmployeeId = empSub.Id, TicketCode = "P1", Status = PenaltyTicketStatus.Pending, IsActive = true },
            new PenaltyTicket { Id = Guid.NewGuid(), StoreId = store, EmployeeId = empOther.Id, TicketCode = "P2", Status = PenaltyTicketStatus.Pending, IsActive = true },
            new PenaltyTicket { Id = Guid.NewGuid(), StoreId = store, EmployeeId = empOther.Id, TicketCode = "P3", Status = PenaltyTicketStatus.Approved, IsActive = true });

        // Chấm công hôm qua: cấp dưới vào 08:30 (ca 08:00) → trễ 30 phút; NV kia có ca mà không chấm → vắng
        db.WorkSchedules.AddRange(
            new WorkSchedule { Id = Guid.NewGuid(), StoreId = store, EmployeeUserId = sub, Date = DataDay, StartTime = new TimeSpan(8, 0, 0), IsActive = true },
            new WorkSchedule { Id = Guid.NewGuid(), StoreId = store, EmployeeUserId = other, Date = DataDay, StartTime = new TimeSpan(8, 0, 0), IsActive = true });
        db.MobileAttendanceRecords.Add(new MobileAttendanceRecord
        {
            Id = Guid.NewGuid(), StoreId = store, OdooEmployeeId = sub.ToString(), PunchTime = DataDay.AddHours(8).AddMinutes(30),
            PunchType = 0, IsActive = true,
        });

        db.AiMorningBriefSettings.Add(new AiMorningBriefSetting
        {
            Id = Guid.NewGuid(), StoreId = store, Enabled = enabled, SendMinute = sendMinute,
            Recipients = "owner,manager", Sections = AiMorningBriefOptions.DefaultSections,
        });
        await db.SaveChangesAsync();

        var perms = new FakePerms();
        perms.Grant(manager, "Leave", approve: true);
        perms.Grant(manager, "PenaltyTickets", approve: true);
        perms.Grant(manager, "PosSalesReport");
        perms.Grant(cashier, "PosSalesReport");
        return new Ctx(store, owner, manager, sub, other, cashier, accountant, perms);
    }

    // ─── Số liệu ─────────────────────────────────────────────────

    [Fact]
    public async Task Doanh_thu_hom_qua_so_voi_cung_thu_tuan_truoc_va_luy_ke_thang()
    {
        var name = Guid.NewGuid().ToString();
        var c = await SeedAsync(name);
        await using var db = NewDb(name);
        var s = await AiMorningBriefCollector.SalesAsync(db, c.Store, DataDay, default);

        Assert.Equal(2, s.Orders);
        Assert.Equal(500_000m, s.Revenue);
        Assert.Equal(1, s.LastWeekOrders);
        Assert.Equal(400_000m, s.LastWeekRevenue);
        Assert.Equal(25m, AiMorningBriefFormatter.ChangePercent(s.Revenue, s.LastWeekRevenue));
        Assert.Equal(5, s.MonthOrders); // 05/10, 20/10, 26/10 23:30, 2 đơn hôm qua — không tính đơn hôm nay / đã hủy
        Assert.Equal(1_950_000m, s.MonthRevenue);
        Assert.Equal(["Cà phê", "Trà đào"], s.TopItems.Select(t => t.Name));
    }

    [Fact]
    public async Task Hang_duoi_ton_toi_thieu_va_cong_no()
    {
        var name = Guid.NewGuid().ToString();
        var c = await SeedAsync(name);
        await using var db = NewDb(name);

        var stock = await AiMorningBriefCollector.StockAsync(db, c.Store, default);
        Assert.Equal(2, stock.LowCount);
        Assert.Equal(1, stock.OutCount);
        Assert.Equal("Sữa", stock.Items[0].Name); // hết hàng xếp trước

        var debt = await AiMorningBriefCollector.DebtAsync(db, c.Store, DataDay, default);
        Assert.Equal(2_500_000m, debt.TotalDebt);
        Assert.Equal(2, debt.DebtorCount);
        Assert.Equal(50_000m, debt.NewDebt);
        Assert.Equal(1, debt.NewDebtOrders);
        Assert.Equal("Chị Lan", Assert.Single(debt.OverLimit).Name);
    }

    [Fact]
    public async Task Cho_duyet_va_cham_cong_theo_pham_vi_nguoi_nhan()
    {
        var name = Guid.NewGuid().ToString();
        var c = await SeedAsync(name);
        await using var db = NewDb(name);
        var svc = Service(db, c.Perms, OkAi(), new FakeNotifier());
        var data = await AiMorningBriefCollector.CollectStoreAsync(db, c.Store, BriefDay, AiMorningBriefOptions.AllSections, default);

        Assert.Equal(2, data.Attendance!.Scheduled);
        Assert.Equal(30, Assert.Single(data.Attendance.Late).Minutes);
        Assert.Single(data.Attendance.Absent);

        // Chủ cửa hàng: toàn cửa hàng
        var owner = await svc.ViewForAsync(data, c.Owner, "Admin", default);
        Assert.Equal(2, owner.Approvals!.Leave);
        Assert.Equal(2, owner.Approvals.Penalty);
        Assert.True(owner.Ai);

        // Quản lý: chỉ cấp dưới; không có quyền duyệt ứng lương → không có dòng đó; không xem tồn kho / công nợ
        var mgr = await svc.ViewForAsync(data, c.Manager, "Manager", default);
        Assert.Equal(1, mgr.Approvals!.Leave);
        Assert.Equal(1, mgr.Approvals.Penalty);
        Assert.Null(mgr.Approvals.Advance);
        Assert.True(mgr.Sales);
        Assert.False(mgr.Stock);
        Assert.False(mgr.Ai); // gợi ý AI viết từ số liệu cả cửa hàng → không đưa cho người xem một phần

        var msg = AiMorningBriefFormatter.ForRecipient(data, mgr, ["Gợi ý bí mật"])!;
        Assert.Contains("Nguyễn An (30 phút)", msg.FullText);
        Assert.DoesNotContain("Trần Bình", msg.FullText); // vắng nhưng ngoài phạm vi
        Assert.DoesNotContain("TỒN KHO", msg.FullText);
        Assert.DoesNotContain("Gợi ý bí mật", msg.FullText);
        Assert.Contains("trong phạm vi bạn quản lý", msg.FullText);
        Assert.True(msg.PushBody.Split('\n').Length <= 3);

        // Nhân viên tự phục vụ: không có mục nào → không gửi
        var emp = await svc.ViewForAsync(data, c.Sub, "Employee", default);
        Assert.Null(AiMorningBriefFormatter.ForRecipient(data, emp, null));
    }

    // ─── Lịch gửi ────────────────────────────────────────────────

    [Fact]
    public void Den_gio_gui_theo_gio_VN()
    {
        var d = new DateTime(2026, 10, 27, 0, 0, 0, DateTimeKind.Utc);
        Assert.False(AiMorningBriefSchedule.IsDue(420, d.AddMinutes(-1), false)); // 06:59 VN
        Assert.True(AiMorningBriefSchedule.IsDue(420, d, false));                 // 07:00 VN
        Assert.True(AiMorningBriefSchedule.IsDue(420, d.AddHours(6).AddMinutes(-1), false));
        Assert.False(AiMorningBriefSchedule.IsDue(420, d.AddHours(6), false));    // quá 6 tiếng → bỏ lượt hôm nay
        Assert.False(AiMorningBriefSchedule.IsDue(420, d.AddHours(1), true));     // đã gửi hôm nay
        // 17:30 UTC = 00:30 VN hôm sau
        Assert.Equal(new DateTime(2026, 10, 28), AiMorningBriefSchedule.BriefDate(new DateTime(2026, 10, 27, 17, 30, 0, DateTimeKind.Utc)));
        Assert.Equal(420, AiMorningBriefSchedule.Parse("07:00"));
        Assert.Null(AiMorningBriefSchedule.Parse("25:00"));
    }

    [Fact]
    public async Task Chon_cua_hang_den_gio_chua_gui()
    {
        var name = Guid.NewGuid().ToString();
        var due = await SeedAsync(name);
        await using (var db = NewDb(name))
        {
            Guid S(string code, bool locked = false)
            {
                var id = Guid.NewGuid();
                db.Stores.Add(new Store { Id = id, Name = code, Code = code, IsActive = true, IsLocked = locked });
                return id;
            }
            var late = S("late");
            var off = S("off");
            var sent = S("sent");
            var locked = S("locked", locked: true);
            db.AiMorningBriefSettings.AddRange(
                new AiMorningBriefSetting { Id = Guid.NewGuid(), StoreId = late, Enabled = true, SendMinute = 9 * 60 },
                new AiMorningBriefSetting { Id = Guid.NewGuid(), StoreId = off, Enabled = false, SendMinute = 420 },
                new AiMorningBriefSetting { Id = Guid.NewGuid(), StoreId = sent, Enabled = true, SendMinute = 420 },
                new AiMorningBriefSetting { Id = Guid.NewGuid(), StoreId = locked, Enabled = true, SendMinute = 420 });
            db.AiMorningBriefLogs.Add(new AiMorningBriefLog { Id = Guid.NewGuid(), StoreId = sent, BriefDate = BriefDay, Status = "sent" });
            await db.SaveChangesAsync();
        }
        await using var db2 = NewDb(name);
        var ids = await Service(db2, due.Perms, OkAi(), new FakeNotifier()).DueStoreIdsAsync(Now, default);
        Assert.Equal([due.Store], ids);
    }

    // ─── Gửi + chống trùng + AI ──────────────────────────────────

    [Fact]
    public async Task Gui_mot_lan_mot_ngay_va_chi_goi_AI_mot_lan()
    {
        var name = Guid.NewGuid().ToString();
        var c = await SeedAsync(name);
        var ai = OkAi();
        var notifier = new FakeNotifier();

        await using (var db = NewDb(name))
        {
            // Xem thử trước giờ gửi → lượt gọi AI của ngày
            var preview = await Service(db, c.Perms, ai, new FakeNotifier()).PreviewAsync(c.Store, c.Owner, "Admin", Now, default);
            Assert.Contains("GỢI Ý TỪ AI", preview.Text);
            Assert.True(preview.AiUsed);
        }
        await using (var db = NewDb(name))
        {
            var r = await Service(db, c.Perms, ai, notifier).SendStoreAsync(c.Store, Now, default);
            Assert.True(r.Sent);
            Assert.Equal(2, r.Recipients); // chủ + quản lý (tài khoản quản lý đã khóa không nhận)
        }
        await using (var db = NewDb(name))
        {
            // Khởi động lại / lượt quét sau: không gửi lại
            var again = await Service(db, c.Perms, ai, notifier).SendStoreAsync(c.Store, Now.AddMinutes(5), default);
            Assert.False(again.Sent);
            Assert.Equal("already", again.Skipped);
            Assert.Empty(await Service(db, c.Perms, ai, notifier).DueStoreIdsAsync(Now.AddMinutes(5), default));
        }

        Assert.Equal(1, ai.Calls);
        Assert.Equal(2, notifier.Sent.Count);
        var ownerMsg = notifier.Sent.Single(s => s.User == c.Owner).Msg;
        Assert.Equal("Bản tin sáng 28/10", ownerMsg.Title);
        Assert.Contains("Nhập thêm Cà phê trước giờ cao điểm", ownerMsg.FullText);
        Assert.Contains("+25%", ownerMsg.FullText);
        Assert.StartsWith("Doanh thu 27/10: 500k · 2 đơn (+25% so với tuần trước)", ownerMsg.PushBody);
        Assert.True(ownerMsg.PushBody.Split('\n').Length <= 3);
        Assert.Contains("DOANH THU", ai.LastPrompt);

        await using var check = NewDb(name);
        var log = await check.AiMorningBriefLogs.SingleAsync();
        Assert.Equal("sent", log.Status);
        Assert.Equal(2, log.RecipientCount);
        Assert.True(log.AiUsed);
    }

    [Fact]
    public async Task AI_loi_van_gui_ban_tin_so_lieu()
    {
        var name = Guid.NewGuid().ToString();
        var c = await SeedAsync(name);
        var ai = new FakeGemini(() => throw new AiApiException(GeminiAiService.QuotaMessage, 429));
        var notifier = new FakeNotifier();
        await using (var db = NewDb(name))
        {
            var r = await Service(db, c.Perms, ai, notifier).SendStoreAsync(c.Store, Now, default);
            Assert.True(r.Sent);
            Assert.False(r.AiUsed);
        }
        Assert.Equal(1, ai.Calls);
        Assert.Equal(2, notifier.Sent.Count);
        Assert.All(notifier.Sent, s => Assert.DoesNotContain("GỢI Ý TỪ AI", s.Msg.FullText));
        Assert.Contains("DOANH THU", notifier.Sent[0].Msg.FullText);

        await using var check = NewDb(name);
        var log = await check.AiMorningBriefLogs.SingleAsync();
        Assert.False(log.AiUsed);
        Assert.Equal("AI đã hết lượt dùng", log.AiError);
    }

    [Fact]
    public async Task Goi_khong_co_tro_ly_AI_thi_khong_gui()
    {
        var name = Guid.NewGuid().ToString();
        var c = await SeedAsync(name, aiModule: false);
        var ai = OkAi();
        var notifier = new FakeNotifier();
        await using var db = NewDb(name);
        var r = await Service(db, c.Perms, ai, notifier).SendStoreAsync(c.Store, Now, default);
        Assert.False(r.Sent);
        Assert.Equal("no-module", r.Skipped);
        Assert.Equal(0, ai.Calls);
        Assert.Empty(notifier.Sent);
    }

    [Fact]
    public void Doc_goi_y_AI()
    {
        Assert.Equal(["A", "B"], AiMorningBriefService.ParseSuggestions("""{"suggestions":["- A","B","C"]}"""));
        Assert.Equal(["X"], AiMorningBriefService.ParseSuggestions("""["X"]"""));
        Assert.Empty(AiMorningBriefService.ParseSuggestions("không phải json"));
    }

    // ─── Người nhận ──────────────────────────────────────────────

    [Fact]
    public async Task Chon_nguoi_nhan_theo_nhom()
    {
        var name = Guid.NewGuid().ToString();
        var c = await SeedAsync(name);
        await using var db = NewDb(name);

        async Task<HashSet<Guid>> Pick(params string[] groups) =>
            (await AiMorningBriefCollector.SelectRecipientsAsync(db, c.Perms, c.Store, groups, default)).Select(r => r.UserId).ToHashSet();

        Assert.Equal([c.Owner, c.Manager], await Pick(AiMorningBriefOptions.Owner, AiMorningBriefOptions.Manager));
        Assert.Equal([c.Accountant], await Pick(AiMorningBriefOptions.Accountant));
        // Có quyền xem Báo cáo bán hàng: chủ (toàn quyền), quản lý, thu ngân được cấp quyền
        Assert.Equal([c.Owner, c.Manager, c.Cashier], await Pick(AiMorningBriefOptions.SalesViewers));
        Assert.Empty(await Pick());
    }
}
