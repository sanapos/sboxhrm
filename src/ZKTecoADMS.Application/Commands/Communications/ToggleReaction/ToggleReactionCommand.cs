using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Communications.ToggleReaction;

public record ToggleReactionCommand(
    Guid CommunicationId,
    Guid UserId,
    ReactionType ReactionType
) : ICommand<AppResponse<bool>>;
