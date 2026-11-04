using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.Permissions;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Trợ lý AI dùng đúng hướng dẫn sử dụng của app (HelpCorpus/landing-guide.json, xuất từ flutter_client):
/// đủ mọi bước, mở được mọi mục kể cả ngành hàng, nút điều hướng có thật.
/// </summary>
public class AiAssistantHelpCorpusTests
{
    [Fact]
    public void Doc_du_moi_buoc_huong_dan_cua_app()
    {
        var all = AiAssistantHelpCorpus.All;
        Assert.True(all.Count >= 60, $"chỉ có {all.Count} bước");
        foreach (var mode in AiAssistantHelpCorpus.Modes)
            Assert.Contains(all, c => c.Mode == mode);
        Assert.Equal(all.Count, all.Select(c => c.StepId).Distinct().Count());
        Assert.All(all, c =>
        {
            Assert.False(string.IsNullOrWhiteSpace(c.Title), c.StepId);
            Assert.NotEmpty(c.Bullets);
        });
    }

    [Fact]
    public void Moi_buoc_co_lop_tu_khoa_rieng_va_khong_thua()
    {
        var ids = AiAssistantHelpCorpus.All.Where(AiAssistantHelpCorpus.HasAppGuide).Select(c => c.StepId).ToHashSet();
        Assert.Empty(ids.Except(AiAssistantHelpCorpus.Overlays.Keys));
        Assert.Empty(AiAssistantHelpCorpus.Overlays.Keys.Except(ids));
    }

    [Fact]
    public void Nut_dieu_huong_deu_co_that()
    {
        var known = AiAssistantPermissionRules.AllowedActionTags(new Dictionary<string, ModulePermissionDto>(), isSuperUser: true);
        foreach (var c in AiAssistantHelpCorpus.All)
            foreach (var tag in c.ActionTags)
                Assert.True(known.Contains(tag), $"{c.StepId}: {tag}");
    }

    [Theory]
    [InlineData("industry/ind_hotel", "industry", "ind_hotel")]
    [InlineData("pos/pos_einvoice", "pos", "pos_einvoice")]
    // AI ghi nhầm mục: vẫn mở đúng bước (tài khoản nằm ở mục Triển khai).
    [InlineData("advanced/employee_account", "basic", "employee_account")]
    public void The_GUIDE_mo_dung_buoc(string tag, string mode, string stepId)
    {
        Assert.True(AiAssistantHelpCorpus.TryParseGuideTag(tag, out var m, out var s));
        Assert.Equal(mode, m);
        Assert.Equal(stepId, s);
    }

    [Fact]
    public void The_GUIDE_buoc_khong_co_bi_bo()
    {
        Assert.False(AiAssistantHelpCorpus.TryParseGuideTag("basic/khong_co", out _, out _));
        Assert.False(AiAssistantHelpCorpus.TryParseGuideTag("ind_hotel", out _, out _));
    }

    [Theory]
    [InlineData("karaoke tính tiền giờ thế nào", "ind_room_hourly")]
    [InlineData("cách tạo phiếu ứng lương", "advance")]
    [InlineData("kết nối hóa đơn điện tử viettel", "pos_einvoice")]
    [InlineData("đổi ca với đồng nghiệp", "shift_swap")]
    public void Tim_dung_buoc_theo_cau_hoi(string query, string stepId)
    {
        var hits = AiAssistantHelpCorpus.Search(query, topK: 3);
        Assert.Contains(hits, h => h.StepId == stepId);
    }

    [Theory]
    // Gõ / nói không dấu vẫn trúng bước.
    [InlineData("karaoke tinh tien gio", "ind_room_hourly")]
    [InlineData("tao phieu ung luong", "advance")]
    public void Tim_khong_dau(string query, string stepId) =>
        Assert.Contains(AiAssistantHelpCorpus.Search(query, topK: 3), h => h.StepId == stepId);

