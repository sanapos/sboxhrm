using Xunit;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests;

/// <summary>
/// Nút «Kiểm tra khóa»: không được chờ lại model đang quá tải cho từng khóa, và phải nói rõ
/// «đang hết lượt» / «Google quá tải» thay vì «không khóa nào dùng được».
/// </summary>
public class GeminiKeyTesterTests
{
    static GeminiKeyTester.KeyResult R(int i, string status) => new(i, $"AIza****000{i}", status, status);

    [Fact]
    public void Model_dang_qua_tai_xep_cuoi_va_khong_lap_lai()
    {
        var cfg = new GeminiConfig { Model = GeminiModels.Flash };

        // Model đã chọn trùng model dự phòng → chỉ còn mỗi model một lần.
        Assert.Equal([GeminiModels.Flash, GeminiModels.FlashLite], GeminiKeyTester.Models(cfg));

        // 14/11/2026: flash quá tải, 3 khóa chạy nối tiếp mỗi khóa chờ lại flash 20–45 giây → nút treo quá 4 phút.
        GeminiKeyPool.MarkModelOverloaded(GeminiModels.Flash, TimeSpan.FromSeconds(30));
        try
        {
            Assert.Equal([GeminiModels.FlashLite, GeminiModels.Flash], GeminiKeyTester.Models(cfg));
        }
        finally
        {
            GeminiKeyPool.MarkModelOverloaded(GeminiModels.Flash, TimeSpan.Zero);
        }
    }

    [Fact]
    public void Tom_tat_noi_ro_het_luot_hay_qua_tai()
    {
        Assert.StartsWith("2/3 khóa hoạt động", GeminiKeyTester.Summary(
            [R(1, "ok"), R(2, "ok"), R(3, "invalid")]));

        // Khóa đúng nhưng hết lượt: trước đây báo «không khóa nào dùng được» làm người dùng tưởng nhập sai khóa.
        Assert.Contains("đang hết lượt", GeminiKeyTester.Summary([R(1, "quota"), R(2, "invalid")]));

        Assert.Contains("Google đang quá tải", GeminiKeyTester.Summary([R(1, "timeout"), R(2, "timeout")]));

        Assert.Contains("Không khóa nào dùng được", GeminiKeyTester.Summary([R(1, "invalid")]));
    }

    [Fact]
    public void Ngan_sach_phai_duoi_gioi_han_60_giay_cua_nginx()
    {
        // nginx production cắt /api/ ở 60 giây — nút kiểm tra phải trả lời trước đó, kể cả khi Google treo.
        Assert.InRange(GeminiKeyTester.Budget.TotalSeconds, 10, 55);
        // Mỗi model phải bỏ sớm hơn ngân sách chung, nếu không model treo sẽ ăn hết giờ và model dự phòng
        // (vẫn trả lời trong 1–2 giây) không bao giờ được thử.
        var cfg = new GeminiConfig { Model = GeminiModels.Flash };
        Assert.True(GeminiKeyTester.AttemptTimeout * GeminiKeyTester.Models(cfg).Count < GeminiKeyTester.Budget);
    }
}
