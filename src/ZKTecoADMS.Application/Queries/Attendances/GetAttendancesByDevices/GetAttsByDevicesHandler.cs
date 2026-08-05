using ZKTecoADMS.Application.DTOs.Attendances;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Queries.Attendances.GetAttendancesByDevices;

public class GetAttsByDevicesHandler(
    IRepositoryPagedQuery<Attendance> attRepository,
    IRepository<Employee> employeeRepository,
    IRepository<MobileAttendanceRecord> mobileAttendanceRepository,
    IRepository<Device> deviceRepository,
    IRepository<DeviceUser> deviceUserRepository
) : ICommandHandler<GetAttsByDevicesQuery, AppResponse<PagedResult<AttendanceDto>>>
{
    public async Task<AppResponse<PagedResult<AttendanceDto>>> Handle(GetAttsByDevicesQuery request, CancellationToken cancellationToken)
    {
        var allowedPins = request.Filter.AllowedPins;
        var hasPinFilter = allowedPins != null && allowedPins.Count > 0;

        // FromDate inclusive (start of day), ToDate exclusive (start of next day after To calendar day).
        var fromInclusive = request.Filter.FromDate.Date;
        var toExclusive = request.Filter.ToDate.Date.AddDays(1);
        if (request.Filter.ToDate.TimeOfDay > TimeSpan.Zero
            && request.Filter.ToDate > request.Filter.ToDate.Date)
        {
            // Client gửi "đến giờ hiện tại" — vẫn bao trùm hết ngày ToDate.
            toExclusive = request.Filter.ToDate.Date.AddDays(1);
        }

        var deviceIds = request.Filter.DeviceIds;
        var hasDeviceFilter = deviceIds is { Count: > 0 };

        var pagination = request.PaginationRequest;

        var atts = await attRepository.GetPagedResultWithProjectionAsync(
            pagination,
            filter: a => 
                a.AttendanceTime >= fromInclusive
                && a.AttendanceTime < toExclusive
                && (!hasDeviceFilter || deviceIds!.Contains(a.DeviceId))
                && (!hasPinFilter || allowedPins!.Contains(a.PIN)),
            projection: a => new AttendanceDto(
                a.Id,
                a.AttendanceTime,
                a.Device.DeviceName,
                a.PIN,
                // Mã NV: Lấy từ Employee nếu có, nếu không có (manual) thì để null
                a.EmployeeId.HasValue && a.Employee!.Employee != null ? a.Employee.Employee.EmployeeCode : null,
                // Tên nhân viên: Lấy từ Employee nếu có, nếu không (manual) thì lấy từ WorkCode
                a.EmployeeId.HasValue && a.Employee!.Employee != null 
                    ? a.Employee.Employee.LastName + " " + a.Employee.Employee.FirstName 
                    : (a.WorkCode ?? "Thủ công"),
                // Tên trong máy: Lấy từ DeviceUser nếu có
                a.EmployeeId.HasValue ? a.Employee!.Name : null,
                a.EmployeeId.HasValue ? a.Employee!.Privilege : 0,
                a.VerifyMode,
                a.AttendanceState,
                a.WorkCode,
                a.Note,
                a.MobileAttendanceRecordId,
                null,
                null,
                null,
                null,
                a.DeviceId
            ),
            applyOrdering: q => q.OrderBy(a => a.AttendanceTime).ThenBy(a => a.Id),
            cancellationToken: cancellationToken);
        
        // Enrich manual attendances with full employee names
        var dtoList = atts.Items.ToList();

        var mobileIds = dtoList
            .Where(d => d.MobileAttendanceRecordId.HasValue)
            .Select(d => d.MobileAttendanceRecordId!.Value)
            .Distinct()
            .ToList();
        if (mobileIds.Count > 0)
        {
            var mobileRecords = await mobileAttendanceRepository.GetAllAsync(
                r => mobileIds.Contains(r.Id),
                cancellationToken: cancellationToken);
            var mobileById = mobileRecords.ToDictionary(r => r.Id);
            for (var i = 0; i < dtoList.Count; i++)
            {
                var dto = dtoList[i];
                if (dto.MobileAttendanceRecordId.HasValue
                    && mobileById.TryGetValue(dto.MobileAttendanceRecordId.Value, out var mob))
                {
                    dtoList[i] = dto with
                    {
                        Latitude = mob.Latitude,
                        Longitude = mob.Longitude,
                        LocationName = mob.LocationName,
                        SitePhotoUrl = string.Equals(mob.Status, "pending", StringComparison.OrdinalIgnoreCase)
                            ? NormalizeSitePhotoUrl(mob.SitePhotoUrl)
                            : null
                    };
                }
            }
        }

        // Fallback: ảnh chụp sau chấm — ghép theo PIN + thời gian khi thiếu liên kết Id.
        var storeIds = await ResolveStoreIdsAsync(deviceIds, cancellationToken);
        await ApplySitePhotoFallbackByPinAndTimeAsync(dtoList, storeIds, cancellationToken);
        await EnrichManualAttendanceNamesAsync(dtoList, deviceIds, storeIds, cancellationToken);

        // Luôn trả dtoList (GPS/ảnh hiện trường từ mobile); trước đây chỉ gán lại khi có chấm thủ công.
        atts = new PagedResult<AttendanceDto>(dtoList, atts);
        return AppResponse<PagedResult<AttendanceDto>>.Success(atts);
    }

    private async Task<List<Guid>> ResolveStoreIdsAsync(
        IReadOnlyList<Guid>? deviceIds,
        CancellationToken cancellationToken)
    {
        if (deviceIds is not { Count: > 0 })
            return [];

        var devices = await deviceRepository.GetAllAsync(
            d => deviceIds.Contains(d.Id),
            cancellationToken: cancellationToken);
        return devices
            .Where(d => d.StoreId.HasValue)
            .Select(d => d.StoreId!.Value)
            .Distinct()
            .ToList();
    }

    private async Task EnrichManualAttendanceNamesAsync(
        List<AttendanceDto> dtoList,
        IReadOnlyList<Guid>? deviceIds,
        IReadOnlyList<Guid> storeIds,
        CancellationToken cancellationToken)
    {
        var manualAttendances = dtoList.Where(a => (int)a.VerifyMode == 100).ToList();
        if (manualAttendances.Count == 0)
            return;

        var pins = manualAttendances
            .Select(a => a.Pin)
            .Where(p => !string.IsNullOrWhiteSpace(p))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        if (pins.Count == 0)
            return;

        // 1) Ưu tiên DeviceUser trên đúng máy của dòng chấm (PIN có thể khác EmployeeCode).
        var scopedDeviceIds = deviceIds is { Count: > 0 }
            ? deviceIds.ToList()
            : manualAttendances
                .Where(a => a.DeviceId.HasValue)
                .Select(a => a.DeviceId!.Value)
                .Distinct()
                .ToList();

        // Key: "{deviceId}|{pin}" — pin so sánh không phân biệt hoa thường.
        var byDevicePin = new Dictionary<string, (string FullName, string? EmployeeCode)>(StringComparer.OrdinalIgnoreCase);
        if (scopedDeviceIds.Count > 0)
        {
            var deviceUsers = await deviceUserRepository.GetAllAsync(
                du => scopedDeviceIds.Contains(du.DeviceId)
                      && pins.Contains(du.Pin),
                includeProperties: [nameof(DeviceUser.Employee)],
                cancellationToken: cancellationToken);

            foreach (var du in deviceUsers)
            {
                if (string.IsNullOrWhiteSpace(du.Pin))
                    continue;
                string fullName;
                string? code = null;
                if (du.Employee != null)
                {
                    fullName = $"{du.Employee.LastName} {du.Employee.FirstName}".Trim();
                    code = du.Employee.EmployeeCode;
                }
                else
                {
                    fullName = du.Name?.Trim() ?? string.Empty;
                }

                if (string.IsNullOrWhiteSpace(fullName))
                    continue;

                var key = $"{du.DeviceId:D}|{du.Pin.Trim()}";
                byDevicePin.TryAdd(key, (fullName, code));
            }
        }

        // 2) Fallback: Employee theo StoreId của các máy đang query (mã unique trong store).
        Dictionary<string, string> byStoreCode = new(StringComparer.OrdinalIgnoreCase);
        if (storeIds.Count > 0)
        {
            var employees = await employeeRepository.GetAllAsync(
                e => e.StoreId.HasValue
                     && storeIds.Contains(e.StoreId.Value)
                     && e.EmployeeCode != null
                     && pins.Contains(e.EmployeeCode),
                cancellationToken: cancellationToken);

            byStoreCode = employees
                .Where(e => !string.IsNullOrWhiteSpace(e.EmployeeCode))
                .GroupBy(e => e.EmployeeCode!.Trim(), StringComparer.OrdinalIgnoreCase)
                .ToDictionary(
                    g => g.Key,
                    g =>
                    {
                        // Khi admin query nhiều store cùng lúc vẫn có thể trùng mã —
                        // ưu tiên bản ghi có tên đầy đủ; không crash.
                        var e = g.OrderByDescending(x =>
                                !string.IsNullOrWhiteSpace(x.FirstName)
                                || !string.IsNullOrWhiteSpace(x.LastName))
                            .First();
                        return $"{e.LastName} {e.FirstName}".Trim();
                    },
                    StringComparer.OrdinalIgnoreCase);
        }

        for (var i = 0; i < dtoList.Count; i++)
        {
            var dto = dtoList[i];
            if ((int)dto.VerifyMode != 100 || string.IsNullOrWhiteSpace(dto.Pin))
                continue;

            var pin = dto.Pin.Trim();
            string? fullName = null;
            string? employeeCode = dto.EmployeeCode;

            if (dto.DeviceId.HasValue
                && byDevicePin.TryGetValue($"{dto.DeviceId.Value:D}|{pin}", out var fromDu)
                && !string.IsNullOrWhiteSpace(fromDu.FullName))
            {
                fullName = fromDu.FullName;
                employeeCode ??= fromDu.EmployeeCode ?? pin;
            }
            else if (byStoreCode.TryGetValue(pin, out var fromEmp)
                     && !string.IsNullOrWhiteSpace(fromEmp))
            {
                fullName = fromEmp;
                employeeCode ??= pin;
            }

            if (string.IsNullOrWhiteSpace(fullName))
                continue;

            // Chỉ ghi đè khi tên đang là placeholder / WorkCode cắt ngắn.
            var current = dto.UserName?.Trim() ?? string.Empty;
            var shouldReplace = string.IsNullOrWhiteSpace(current)
                || string.Equals(current, "Thủ công", StringComparison.OrdinalIgnoreCase)
                || (dto.WorkCode != null
                    && string.Equals(current, dto.WorkCode.Trim(), StringComparison.OrdinalIgnoreCase)
                    && fullName.Length > current.Length);

            if (!shouldReplace && !string.IsNullOrWhiteSpace(dto.EmployeeCode))
                continue;

            dtoList[i] = dto with { UserName = fullName, EmployeeCode = employeeCode ?? pin };
        }
    }

    private static string? NormalizeSitePhotoUrl(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return null;
        var p = path.Trim();
        if (p.StartsWith('/')) return p;
        if (p.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || p.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var uri = new Uri(p);
                return uri.AbsolutePath;
            }
            catch
            {
                return p;
            }
        }
        return p.StartsWith('/') ? p : "/" + p;
    }

    private async Task ApplySitePhotoFallbackByPinAndTimeAsync(
        List<AttendanceDto> dtoList,
        IReadOnlyList<Guid> storeIds,
        CancellationToken cancellationToken)
    {
        var targets = dtoList
            .Where(d => string.IsNullOrWhiteSpace(d.SitePhotoUrl))
            .Where(d =>
                (d.Note != null && d.Note.Contains("Mobile", StringComparison.OrdinalIgnoreCase))
                || (d.DeviceName != null && d.DeviceName.Contains("MOBILE", StringComparison.OrdinalIgnoreCase))
                || d.MobileAttendanceRecordId.HasValue)
            .ToList();
        if (targets.Count == 0)
            return;

        var pins = targets.Select(d => d.Pin).Where(p => !string.IsNullOrWhiteSpace(p)).Distinct().ToList();
        if (pins.Count == 0)
            return;

        // Chỉ map PIN → ApplicationUser trong các store đang query (tránh PIN "1" lấy user store khác).
        var employeeFilter = storeIds.Count > 0
            ? (System.Linq.Expressions.Expression<Func<Employee, bool>>)(e =>
                e.StoreId.HasValue
                && storeIds.Contains(e.StoreId.Value)
                && pins.Contains(e.EmployeeCode ?? ""))
            : e => pins.Contains(e.EmployeeCode ?? "");

        var employees = await employeeRepository.GetAllAsync(
            employeeFilter,
            cancellationToken: cancellationToken);
        var pinToUserId = employees
            .Where(e => e.ApplicationUserId.HasValue && !string.IsNullOrWhiteSpace(e.EmployeeCode))
            .GroupBy(e => e.EmployeeCode!.Trim(), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(
                g => g.Key,
                g => g.First().ApplicationUserId!.Value.ToString(),
                StringComparer.OrdinalIgnoreCase);

        var from = targets.Min(d => d.AttendanceTime).AddMinutes(-15);
        var to = targets.Max(d => d.AttendanceTime).AddMinutes(15);
        var userIds = pinToUserId.Values.Distinct().ToList();
        if (userIds.Count == 0)
            return;

        var mobileCandidates = await mobileAttendanceRepository.GetAllAsync(
            r => userIds.Contains(r.OdooEmployeeId)
                 && r.PunchTime >= from
                 && r.PunchTime <= to
                 && r.Status == "pending"
                 && r.SitePhotoUrl != null
                 && r.SitePhotoUrl != "",
            cancellationToken: cancellationToken);

        for (var i = 0; i < dtoList.Count; i++)
        {
            var dto = dtoList[i];
            if (!string.IsNullOrWhiteSpace(dto.SitePhotoUrl))
                continue;
            var isMobileRow = (dto.Note != null && dto.Note.Contains("Mobile", StringComparison.OrdinalIgnoreCase))
                || (dto.DeviceName != null && dto.DeviceName.Contains("MOBILE", StringComparison.OrdinalIgnoreCase))
                || dto.MobileAttendanceRecordId.HasValue;
            if (!isMobileRow)
                continue;
            if (!pinToUserId.TryGetValue(dto.Pin, out var odooId))
                continue;

            var match = mobileCandidates
                .Where(r => string.Equals(r.OdooEmployeeId, odooId, StringComparison.OrdinalIgnoreCase))
                .OrderBy(r => Math.Abs((r.PunchTime - dto.AttendanceTime).TotalMinutes))
                .FirstOrDefault();
            if (match == null || string.IsNullOrWhiteSpace(match.SitePhotoUrl))
                continue;

            dtoList[i] = dto with
            {
                Latitude = dto.Latitude ?? match.Latitude,
                Longitude = dto.Longitude ?? match.Longitude,
                LocationName = dto.LocationName ?? match.LocationName,
                SitePhotoUrl = NormalizeSitePhotoUrl(match.SitePhotoUrl),
                MobileAttendanceRecordId = dto.MobileAttendanceRecordId ?? match.Id,
            };
        }
    }
}
