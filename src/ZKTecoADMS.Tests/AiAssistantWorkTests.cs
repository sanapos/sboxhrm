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
/// Đợt 1 mở rộng trợ lý: duyệt chấm công mobile / đổi ca / đăng ký lịch / công tác phí, tạo công tác phí, kiến nghị,
/// suất ăn, sửa hồ sơ nhân viên, trả nợ NCC, xuất HĐĐT, tiếp nhận bảo hành, đơn tạm theo bàn.
/// </summary>
public class AiAssistantWorkTests
{
    static readonly AiAssistantActions Catalog = new(null!, null!, null!, NullLogger<AiAssistantActions>.Instance);

    static string Json(object o) => JsonSerializer.Serialize(o,
        new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });

    static ModulePermissionDto P(string m, bool create = false, bool edit = false, bool approve = false) =>
        new() { Module = m, CanView = true, CanCreate = create, CanEdit = edit, CanApprove = approve };

    static readonly Guid Store = Guid.NewGuid();
    static readonly Guid HeadUser = Guid.NewGuid(), HeadEmp = Guid.NewGuid();
    static readonly Guid AUser = Guid.NewGuid(), AEmp = Guid.NewGuid();
    static readonly Guid OutUser = Guid.NewGuid();
    static readonly Guid Lunch = Guid.NewGuid(), Supplier = Guid.NewGuid(), Paid = Guid.NewGuid(), Open = Guid.NewGuid();
    static readonly Guid Phone = Guid.NewGuid(), Old = Guid.NewGuid(), Coca = Guid.NewGuid(), Table5 = Guid.NewGuid();
    static readonly Guid MobileIn = Guid.NewGuid(), MobileOut = Guid.NewGuid(), Swap = Guid.NewGuid(), Trip = Guid.NewGuid();

    static AiAssistantScope Team => AiAssistantScope.Of(HeadEmp, [(HeadEmp, HeadUser), (AEmp, AUser)], selfOnly: false);
    static AiAssistantScope Self => AiAssistantScope.Of(AEmp, [(AEmp, AUser)], selfOnly: true);

    static AiAssistantActions.Ctx Ctx(AiAssistantScope scope, Guid user, params ModulePermissionDto[] perms) =>
        new(Store, user, "Custom", perms.ToDictionary(p => p.Module), false, null, scope);

    static ZKTecoDbContext Seed()
    {
        var db = new ZKTecoDbContext(new DbContextOptionsBuilder<ZKTecoDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking).Options);
        db.Employees.AddRange(
            new Employee { Id = HeadEmp, StoreId = Store, ApplicationUserId = HeadUser, FirstName = "Head", LastName = "", EmployeeCode = "NV009", WorkStatus = EmployeeWorkStatus.Active, IsActive = true },
            new Employee
            {
                Id = AEmp, StoreId = Store, ApplicationUserId = AUser, FirstName = "An", LastName = "", EmployeeCode = "NV010",
                WorkStatus = EmployeeWorkStatus.Active, IsActive = true, Department = "Bếp", Position = "Phụ bếp",
            });
        db.MealSessions.Add(new MealSession { Id = Lunch, StoreId = Store, Name = "Bữa trưa", StartTime = new TimeSpan(11, 30, 0), EndTime = new TimeSpan(13, 0, 0), IsActive = true });
        db.PosSuppliers.Add(new PosSupplier { Id = Supplier, StoreId = Store, SupplierCode = "NCC1", Name = "Bia Sài Gòn", CurrentDebt = 3_000_000 });
        db.PosStockReceipts.Add(new PosStockReceipt
        {
            Id = Guid.NewGuid(), StoreId = Store, SupplierId = Supplier, ReceiptNo = "PN1", Status = PosPurchaseReceiptStatus.Completed,
            TotalCost = 5_000_000, PaidAmount = 1_000_000,
        });
        db.PosSaleOrders.AddRange(
            new PosSaleOrder { Id = Paid, StoreId = Store, OrderNo = "HD001", Status = PosSaleOrderStatus.Completed, Total = 500_000 },
            new PosSaleOrder { Id = Open, StoreId = Store, OrderNo = "TAM01", Status = PosSaleOrderStatus.Draft, Total = 50_000, ServiceResourceId = Table5 });
        db.PosProducts.Add(new PosProduct { Id = Coca, StoreId = Store, ProductCode = "HH001", Name = "Coca", BasePrice = 10000, BaseUnitName = "Lon", IsActive = true });
        db.PosServiceResources.Add(new PosServiceResource { Id = Table5, StoreId = Store, Name = "Bàn 5", Code = "B5", Capacity = 4, IsActive = true });
        db.PosProductWarrantyRegistrations.AddRange(
            new PosProductWarrantyRegistration
            {
                Id = Phone, StoreId = Store, SaleOrderId = Paid, ProductId = Coca, SerialNumber = "SN12345",
                WarrantyExpiry = DateTime.UtcNow.AddMonths(6), SaleDate = DateTime.UtcNow.AddMonths(-6), Status = PosWarrantyStatus.Active,
            },
            new PosProductWarrantyRegistration
            {
                Id = Old, StoreId = Store, SaleOrderId = Paid, ProductId = Coca, SerialNumber = "SN99999",
                WarrantyExpiry = DateTime.UtcNow.AddMonths(-1), SaleDate = DateTime.UtcNow.AddMonths(-13), Status = PosWarrantyStatus.Returned,
            });
        db.MobileAttendanceRecords.AddRange(
            new MobileAttendanceRecord { Id = MobileIn, StoreId = Store, OdooEmployeeId = AUser.ToString(), EmployeeName = "An", PunchTime = DateTime.UtcNow, Status = "pending", IsOutside = true, OutsideReason = "Đi giao hàng" },
            // Người ngoài phạm vi quản lý — không được hiện.
            new MobileAttendanceRecord { Id = MobileOut, StoreId = Store, OdooEmployeeId = OutUser.ToString(), EmployeeName = "Khác", PunchTime = DateTime.UtcNow, Status = "pending" });
        db.ShiftSwapRequests.Add(new ShiftSwapRequest
        {
            Id = Swap, StoreId = Store, RequesterUserId = AUser, TargetUserId = HeadUser, RequesterDate = DateTime.Today.AddDays(2),
            TargetDate = DateTime.Today.AddDays(3), Status = ShiftSwapStatus.TargetAccepted,
        });
        db.BusinessTripCases.Add(new BusinessTripCase
        {
            Id = Trip, StoreId = Store, EmployeeId = AEmp, EmployeeUserId = AUser, CaseCode = "CT001", Title = "Đi Đà Nẵng",
            Status = BusinessTripCaseStatus.SettlementPending, AdvanceAmount = 2_000_000, SettledAmount = 2_400_000,
        });
        db.SaveChanges();
        return db;
    }

    static AiAssistantActions Actions(ZKTecoDbContext db) =>
        new(db, new MemoryCache(new MemoryCacheOptions()), null!, NullLogger<AiAssistantActions>.Instance);

    static async Task<(string Res, List<AiAssistantActions.Pending> Proposed)> Run(ZKTecoDbContext db, string tool, object args,
        AiAssistantActions.Ctx c)
    {
        var proposed = new List<AiAssistantActions.Pending>();
        var res = Json(await Actions(db).HandleAsync(tool, JsonSerializer.SerializeToElement(args), c, proposed, CancellationToken.None));
        return (res, proposed);
    }

    static System.Text.Json.Nodes.JsonNode Body(AiAssistantActions.Pending p) => System.Text.Json.Nodes.JsonNode.Parse(p.Body!)!;

    // ─── Quyền ─────────────────────────────────────────────────────

    [Fact]
    public void Cong_cu_moi_theo_dung_quyen()
    {
        var all = Catalog.AllowedToolNames(Ctx(Team, HeadUser, P("BusinessTripExpense", create: true), P("Feedback", create: true),
            P("Meal", create: true), P("Employee", edit: true), P("PosPurchaseReceipts", edit: true), P("PosEInvoice", approve: true),
            P("PosWarranty", edit: true)));
        foreach (var t in new[] { "propose_business_trip", "propose_feedback", "propose_meal", "propose_update_employee",
                     "propose_supplier_payment", "propose_einvoice", "propose_warranty_claim" })
            Assert.Contains(t, all);
        // Chỉ xem → không có thao tác nào.
        Assert.Empty(Catalog.AllowedToolNames(Ctx(Team, HeadUser, P("BusinessTripExpense"), P("Employee"), P("PosEInvoice"))));
        // Nhân viên tự phục vụ: không sửa hồ sơ người khác dù có quyền sửa.
        Assert.DoesNotContain("propose_update_employee", Catalog.AllowedToolNames(Ctx(Self, AUser, P("Employee", edit: true))));

        var decl = Json(Catalog.ToolDeclarations(Ctx(Self, AUser, P("Meal", create: true), P("PosWarranty", edit: true),
            P("PosSell", create: true))));
        Assert.Contains("find_meal_sessions", decl);
        Assert.Contains("find_warranty", decl);
        Assert.Contains("find_resources", decl);
    }

    [Theory]
    [InlineData("Tạo hồ sơ đi công tác Đà Nẵng tuần sau, tạm ứng 3 triệu", "hr")]
    [InlineData("Đăng ký suất ăn trưa mai", "hr")]
    [InlineData("Chuyển An sang phòng kinh doanh", "hr")]
    [InlineData("Trả nợ nhà cung cấp Bia Sài Gòn 2 triệu", "cash")]
    [InlineData("Xuất hóa đơn điện tử cho HD001", "sale")]
    [InlineData("Nhận bảo hành máy seri SN12345", "sale")]
    [InlineData("Duyệt chấm công mobile của An", "review")]
    public void Doan_nhom(string q, string group) => Assert.Contains(group, AiAssistantIntent.Groups([q])!);

    [Theory]
    [InlineData("Đi công tác Hà Nội 2 ngày, tạm ứng 5 triệu")]
    [InlineData("Gửi góp ý về giờ nghỉ trưa")]
    [InlineData("Cho An nghỉ việc từ cuối tháng")]
    [InlineData("Trả nợ NCC Bia Sài Gòn hết")]
    [InlineData("Mở bàn 5 gọi 2 Coca")]
    public void Nhan_lenh(string q) => Assert.True(AiAssistantIntent.LooksLikeAction(q), q);

    [Fact]
    public void Huong_dan_nhac_cong_cu_moi_va_van_gon()
    {
        var text = AiAssistantActions.Instructions(true);
        foreach (var t in new[] { "propose_business_trip", "propose_meal", "propose_update_employee", "propose_supplier_payment",
                     "propose_einvoice", "propose_warranty_claim", "mode=draft" })
            Assert.Contains(t, text);
        Assert.True(text.Length < 6500, $"Instructions dài {text.Length} ký tự");
    }

    // ─── Nhân sự ───────────────────────────────────────────────────

    [Fact]
    public async Task Cong_tac_kem_tam_ung_la_hai_buoc()
    {
        await using var db = Seed();
        var from = DateTime.Today.AddDays(7).ToString("yyyy-MM-dd");
        var (_, proposed) = await Run(db, "propose_business_trip",
            new { title = "Gặp khách Đà Nẵng", destination = "Đà Nẵng", from, to = DateTime.Today.AddDays(9).ToString("yyyy-MM-dd"), advance_amount = "3 triệu" },
            Ctx(Self, AUser, P("BusinessTripExpense", create: true)));
        var p = Assert.Single(proposed);
        Assert.NotNull(p.Steps);
        Assert.Equal(2, p.Steps!.Count);
        Assert.Equal("/api/BusinessTripCases/{id}/advance", p.Steps[1].Path);
        Assert.Contains("3000000", p.Steps[1].Body);
        Assert.Contains(p.Lines, l => l.Value.Contains("3 ngày"));

        // Không xin ứng → một lời gọi.
        (_, proposed) = await Run(db, "propose_business_trip", new { title = "Họp", from },
            Ctx(Self, AUser, P("BusinessTripExpense", create: true)));
        Assert.Null(Assert.Single(proposed).Steps);
    }

    [Fact]
    public async Task Suat_an_bo_ngay_qua_han()
    {
        await using var db = Seed();
        var today = AiAssistantVnTime.NowVn().Date;
        var (_, proposed) = await Run(db, "propose_meal",
            new { session_id = Lunch.ToString(), dates = $"{today.AddDays(-1):yyyy-MM-dd},{today.AddDays(1):yyyy-MM-dd},{today.AddDays(2):yyyy-MM-dd}" },
            Ctx(Self, AUser, P("Meal", create: true)));
        var p = Assert.Single(proposed);
        Assert.Equal("/api/Meals/register/batch", p.Path);
        Assert.Equal(2, Body(p)["registrations"]!.AsArray().Count);
        Assert.Contains(p.Warnings, w => w.Contains("quá hạn"));
    }

    [Fact]
    public async Task Sua_ho_so_chi_gui_truong_doi_va_nghi_viec_la_rui_ro_cao()
    {
        await using var db = Seed();
        var c = Ctx(Team, HeadUser, P("Employee", edit: true));
        var (_, proposed) = await Run(db, "propose_update_employee",
            new { employee_id = AEmp.ToString(), department = "Kinh doanh", position = "Phụ bếp" }, c);
        var p = Assert.Single(proposed);
        Assert.Equal("PUT", p.Method);
        Assert.Equal($"/api/Employees/{AEmp}", p.MergeFrom);
        var b = Body(p).AsObject();
        Assert.Equal("Kinh doanh", b["department"]!.GetValue<string>());
        Assert.False(b.ContainsKey("position")); // không đổi → không gửi
        Assert.Equal("normal", p.Risk);

        (_, proposed) = await Run(db, "propose_update_employee",
            new { employee_id = AEmp.ToString(), resign_date = "2026-12-31", resign_reason = "Chuyển nhà" }, c);
        Assert.Equal("high", Assert.Single(proposed).Risk);

        var (res, none) = await Run(db, "propose_update_employee", new { employee_id = AEmp.ToString(), department = "Bếp" }, c);
        Assert.Empty(none);
        Assert.Contains("Không có thông tin nào thay đổi", res);
    }

    // ─── Duyệt ─────────────────────────────────────────────────────

    [Fact]
    public async Task Duyet_cham_cong_mobile_chi_trong_pham_vi()
    {
        await using var db = Seed();
        var c = Ctx(Team, HeadUser, P("MobileAttendanceApproval", approve: true));
        var (res, _) = await Run(db, "find_pending_requests", new { kind = "mobile_attendance" }, c);
        Assert.Contains(MobileIn.ToString(), res);
        Assert.Contains("NGOÀI vùng", res);
        Assert.DoesNotContain(MobileOut.ToString(), res);

        var (_, proposed) = await Run(db, "propose_review_requests",
            new { kind = "mobile_attendance", ids = $"{MobileIn},{MobileOut}", decision = "approve" }, c);
        var p = Assert.Single(proposed);
        var step = Assert.Single(p.Steps!);
        Assert.Equal($"/api/mobile-attendance/approve/{MobileIn}", step.Path);
        Assert.Contains("\"approved\":true", step.Body);
    }

    [Fact]
    public async Task Duyet_cong_tac_phi_dung_buoc_quyet_toan_va_doi_ca()
    {
        await using var db = Seed();
        var c = Ctx(Team, HeadUser, P("BusinessTripExpense", approve: true), P("ShiftSwap", approve: true));
        var (_, proposed) = await Run(db, "propose_review_requests", new { kind = "business_trip", ids = Trip.ToString(), decision = "approve" }, c);
        var step = Assert.Single(Assert.Single(proposed).Steps!);
        Assert.Equal($"/api/BusinessTripCases/{Trip}/settlement/approve", step.Path);
        Assert.Null(Assert.Single(proposed[0].BatchUndo!)); // quyết toán không hoàn tác được

        (_, proposed) = await Run(db, "propose_review_requests",
            new { kind = "shift_swap", ids = Swap.ToString(), decision = "reject", reason = "Thiếu người" }, c);
        step = Assert.Single(Assert.Single(proposed).Steps!);
        Assert.Equal($"/api/ShiftSwaps/{Swap}/approve", step.Path);
        Assert.Contains("\"approve\":false", step.Body);
    }

    // ─── POS ───────────────────────────────────────────────────────

    [Fact]
    public async Task Tra_no_ncc_khong_vuot_no_va_tra_het()
    {
        await using var db = Seed();
        var c = Ctx(Team, HeadUser, P("PosPurchaseReceipts", edit: true));
        var (res, none) = await Run(db, "propose_supplier_payment", new { supplier_id = Supplier.ToString(), amount = "9 triệu" }, c);
        Assert.Empty(none);
        Assert.Contains("vượt tổng nợ", res);

        var (_, proposed) = await Run(db, "propose_supplier_payment", new { supplier_id = Supplier.ToString(), amount = "all", method = "bank" }, c);
        var p = Assert.Single(proposed);
        Assert.Equal($"/api/pos/purchase/suppliers/{Supplier}/pay", p.Path);
        // Nợ theo phiếu (4tr) lớn hơn số dư ghi sổ (3tr) → trả theo phiếu.
        Assert.Equal(4_000_000m, Body(p)["amount"]!.GetValue<decimal>());
        Assert.Equal("Chuyển khoản", Body(p)["paymentMethod"]!.GetValue<string>());
    }

    [Fact]
    public async Task Hddt_chi_cho_don_da_thanh_toan_va_xac_nhan_hai_lan()
    {
        await using var db = Seed();
        var c = Ctx(Team, HeadUser, P("PosEInvoice", approve: true));
        var (res, none) = await Run(db, "propose_einvoice", new { order_id = Open.ToString() }, c);
        Assert.Empty(none);
        Assert.Contains("đã thanh toán", res);

        var (_, proposed) = await Run(db, "propose_einvoice",
            new { order_id = Paid.ToString(), tax_code = "0312345678", company_name = "Công ty ABC" }, c);
        var p = Assert.Single(proposed);
        Assert.Equal($"/api/pos/einvoice/issue/{Paid}", p.Path);
        Assert.Equal("high", p.Risk);
        Assert.Equal("0312345678", Body(p)["taxCode"]!.GetValue<string>());
    }

    [Fact]
    public async Task Bao_hanh_tim_theo_seri_va_may_da_tra_chi_ghi_chu()
    {
        await using var db = Seed();
        var c = Ctx(Team, HeadUser, P("PosWarranty", edit: true));
        var (res, _) = await Run(db, "find_warranty", new { query = "SN123" }, c);
        Assert.Contains(Phone.ToString(), res);
        Assert.Contains("còn bảo hành", res);

        var (_, proposed) = await Run(db, "propose_warranty_claim", new { warranty_id = Phone.ToString(), description = "Không lên nguồn" }, c);
        Assert.Equal("Repair", Body(Assert.Single(proposed))["claimType"]!.GetValue<string>());

        (res, proposed) = await Run(db, "propose_warranty_claim", new { warranty_id = Old.ToString(), description = "Hỏi bảo hành" }, c);
        Assert.Empty(proposed);
        Assert.Contains("note_only", res);
        (_, proposed) = await Run(db, "propose_warranty_claim", new { warranty_id = Old.ToString(), description = "Khách hỏi", note_only = true }, c);
        Assert.Equal("Note", Body(Assert.Single(proposed))["claimType"]!.GetValue<string>());
    }

    [Fact]
    public async Task Don_tam_theo_ban_khong_thu_tien_va_ban_dang_co_don_thi_bao()
    {
        await using var db = Seed();
        var c = Ctx(Team, HeadUser, P("PosSell", create: true));
        var items = new[] { new { product_id = Coca.ToString(), qty = 2 } };
        var (res, none) = await Run(db, "propose_sale_order", new { mode = "draft", resource_id = Table5.ToString(), items }, c);
        Assert.Empty(none);
        Assert.Contains("TAM01", res);

        var (_, proposed) = await Run(db, "propose_sale_order", new { mode = "draft", items }, c);
        var p = Assert.Single(proposed);
        Assert.Equal("sale_draft", p.Kind);
        Assert.False(Body(p)["complete"]!.GetValue<bool>());
        Assert.Equal(0m, Body(p)["paidAmount"]!.GetValue<decimal>());
    }
}
