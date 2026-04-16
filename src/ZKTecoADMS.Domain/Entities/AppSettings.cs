using ZKTecoADMS.Domain.Entities.Base;

namespace ZKTecoADMS.Domain.Entities;

/// <summary>
/// Thiết lập thông tin phần mềm/công ty
/// </summary>
public class AppSettings : AuditableEntity<Guid>
{
    /// <summary>
    /// Key định danh setting (unique)
    /// </summary>
    public string Key { get; set; } = string.Empty;
    
    /// <summary>
    /// Giá trị của setting
    /// </summary>
    public string? Value { get; set; }
    
    /// <summary>
    /// Mô tả setting
    /// </summary>
    public string? Description { get; set; }
    
    /// <summary>
    /// Nhóm setting (General, Contact, Social, Legal)
    /// </summary>
    public string Group { get; set; } = "General";
    
    /// <summary>
    /// Loại dữ liệu (text, textarea, image, url, email, phone)
    /// </summary>
    public string DataType { get; set; } = "text";
    
    /// <summary>
    /// Thứ tự hiển thị
    /// </summary>
    public int DisplayOrder { get; set; }
    
    /// <summary>
    /// Setting có được public hay không (cho phép client đọc không cần auth)
    /// </summary>
    public bool IsPublic { get; set; } = true;

    /// <summary>
    /// Cửa hàng sở hữu setting
    /// </summary>
    public Guid? StoreId { get; set; }
    public virtual Store? Store { get; set; }
}

/// <summary>
/// Các key setting mặc định
/// </summary>
public static class AppSettingKeys
{
    // General
    public const string CompanyLogo = "company_logo";
    public const string CompanyName = "company_name";
    public const string CompanyAddress = "company_address";
    public const string CompanyDescription = "company_description";
    
    // Contact
    public const string FeedbackEmail = "feedback_email";
    public const string TechnicalSupportPhone = "technical_support_phone";
    public const string TechnicalSupportEmail = "technical_support_email";
    public const string SalesPhone = "sales_phone";
    public const string SalesEmail = "sales_email";
    
    // Social
    public const string FacebookUrl = "facebook_url";
    public const string YoutubeUrl = "youtube_url";
    public const string ZaloUrl = "zalo_url";
    public const string WebsiteUrl = "website_url";
    
    // Legal
    public const string TermsOfService = "terms_of_service";
    public const string PrivacyPolicy = "privacy_policy";
    
    // AI / Gemini
    public const string GeminiApiKey = "gemini_api_key";
    public const string GeminiModel = "gemini_model";
    public const string GeminiMaxTokens = "gemini_max_tokens";
    public const string GeminiTemperature = "gemini_temperature";
    
    // Google Drive Storage
    public const string GoogleDriveEnabled = "google_drive_enabled";
    public const string GoogleDriveCredentialsJson = "google_drive_credentials_json";
    public const string GoogleDriveFolderId = "google_drive_folder_id";
    public const string GoogleDriveFolderName = "google_drive_folder_name";
}
