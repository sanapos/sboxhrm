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

    // Footer (login screen external links)
    public const string LearnMoreUrl = "learn_more_url";
    public const string ContactUrl = "contact_url";
    public const string SupportUrl = "support_url";

    // Landing page videos
    public const string LandingVideoIntro = "landing_video_intro";
    public const string LandingVideoGuide = "landing_video_guide";

    // Landing page content (editable by SuperAdmin)
    public const string LandingHeroTitle = "landing_hero_title";
    public const string LandingHeroSubtext = "landing_hero_subtext";
    public const string LandingFeaturesJson = "landing_features_json";
    public const string LandingPricingJson = "landing_pricing_json";
    public const string LandingGuideJson = "landing_guide_json";
    public const string LandingProducts = "landing_products";
    public const string LandingDownloadsJson = "landing_downloads_json";
    public const string LandingFaqJson = "landing_faq_json";

    // SEO / Google (public – used by homepage & analytics)
    public const string GoogleSiteVerification = "google_site_verification";
    public const string GoogleTagId = "google_tag_id";
    public const string SeoMetaTitle = "seo_meta_title";
    public const string SeoMetaDescription = "seo_meta_description";
    public const string SeoMetaKeywords = "seo_meta_keywords";
    public const string SeoOgTitle = "seo_og_title";
    public const string SeoOgDescription = "seo_og_description";
    public const string SeoOgImage = "seo_og_image";
    public const string SeoCanonicalUrl = "seo_canonical_url";

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
    public const string GoogleDriveImpersonateEmail = "google_drive_impersonate_email";

    /// <summary>Số ngày lưu chấm công thô trước khi tự động xóa (mặc định 180).</summary>
    public const string RawAttendanceRetentionDays = "raw_attendance_retention_days";
}
