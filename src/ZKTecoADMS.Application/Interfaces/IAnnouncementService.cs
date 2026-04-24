using ZKTecoADMS.Application.DTOs.SystemAdmin;

namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Resolve audience spec → list of (UserId, StoreId).
/// </summary>
public interface IAudienceResolver
{
    Task<List<AudienceMember>> ResolveAsync(AudienceSpec spec, CancellationToken ct = default);
    Task<AudiencePreviewDto> PreviewAsync(AudienceSpec spec, CancellationToken ct = default);
}

public sealed record AudienceMember(Guid UserId, Guid? StoreId, string? Role);

/// <summary>
/// Quản lý SystemAnnouncement: tạo, gửi (fan-out delivery), thống kê,
/// trả về danh sách announcement đang active cho client banner.
/// </summary>
public interface IAnnouncementService
{
    Task<SystemAnnouncementDto> CreateAsync(CreateSystemAnnouncementDto request, Guid actorUserId, CancellationToken ct = default);
    Task<SystemAnnouncementDto?> GetAsync(Guid id, CancellationToken ct = default);
    Task<List<SystemAnnouncementDto>> ListAsync(int page, int pageSize, string? keyword, int? kind, int? status, CancellationToken ct = default);
    Task<bool> CancelAsync(Guid id, CancellationToken ct = default);
    Task<bool> DeleteAsync(Guid id, CancellationToken ct = default);
    Task<int> SendAsync(Guid id, CancellationToken ct = default);
    Task<int> ResendFailedAsync(Guid id, CancellationToken ct = default);
    Task<AnnouncementStatsDto> GetStatsAsync(Guid id, CancellationToken ct = default);

    Task<List<ActiveAnnouncementDto>> GetActiveForUserAsync(Guid userId, CancellationToken ct = default);
    Task MarkSeenAsync(Guid announcementId, Guid userId, CancellationToken ct = default);
    Task MarkClickedAsync(Guid announcementId, Guid userId, CancellationToken ct = default);
    Task MarkAckedAsync(Guid announcementId, Guid userId, CancellationToken ct = default);
    Task MarkDismissedAsync(Guid announcementId, Guid userId, CancellationToken ct = default);
}
