using ZKTecoADMS.Application.DTOs.Leaves;

namespace ZKTecoADMS.Application.Queries.Leaves.GetMyLeaves;

public class GetMyLeavesHandler(
    IRepository<Leave> repository,
    IRepository<ShiftTemplate> shiftTemplateRepository,
    IRepository<Employee> employeeRepository)
    : IQueryHandler<GetMyLeavesQuery, AppResponse<List<LeaveDto>>>
{
    public async Task<AppResponse<List<LeaveDto>>> Handle(GetMyLeavesQuery request, CancellationToken cancellationToken)
    {
        var leaves = await repository.GetAllAsync(
            filter: l => l.StoreId == request.StoreId && l.EmployeeUserId == request.ApplicationUserId,
            orderBy: query => query.OrderByDescending(l => l.CreatedAt),
            includeProperties: [nameof(Leave.EmployeeUser), nameof(Leave.ApprovalRecords)],
            cancellationToken: cancellationToken);

        var dtos = leaves.Adapt<List<LeaveDto>>();

        // Populate ShiftName and ReplacementEmployeeName
        var shiftIds = dtos.Where(d => d.ShiftId != Guid.Empty).Select(d => d.ShiftId).Distinct().ToList();
        var replacementIds = dtos.Where(d => d.ReplacementEmployeeId.HasValue).Select(d => d.ReplacementEmployeeId!.Value).Distinct().ToList();

        var shiftTemplates = shiftIds.Any()
            ? await shiftTemplateRepository.GetAllAsync(filter: s => shiftIds.Contains(s.Id), cancellationToken: cancellationToken)
            : [];
        var replacementEmployees = replacementIds.Any()
            ? await employeeRepository.GetAllAsync(filter: e => replacementIds.Contains(e.Id), cancellationToken: cancellationToken)
            : [];

        var shiftMap = shiftTemplates.ToDictionary(s => s.Id, s => s.Name);
        var empMap = replacementEmployees.ToDictionary(e => e.Id, e => $"{e.LastName} {e.FirstName}".Trim());

        // Resolve all shift IDs for multi-shift support
        var allShiftIds = dtos.SelectMany(d => d.ShiftIds).Distinct().ToList();
        var extraShiftIds = allShiftIds.Except(shiftIds).ToList();
        if (extraShiftIds.Any())
        {
            var extraShifts = await shiftTemplateRepository.GetAllAsync(filter: s => extraShiftIds.Contains(s.Id), cancellationToken: cancellationToken);
            foreach (var s in extraShifts) shiftMap.TryAdd(s.Id, s.Name);
        }

        foreach (var dto in dtos)
        {
            if (shiftMap.TryGetValue(dto.ShiftId, out var shiftName)) dto.ShiftName = shiftName;
            dto.ShiftNames = dto.ShiftIds.Where(id => shiftMap.ContainsKey(id)).Select(id => shiftMap[id]).ToList();
            if (!dto.ShiftNames.Any() && dto.ShiftName != null) dto.ShiftNames = [dto.ShiftName];
            if (dto.ReplacementEmployeeId.HasValue && empMap.TryGetValue(dto.ReplacementEmployeeId.Value, out var repName))
                dto.ReplacementEmployeeName = repName;
        }

        // Resolve EmployeeName from Employee table when EmployeeId is set
        var leaveEmployeeIds = dtos.Where(d => d.EmployeeId.HasValue).Select(d => d.EmployeeId!.Value).Distinct().ToList();
        if (leaveEmployeeIds.Any())
        {
            var leaveEmployees = await employeeRepository.GetAllAsync(filter: e => leaveEmployeeIds.Contains(e.Id), cancellationToken: cancellationToken);
            var leaveEmpMap = leaveEmployees.ToDictionary(e => e.Id, e => $"{e.LastName} {e.FirstName}".Trim());
            foreach (var dto in dtos)
            {
                if (dto.EmployeeId.HasValue && leaveEmpMap.TryGetValue(dto.EmployeeId.Value, out var empName))
                    dto.EmployeeName = empName;
            }
        }

        return AppResponse<List<LeaveDto>>.Success(dtos);
    }
}
