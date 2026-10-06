using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers.Reports;

/// <summary>
/// Ca được gán cho từng nhân viên (giống báo cáo «Đi muộn / về sớm» và tab Flutter «Tổng hợp theo ca»):
/// mức lương ca (ShiftSalaryLevel.EmployeeIds) + hồ sơ lương «shifts:Ca A,Ca B». NV chưa gán ca → mọi ca đang dùng.
/// Dùng để tính đi muộn theo ĐÚNG CA thay cho ngưỡng cố định 08:30 (ca chiều / ca đêm bị tính muộn oan).
/// </summary>
public sealed class ShiftAssignmentResolver
{
    /// <summary>Ngưỡng cũ — chỉ dùng khi cửa hàng chưa tạo ca nào.</summary>
    public static readonly TimeSpan LegacyLateThreshold = new(8, 30, 0);

    readonly Dictionary<Guid, List<ShiftMatchHelper.Candidate>> _byEmployee;
    readonly List<ShiftMatchHelper.Candidate> _all;

    ShiftAssignmentResolver(Dictionary<Guid, List<ShiftMatchHelper.Candidate>> byEmployee, List<ShiftMatchHelper.Candidate> all)
    {
        _byEmployee = byEmployee;
        _all = all;
    }

    public bool HasShifts => _all.Count > 0;

    public IReadOnlyList<ShiftMatchHelper.Candidate> CandidatesFor(Guid employeeId) =>
        _byEmployee.TryGetValue(employeeId, out var list) && list.Count > 0 ? list : _all;

    /// <summary>
    /// Số phút đi muộn (sau ân hạn) của giờ vào đầu tiên trong ngày công, theo ca khớp nhất.
    /// Chưa có ca nào → so ngưỡng 08:30 như trước. Có ca nhưng giờ vào không gần ca nào → không tính muộn.
    /// </summary>
    public int LateMinutes(Guid employeeId, TimeSpan firstIn)
    {
        if (!HasShifts)
            return firstIn > LegacyLateThreshold ? (int)(firstIn - LegacyLateThreshold).TotalMinutes : 0;
        var fit = ShiftMatchHelper.FindBestForCheckIn(CandidatesFor(employeeId), firstIn);
        if (fit != null) return fit.EffectiveLateIn;
        // Muộn quá «muộn tối đa cho phép» → bộ ghép ca loại ca đó (không tính công ca, giống bảng lương);
        // báo cáo đi muộn vẫn phải ghi nhận: lấy ca có giờ vào gần nhất (≤ 3 giờ) và tính phút muộn thật.
        var near = NearestByStart(employeeId, firstIn);
        if (near == null) return 0;
        var late = ShiftMatchHelper.MinutesLateAfterStart(firstIn, near.StartTime, near.EndTime) - Math.Max(0, near.LateGraceMinutes);
        return late > 0 ? late : 0;
    }

    /// <summary>Ca có giờ vào gần giờ chấm nhất (vòng 24h), tối đa 3 giờ — dùng khi không ca nào khớp theo luật ca.</summary>
    public ShiftMatchHelper.Candidate? NearestByStart(Guid employeeId, TimeSpan punch) =>
        CandidatesFor(employeeId)
            .Select(c => (c, d: ShiftMatchHelper.CircularMinutes(punch, c.StartTime)))
            .Where(x => x.d <= 180)
            .OrderBy(x => x.d)
            .Select(x => x.c)
            .FirstOrDefault();

    /// <summary>Ca khớp nhất cho cặp vào / ra (để so «đến sớm / về muộn bất thường» theo giờ ca).</summary>
    public ShiftMatchHelper.Candidate? BestShift(Guid employeeId, TimeSpan firstIn, TimeSpan? lastOut) =>
        HasShifts
            ? ShiftMatchHelper.FindBest(CandidatesFor(employeeId), firstIn, lastOut)?.Shift ?? NearestByStart(employeeId, firstIn)
            : null;

