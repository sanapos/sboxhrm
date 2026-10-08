using Microsoft.EntityFrameworkCore;
using Xunit;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Tests.Pos;

/// <summary>Chứng từ báo giá / hợp đồng / nghiệm thu / đề nghị thanh toán lấy đúng dữ liệu thật.</summary>
[Collection("pos-pg")]
public class PosQuoteDocumentTests(PosPgFixture fx) : PosFlowTestBase(fx)
{
    async Task<(Guid Store, Guid Quote)> SeedAsync(bool withStages, bool withCompany = true, decimal paid = 0)
    {
        var store = await Fx.NewStoreAsync();
        await using var db = Fx.NewDb();
        db.PosStoreCommercialProfiles.Add(new PosStoreCommercialProfile
        {
            Id = Guid.NewGuid(), StoreId = store, CompanyName = "CÔNG TY TNHH NỘI THẤT SANA", TaxCode = "0401234567",
            Address = "184 Nam Cao, Đà Nẵng", Phone = "0973024042", BankAccountNumber = "0041000123456", BankName = "Vietcombank",
            LegalRepresentative = "Nguyễn Văn An", LegalTitle = "Giám đốc",
            WarrantyPolicy = "Bảo hành 24 tháng phần khung", DefaultTerms = "Giá gồm vận chuyển nội thành.", IsActive = true,
        });
        var cust = new PosCustomer
        {
            Id = Guid.NewGuid(), StoreId = store, Name = "Trần Thị Bình", Phone = "0905111222",
            CompanyName = withCompany ? "CÔNG TY CP XÂY DỰNG MIỀN TRUNG" : null, TaxCode = withCompany ? "0409876543" : null,
            IsActive = true,
        };
        db.PosCustomers.Add(cust);
        var q = new PosQuote
        {
            Id = Guid.NewGuid(), StoreId = store, QuoteNo = "BG0007", CustomerId = cust.Id, CustomerName = "Trần Thị Bình",
            CustomerAddress = "12 Lê Duẩn, Đà Nẵng", SubTotal = 98_000_000, Discount = 2_000_000, VatMode = "added", VatPercent = 8,
            VatAmount = 7_680_000, Total = 103_680_000, DepositPercent = 30, DepositAmount = 28_800_000,
            ContractNo = "HĐ 25/2026/SANA", ContractSignedAt = new DateTime(2026, 10, 1, 17, 0, 0, DateTimeKind.Utc),
            HandoverDueAt = new DateTime(2026, 10, 24, 17, 0, 0, DateTimeKind.Utc), IsActive = true,
        };
        q.Lines.Add(new PosQuoteLine { Id = Guid.NewGuid(), StoreId = store, ProductName = "Tủ bếp", UnitName = "md", Qty = 4.5m, UnitPrice = 9_500_000, LineTotal = 42_750_000, WarrantyMonths = 24, SortOrder = 1, IsActive = true });
        q.Lines.Add(new PosQuoteLine { Id = Guid.NewGuid(), StoreId = store, ProductName = "Lắp đặt", UnitName = "gói", Qty = 1, UnitPrice = 55_250_000, LineTotal = 55_250_000, SortOrder = 2, IsActive = true });
        if (withStages)
        {
            q.PaymentStages.Add(new PosQuotePaymentStage { Id = Guid.NewGuid(), StoreId = store, Title = "Đặt cọc ký hợp đồng", Percent = 30, Amount = 0, SortOrder = 1, IsActive = true });
            q.PaymentStages.Add(new PosQuotePaymentStage { Id = Guid.NewGuid(), StoreId = store, Title = "Giao hàng", Percent = 50, SortOrder = 2, IsActive = true });
            q.PaymentStages.Add(new PosQuotePaymentStage { Id = Guid.NewGuid(), StoreId = store, Title = "Nghiệm thu bàn giao", Percent = 20, SortOrder = 3, IsActive = true });
        }
        if (paid > 0)
            q.Payments.Add(new PosQuotePayment { Id = Guid.NewGuid(), StoreId = store, Amount = paid, IsActive = true });
        db.PosQuotes.Add(q);
        await db.SaveChangesAsync();
        return (store, q.Id);
    }

    async Task<string> HtmlAsync(Guid quoteId, PosQuoteDocumentKind kind, string? dumpName = null)
    {
        await using var db = Fx.NewDb();
        var quote = await db.PosQuotes.Include(x => x.Lines).FirstAsync(x => x.Id == quoteId);
        var html = await PosQuoteDocumentHtml.BuildAsync(db, quote, kind, "DOC01", null);
        var dumpDir = Environment.GetEnvironmentVariable("SBOX_DOC_DUMP");
        if (!string.IsNullOrEmpty(dumpDir))
        {
            Directory.CreateDirectory(dumpDir);
            await File.WriteAllTextAsync(Path.Combine(dumpDir, (dumpName ?? kind.ToString()) + ".html"), html);
        }
        return html;
    }

