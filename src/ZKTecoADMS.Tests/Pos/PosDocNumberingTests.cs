using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Mẫu đánh số báo giá / hợp đồng: kiểm mẫu, tách phần chữ quanh {SEQ}, số kế tiếp.</summary>
public class PosDocNumberingTests
{
    static readonly DateTime Day = new(2026, 11, 2);

    [Fact]
    public void Mau_mac_dinh_ra_dung_so_cu()
    {
        Assert.Equal("BG{DD}{MM}{YYYY}{SEQ:4}", PosDocNumbering.DefaultPattern(PosQuoteDocumentKind.Quote));
        Assert.Equal("HDKT{DD}{MM}{YYYY}{SEQ:4}", PosDocNumbering.DefaultPattern(PosQuoteDocumentKind.Contract));
        var (p, s, d) = PosDocNumbering.Split("BG{DD}{MM}{YYYY}{SEQ:4}", Day);
        Assert.Equal(("BG02112026", "", 4), (p, s, d));
        Assert.Equal("BG021120260008",
            PosDocNumbering.NextFrom(p, s, d, ["BG021120260007", "BG021120260003", "BG011120260099"]));
    }

    [Fact]
    public void Seq_o_dau_va_phan_duoi_co_dinh()
    {
        var (p, s, d) = PosDocNumbering.Split("{SEQ:3}/{YYYY}/HĐKT-SANA", Day);
        Assert.Equal(("", "/2026/HĐKT-SANA", 3), (p, s, d));
        Assert.Equal("001/2026/HĐKT-SANA", PosDocNumbering.NextFrom(p, s, d, []));
        Assert.Equal("013/2026/HĐKT-SANA",
            PosDocNumbering.NextFrom(p, s, d, ["012/2026/HĐKT-SANA", "099/2025/HĐKT-SANA", "abc/2026/HĐKT-SANA"]));
    }

    [Fact]
    public void Doi_mau_khong_lam_so_nhay_vot_theo_so_cu()
    {
        // Mẫu mới không có ngày: số cũ BG021120260007 không được hiểu là thứ tự 21120260007.
        Assert.Equal("BG0001", PosDocNumbering.NextFrom("BG", "", 4, ["BG021120260007"]));
        // Vượt 9999 vẫn nối tiếp
        Assert.Equal("BG10000", PosDocNumbering.NextFrom("BG", "", 4, ["BG9999"]));
        Assert.Equal("BG10001", PosDocNumbering.NextFrom("BG", "", 4, ["BG9999", "BG10000"]));
    }

    [Fact]
    public void Ky_hieu_nam_thang_ngay()
    {
        var (p, s, _) = PosDocNumbering.Split("HĐ{YY}{MM}-{SEQ}-{DD}", Day);
        Assert.Equal(("HĐ2611-", "-02"), (p, s));
        Assert.Equal(4, PosDocNumbering.Split("X{seq}", Day).Digits);
    }

    [Theory]
    [InlineData("BG{DD}{MM}{YYYY}{SEQ:4}", null)]
    [InlineData("{SEQ}", null)]
    [InlineData("BG-{YYYY}", "đúng một {SEQ}")]
    [InlineData("{SEQ}{SEQ}", "đúng một {SEQ}")]
    [InlineData("BG{NAM}{SEQ}", "Không hiểu {NAM}")]
    [InlineData("BG{SEQ:0}", "n từ 1 đến 9")]
    [InlineData("BG{SEQ}}", "Dấu { }")]
    [InlineData("", "trống")]
    [InlineData("CONG-TY-TNHH-NOI-THAT-{YYYY}-{SEQ:6}", "dài quá")]
    public void Kiem_mau(string pattern, string? error)
    {
        var err = PosDocNumbering.Validate(pattern);
        if (error == null) Assert.Null(err);
        else Assert.Contains(error, err);
    }

    [Fact]
    public void Doc_thiet_lap_tu_ExtraJson()
    {
        const string json = """
            {"debt":{"termDays":30},
             "docNumbering":{"quote":{"manual":true,"pattern":"BG-{YYYY}-{SEQ:3}"},"contract":{"pattern":"{SEQ"}}}
            """;
        Assert.Equal(new PosDocNumbering.Rule(true, "BG-{YYYY}-{SEQ:3}"),
            PosDocNumbering.Parse(json, PosQuoteDocumentKind.Quote));
        // Mẫu hỏng → về mặc định, vẫn tự nhảy
        Assert.Equal(new PosDocNumbering.Rule(false, "HDKT{DD}{MM}{YYYY}{SEQ:4}"),
            PosDocNumbering.Parse(json, PosQuoteDocumentKind.Contract));
        // Loại chứng từ khác không theo thiết lập
        Assert.Equal(new PosDocNumbering.Rule(false, "BB{DD}{MM}{YYYY}{SEQ:4}"),
            PosDocNumbering.Parse(json, PosQuoteDocumentKind.Handover));
        Assert.False(PosDocNumbering.Parse(null, PosQuoteDocumentKind.Quote).Manual);
        Assert.False(PosDocNumbering.Parse("không phải json", PosQuoteDocumentKind.Quote).Manual);
    }
}
