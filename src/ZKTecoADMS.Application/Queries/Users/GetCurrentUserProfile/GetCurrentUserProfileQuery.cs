using ZKTecoADMS.Application.CQRS;
using ZKTecoADMS.Application.DTOs.Users;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Application.Queries.Users.GetCurrentUserProfile;

public record GetCurrentUserProfileQuery(Guid UserId) : IQuery<AppResponse<UserProfileDto>>;
