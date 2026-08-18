namespace ZKTecoADMS.Application.DTOs.Hkd;

public record HkdPreviewStatDto(string Label, decimal Value);

public record HkdPreviewColumnDto(
    string Key,
    string Label,
    bool Money = false,
    bool Qty = false);

public class HkdBookPreviewDto
{
    public string Book { get; set; } = "";
    public string Title { get; set; } = "";
    public string PeriodLabel { get; set; } = "";
    public int TaxGroup { get; set; }
    public string TaxCode { get; set; } = "";
    public string BusinessName { get; set; } = "";
    public string Industry { get; set; } = "";
    public double VatPercent { get; set; }
    public double PitPercent { get; set; }
    public List<HkdPreviewStatDto> Summary { get; set; } = [];
    public List<HkdPreviewColumnDto> Columns { get; set; } = [];
    public List<Dictionary<string, object?>> Rows { get; set; } = [];
    public int RowCount { get; set; }
    public bool Truncated { get; set; }
    public string? Note { get; set; }
}
