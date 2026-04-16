using System.ComponentModel.DataAnnotations;
using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Tài khoản ngân hàng - cho VietQR
/// </summary>
public class BankAccount : AuditableEntity<Guid>
{
    /// <summary>
    /// Tên tài khoản (người thụ hưởng)
    /// </summary>
    [Required]
    [MaxLength(200)]
    public string AccountName { get; set; } = string.Empty;

    /// <summary>
    /// Số tài khoản
    /// </summary>
    [Required]
    [MaxLength(50)]
    public string AccountNumber { get; set; } = string.Empty;

    /// <summary>
    /// Mã ngân hàng (BIN - VietQR)
    /// VCB: 970436, TCB: 970407, ACB: 970416, VTB: 970415, BIDV: 970418, MBB: 970422
    /// </summary>
    [Required]
    [MaxLength(10)]
    public string BankCode { get; set; } = string.Empty;

    /// <summary>
    /// Tên ngân hàng
    /// </summary>
    [Required]
    [MaxLength(200)]
    public string BankName { get; set; } = string.Empty;

    /// <summary>
    /// Tên viết tắt ngân hàng (shortName)
    /// </summary>
    [MaxLength(50)]
    public string? BankShortName { get; set; }

    /// <summary>
    /// Chi nhánh ngân hàng
    /// </summary>
    [MaxLength(200)]
    public string? BranchName { get; set; }

    /// <summary>
    /// Logo URL của ngân hàng
    /// </summary>
    [MaxLength(500)]
    public string? BankLogoUrl { get; set; }

    /// <summary>
    /// Là tài khoản mặc định
    /// </summary>
    public bool IsDefault { get; set; } = false;

    /// <summary>
    /// Cửa hàng sở hữu tài khoản
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }

    /// <summary>
    /// Ghi chú/mô tả
    /// </summary>
    [MaxLength(500)]
    public string? Note { get; set; }

    /// <summary>
    /// Template VietQR (compact, compact2, qr_only, print)
    /// </summary>
    [MaxLength(20)]
    public string VietQRTemplate { get; set; } = "compact2";

    // Navigation Properties
    public virtual ICollection<CashTransaction> Transactions { get; set; } = new List<CashTransaction>();
}

/// <summary>
/// Danh sách ngân hàng Việt Nam hỗ trợ VietQR
/// </summary>
public static class VietQRBanks
{
    public static readonly Dictionary<string, (string BIN, string Name, string ShortName, string Logo)> Banks = new()
    {
        { "VCB", ("970436", "Ngân hàng TMCP Ngoại thương Việt Nam", "Vietcombank", "https://api.vietqr.io/img/VCB.png") },
        { "TCB", ("970407", "Ngân hàng TMCP Kỹ Thương Việt Nam", "Techcombank", "https://api.vietqr.io/img/TCB.png") },
        { "ACB", ("970416", "Ngân hàng TMCP Á Châu", "ACB", "https://api.vietqr.io/img/ACB.png") },
        { "VTB", ("970415", "Ngân hàng TMCP Công Thương Việt Nam", "VietinBank", "https://api.vietqr.io/img/CTG.png") },
        { "BIDV", ("970418", "Ngân hàng TMCP Đầu tư và Phát triển Việt Nam", "BIDV", "https://api.vietqr.io/img/BIDV.png") },
        { "MBB", ("970422", "Ngân hàng TMCP Quân đội", "MB Bank", "https://api.vietqr.io/img/MB.png") },
        { "VPB", ("970432", "Ngân hàng TMCP Việt Nam Thịnh Vượng", "VPBank", "https://api.vietqr.io/img/VPB.png") },
        { "TPB", ("970423", "Ngân hàng TMCP Tiên Phong", "TPBank", "https://api.vietqr.io/img/TPB.png") },
        { "SACOMBANK", ("970403", "Ngân hàng TMCP Sài Gòn Thương Tín", "Sacombank", "https://api.vietqr.io/img/STB.png") },
        { "SHB", ("970443", "Ngân hàng TMCP Sài Gòn - Hà Nội", "SHB", "https://api.vietqr.io/img/SHB.png") },
        { "AGRIBANK", ("970405", "Ngân hàng Nông nghiệp và Phát triển Nông thôn", "Agribank", "https://api.vietqr.io/img/VBA.png") },
        { "OCB", ("970448", "Ngân hàng TMCP Phương Đông", "OCB", "https://api.vietqr.io/img/OCB.png") },
        { "MSB", ("970426", "Ngân hàng TMCP Hàng Hải Việt Nam", "MSB", "https://api.vietqr.io/img/MSB.png") },
        { "HDBank", ("970437", "Ngân hàng TMCP Phát triển Thành phố Hồ Chí Minh", "HDBank", "https://api.vietqr.io/img/HDB.png") },
        { "EIB", ("970431", "Ngân hàng TMCP Xuất nhập khẩu Việt Nam", "Eximbank", "https://api.vietqr.io/img/EIB.png") },
        { "VIB", ("970441", "Ngân hàng TMCP Quốc tế Việt Nam", "VIB", "https://api.vietqr.io/img/VIB.png") },
        { "SeABank", ("970440", "Ngân hàng TMCP Đông Nam Á", "SeABank", "https://api.vietqr.io/img/SEAB.png") },
        { "LPB", ("970449", "Ngân hàng TMCP Bưu điện Liên Việt", "LienVietPostBank", "https://api.vietqr.io/img/LPB.png") },
        { "NCB", ("970419", "Ngân hàng TMCP Quốc Dân", "NCB", "https://api.vietqr.io/img/NCB.png") },
        { "ABB", ("970425", "Ngân hàng TMCP An Bình", "ABBank", "https://api.vietqr.io/img/ABB.png") },
        { "CAKE", ("546034", "Ngân hàng số CAKE by VPBank", "CAKE", "https://api.vietqr.io/img/CAKE.png") },
        { "Ubank", ("546035", "Ngân hàng số Ubank by VPBank", "Ubank", "https://api.vietqr.io/img/Ubank.png") },
    };

    /// <summary>
    /// Tạo VietQR URL từ thông tin tài khoản
    /// </summary>
    public static string GenerateVietQRUrl(
        string bankCode,
        string accountNumber,
        decimal? amount = null,
        string? description = null,
        string template = "compact2")
    {
        // Base URL: https://img.vietqr.io/image/{BANK_ID}-{ACCOUNT_NO}-{TEMPLATE}.png
        var baseUrl = $"https://img.vietqr.io/image/{bankCode}-{accountNumber}-{template}.png";
        
        var queryParams = new List<string>();
        
        if (amount.HasValue && amount > 0)
        {
            queryParams.Add($"amount={amount.Value:0}");
        }
        
        if (!string.IsNullOrEmpty(description))
        {
            // Encode description for URL (VietQR supports Vietnamese)
            var encodedDesc = Uri.EscapeDataString(description);
            queryParams.Add($"addInfo={encodedDesc}");
        }
        
        if (queryParams.Any())
        {
            baseUrl += "?" + string.Join("&", queryParams);
        }
        
        return baseUrl;
    }
}
