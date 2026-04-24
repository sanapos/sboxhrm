using ZKTecoADMS.Application.DTOs.SystemAdmin;

namespace ZKTecoADMS.Application.Interfaces;

public interface IMarketingService
{
    // Templates
    Task<List<NotificationTemplateDto>> ListTemplatesAsync(bool? activeOnly, CancellationToken ct = default);
    Task<NotificationTemplateDto> CreateTemplateAsync(CreateNotificationTemplateDto dto, CancellationToken ct = default);
    Task<bool> UpdateTemplateAsync(Guid id, CreateNotificationTemplateDto dto, CancellationToken ct = default);
    Task<bool> DeleteTemplateAsync(Guid id, CancellationToken ct = default);

    // Campaigns
    Task<List<MarketingCampaignDto>> ListCampaignsAsync(int page, int pageSize, CancellationToken ct = default);
    Task<MarketingCampaignDto> CreateCampaignAsync(CreateMarketingCampaignDto dto, Guid actorUserId, CancellationToken ct = default);
    Task<bool> LaunchCampaignAsync(Guid id, CancellationToken ct = default);
    Task<bool> CancelCampaignAsync(Guid id, CancellationToken ct = default);
    Task<bool> DeleteCampaignAsync(Guid id, CancellationToken ct = default);
    Task<MarketingCampaignDto?> GetCampaignAsync(Guid id, CancellationToken ct = default);
}
