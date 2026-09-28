using System.IO.Compression;
using System.Text;
using ClosedXML.Excel;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Tests;

/// <summary>Truyền thông v2: đọc tài liệu cho AI, đối tượng nhận, kênh mặc định, đăng hẹn giờ, lọc HTML.</summary>
public class CommunicationV2Tests
{
    private static byte[] Docx(string bodyXml)
    {
        using var ms = new MemoryStream();
        using (var zip = new ZipArchive(ms, ZipArchiveMode.Create, true))
        {
            using var w = new StreamWriter(zip.CreateEntry("word/document.xml").Open(), new UTF8Encoding(false));
            w.Write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>"
                    + bodyXml + "</w:body></w:document>");
        }
        return ms.ToArray();
    }

    [Fact]
    public void Reads_word_with_headings_lists_and_tables()
    {
        var data = Docx(
            "<w:p><w:pPr><w:pStyle w:val=\"Heading1\"/></w:pPr><w:r><w:t>Quy định chấm công</w:t></w:r></w:p>" +
            "<w:p><w:r><w:t xml:space=\"preserve\">Đi trễ quá </w:t></w:r><w:r><w:t>15 phút tính nửa công.</w:t></w:r></w:p>" +
            "<w:p><w:pPr><w:numPr/></w:pPr><w:r><w:t>Xin nghỉ trước 48 giờ</w:t></w:r></w:p>" +
            "<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Lỗi</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Mức phạt</w:t></w:r></w:p></w:tc></w:tr></w:tbl>");
        Assert.True(CommDocumentReader.MagicMatches(data, "a.docx"));
        var doc = CommDocumentReader.Read(data, "Quy dinh.docx");
        Assert.Equal("word", doc.Kind);
        Assert.Null(doc.Warning);
        Assert.Contains("# Quy định chấm công", doc.Text);
        Assert.Contains("Đi trễ quá 15 phút tính nửa công.", doc.Text);
        Assert.Contains("- Xin nghỉ trước 48 giờ", doc.Text);
        Assert.Contains("| Lỗi | Mức phạt |", doc.Text);
    }

    [Fact]
    public void Reads_excel_sheets_as_tables()
    {
        using var wb = new XLWorkbook();
        var ws = wb.AddWorksheet("Phụ cấp");
        ws.Cell(1, 1).Value = "Chức danh";
        ws.Cell(1, 2).Value = "Phụ cấp";
        ws.Cell(2, 1).Value = "Trưởng ca";
        ws.Cell(2, 2).Value = 500000;
        using var ms = new MemoryStream();
        wb.SaveAs(ms);
        var doc = CommDocumentReader.Read(ms.ToArray(), "phu-cap.xlsx");
        Assert.Contains("## Sheet: Phụ cấp", doc.Text);
        Assert.Contains("| Trưởng ca | 500000 |", doc.Text);
    }

    [Fact]
    public void Pdf_and_images_go_to_ai_inline_and_old_formats_warn()
    {
        var pdf = Encoding.ASCII.GetBytes("%PDF-1.4\n...");
        var d = CommDocumentReader.Read(pdf, "a.pdf");
        Assert.NotNull(d.FilePart);
        Assert.Equal("application/pdf", d.FilePart!.MimeType);
        Assert.Null(d.Text);

        var old = CommDocumentReader.Read(new byte[] { 0xD0, 0xCF, 0x11, 0xE0, 1, 2 }, "cu.doc");
        Assert.Null(old.Text);
        Assert.NotNull(old.Warning);

        // Đổi đuôi .pdf cho file không phải PDF → bị chặn.
        Assert.False(CommDocumentReader.MagicMatches(Encoding.ASCII.GetBytes("MZ-not-a-pdf"), "x.pdf"));
        Assert.False(CommDocumentReader.MagicMatches(Encoding.ASCII.GetBytes("hello"), "x.exe"));
    }

    [Fact]
    public void Broken_office_file_returns_warning_not_exception()
    {
        var bad = new byte[] { 0x50, 0x4B, 0x03, 0x04, 9, 9, 9 };
        var d = CommDocumentReader.Read(bad, "hong.docx");
        Assert.Null(d.Text);
        Assert.NotNull(d.Warning);
    }

    [Fact]
    public void Audience_matching()
    {
        var branch = Guid.NewGuid();
        var dept = Guid.NewGuid();
        var emp = Guid.NewGuid();
        var staff = new CommViewer(Guid.NewGuid(), emp, branch, dept, "Thu ngân", false, "A");
        Assert.True(CommV2Helper.Matches(new CommAudience(), null, staff));
        Assert.True(CommV2Helper.Matches(new CommAudience { All = false, BranchIds = { branch } }, null, staff));
        Assert.True(CommV2Helper.Matches(new CommAudience { All = false, Positions = { " thu ngân " } }, null, staff));
        Assert.False(CommV2Helper.Matches(new CommAudience { All = false, DepartmentIds = { Guid.NewGuid() } }, null, staff));
        // Kênh riêng chi nhánh khác → không thấy dù bài gửi mọi người.
        Assert.False(CommV2Helper.Matches(new CommAudience(), new CommChannel { BranchId = Guid.NewGuid() }, staff));
        Assert.True(CommV2Helper.Matches(new CommAudience { All = false, EmployeeIds = { Guid.NewGuid() } }, null, staff with { IsManager = true }));
    }

    [Fact]
    public void Sanitizes_dangerous_html()
    {
        var html = "<h2 onclick=\"x()\">Tiêu đề</h2><script>alert(1)</script><p><a href=\"javascript:alert(1)\">bấm</a></p><iframe src=\"//x\"></iframe><img src=x onerror=alert(1)>";
        var s = CommV2Helper.SanitizeHtml(html);
        Assert.DoesNotContain("script", s, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("onclick", s, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("onerror", s, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("javascript:", s, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("iframe", s, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("Tiêu đề", s);
        Assert.Equal("Tiêu đề\nbấm", CommV2Helper.HtmlToText("<h2>Tiêu đề</h2><p>bấm</p>").Trim());
    }

    private static ServiceProvider Provider()
    {
        var services = new ServiceCollection();
        services.AddDbContext<ZKTecoDbContext>(o => o
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking));
        return services.BuildServiceProvider();
    }

    [Fact]
    public async Task Default_channels_seeded_once_and_legacy_posts_mapped_by_type()
    {
        using var sp = Provider();
        using var scope = sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var store = Guid.NewGuid();
        db.InternalCommunications.AddRange(
            new InternalCommunication { Id = Guid.NewGuid(), StoreId = store, Title = "Nội quy", Content = "x", Type = CommunicationType.Regulation, AuthorId = Guid.NewGuid() },
            new InternalCommunication { Id = Guid.NewGuid(), StoreId = store, Title = "Tin", Content = "y", Type = CommunicationType.News, AuthorId = Guid.NewGuid() });
        await db.SaveChangesAsync();

        var channels = await CommV2Helper.EnsureChannelsAsync(db, store, "t");
        Assert.Equal(CommV2Helper.Defaults.Length, channels.Count);
        var again = await CommV2Helper.EnsureChannelsAsync(db, store, "t");
        Assert.Equal(channels.Count, again.Count);

        var posts = await db.InternalCommunications.ToListAsync();
        Assert.Equal(channels.First(c => c.Key == "policy").Id, posts.First(p => p.Title == "Nội quy").ChannelId);
        Assert.Equal(channels.First(c => c.Key == "feed").Id, posts.First(p => p.Title == "Tin").ChannelId);
    }

    [Fact]
    public async Task Scheduled_posts_publish_when_due()
    {
        using var sp = Provider();
        using var scope = sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var store = Guid.NewGuid();
        var now = DateTime.UtcNow;
        var due = new InternalCommunication { Id = Guid.NewGuid(), StoreId = store, Title = "Đến giờ", Content = "a", AuthorId = Guid.NewGuid(), Status = CommunicationStatus.Scheduled, ScheduledAt = now.AddMinutes(-1) };
        var later = new InternalCommunication { Id = Guid.NewGuid(), StoreId = store, Title = "Chưa", Content = "b", AuthorId = Guid.NewGuid(), Status = CommunicationStatus.Scheduled, ScheduledAt = now.AddHours(2) };
        db.InternalCommunications.AddRange(due, later);
        await db.SaveChangesAsync();

        var n = await CommScheduleBackgroundService.PublishDueAsync(db, null, now, CancellationToken.None);
        Assert.Equal(1, n);
        var list = await db.InternalCommunications.ToListAsync();
        Assert.Equal(CommunicationStatus.Published, list.First(p => p.Id == due.Id).Status);
        Assert.NotNull(list.First(p => p.Id == due.Id).PublishedAt);
        Assert.Equal(CommunicationStatus.Scheduled, list.First(p => p.Id == later.Id).Status);
    }

    [Fact]
    public async Task Audience_employees_filter_by_branch_position_and_skip_resigned()
    {
        using var sp = Provider();
        using var scope = sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var store = Guid.NewGuid();
        var b1 = Guid.NewGuid();
        db.Employees.AddRange(
            new Employee { Id = Guid.NewGuid(), StoreId = store, FirstName = "An", LastName = "Lê", BranchId = b1 },
            new Employee { Id = Guid.NewGuid(), StoreId = store, FirstName = "Bình", LastName = "Trần", Position = "Bếp trưởng" },
            new Employee { Id = Guid.NewGuid(), StoreId = store, FirstName = "Cường", LastName = "Phạm", BranchId = b1, WorkStatus = EmployeeWorkStatus.Resigned },
            new Employee { Id = Guid.NewGuid(), StoreId = Guid.NewGuid(), FirstName = "X", LastName = "Y", BranchId = b1 });
        await db.SaveChangesAsync();
        var all = await CommV2Helper.AudienceEmployeesAsync(db, store, new CommAudience(), null);
        Assert.Equal(2, all.Count);
        var branch = await CommV2Helper.AudienceEmployeesAsync(db, store, new CommAudience { All = false, BranchIds = { b1 } }, null);
        Assert.Single(branch);
        var pos = await CommV2Helper.AudienceEmployeesAsync(db, store, new CommAudience { All = false, Positions = { "bếp trưởng" } }, null);
        Assert.Equal("Trần Bình", pos.Single().Name);
    }
}