    [Fact]
    public async Task Hop_dong_dung_so_HD_ngay_ky_cac_dot_thanh_toan_va_bao_hanh()
    {
        if (NoDb) return;
        var (_, q) = await SeedAsync(withStages: true);
        var html = await HtmlAsync(q, PosQuoteDocumentKind.Contract);
        Assert.Contains("HĐ 25/2026/SANA", html);
        Assert.Contains("ngày 02 tháng 10 năm 2026", html);       // ký 01/10 17:00 UTC = 02/10 giờ VN
        Assert.Contains("Đặt cọc ký hợp đồng", html);
        Assert.Contains("31.104.000", html);                       // 30% × 103.680.000
        Assert.Contains("51.840.000", html);
        Assert.DoesNotContain("50% —", html);
        Assert.Contains("hoàn thành trước ngày 25/10/2026", html);
        Assert.Contains("Bảo hành 24 tháng phần khung", html);
        Assert.Contains("Giá gồm vận chuyển nội thành.", html);
        Assert.Contains("Giá đã cộng thuế GTGT 8%", html);
        Assert.DoesNotContain("<!--IF", html);
        Assert.DoesNotContain("{", html.Replace("{{", "")[(html.IndexOf("<body", StringComparison.Ordinal))..]);
    }

    [Fact]
    public async Task Bao_gia_khong_tu_gan_coc_50_va_an_dong_trong()
    {
        if (NoDb) return;
        var (_, q) = await SeedAsync(withStages: false, withCompany: false);
        await using (var db = Fx.NewDb())
        {
            var quote = await db.PosQuotes.AsTracking().FirstAsync(x => x.Id == q);
            quote.DepositAmount = 0;
            quote.DepositPercent = null;
            await db.SaveChangesAsync();
        }
        var html = await HtmlAsync(q, PosQuoteDocumentKind.Quote, "QuoteNoDeposit");
        Assert.DoesNotContain("Đặt cọc", html);
        Assert.DoesNotContain("MST: </", html);
        Assert.DoesNotContain("Tài khoản: —", html);
        Assert.Contains("Kính gửi:</b> Trần Thị Bình", html);
    }

    [Fact]
    public async Task De_nghi_thanh_toan_tru_so_da_thu_va_lay_dot_den_han()
    {
        if (NoDb) return;
        var (_, q) = await SeedAsync(withStages: true, paid: 31_104_000);
        var html = await HtmlAsync(q, PosQuoteDocumentKind.PaymentRequest);
        Assert.Contains("V/v: Giao hàng", html);
        Assert.Contains("<b>51.840.000 đ</b>", html);
        var acc = await HtmlAsync(q, PosQuoteDocumentKind.Acceptance);
        Assert.Contains("Căn cứ hợp đồng số <b>HĐ 25/2026/SANA</b>", acc);
        Assert.Contains("Còn phải thanh toán: <b>72.576.000 đ</b>", acc);
        await HtmlAsync(q, PosQuoteDocumentKind.Quote);
        await HtmlAsync(q, PosQuoteDocumentKind.Handover);
    }

