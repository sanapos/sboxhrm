namespace SboxPrintAgent;

/// <summary>
/// Server của bản build. Mỗi server (database riêng) phát hành một bản agent riêng:
/// <c>dotnet publish -p:SboxServer=pos</c> → sboxpos.com; mặc định → sboxhrm.com.
/// Bản POS lưu cấu hình và khóa tự khởi động riêng để cài song song với bản HRM.
/// </summary>
public static class BuildServer
{
#if SBOX_SERVER_POS
    public const bool IsPos = true;
    public const string DefaultApiBaseUrl = "https://sboxpos.com";
    public const string Label = "SBOX POS";
    public const string DataFolderName = "SboxPrintAgent-POS";
    public const string StartupValueName = "SboxPrintAgent-POS";
#else
    public const bool IsPos = false;
    public const string DefaultApiBaseUrl = "https://sboxhrm.com";
    public const string Label = "SBOX HRM";
    public const string DataFolderName = "SboxPrintAgent";
    public const string StartupValueName = "SboxPrintAgent";
#endif
}
