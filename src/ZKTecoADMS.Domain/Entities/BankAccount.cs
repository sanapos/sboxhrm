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
    public static (string Code, string BIN, string Name, string ShortName, string Logo)? FindByBin(string? bin)
    {
        var needle = (bin ?? "").Trim();
        if (needle.Length == 0) return null;
        foreach (var kv in Banks)
        {
            if (string.Equals(kv.Value.BIN, needle, StringComparison.OrdinalIgnoreCase))
                return (kv.Key, kv.Value.BIN, kv.Value.Name, kv.Value.ShortName, kv.Value.Logo);
        }
        return null;
    }

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
        { "PVCB", ("970412", "Ngân hàng TMCP Đại Chúng Việt Nam", "PVcomBank", "https://api.vietqr.io/img/PVCB.png") },
        { "NAB", ("970428", "Ngân hàng TMCP Nam Á", "Nam A Bank", "https://api.vietqr.io/img/NAB.png") },
        { "BAB", ("970409", "Ngân hàng TMCP Bắc Á", "Bac A Bank", "https://api.vietqr.io/img/BAB.png") },
        { "KLB", ("970452", "Ngân hàng TMCP Kiên Long", "KienlongBank", "https://api.vietqr.io/img/KLB.png") },
        { "SCB", ("970429", "Ngân hàng TMCP Sài Gòn", "SCB", "https://api.vietqr.io/img/SCB.png") },
        { "VAB", ("970427", "Ngân hàng TMCP Việt Á", "VietABank", "https://api.vietqr.io/img/VAB.png") },
        { "VIETBANK", ("970433", "Ngân hàng TMCP Việt Nam Thương Tín", "VietBank", "https://api.vietqr.io/img/VIETBANK.png") },
        { "BVB", ("970438", "Ngân hàng TMCP Bảo Việt", "BaoVietBank", "https://api.vietqr.io/img/BVB.png") },
        { "VCCB", ("970454", "Ngân hàng TMCP Bản Việt", "BVBank", "https://api.vietqr.io/img/VCCB.png") },
        { "PGB", ("970430", "Ngân hàng TMCP Thịnh vượng và Phát triển", "PGBank", "https://api.vietqr.io/img/PGB.png") },
        { "SGICB", ("970400", "Ngân hàng TMCP Sài Gòn Công Thương", "SaigonBank", "https://api.vietqr.io/img/SGICB.png") },
        { "GPB", ("970408", "Ngân hàng Thương mại TNHH MTV Dầu Khí Toàn Cầu", "GPBank", "https://api.vietqr.io/img/GPB.png") },
        { "OCEANBANK", ("970414", "Ngân hàng Thương mại TNHH MTV Đại Dương", "OceanBank", "https://api.vietqr.io/img/OCEANBANK.png") },
        { "SHBVN", ("970424", "Ngân hàng TNHH MTV Shinhan Việt Nam", "ShinhanBank", "https://api.vietqr.io/img/SHBVN.png") },
        { "WVN", ("970457", "Ngân hàng TNHH MTV Woori Việt Nam", "Woori", "https://api.vietqr.io/img/WVN.png") },
        { "CBB", ("970444", "Ngân hàng Thương mại TNHH MTV Xây dựng Việt Nam", "CBBank", "https://api.vietqr.io/img/CBB.png") },
        { "COOPBANK", ("970446", "Ngân hàng Hợp tác xã Việt Nam", "Co-opBank", "https://api.vietqr.io/img/COOPBANK.png") },
    };

    /// <summary>Tên gọi khác (trên hồ sơ nhân viên) → mã trong <see cref="Banks"/>.</summary>
    private static readonly (string Alias, string Code)[] Aliases =
    [
        ("vietcombank", "VCB"), ("vcb", "VCB"), ("ngoai thuong", "VCB"),
        ("techcombank", "TCB"), ("tcb", "TCB"), ("ky thuong", "TCB"),
        ("vietinbank", "VTB"), ("viettinbank", "VTB"), ("ctg", "VTB"), ("cong thuong viet nam", "VTB"),
        ("bidv", "BIDV"), ("dau tu va phat trien", "BIDV"),
        ("agribank", "AGRIBANK"), ("nong nghiep", "AGRIBANK"),
        ("mb bank", "MBB"), ("mbbank", "MBB"), ("quan doi", "MBB"), ("mb", "MBB"),
        ("acb", "ACB"), ("a chau", "ACB"),
        ("vpbank", "VPB"), ("thinh vuong", "VPB"),
        ("sacombank", "SACOMBANK"), ("sai gon thuong tin", "SACOMBANK"),
        ("tpbank", "TPB"), ("tien phong", "TPB"),
        ("hdbank", "HDBank"), ("phat trien tp", "HDBank"), ("phat trien thanh pho", "HDBank"),
        ("shb", "SHB"), ("sai gon - ha noi", "SHB"), ("sai gon ha noi", "SHB"),
        ("vib", "VIB"), ("quoc te", "VIB"),
        ("seabank", "SeABank"), ("dong nam a", "SeABank"),
        ("msb", "MSB"), ("maritime", "MSB"), ("hang hai", "MSB"),
        ("eximbank", "EIB"), ("xuat nhap khau", "EIB"),
        ("ocb", "OCB"), ("phuong dong", "OCB"),
        ("lienvietpostbank", "LPB"), ("lpbank", "LPB"), ("buu dien lien viet", "LPB"), ("loc phat", "LPB"),
        ("ncb", "NCB"), ("quoc dan", "NCB"),
        ("abbank", "ABB"), ("an binh", "ABB"),
        ("pvcombank", "PVCB"), ("dai chung", "PVCB"),
        ("nam a", "NAB"), ("bac a", "BAB"),
        ("kienlongbank", "KLB"), ("kien long", "KLB"),
        ("scb", "SCB"), ("viet a", "VAB"), ("vietabank", "VAB"),
        ("vietbank", "VIETBANK"), ("viet nam thuong tin", "VIETBANK"),
        ("baovietbank", "BVB"), ("bao viet", "BVB"),
        ("bvbank", "VCCB"), ("ban viet", "VCCB"), ("viet capital", "VCCB"),
        ("pgbank", "PGB"), ("saigonbank", "SGICB"), ("sai gon cong thuong", "SGICB"),
        ("gpbank", "GPB"), ("oceanbank", "OCEANBANK"), ("dai duong", "OCEANBANK"),
        ("shinhan", "SHBVN"), ("woori", "WVN"), ("cbbank", "CBB"), ("xay dung", "CBB"),
        ("co-opbank", "COOPBANK"), ("coopbank", "COOPBANK"), ("hop tac xa", "COOPBANK"),
        ("cake", "CAKE"), ("ubank", "Ubank"),
    ];

    private static string Fold(string s)
    {
        var d = s.Normalize(System.Text.NormalizationForm.FormD);
        var sb = new System.Text.StringBuilder(d.Length);
        foreach (var c in d)
        {
            if (System.Globalization.CharUnicodeInfo.GetUnicodeCategory(c) == System.Globalization.UnicodeCategory.NonSpacingMark) continue;
            sb.Append(c switch { 'đ' => 'd', 'Đ' => 'D', _ => c });
        }
        return sb.ToString().Normalize(System.Text.NormalizationForm.FormC).ToLowerInvariant();
    }

    /// <summary>
    /// Nhận diện ngân hàng từ chữ tự do trên hồ sơ nhân viên («Vietcombank - NH TMCP Ngoại thương…», «970436», «VCB»…).
    /// Ưu tiên tên viết tắt đứng đầu (trước dấu «-»), sau đó tới tên đầy đủ.
    /// </summary>
    public static (string Code, string BIN, string Name, string ShortName, string Logo)? Resolve(string? text)
    {
        var raw = (text ?? "").Trim();
        if (raw.Length == 0) return null;
        if (raw.All(char.IsDigit)) return FindByBin(raw);
        if (Banks.TryGetValue(raw, out var exact)) return (raw, exact.BIN, exact.Name, exact.ShortName, exact.Logo);
        foreach (var kv in Banks)
            if (string.Equals(kv.Key, raw, StringComparison.OrdinalIgnoreCase) || string.Equals(kv.Value.ShortName, raw, StringComparison.OrdinalIgnoreCase))
                return (kv.Key, kv.Value.BIN, kv.Value.Name, kv.Value.ShortName, kv.Value.Logo);

        var folded = Fold(raw);
        var head = folded.Split(" - ")[0].Trim();
        (string Code, string BIN, string Name, string ShortName, string Logo)? Hit(string code) =>
            Banks.TryGetValue(code, out var v) ? (code, v.BIN, v.Name, v.ShortName, v.Logo) : null;

        // Tên viết tắt ở đầu chuỗi (khớp nguyên từ).
        foreach (var (alias, code) in Aliases.OrderByDescending(a => a.Alias.Length))
            if (head == alias || head.StartsWith(alias + " ")) return Hit(code);
        // Tên đầy đủ / cụm đặc trưng ở bất kỳ đâu (cụm dài trước để «sai gon thuong tin» thắng «sai gon»).
        foreach (var (alias, code) in Aliases.Where(a => a.Alias.Length >= 4).OrderByDescending(a => a.Alias.Length))
            if (folded.Contains(alias)) return Hit(code);
        foreach (var kv in Banks)
            if (folded.Contains(Fold(kv.Value.Name))) return Hit(kv.Key);
        return null;
    }

    /// <summary>Mã app ngân hàng cho link mở app của VietQR (dl.vietqr.io/pay?app=…), theo BIN. Null = không hỗ trợ.</summary>
    public static string? DeeplinkAppId(string? bin) => (bin ?? "").Trim() switch
    {
        "970436" => "vcb", "970407" => "tcb", "970416" => "acb", "970415" => "icb", "970418" => "bidv",
        "970422" => "mb", "970432" => "vpb", "970423" => "tpb", "970443" => "shb", "970405" => "vba",
        "970448" => "ocb", "970437" => "hdb", "970431" => "eib", "970441" => "vib", "970440" => "seab",
        "970449" => "lpb", "970419" => "ncb", "970425" => "abb", "546034" => "cake", "970412" => "pvcb",
        "970428" => "nab", "970452" => "klb", "970429" => "scb", "970433" => "vietbank", "970438" => "bvb",
        "970427" => "vab", "970424" => "shbvn", "970457" => "wvn", "970414" => "oceanbank", "970400" => "sgicb",
        "970446" => "coopbank",
        _ => null,
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
