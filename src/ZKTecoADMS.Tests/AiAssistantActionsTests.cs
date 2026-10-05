using Xunit;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Tests;

/// <summary>Trợ lý ảo thêm / sửa chứng từ: đọc số tiền theo lời nói, nhận câu ra lệnh, tệp âm thanh đọc.</summary>
public class AiAssistantActionsTests
{
    [Theory]
    [InlineData("500000", 500000)]
    [InlineData("500.000", 500000)]
    [InlineData("1.500.000", 1500000)]
    [InlineData("500k", 500000)]
    [InlineData("2 triệu", 2000000)]
    [InlineData("1,5 triệu", 1500000)]
    [InlineData("1tr2", 1200000)]
    [InlineData("350 nghìn", 350000)]
    [InlineData("1500000.0", 1500000)]
    public void Doc_so_tien_theo_cach_noi(string raw, decimal expected) =>
        Assert.Equal(expected, AiAssistantActions.ParseMoney(raw));

    [Theory]
    [InlineData("Phạt An 50k vì đi trễ", true)]
    [InlineData("Tạo phiếu chi 350k tiền điện", true)]
    [InlineData("Cho Châu ứng 2 triệu", true)]
    [InlineData("Bán 2 Coca cho khách lẻ", true)]
    [InlineData("Doanh thu hôm nay bao nhiêu?", false)]
    [InlineData("Tôi còn bao nhiêu ngày phép?", false)]
    public void Nhan_cau_ra_lenh_them_sua(string q, bool expected) =>
        Assert.Equal(expected, AiAssistantAgent.LooksLikeWrite(q));

    [Fact]
    public void Dong_goi_wav_dung_header()
    {
        var wav = AiVoiceService.Wav(new byte[480], 24000);
        Assert.Equal(44 + 480, wav.Length);
        Assert.Equal("RIFF", System.Text.Encoding.ASCII.GetString(wav, 0, 4));
        Assert.Equal("WAVE", System.Text.Encoding.ASCII.GetString(wav, 8, 4));
        Assert.Equal(24000, BitConverter.ToInt32(wav, 24));
    }
}