    [Theory]
    [InlineData("máy in bếp không in được", true)]
    [InlineData("tại sao nhân viên không chấm công được", true)]
    [InlineData("cai dat hoa don dien tu o dau", true)]
    [InlineData("sao in bị lỗi", true)]
    [InlineData("lợi nhuận tháng này bao nhiêu", false)]
    [InlineData("trả lời giúp tôi doanh thu hôm nay", false)]
    public void Nhan_cau_hoi_cach_dung(string q, bool expected) =>
        Assert.Equal(expected, AiAssistantQueryTools.LooksLikeHowTo(q.ToLowerInvariant()));

    static bool Guide(string q) => AiAssistantIntent.IsGuideQuestion(q, AiAssistantHelpCorpus.DirectAnswerScore(q));

    [Theory]
    // Rà soát 04/11/2026: mọi câu có «máy chấm công» ra bài Gateway WiFi, «đóng bhxh» ra bài phân quyền — và trả thẳng không qua AI.
    [InlineData("cách kết nối máy chấm công", "device_connect")]
    [InlineData("máy chấm công đời cũ không có máy chủ đám mây", "gateway_wifi")]
    [InlineData("máy chấm công mất kết nối phải làm sao", "hrm-zkteco-mat-ket-noi")]
    [InlineData("máy chấm công không đẩy dữ liệu được", "hrm-zkteco-mat-ket-noi")]
    [InlineData("cách khắc phục máy chấm công bị sai giờ", "hrm-zkteco-mat-ket-noi")]
    [InlineData("máy chấm công đầy bộ nhớ", "hrm-zkteco-mat-ket-noi")]
    [InlineData("cách chọn máy chấm công", "hrm-chon-mua-may-cham-cong")]
    [InlineData("nên mua máy khuôn mặt hay vân tay", "hrm-khuon-mat-hay-van-tay")]
    [InlineData("chi phí lắp đặt máy chấm công bao nhiêu", "hrm-chi-phi-lap-dat-may-cham-cong")]
    [InlineData("dữ liệu chấm công cloud có an toàn không", "hrm-cham-cong-cloud-an-toan")]
    [InlineData("chấm công bằng mã qr được không", "hrm-cham-cong-qr")]
    [InlineData("làm sao chống chấm công hộ", "hrm-chong-cham-cong-ho")]
    [InlineData("mức đóng bhxh là bao nhiêu phần trăm", "hrm-cach-tinh-bhxh")]
    [InlineData("cách tính bhxh", "hrm-cach-tinh-bhxh")]
    [InlineData("lương tối thiểu vùng 2026 bao nhiêu", "hrm-luong-toi-thieu-vung")]
    [InlineData("tăng ca ngày lễ tính bao nhiêu phần trăm", "hrm-luong-tang-ca")]
    [InlineData("quy trình onboarding nhân viên mới", "hrm-onboarding")]
    [InlineData("cách tính giá vốn món ăn", "pos-gia-von-mon-an")]
    [InlineData("duyệt lịch làm việc ở đâu", "sys_schedule_approval")]
    [InlineData("tắt thông báo đẩy trên điện thoại", "sys_notification_settings")]
    [InlineData("sửa mẫu in báo giá ở đâu", "pos_print_templates")]
    [InlineData("xem báo cáo đi trễ về sớm", "hr_attendance_reports")]
    [InlineData("app nhân viên có những chức năng gì", "sys_employee_app")]
    [InlineData("app boss xem doanh thu trên điện thoại", "sys_boss_app")]
    [InlineData("chọn máy in 58 hay 80mm", "pos-may-in-hoa-don")]
    public void Cau_hoi_kien_thuc_ra_dung_bai(string q, string expected)
    {
        var top = AiAssistantHelpCorpus.Search(q, topK: 1)[0];
        Assert.True(top.StepId == expected || top.StepId.StartsWith(expected + "#"), $"{q} → {top.StepId}");
    }

