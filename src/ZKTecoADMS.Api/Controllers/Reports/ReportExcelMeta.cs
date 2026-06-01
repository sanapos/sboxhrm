using System.Security.Claims;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Constants;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Metadata block printed above data tables in Excel exports.</summary>
internal sealed class ReportExcelMeta
{
    public string Title { get; init; } = "BÁO CÁO";
    public string? StoreName { get; init; }
    public string? PeriodLabel { get; init; }
    public string? FilterLabel { get; init; }
    public string? ExportedBy { get; init; }
    public DateTime ExportedAtVn { get; init; } = ReportHelpers.NowVn();
    public IReadOnlyList<string> SummaryLines { get; init; } = Array.Empty<string>();
    public int? DataRowCount { get; init; }

    public static ReportExcelMeta FromUser(
        ClaimsPrincipal? user,
        string title,
        string? periodLabel = null,
        string? filterLabel = null,
        IReadOnlyList<string>? summaryLines = null,
        int? dataRowCount = null)
    {
        var exportedBy = user?.FindFirst(ClaimTypes.Email)?.Value
            ?? user?.FindFirst(ClaimTypes.Name)?.Value;
        var storeName = user?.FindFirst(ClaimTypeNames.StoreName)?.Value;

        return new ReportExcelMeta
        {
            Title = title,
            StoreName = string.IsNullOrWhiteSpace(storeName) ? null : storeName.Trim(),
            PeriodLabel = string.IsNullOrWhiteSpace(periodLabel) ? null : periodLabel.Trim(),
            FilterLabel = string.IsNullOrWhiteSpace(filterLabel) ? null : filterLabel.Trim(),
            ExportedBy = string.IsNullOrWhiteSpace(exportedBy) ? null : exportedBy.Trim(),
            SummaryLines = summaryLines ?? Array.Empty<string>(),
            DataRowCount = dataRowCount,
        };
    }
}
