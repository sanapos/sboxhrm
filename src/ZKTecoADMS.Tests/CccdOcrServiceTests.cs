using System.Text;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Tests;

/// <summary>Đọc chữ trên căn cước công dân (văn bản do OCR trên máy gửi lên).</summary>
public class CccdOcrServiceTests
{
    private static readonly CccdOcrService Svc = new(NullLogger<CccdOcrService>.Instance);

    private static string Front(string name, string sexLine, string idNumber = "079090001234") => string.Join("\n",
        "CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM",
        "Độc lập - Tự do - Hạnh phúc",
        "CĂN CƯỚC CÔNG DÂN",
        $"Số / No.: {idNumber}",
        "Họ và tên / Full name:",
        name,
        "Ngày sinh / Date of birth: 15/03/1990",
        sexLine,
        "Quê quán / Place of origin:",
        "Hà Nam",
        "Nơi thường trú / Place of residence:",
        "12 Lê Lợi, Quận 1, TP Hồ Chí Minh",
        "Có giá trị đến: 15/03/2030");

    [Fact]
    public void Front_Standard_ReadsAllFields()
    {
        var r = Svc.ParseCccdText(Front("NGUYỄN VĂN AN", "Giới tính / Sex: Nam"));
        Assert.True(r.IsSuccess);
        Assert.Equal("079090001234", r.IdNumber);
        Assert.Equal("NGUYỄN VĂN AN", r.FullName);
        Assert.Equal(new DateTime(1990, 3, 15), r.DateOfBirth);
        Assert.Equal("Nam", r.Gender);
        Assert.Equal(new DateTime(2030, 3, 15), r.ExpiryDate);
    }

    [Theory]
    [InlineData("NGUYỄN QUỐC ANH")]   // «QUỐC» trùng tên một trường trên thẻ
    [InlineData("LÊ THỊ NGỌC HÀ")]
    [InlineData("TRẦN HỌC LỘC")]
    [InlineData("PHẠM NGÀY MAI")]
    [InlineData("ĐẶNG GIỚI THIỆU")]
    public void Front_NameContainingFieldWords_IsStillTheName(string name)
    {
        var r = Svc.ParseCccdText(Front(name, "Giới tính / Sex: Nam"));
        Assert.Equal(name, r.FullName);
    }

    [Theory]
    [InlineData("Giới tính / Sex: Nam   Quốc tịch / Nationality: Việt Nam", "Nam")]
    [InlineData("Giới tính / Sex: Nữ   Quốc tịch / Nationality: Việt Nam", "Nữ")]     // «NAM» trong «VIỆT NAM» không được làm thành Nam
    [InlineData("Giới tính / Sex: Nữ", "Nữ")]
    [InlineData("Giới tính / Sex: Nam", "Nam")]
    [InlineData("GIỚI TÍNH: NỮ QUỐC TỊCH: VIỆT NAM", "Nữ")]
    public void Front_Gender_IsReadFromTheSexFieldOnly(string line, string expected)
    {
        var r = Svc.ParseCccdText(Front("NGUYỄN THỊ HOA", line));
        Assert.Equal(expected, r.Gender);
    }

    [Fact]
    public void Front_Nationality_OnSameLineAsSex_IsJustTheCountry()
    {
        var r = Svc.ParseCccdText(Front("NGUYỄN THỊ HOA", "Giới tính / Sex: Nữ   Quốc tịch / Nationality: Việt Nam"));
        Assert.Equal("VIỆT NAM", r.Nationality?.ToUpperInvariant());
    }

    [Fact]
    public void Gender_Missing_IsNotGuessed()
    {
        var r = Svc.ParseCccdText("Họ và tên: NGUYỄN VĂN AN\nSố: 079090001234");
        Assert.True(string.IsNullOrEmpty(r.Gender));
    }

    [Fact]
    public void DecomposedUnicode_FromOcr_IsRecognised()
    {
        var text = Front("NGUYỄN VĂN AN", "Giới tính / Sex: Nam").Normalize(NormalizationForm.FormD);
        var r = Svc.ParseCccdText(text);
        Assert.Equal("NGUYỄN VĂN AN", r.FullName?.Normalize(NormalizationForm.FormC));
        Assert.Equal(new DateTime(1990, 3, 15), r.DateOfBirth);
    }

    [Fact]
    public void Back_IssueDateAndPlace_AreRead()
    {
        var back = string.Join("\n",
            "Đặc điểm nhân dạng / Personal identification:",
            "Sẹo chấm C: 2cm trên sau cánh mũi phải",
            "Ngày, tháng, năm / Date, month, year: 15/03/2021",
            "CỤC TRƯỞNG CỤC CẢNH SÁT QUẢN LÝ HÀNH CHÍNH VỀ TRẬT TỰ XÃ HỘI");
        var r = Svc.ParseCccdText(back);
        Assert.Equal(new DateTime(2021, 3, 15), r.IssueDate);
    }

    [Fact]
    public void Empty_Text_IsRejected()
    {
        Assert.False(Svc.ParseCccdText("   ").IsSuccess);
    }

    [Fact]
    public void IdNumber_Prefers12Digits_AndIgnoresPhoneNumbers()
    {
        var r = Svc.ParseCccdText("Số: 079090001234\nĐiện thoại: 0912345678");
        Assert.Equal("079090001234", r.IdNumber);
    }

    [Theory]
    [InlineData("Ngày sinh: 01012000", 2000, 1, 1)]
    [InlineData("Ngày sinh: 1/2/1985", 1985, 2, 1)]
    [InlineData("Ngày sinh: 31.12.1999", 1999, 12, 31)]
    public void DateFormats(string line, int y, int m, int d)
    {
        var r = Svc.ParseCccdText("Họ và tên: AN\n" + line);
        Assert.Equal(new DateTime(y, m, d), r.DateOfBirth);
    }
}