    [Fact]
    public async Task Chung_tu_sua_rieng_giu_loi_van_bao_cu_khi_so_lieu_doi_va_bo_dau()
    {
        if (NoDb) return;
        var (store, q) = await SeedAsync(withStages: true);
        Guid docId;
        await using (var db = Fx.NewDb())
        {
            var quote = await db.PosQuotes.Include(x => x.Lines).FirstAsync(x => x.Id == q);
            var doc = new PosQuoteDocument
            {
                Id = Guid.NewGuid(), StoreId = store, QuoteId = q, Kind = PosQuoteDocumentKind.PaymentRequest, DocNo = "DN01",
                IsCustomWording = true, IsActive = true,
                HtmlContent = "<p>ĐỀ NGHỊ RIÊNG đợt 2</p><img data-sbox=\"stamp\" src=\"data:image/png;base64,AAAA\"/>",
                SourceHash = await PosQuoteDocumentHtml.SourceHashAsync(db, quote, PosQuoteDocumentKind.PaymentRequest, "DN01", null),
            };
            db.PosQuoteDocuments.Add(doc);
            await db.SaveChangesAsync();
            docId = doc.Id;
        }
        await using (var db = Fx.NewDb())
        {
            var quote = await db.PosQuotes.Include(x => x.Lines).FirstAsync(x => x.Id == q);
            var doc = await db.PosQuoteDocuments.FirstAsync(x => x.Id == docId);
            var (html, stale) = await PosQuoteDocumentHtml.RenderDocumentAsync(db, quote, doc);
            Assert.Contains("ĐỀ NGHỊ RIÊNG đợt 2", html);
            Assert.False(stale);
            var (noStamp, _) = await PosQuoteDocumentHtml.RenderDocumentAsync(db, quote, doc, includeStamp: false);
            Assert.DoesNotContain("data-sbox", noStamp);
        }
        await using (var db = Fx.NewDb())
        {
            // Thu thêm tiền → số liệu đổi → bản sửa riêng báo cũ (vẫn in lời văn đã sửa).
            db.Set<PosQuotePayment>().Add(new PosQuotePayment { Id = Guid.NewGuid(), StoreId = store, QuoteId = q, Amount = 31_104_000, IsActive = true });
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
        {
            var quote = await db.PosQuotes.Include(x => x.Lines).FirstAsync(x => x.Id == q);
            var doc = await db.PosQuoteDocuments.FirstAsync(x => x.Id == docId);
            var (html, stale) = await PosQuoteDocumentHtml.RenderDocumentAsync(db, quote, doc);
            Assert.True(stale);
            Assert.Contains("ĐỀ NGHỊ RIÊNG đợt 2", html);
        }
    }

    [Fact]
    public async Task Mau_chon_rieng_cho_chung_tu_khong_doi_mau_chung()
    {
        if (NoDb) return;
        var (store, q) = await SeedAsync(withStages: false);
        var own = Guid.NewGuid();
        await using (var db = Fx.NewDb())
        {
            db.PosPrintTemplates.Add(new PosPrintTemplate
            {
                Id = own, StoreId = store, Name = "HĐ mẫu riêng", DocumentType = PosPrintDocumentType.Contract,
                PaperSize = PosPrintPaperSize.A4, IsActive = true,
                HtmlContent = "<!--POS_A4_V9--><div>HỢP ĐỒNG MẪU RIÊNG {So_Hop_Dong}</div>",
            });
            db.PosPrintTemplates.Add(new PosPrintTemplate
            {
                Id = Guid.NewGuid(), StoreId = store, Name = "HĐ mẫu chung", DocumentType = PosPrintDocumentType.Contract,
                PaperSize = PosPrintPaperSize.A4, IsActive = true, IsDefault = true,
                HtmlContent = "<!--POS_A4_V9--><div>HỢP ĐỒNG MẪU CHUNG {So_Hop_Dong}</div>",
            });
            await db.SaveChangesAsync();
        }
        await using (var db = Fx.NewDb())
        {
            var quote = await db.PosQuotes.Include(x => x.Lines).FirstAsync(x => x.Id == q);
            var doc = new PosQuoteDocument { Id = Guid.NewGuid(), StoreId = store, QuoteId = q, Kind = PosQuoteDocumentKind.Contract, DocNo = "HD02", PrintTemplateId = own };
            var (picked, _) = await PosQuoteDocumentHtml.RenderDocumentAsync(db, quote, doc);
            Assert.Contains("HỢP ĐỒNG MẪU RIÊNG HĐ 25/2026/SANA", picked);
            // Chứng từ khác cùng loại (không chọn mẫu) → vẫn mẫu mặc định của cửa hàng.
            var other = await PosQuoteDocumentHtml.BuildAsync(db, quote, PosQuoteDocumentKind.Contract, "HD03", null);
            Assert.DoesNotContain("MẪU RIÊNG", other);
            Assert.Contains("HỢP ĐỒNG MẪU CHUNG", other);
        }
    }

    [Fact]
    public void Loi_van_luu_bo_ma_doc()
    {
        var html = OfficePdfConverter.SanitizeHtml(
            "<p onclick=\"x()\">A</p><img src=\"x\" onerror=\"alert(1)\"/><iframe src=\"https://e.vn\"></iframe><a href=\"javascript:alert(1)\">b</a>");
        Assert.DoesNotContain("onclick", html);
        Assert.DoesNotContain("onerror", html);
        Assert.DoesNotContain("iframe", html);
        Assert.DoesNotContain("javascript:", html);
        Assert.Contains(">A</p>", html);
    }

    [Fact]
    public void Khoi_dieu_kien_IF_IFNOT_long_nhau()
    {
        var data = new Dictionary<string, string> { ["A"] = "x", ["B"] = "0", ["C"] = "Theo thỏa thuận" };
        var html = PosPrintTemplateHtmlRenderer.ApplyConditionals(
            "<!--IF:A-->a<!--IF:B-->b<!--ENDIF:B--><!--IFNOT:B-->nb<!--ENDIFNOT:B--><!--ENDIF:A--><!--IF:C-->c<!--ENDIF:C--><!--IF:Z-->z<!--ENDIF:Z-->",
            data);
        Assert.Equal("anbc", html);
    }
}
