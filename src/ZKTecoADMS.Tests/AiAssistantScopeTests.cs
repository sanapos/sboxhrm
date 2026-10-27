using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.Permissions;

namespace ZKTecoADMS.Tests;

/// <summary>Trợ lý ảo trả lời / thao tác theo quyền + phạm vi dữ liệu; chỉ gửi công cụ cần cho câu hỏi.</summary>
public class AiAssistantScopeTests
{
    // Danh mục công cụ không đụng CSDL — dựng không cần DbContext.
    static readonly AiAssistantActions Actions = new(null!, null!, null!, NullLogger<AiAssistantActions>.Instance);

    static string Json(object o) => JsonSerializer.Serialize(o, new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping });

    static readonly Guid Self = Guid.NewGuid();
    static readonly Guid Other = Guid.NewGuid();

    static ModulePermissionDto P(string m, bool create = false, bool edit = false, bool delete = false, bool approve = false) =>
        new() { Module = m, CanView = true, CanCreate = create, CanEdit = edit, CanDelete = delete, CanApprove = approve };

    static AiAssistantActions.Ctx Ctx(AiAssistantScope scope, params ModulePermissionDto[] perms) =>
        new(Guid.NewGuid(), Guid.NewGuid(), "Custom", perms.ToDictionary(p => p.Module), false, null, scope);

    static AiAssistantScope SelfOnly => AiAssistantScope.Of(Self, [(Self, Guid.NewGuid())], selfOnly: true);
    static AiAssistantScope Manager => AiAssistantScope.Of(Self, [(Self, Guid.NewGuid()), (Other, Guid.NewGuid())], selfOnly: false);

    [Fact]
    public void Nhan_vien_chi_lap_phieu_cho_minh_khong_duyet_khong_phat()
    {
        var c = Ctx(SelfOnly, P("AdvanceRequests", create: true), P("PenaltyTickets", create: true, approve: true), P("Leave", approve: true));
        var tools = Actions.AllowedToolNames(c);
        Assert.Contains("propose_advance", tools);
        Assert.DoesNotContain("propose_penalty", tools);
        Assert.DoesNotContain("propose_review_requests", tools);
        Assert.False(SelfOnly.ManagesOthers);
    }

    [Fact]
    public void Vai_tro_tu_tao_co_cap_duoi_thi_duoc_duyet_dung_loai_co_quyen()
    {
        var c = Ctx(Manager, P("Leave", approve: true), P("Overtime"));
        Assert.Contains("propose_review_requests", Actions.AllowedToolNames(c));
        var json = Json(Actions.ToolDeclarations(c));
        Assert.Contains("find_pending_requests", json);
        Assert.Contains("leave (đơn nghỉ phép)", json);
        Assert.DoesNotContain("overtime (tăng ca)", json);
    }

    [Fact]
    public void Xoa_huy_can_quyen_xoa_hoac_sua_tung_loai()
    {
        var none = Ctx(Manager, P("PenaltyTickets", create: true));
        Assert.DoesNotContain("propose_delete", Actions.AllowedToolNames(none));
        Assert.DoesNotContain("propose_cancel_document", Actions.AllowedToolNames(none));

        var c = Ctx(Manager, P("PenaltyTickets", delete: true), P("PosStockCounts", edit: true));
        var tools = Actions.AllowedToolNames(c);
        Assert.Contains("propose_delete", tools);
        Assert.Contains("propose_cancel_document", tools);
        var json = Json(Actions.ToolDeclarations(c));
        Assert.Contains("stock_count", json);
        Assert.DoesNotContain("sale_order", json);
    }

    [Fact]
    public void Goi_dich_vu_khong_co_chuc_nang_thi_khong_co_cong_cu()
    {
        var c = Ctx(AiAssistantScope.Whole(), P("PosPromotions", create: true, delete: true)) with { IsSuper = true, Package = ["PosSell"] };
        var tools = Actions.AllowedToolNames(c);
        Assert.DoesNotContain("propose_promotion", tools);
        Assert.Contains("propose_sale_order", tools);
    }

    [Fact]
    public void Chi_gui_cong_cu_cua_nhom_lien_quan()
    {
        var c = Ctx(AiAssistantScope.Whole()) with { IsSuper = true };
        var stock = Json(Actions.ToolDeclarations(c, AiAssistantIntent.Groups(["Đổi giá cà phê sữa thành 30k"])));
        Assert.Contains("propose_update_product", stock);
        Assert.DoesNotContain("propose_penalty", stock);
        var all = Json(Actions.ToolDeclarations(c));
        Assert.True(all.Length > stock.Length * 2, "Khai báo theo nhóm phải gọn hơn nhiều so với gửi tất cả");
    }

    [Theory]
    [InlineData("Duyệt hết đơn nghỉ phép hôm nay", "review")]
    [InlineData("Hủy hóa đơn HD0012", "manage")]
    [InlineData("Nhập 20 thùng bia từ NCC Hùng", "stock")]
    [InlineData("Phạt Lan 50k đi trễ", "hr")]
    public void Doan_nhom_cong_cu(string q, string group) =>
        Assert.Contains(group, AiAssistantIntent.Groups([q])!);

    [Theory]
    [InlineData("Duyệt đơn phép của Lan", true)]
    [InlineData("Xóa phiếu chi tiền điện hôm qua", true)]
    [InlineData("Ngừng bán bánh mì", true)]
    [InlineData("Từ chối đơn ứng lương của An vì đã ứng tháng này", true)]
    [InlineData("Doanh thu tuần này so với tuần trước?", false)]
    [InlineData("Hôm nay ai đi trễ?", false)]
    public void Nhan_cau_ra_lenh_xoa_huy_duyet(string q, bool expected) =>
        Assert.Equal(expected, AiAssistantIntent.LooksLikeAction(q));

    [Fact]
    public void De_xuat_luu_nhat_ky_doc_lai_du_buoc_va_rui_ro()
    {
        // Đề xuất nằm ở bảng AiActionLogs dạng JSON — khởi động lại máy chủ vẫn xác nhận được đúng nội dung.
        var id = Guid.NewGuid();
        var p = new AiAssistantActions.Pending(Guid.NewGuid().ToString("N"), Guid.NewGuid(), Guid.NewGuid(), "review_approve",
                "Duyệt đơn nghỉ phép", [new("Lan", "Phép năm 02/11")], "POST", "/api/Leaves/x/approve", null, "Leave", ["cảnh báo"])
        {
            Steps = [new("POST", $"/api/Leaves/{id}/approve", "{}", Label: "Lan")],
            BatchUndo = [new AiAssistantActions.Step("POST", $"/api/Leaves/{id}/undo-approve", null)],
            Batch = true, Risk = "high", LineQty = new() { [id] = 2.5m },
        };
        var opts = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };
        var back = JsonSerializer.Deserialize<AiAssistantActions.Pending>(JsonSerializer.Serialize(p, opts), opts)!;
        Assert.Equal(p.Title, back.Title);
        Assert.Equal("high", back.Risk);
        Assert.True(back.Batch);
        Assert.Equal("Lan", back.Steps![0].Label);
        Assert.Equal($"/api/Leaves/{id}/undo-approve", back.BatchUndo![0]!.Path);
        Assert.Equal(2.5m, back.LineQty![id]);
        Assert.Equal("Phép năm 02/11", back.Lines[0].Value);
    }

    [Theory]
    [InlineData("en-US", "en")]
    [InlineData("zh_CN", "zh")]
    [InlineData("ko", "ko")]
    [InlineData("fr", "vi")]
    [InlineData(null, "vi")]
    public void Ngon_ngu_tra_loi_theo_giao_dien(string? raw, string expected)
    {
        Assert.Equal(expected, AiLanguage.Normalize(raw));
        if (expected == "vi") Assert.Equal("Trả lời bằng tiếng Việt.", AiLanguage.AnswerRule(raw));
        else Assert.Contains("LUÔN trả lời bằng", AiLanguage.AnswerRule(raw));
    }

    [Fact]
    public void Xoa_voucher_theo_quyen_sua_hang_hoa_nhu_api()
    {
        var c = Ctx(Manager, P("PosProducts", edit: true));
        Assert.Contains("propose_delete", Actions.AllowedToolNames(c));
        Assert.Contains("voucher (mã giảm giá (voucher))", Json(Actions.ToolDeclarations(c)));
    }

    [Fact]
    public void Pham_vi_chi_gom_nguoi_duoc_giao()
    {
        Assert.True(Manager.HasEmployee(Other));
        Assert.False(Manager.HasEmployee(Guid.NewGuid()));
        Assert.True(AiAssistantScope.Whole().HasEmployee(Guid.NewGuid()));
        Assert.Null(AiAssistantScope.Whole().EmployeeIds);
        Assert.True(AiAssistantScope.IsWholeStoreRole("Accountant"));
        Assert.True(AiAssistantScope.IsSelfServiceRole("Cashier"));
        Assert.False(AiAssistantScope.IsSelfServiceRole("DepartmentHead"));
    }
}
