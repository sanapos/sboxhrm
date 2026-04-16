using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Communications;

/// <summary>
/// DTO for Internal Communication response
/// </summary>
public class InternalCommunicationDto
{
    public Guid Id { get; set; }
    public Guid StoreId { get; set; }
    public string Title { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;
    public string? Summary { get; set; }
    public string? ThumbnailUrl { get; set; }
    public List<string> AttachedImages { get; set; } = new();
    public CommunicationType Type { get; set; }
    public string TypeName => Type.ToString();
    public CommunicationPriority Priority { get; set; }
    public string PriorityName => Priority.ToString();
    public CommunicationStatus Status { get; set; }
    public string StatusName => Status.ToString();
    public Guid AuthorId { get; set; }
    public string? AuthorName { get; set; }
    public Guid? TargetDepartmentId { get; set; }
    public string? TargetDepartmentName { get; set; }
    public DateTime? PublishedAt { get; set; }
    public DateTime? ExpiresAt { get; set; }
    public int ViewCount { get; set; }
    public int LikeCount { get; set; }
    public int CommentCount { get; set; }
    public bool IsPinned { get; set; }
    public bool IsAiGenerated { get; set; }
    public string? Tags { get; set; }
    public List<string> TagList => string.IsNullOrEmpty(Tags) 
        ? new List<string>() 
        : Tags.Split(',', StringSplitOptions.RemoveEmptyEntries).Select(t => t.Trim()).ToList();
    public DateTime CreatedAt { get; set; }
    public DateTime? UpdatedAt { get; set; }
    public bool HasUserReacted { get; set; }
    public ReactionType? UserReactionType { get; set; }
}

/// <summary>
/// DTO for creating a new communication
/// </summary>
public class CreateCommunicationDto
{
    public string Title { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;
    public string? Summary { get; set; }
    public string? ThumbnailUrl { get; set; }
    public List<string>? AttachedImages { get; set; }
    public CommunicationType Type { get; set; } = CommunicationType.News;
    public CommunicationPriority Priority { get; set; } = CommunicationPriority.Normal;
    public Guid? TargetDepartmentId { get; set; }
    public DateTime? PublishedAt { get; set; }
    public DateTime? ExpiresAt { get; set; }
    public bool IsPinned { get; set; }
    public string? Tags { get; set; }
    public bool PublishImmediately { get; set; } = false;
    
    // AI generation metadata
    public bool IsAiGenerated { get; set; }
    public string? AiPrompt { get; set; }
}

/// <summary>
/// DTO for updating a communication
/// </summary>
public class UpdateCommunicationDto
{
    public Guid Id { get; set; }
    public string? Title { get; set; }
    public string? Content { get; set; }
    public string? Summary { get; set; }
    public string? ThumbnailUrl { get; set; }
    public List<string>? AttachedImages { get; set; }
    public CommunicationType? Type { get; set; }
    public CommunicationPriority? Priority { get; set; }
    public CommunicationStatus? Status { get; set; }
    public Guid? TargetDepartmentId { get; set; }
    public DateTime? PublishedAt { get; set; }
    public DateTime? ExpiresAt { get; set; }
    public bool? IsPinned { get; set; }
    public string? Tags { get; set; }
}

/// <summary>
/// DTO for communication comment
/// </summary>
public class CommunicationCommentDto
{
    public Guid Id { get; set; }
    public Guid CommunicationId { get; set; }
    public Guid UserId { get; set; }
    public string? UserName { get; set; }
    public string Content { get; set; } = string.Empty;
    public Guid? ParentCommentId { get; set; }
    public int LikeCount { get; set; }
    public DateTime CreatedAt { get; set; }
    public List<CommunicationCommentDto> Replies { get; set; } = new();
}

/// <summary>
/// DTO for adding a comment
/// </summary>
public class AddCommentDto
{
    public Guid CommunicationId { get; set; }
    public string Content { get; set; } = string.Empty;
    public Guid? ParentCommentId { get; set; }
}

/// <summary>
/// DTO for reaction
/// </summary>
public class CommunicationReactionDto
{
    public Guid CommunicationId { get; set; }
    public ReactionType ReactionType { get; set; } = ReactionType.Like;
}

/// <summary>
/// DTO for AI content generation request
/// </summary>
public class AiContentGenerationDto
{
    public string Prompt { get; set; } = string.Empty;
    public CommunicationType Type { get; set; } = CommunicationType.News;
    public string? Context { get; set; }
    public string? Tone { get; set; } = "professional";
    public int MaxLength { get; set; } = 1000;
    public string Language { get; set; } = "vi";
    /// <summary>
    /// AI provider to use: "gemini" or "deepseek". Defaults to first enabled provider.
    /// </summary>
    public string? Provider { get; set; }
}

/// <summary>
/// DTO for AI generated content response
/// </summary>
public class AiGeneratedContentDto
{
    public string Title { get; set; } = string.Empty;
    public string Content { get; set; } = string.Empty;
    public string? Summary { get; set; }
    public List<string>? SuggestedTags { get; set; }
    public string Prompt { get; set; } = string.Empty;
}

/// <summary>
/// Filter for querying communications
/// </summary>
public class CommunicationFilterDto
{
    public CommunicationType? Type { get; set; }
    public CommunicationStatus? Status { get; set; }
    public CommunicationPriority? Priority { get; set; }
    public Guid? AuthorId { get; set; }
    public Guid? DepartmentId { get; set; }
    public DateTime? FromDate { get; set; }
    public DateTime? ToDate { get; set; }
    public string? SearchTerm { get; set; }
    public bool? IsPinned { get; set; }
    public bool? IsAiGenerated { get; set; }
    public string? Tags { get; set; }
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 10;
    public string SortBy { get; set; } = "CreatedAt";
    public bool SortDescending { get; set; } = true;
}

/// <summary>
/// DTO for updating Gemini AI configuration
/// </summary>
public class UpdateGeminiConfigDto
{
    public string? ApiKey { get; set; }
    public string? Model { get; set; }
    public int? MaxOutputTokens { get; set; }
    public double? Temperature { get; set; }
    public bool? Enabled { get; set; }
}

/// <summary>
/// DTO for DeepSeek AI configuration
/// </summary>
public class UpdateDeepSeekConfigDto
{
    public string? ApiKey { get; set; }
    public string? Model { get; set; }
    public int? MaxOutputTokens { get; set; }
    public double? Temperature { get; set; }
    public bool? Enabled { get; set; }
}

/// <summary>
/// DTO for base64 image upload (web compatibility)
/// </summary>
public class ImageBase64UploadDto
{
    public string FileName { get; set; } = string.Empty;
    public string Base64Data { get; set; } = string.Empty;
}
