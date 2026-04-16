using ZKTecoADMS.Application.DTOs.Shifts;

namespace ZKTecoADMS.Application.Queries.ShiftTemplates.GetShiftTemplates;

public record GetShiftTemplatesQuery(Guid UserId, Guid StoreId, bool IsManager, bool IsAdmin = false) : IQuery<AppResponse<List<ShiftTemplateDto>>>;
