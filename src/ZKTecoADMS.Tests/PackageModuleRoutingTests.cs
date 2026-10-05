using Xunit;
using ZKTecoADMS.Api.Middlewares;
using ZKTecoADMS.Application.Authorization;

namespace ZKTecoADMS.Tests;

public class PackageModuleRoutingTests
{
    [Theory]
    [InlineData("/api/pos/quotes", "PosQuotes")]
    [InlineData("/api/pos/quotes/abc", "PosQuotes")]
    [InlineData("/api/pos/quotes/abc/contract", "PosContracts")]
    [InlineData("/api/pos/quotes/abc/contract/installments", "PosContracts")]
    [InlineData("/api/pos/quotes/abc/payments", "PosContracts")]
    [InlineData("/api/pos/quotes/receivables", "PosContracts")]
    [InlineData("/api/pos/promotions", "PosPromotions")]
    [InlineData("/api/pos/promotions/active", "PosPromotions")]
    [InlineData("/api/pos/reports/stock/reorder-suggestions", "PosReportStock")]
    [InlineData("/api/pos/products/abc/scale-plu", "PosProducts")]
    [InlineData("/api/payslips", "Payslip")]
    [InlineData("/api/payslips/my", "Payslip")]
    [InlineData("/api/payslips/pay", "Payroll")]
    [InlineData("/api/payslips/payment-info", "Payroll")]
    [InlineData("/api/payslips/bank-export", "Payroll")]
    [InlineData("/api/payslips/bank-export/templates", "Payroll")]
    [InlineData("/api/payslips/finalize", "Payroll")]
    public void Duong_dan_map_dung_chuc_nang_goi(string path, string expected) =>
        Assert.Equal(expected, StorePackageModuleMiddleware.ResolveModule(path));

    [Fact]
    public void Hop_dong_la_chuc_nang_chon_duoc_va_can_bao_gia()
    {
        Assert.Contains(FeatureModuleCatalog.PackageSelectable, m => m.Code == "PosContracts");
        Assert.Contains("PosQuotes", FeatureModuleCatalog.Requires["PosContracts"]);
    }
}
