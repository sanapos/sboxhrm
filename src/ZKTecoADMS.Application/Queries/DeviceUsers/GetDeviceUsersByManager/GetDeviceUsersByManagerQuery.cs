using ZKTecoADMS.Application.DTOs.Commons;

namespace ZKTecoADMS.Application.Queries.DeviceUsers.GetDeviceUsersByManager;

public record GetDeviceUsersByManagerQuery(Guid ManagerId, List<Guid>? SubordinateUserIds = null) : IQuery<AppResponse<IEnumerable<AccountDto>>>;
