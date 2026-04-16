using ZKTecoADMS.Application.DTOs.Notifications;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Mappings;

public class NotificationMappingConfig : IRegister
{
    public void Register(TypeAdapterConfig config)
    {
        config.NewConfig<Notification, NotificationDto>()
            .Map(dest => dest.Id, src => src.Id)
            .Map(dest => dest.TargetUserId, src => src.TargetUserId)
            .Map(dest => dest.TargetUserName, src => src.TargetUser != null 
                ? $"{src.TargetUser.LastName} {src.TargetUser.FirstName}".Trim() 
                : "")
            .Map(dest => dest.Type, src => src.Type)
            .Map(dest => dest.Title, src => src.Title)
            .Map(dest => dest.Message, src => src.Message)
            .Map(dest => dest.Timestamp, src => src.Timestamp)
            .Map(dest => dest.IsRead, src => src.IsRead)
            .Map(dest => dest.ReadAt, src => src.ReadAt)
            .Map(dest => dest.FromUserId, src => src.FromUserId)
            .Map(dest => dest.RelatedUrl, src => src.RelatedUrl)
            .Map(dest => dest.RelatedEntityId, src => src.RelatedEntityId)
            .Map(dest => dest.RelatedEntityType, src => src.RelatedEntityType);

        config.NewConfig<CreateNotificationDto, Notification>()
            .Map(dest => dest.TargetUserId, src => src.TargetUserId)
            .Map(dest => dest.Type, src => src.Type)
            .Map(dest => dest.Title, src => src.Title)
            .Map(dest => dest.Message, src => src.Message)
            .Map(dest => dest.RelatedUrl, src => src.RelatedUrl)
            .Map(dest => dest.RelatedEntityId, src => src.RelatedEntityId)
            .Map(dest => dest.RelatedEntityType, src => src.RelatedEntityType)
            .Map(dest => dest.IsRead, _ => false)
            .Map(dest => dest.Timestamp, _ => DateTime.UtcNow);
    }
}
