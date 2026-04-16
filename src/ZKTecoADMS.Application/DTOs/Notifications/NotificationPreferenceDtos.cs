namespace ZKTecoADMS.Application.DTOs.Notifications;

public class NotificationCategoryDto
{
    public Guid Id { get; set; }
    public string Code { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public string? Description { get; set; }
    public string? Icon { get; set; }
    public int DisplayOrder { get; set; }
    public bool IsSystem { get; set; }
    public bool DefaultEnabled { get; set; }
}

public class NotificationPreferenceDto
{
    public string CategoryCode { get; set; } = string.Empty;
    public string CategoryDisplayName { get; set; } = string.Empty;
    public string? CategoryDescription { get; set; }
    public string? CategoryIcon { get; set; }
    public int DisplayOrder { get; set; }
    public bool IsEnabled { get; set; }
}

public class UpdateNotificationPreferencesRequest
{
    public List<PreferenceItem> Preferences { get; set; } = new();
}

public class PreferenceItem
{
    public string CategoryCode { get; set; } = string.Empty;
    public bool IsEnabled { get; set; }
}