    public static async Task<ShiftAssignmentResolver> LoadAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid> employeeIds, CancellationToken ct = default)
    {
        var templates = await db.ShiftTemplates.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.IsActive)
            .Select(s => new
            {
                s.Id, s.Name, s.StartTime, s.EndTime, s.LateGraceMinutes, s.EarlyLeaveGraceMinutes,
                s.MaximumAllowedLateMinutes, s.EarlyCheckInMinutes, s.MaximumAllowedEarlyLeaveMinutes, s.ShiftType,
            })
            .ToListAsync(ct);
        var all = templates.Select(s => new ShiftMatchHelper.Candidate(
                s.Id, s.StartTime, s.EndTime, s.LateGraceMinutes, s.EarlyLeaveGraceMinutes,
                s.MaximumAllowedLateMinutes > 0 ? s.MaximumAllowedLateMinutes : 30,
                s.EarlyCheckInMinutes > 0 ? s.EarlyCheckInMinutes : 30,
                s.MaximumAllowedEarlyLeaveMinutes > 0 ? s.MaximumAllowedEarlyLeaveMinutes : 120,
                s.ShiftType, s.Name))
            .ToList();
        var byId = all.ToDictionary(c => c.Id);
        static string Norm(string? s) =>
            System.Text.RegularExpressions.Regex.Replace((s ?? string.Empty).Trim().ToLowerInvariant(), @"\s+", " ");
        var byName = all.Where(c => !string.IsNullOrWhiteSpace(c.Name))
            .GroupBy(c => Norm(c.Name)).ToDictionary(g => g.Key, g => g.First());

        var empSet = employeeIds.ToHashSet();
        var map = new Dictionary<Guid, List<ShiftMatchHelper.Candidate>>();
        void Add(Guid emp, Guid shiftId)
        {
            if (!empSet.Contains(emp) || !byId.TryGetValue(shiftId, out var c)) return;
            if (!map.TryGetValue(emp, out var list)) map[emp] = list = [];
            if (!list.Contains(c)) list.Add(c);
        }

        var levels = await db.Set<ShiftSalaryLevel>().AsNoTracking()
            .Select(l => new { l.ShiftTemplateId, l.EmployeeIds })
            .ToListAsync(ct);
        foreach (var lvl in levels)
        {
            if (string.IsNullOrWhiteSpace(lvl.EmployeeIds)) continue;
            List<string>? ids = null;
            try { ids = System.Text.Json.JsonSerializer.Deserialize<List<string>>(lvl.EmployeeIds); } catch { /* JSON lỗi */ }
            foreach (var raw in ids ?? [])
                if (Guid.TryParse(raw, out var g)) Add(g, lvl.ShiftTemplateId);
        }

        var benefits = await (
            from eb in db.Set<EmployeeBenefit>()
            join b in db.Set<Benefit>() on eb.BenefitId equals b.Id
            where b.StoreId == storeId && empSet.Contains(eb.EmployeeId)
            select new { eb.EmployeeId, b.Description, eb.EffectiveDate }
        ).ToListAsync(ct);
        foreach (var g in benefits.GroupBy(x => x.EmployeeId))
        {
            var desc = g.OrderByDescending(x => x.EffectiveDate).First().Description;
            var shifts = DescField(desc, "shifts");
            foreach (var raw in shifts.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
                if (byName.TryGetValue(Norm(raw), out var c)) Add(g.Key, c.Id);
        }
        return new ShiftAssignmentResolver(map, all);
    }

    static string DescField(string? description, string key)
    {
        if (string.IsNullOrEmpty(description)) return string.Empty;
        foreach (var part in description.Split('|'))
        {
            var idx = part.IndexOf(':');
            if (idx > 0 && string.Equals(part[..idx].Trim(), key, StringComparison.Ordinal))
                return part[(idx + 1)..].Trim();
        }
        return string.Empty;
    }
}
