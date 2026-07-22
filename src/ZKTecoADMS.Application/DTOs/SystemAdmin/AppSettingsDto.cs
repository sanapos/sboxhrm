namespace ZKTecoADMS.Application.DTOs.SystemAdmin;

/// <summary>
/// DTO for App Settings
/// </summary>
public record AppSettingsDto(
    Guid Id,
    string Key,
    string? Value,
    string? Description,
    string Group,
    string DataType,
    int DisplayOrder,
    bool IsPublic,
    DateTime? LastModified
);

/// <summary>
/// Request tạo/cập nhật setting
/// </summary>
public record UpsertAppSettingRequest(
    string Key,
    string? Value,
    string? Description,
    string Group,
    string DataType,
    int DisplayOrder,
    bool IsPublic
);

/// <summary>
/// Request cập nhật nhiều settings cùng lúc
/// </summary>
public record UpdateAppSettingsRequest(
    List<AppSettingItem> Settings
);

/// <summary>
/// Item setting trong batch update
/// </summary>
public record AppSettingItem(
    string Key,
    string? Value
);

/// <summary>
/// Response cho public settings (không cần auth)
/// </summary>
public record PublicAppSettingsResponse(
    // General
    string? CompanyLogo,
    string? CompanyName,
    string? CompanyAddress,
    string? CompanyDescription,
    
    // Contact
    string? FeedbackEmail,
    string? TechnicalSupportPhone,
    string? TechnicalSupportEmail,
    string? SalesPhone,
    string? SalesEmail,
    
    // Social
    string? FacebookUrl,
    string? YoutubeUrl,
    string? ZaloUrl,
    string? WebsiteUrl,

    // Footer (login screen external links)
    string? LearnMoreUrl,
    string? ContactUrl,
    string? SupportUrl,

    // Legal
    string? TermsOfService,
    string? PrivacyPolicy,

    // Landing videos
    string? LandingVideoIntro,
    string? LandingVideoGuide,

    // Landing content
    string? LandingHeroTitle,
    string? LandingHeroSubtext,
    string? LandingFeaturesJson,
    string? LandingPricingJson,
    string? LandingGuideJson,
    string? LandingProducts,
    string? LandingDownloadsJson,
    string? LandingFaqJson,

    // SEO / Google
    string? GoogleSiteVerification,
    string? GoogleTagId,
    string? SeoMetaTitle,
    string? SeoMetaDescription,
    string? SeoMetaKeywords,
    string? SeoOgTitle,
    string? SeoOgDescription,
    string? SeoOgImage,
    string? SeoCanonicalUrl
);