    [Theory]
    [InlineData("làm sao đóng bhxh cho nhân viên", "bhxh")]
    [InlineData("hướng dẫn chấm công trên macbook", "macbook")]
    public void Bai_tra_thang_phai_chua_tu_dac_trung(string q, string word)
    {
        Assert.True(AiAssistantHelpCorpus.DirectAnswerScore(q) > 0, q);
        var hit = AiAssistantHelpCorpus.GuideAnswerHits(q)[0];
        Assert.Contains(word, AiAssistantHelpCorpus.FormatForPrompt([hit]), StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("cách khắc phục máy chấm công bị sai giờ", "GMT+7")]
    [InlineData("máy chấm công đầy bộ nhớ", "xóa bớt")]
    public void Cau_hoi_cu_the_tra_dung_muc_trong_bai(string q, string expected)
    {
        var top = AiAssistantHelpCorpus.GuideAnswerHits(q)[0];
        Assert.Contains("#", top.StepId);
        Assert.Contains(expected, AiAssistantHelpCorpus.FormatForPrompt([top]));
    }

    [Fact]
    public void Tra_thang_chi_hien_huong_dan_khong_kem_so_lieu()
    {
        var ctx = "=== LỊCH LÀM HÔM NAY ===\nChưa có ca";
        const string q = "duyệt lịch làm việc ở đâu";
        var r = AiAssistantRuleBot.Build(q, ctx, AiAssistantHelpCorpus.GuideAnswerHits(q), [], [], includeFallback: false, guideQuestion: true);
        Assert.StartsWith("Duyệt lịch làm việc", r.Reply);
    }

    [Fact]
    public void Tu_khong_co_trong_tai_lieu_thi_khong_tra_thang()
    {
        Assert.Equal(0, AiAssistantHelpCorpus.DirectAnswerScore("cách kết nối máy chấm công với blockchain xyzabc"));
    }

    [Fact]
    public void Bai_kien_thuc_co_nguon_khong_gan_GUIDE_khong_con_markdown()
    {
        var kb = AiAssistantHelpCorpus.All.Where(c => c.Mode == AiAssistantKnowledge.Mode).ToList();
        Assert.True(kb.Count > 100, $"chỉ có {kb.Count} đoạn");
        Assert.All(AiAssistantKnowledge.Slugs, s => Assert.Contains(kb, c => c.StepId == s));
        Assert.All(kb, c =>
        {
            Assert.StartsWith("https://", c.SourceUrl);
            Assert.False(AiAssistantHelpCorpus.HasAppGuide(c), c.StepId);
            var text = AiAssistantHelpCorpus.FormatForPrompt([c]);
            Assert.DoesNotContain("[[GUIDE:", text);
            Assert.DoesNotContain("**", text);
            Assert.DoesNotContain("](/", text);
            Assert.DoesNotContain("/register", text);
        });
    }

    [Fact]
    public void So_lieu_phap_luat_dung_muc_hien_hanh_va_co_loi_nhac()
    {
        var bhxh = AiAssistantHelpCorpus.All.Where(c => c.StepId.StartsWith("hrm-cach-tinh-bhxh", StringComparison.Ordinal)).ToList();
        var text = AiAssistantHelpCorpus.FormatForPrompt(bhxh);
        Assert.Contains("50.600.000", text);
        Assert.DoesNotContain("46.800.000", text);
        Assert.All(bhxh, c => Assert.Equal(AiAssistantKnowledge.LegalNote, c.Tip));
    }

    [Theory]
    // Hỏi cách dùng / sự cố → trả lời nội bộ từ hướng dẫn, không gọi Gemini (kể cả câu có «tạo», «báo cáo», «nhập hàng»).
    [InlineData("Cách kết nối hóa đơn điện tử?")]
    [InlineData("Sao máy in bếp không in?")]
    [InlineData("Hướng dẫn chấm công mobile")]
    [InlineData("Cách tạo phiếu phạt?")]
    [InlineData("Cách xem báo cáo doanh thu?")]
    [InlineData("Hướng dẫn nhập hàng")]
    [InlineData("cach tao phieu ung luong")]
    [InlineData("Đặt bàn trước cho khách ở đâu?")]
    public void Cau_hoi_cach_dung_tra_loi_noi_bo(string q) => Assert.True(Guide(q), q);

    [Theory]
    // Lệnh cụ thể / câu hỏi số liệu → vẫn để agent (đọc báo cáo thật, dựng thẻ).
    [InlineData("Tạo phiếu phạt An 50k đi trễ")]
    [InlineData("Hướng dẫn giúp tôi tạo phiếu phạt An 50k")]
    [InlineData("Doanh thu tháng này thế nào?")]
    [InlineData("Tại sao lợi nhuận tháng này giảm?")]
    [InlineData("Báo giá cho chị Lan 10 thùng Coca")]
    [InlineData("Hôm nay ai đi trễ?")]
    public void Lenh_va_cau_hoi_so_lieu_van_qua_agent(string q) => Assert.False(Guide(q), q);

    [Fact]
    public void Bot_noi_bo_tra_loi_bang_huong_dan()
    {
        const string q = "nhân viên không chấm công được trên điện thoại";
        Assert.True(Guide(q), q);
        var r = AiAssistantRuleBot.Build(q, "", AiAssistantHelpCorpus.Search(q, topK: 4), [], [], includeFallback: false,
            guideQuestion: true);
        Assert.True(r.Matched);
        Assert.Contains("mobile", r.Reply, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Tu_vo_nghia_khong_keo_diem()
    {
        // «tôi có thể … không» không được làm bước bất kỳ vượt ngưỡng nạp tự động.
        Assert.All(AiAssistantHelpCorpus.SearchScored("tôi có thể làm được không", topK: 3),
            h => Assert.True(h.Score < AiAssistantHelpCorpus.ConfidentScore, $"{h.Chunk.StepId}: {h.Score}"));
        Assert.True(AiAssistantHelpCorpus.SearchScored("kết nối hóa đơn điện tử viettel", topK: 1)[0].Score
                    >= AiAssistantHelpCorpus.ConfidentScore);
    }

    [Fact]
    public void Moi_buoc_biet_khu_va_nhom_de_chi_duong()
    {
        Assert.All(AiAssistantHelpCorpus.All.Where(AiAssistantHelpCorpus.HasAppGuide), c =>
        {
            Assert.False(string.IsNullOrWhiteSpace(c.Area), c.StepId);
            Assert.StartsWith("Hướng dẫn ", c.Trail);
        });
        var stock = AiAssistantHelpCorpus.All.Single(c => c.StepId == "pos_inventory");
        Assert.Equal("Hướng dẫn POS › Kho hàng", stock.Trail);
        Assert.Contains("Mục hướng dẫn: Hướng dẫn POS › Kho hàng ›", AiAssistantHelpCorpus.FormatForPrompt([stock]));
    }

    [Fact]
    public void Noi_dung_gui_AI_theo_menu_hien_tai_va_kem_chu_thich_anh()
    {
        var text = AiAssistantHelpCorpus.FormatForPrompt(AiAssistantHelpCorpus.Search("cách tạo phiếu ứng lương", topK: 1));
        Assert.Contains("[[GUIDE:basic/advance]]", text);
        Assert.Contains("Tài chính nhân sự", text);
        Assert.Contains("Trên màn hình:", text);
    }

    [Theory]
    // Thử trên C20 03/11/2026: bài hóa đơn điện tử đứng đầu vì «in» khớp chuỗi con, «hóa đơn» trùng tiêu đề.
    [InlineData("Lam sao de ket noi may in hoa don qua LAN?")]
    [InlineData("Cách kết nối máy in hóa đơn qua LAN")]
    public void May_in_hoa_don_ra_bai_may_in_khong_ra_hddt(string query)
    {
        Assert.Equal("pos_printers", AiAssistantHelpCorpus.Search(query, topK: 4)[0].StepId);
        Assert.Equal(["pos_printers"], AiAssistantHelpCorpus.GuideAnswerHits(query).Select(h => h.StepId));
    }

    [Fact]
    public void Y_con_trong_huong_dan_thut_le_khong_lap_dau_cham()
    {
        var hit = AiAssistantHelpCorpus.All.Single(c => c.StepId == "pos_einvoice");
        var text = AiAssistantRuleBot.Build("cach xuat hoa don dien tu", "", [hit], [], [], includeFallback: false, guideQuestion: true).Reply;
        Assert.DoesNotContain("• •", text);
        Assert.Contains("   – Viettel", text);
    }

    [Theory]
    // Rà soát 03/11/2026: các câu này từng ra bài karaoke, gym, «Đơn vị tính & bảng giá», kiểm tra tồn kho.
    [InlineData("cách tạo khuyến mãi giờ vàng", "pos_promotions")]
    [InlineData("cach tao ma giam gia voucher", "pos_vouchers")]
    [InlineData("cach chuyen kho giua chi nhanh", "pos_stock_transfer")]
    [InlineData("làm sao đặt hàng nhà cung cấp khi sắp hết hàng", "pos_reorder_purchase")]
    [InlineData("gia hạn gói ở đâu", "sys_service_package")]
    [InlineData("bảng giá phần mềm sbox", "sys_service_package")]
    [InlineData("cách chuyển bàn cho khách", "pos_table_transfer_merge_split")]
    [InlineData("tach hoa don cho khach tra rieng", "pos_table_transfer_merge_split")]
    [InlineData("cài đặt thuế VAT khi bán", "pos_sell_vat")]
    [InlineData("kết nối cân điện tử", "pos_scale")]
    // «can» (cân) / «ban» (bàn) trùng từ dừng «cần» / «bạn» — thử trên C20 ra bài hóa đơn điện tử.
    [InlineData("lam sao ket noi can dien tu", "pos_scale")]
    [InlineData("chuyen ban cho khach", "pos_table_transfer_merge_split")]
    [InlineData("in tem mã vạch cho hàng hóa", "pos_barcode_labels")]
    [InlineData("mất mạng có bán được không", "pos_offline_sale")]
    [InlineData("xem báo cáo chi nhánh", "pos_branch_report")]
    [InlineData("nhập hàng hóa từ file excel", "sys_excel_import_export")]
    [InlineData("đổi mật khẩu", "sys_change_forgot_password")]
    [InlineData("quên mật khẩu đăng nhập", "sys_change_forgot_password")]
    [InlineData("đổi ngôn ngữ sang tiếng anh", "sys_change_language")]
    [InlineData("phân quyền tài khoản thu ngân", "sys_roles_accounts")]
    [InlineData("xóa dữ liệu bán thử", "sys_reset_trial_data")]
    [InlineData("đăng nhập trên nhiều thiết bị", "sys_multi_device_login")]
    [InlineData("tham số hệ thống giờ chốt ngày", "sys_system_params")]
    [InlineData("đặt lịch tập cho hội viên pt", "pos_gym_trainer_checkin")]
    // Câu thường gặp từng ra bài sai vì bài dài có nhiều dòng trùng chữ.
    [InlineData("tạo phòng ban mới", "org_structure")]
    [InlineData("lập phiếu chi", "pos_cash_book")]
    [InlineData("hướng dẫn bán hàng", "pos_sales")]
    [InlineData("cách tính tiền cho khách", "pos_sale_pay")]
    [InlineData("thiết lập kpi", "kpi")]
    public void Chuc_nang_chua_co_trong_huong_dan_app_van_tra_dung_bai(string query, string stepId) =>
        Assert.Equal(stepId, AiAssistantHelpCorpus.Search(query, topK: 4)[0].StepId);

    [Fact]
    public void Bai_chi_co_o_may_chu_khong_gan_the_GUIDE()
    {
        var hit = AiAssistantHelpCorpus.All.Single(c => c.StepId == "pos_promotions");
        Assert.False(AiAssistantHelpCorpus.HasAppGuide(hit));
        Assert.DoesNotContain("[[GUIDE:", AiAssistantHelpCorpus.FormatForPrompt([hit]));
        Assert.DoesNotContain("[[GUIDE:",
            AiAssistantRuleBot.Build("cach tao khuyen mai", "", [hit], [], [], includeFallback: false, guideQuestion: true).Reply);
    }
}
