using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers.Reports;

/// <summary>
/// Cluster 3 & 4 — HR Analytics & Lifecycle:
/// Headcount movement, Turnover, Tenure, Demographics, Contract/Probation expiry, Birthdays, Retirement, Org headcount.
/// </summary>
[ApiController]
[Route("api/reports/hr")]
[Authorize]
public class HrAnalyticsController(
    ZKTecoDbContext db,
    ILogger<HrAnalyticsController> logger
) : AuthenticatedControllerBase
{
    // ═════════════════════════════════════════════════════════════════════
    // 1. HEADCOUNT MOVEMENT — Tuyển / nghỉ / (chuyển PB nếu có)
    // GET /api/reports/hr/headcount-movement?year=&department=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("headcount-movement")]
    public async Task<IActionResult> GetHeadcountMovement(
        [FromQuery] int? year = null,
        [FromQuery] string? department = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var y = year ?? ReportHelpers.NowVn().Year;
            var storeId = RequiredStoreId;

            var empQ = db.Employees.IgnoreQueryFilters()
                .Where(e => e.StoreId == storeId);
            if (!string.IsNullOrWhiteSpace(department))
                empQ = empQ.Where(e => e.Department != null && e.Department.Contains(department));

            var emps = await empQ
                .Select(e => new { e.JoinDate, e.ResignationDate, e.CreatedAt, e.Deleted, e.WorkStatus, e.Department })
                .ToListAsync(ct);

            var months = new List<HeadcountMovementItemDto>();
            for (int m = 1; m <= 12; m++)
            {
                var monthStart = new DateTime(y, m, 1);
                var monthEnd = monthStart.AddMonths(1);

                var hired = emps.Count(e => (e.JoinDate ?? e.CreatedAt).Date >= monthStart
                    && (e.JoinDate ?? e.CreatedAt).Date < monthEnd);
                var resigned = emps.Count(e =>
                    (e.ResignationDate.HasValue && e.ResignationDate.Value.Date >= monthStart && e.ResignationDate.Value.Date < monthEnd)
                    || (e.Deleted.HasValue && e.Deleted.Value.Date >= monthStart && e.Deleted.Value.Date < monthEnd));
                var headcountEnd = emps.Count(e =>
                    (e.JoinDate ?? e.CreatedAt).Date < monthEnd
                    && !(e.ResignationDate.HasValue && e.ResignationDate.Value.Date < monthEnd)
                    && !(e.Deleted.HasValue && e.Deleted.Value.Date < monthEnd));

                months.Add(new HeadcountMovementItemDto
                {
                    Year = y,
                    Month = m,
                    Hired = hired,
                    Resigned = resigned,
                    EndingHeadcount = headcountEnd,
                    NetChange = hired - resigned
                });
            }

            var report = new HeadcountMovementReportDto
            {
                Year = y,
                Department = department,
                Items = months,
                TotalHired = months.Sum(m => m.Hired),
                TotalResigned = months.Sum(m => m.Resigned),
                YearEndHeadcount = months.Last().EndingHeadcount
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile($"Biến động NS {y}",
                    new[] { "Tháng", "Tuyển mới", "Nghỉ việc", "HC cuối kỳ", "Net" },
                    ws =>
                    {
                        int row = 2;
                        foreach (var i in months)
                        {
                            ws.Cell(row, 1).Value = $"{i.Month:D2}/{i.Year}";
                            ws.Cell(row, 2).Value = i.Hired;
                            ws.Cell(row, 3).Value = i.Resigned;
                            ws.Cell(row, 4).Value = i.EndingHeadcount;
                            ws.Cell(row, 5).Value = i.NetChange;
                            row++;
                        }
                    },
                    $"headcount-movement-{y}.xlsx");
            }

            return Ok(AppResponse<HeadcountMovementReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Headcount movement failed");
            return StatusCode(500, AppResponse<HeadcountMovementReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 2. TURNOVER RATE — Tỷ lệ nghỉ việc theo phòng/kỳ
    // GET /api/reports/hr/turnover?year=&groupBy=department|branch
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("turnover")]
    public async Task<IActionResult> GetTurnover(
        [FromQuery] int? year = null,
        [FromQuery] string groupBy = "department",
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var y = year ?? ReportHelpers.NowVn().Year;
            var yearStart = new DateTime(y, 1, 1);
            var yearEnd = new DateTime(y + 1, 1, 1);
            var storeId = RequiredStoreId;

            var emps = await db.Employees.IgnoreQueryFilters()
                .Where(e => e.StoreId == storeId)
                .Select(e => new { e.Id, e.Department, e.BranchId, BranchName = e.Branch!.Name,
                    e.JoinDate, e.ResignationDate, e.CreatedAt, e.Deleted })
                .ToListAsync(ct);

            IEnumerable<IGrouping<string, dynamic>> groups = groupBy?.ToLowerInvariant() switch
            {
                "branch" => emps.GroupBy(e => (string)(e.BranchName ?? "(Chưa phân chi nhánh)")),
                _ => emps.GroupBy(e => (string)(e.Department ?? "(Chưa phân PB)"))
            };

            var items = new List<TurnoverItemDto>();
            foreach (var g in groups)
            {
                var list = g.ToList();
                var headStart = list.Count(e => (e.JoinDate ?? e.CreatedAt) < yearStart
                    && !((e.ResignationDate.HasValue && e.ResignationDate < yearStart)
                        || (e.Deleted.HasValue && e.Deleted < yearStart)));
                var headEnd = list.Count(e => (e.JoinDate ?? e.CreatedAt) < yearEnd
                    && !((e.ResignationDate.HasValue && e.ResignationDate < yearEnd)
                        || (e.Deleted.HasValue && e.Deleted < yearEnd)));
                var resigned = list.Count(e =>
                    (e.ResignationDate.HasValue && e.ResignationDate >= yearStart && e.ResignationDate < yearEnd)
                    || (e.Deleted.HasValue && e.Deleted >= yearStart && e.Deleted < yearEnd));

                var avg = (headStart + headEnd) / 2.0;
                var rate = avg > 0 ? Math.Round(resigned / avg * 100, 2) : 0;

                items.Add(new TurnoverItemDto
                {
                    GroupName = g.Key,
                    HeadcountStart = headStart,
                    HeadcountEnd = headEnd,
                    Resigned = resigned,
                    TurnoverRate = rate
                });
            }

            var report = new TurnoverReportDto
            {
                Year = y,
                GroupBy = groupBy ?? "department",
                Items = items.OrderByDescending(i => i.TurnoverRate).ToList()
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile($"Turnover {y}",
                    new[] { "Nhóm", "HC đầu năm", "HC cuối năm", "Nghỉ việc", "Tỷ lệ %" },
                    ws =>
                    {
                        int row = 2;
                        foreach (var i in items)
                        {
                            ws.Cell(row, 1).Value = i.GroupName;
                            ws.Cell(row, 2).Value = i.HeadcountStart;
                            ws.Cell(row, 3).Value = i.HeadcountEnd;
                            ws.Cell(row, 4).Value = i.Resigned;
                            ReportHelpers.PercentCell(ws.Cell(row, 5), i.TurnoverRate);
                            row++;
                        }
                    },
                    $"turnover-{y}.xlsx");
            }

            return Ok(AppResponse<TurnoverReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Turnover failed");
            return StatusCode(500, AppResponse<TurnoverReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 3. TENURE DISTRIBUTION — Phân bố thâm niên
    // GET /api/reports/hr/tenure-distribution?department=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("tenure-distribution")]
    public async Task<IActionResult> GetTenureDistribution(
        [FromQuery] string? department = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var storeId = RequiredStoreId;
            var now = ReportHelpers.NowVn();

            var q = db.Employees.Where(e => e.StoreId == storeId && e.Deleted == null
                && e.WorkStatus == EmployeeWorkStatus.Active);
            if (!string.IsNullOrWhiteSpace(department))
                q = q.Where(e => e.Department != null && e.Department.Contains(department));

            var emps = await q
                .Select(e => new { e.Id, e.EmployeeCode, e.FirstName, e.LastName, e.Department, e.JoinDate, e.CreatedAt })
                .ToListAsync(ct);

            string Bucket(double m)
                => m < 6 ? "< 6 tháng"
                : m < 12 ? "6–12 tháng"
                : m < 36 ? "1–3 năm"
                : m < 60 ? "3–5 năm"
                : "> 5 năm";

            var withMonths = emps.Select(e =>
            {
                var start = e.JoinDate ?? e.CreatedAt;
                var months = (now - start).TotalDays / 30.44;
                return new { e, months, bucket = Bucket(months) };
            }).ToList();

            var buckets = new[] { "< 6 tháng", "6–12 tháng", "1–3 năm", "3–5 năm", "> 5 năm" }
                .Select(b => new TenureBucketDto
                {
                    Bucket = b,
                    Count = withMonths.Count(x => x.bucket == b),
                    Percent = withMonths.Count > 0
                        ? Math.Round((double)withMonths.Count(x => x.bucket == b) / withMonths.Count * 100, 2)
                        : 0
                })
                .ToList();

            var report = new TenureDistributionReportDto
            {
                Total = emps.Count,
                Buckets = buckets,
                AvgMonths = withMonths.Count > 0 ? Math.Round(withMonths.Average(x => x.months), 1) : 0
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Tenure",
                    new[] { "Bậc thâm niên", "Số NV", "Tỷ lệ %" },
                    ws =>
                    {
                        int row = 2;
                        foreach (var b in buckets)
                        {
                            ws.Cell(row, 1).Value = b.Bucket;
                            ws.Cell(row, 2).Value = b.Count;
                            ReportHelpers.PercentCell(ws.Cell(row, 3), b.Percent);
                            row++;
                        }
                    },
                    "tenure-distribution.xlsx");
            }

            return Ok(AppResponse<TenureDistributionReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Tenure failed");
            return StatusCode(500, AppResponse<TenureDistributionReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 4. DEMOGRAPHICS — Phân bố độ tuổi / giới tính theo phòng ban
    // GET /api/reports/hr/demographics?department=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("demographics")]
    public async Task<IActionResult> GetDemographics(
        [FromQuery] string? department = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var storeId = RequiredStoreId;
            var now = ReportHelpers.NowVn();

            var q = db.Employees.Where(e => e.StoreId == storeId && e.Deleted == null
                && e.WorkStatus == EmployeeWorkStatus.Active);
            if (!string.IsNullOrWhiteSpace(department))
                q = q.Where(e => e.Department != null && e.Department.Contains(department));

            var emps = await q
                .Select(e => new { e.Gender, e.DateOfBirth, e.Department, e.MaritalStatus })
                .ToListAsync(ct);

            static string AgeBucket(int? age)
                => age == null ? "N/A"
                : age < 25 ? "< 25"
                : age < 35 ? "25–34"
                : age < 45 ? "35–44"
                : age < 55 ? "45–54"
                : "≥ 55";

            var perDept = emps
                .GroupBy(e => e.Department ?? "(Chưa phân PB)")
                .Select(g =>
                {
                    var ages = g.Select(e =>
                    {
                        if (!e.DateOfBirth.HasValue) return (int?)null;
                        var age = now.Year - e.DateOfBirth.Value.Year;
                        if (e.DateOfBirth.Value.Date > now.AddYears(-age)) age--;
                        return age;
                    }).ToList();

                    return new DemographicsItemDto
                    {
                        Department = g.Key,
                        Total = g.Count(),
                        Male = g.Count(x => x.Gender == "Male" || x.Gender == "Nam"),
                        Female = g.Count(x => x.Gender == "Female" || x.Gender == "Nữ"),
                        Other = g.Count(x => x.Gender != null && x.Gender != "Male" && x.Gender != "Female"
                            && x.Gender != "Nam" && x.Gender != "Nữ"),
                        Age_Under25 = ages.Count(a => AgeBucket(a) == "< 25"),
                        Age_25_34 = ages.Count(a => AgeBucket(a) == "25–34"),
                        Age_35_44 = ages.Count(a => AgeBucket(a) == "35–44"),
                        Age_45_54 = ages.Count(a => AgeBucket(a) == "45–54"),
                        Age_55Plus = ages.Count(a => AgeBucket(a) == "≥ 55"),
                        AvgAge = ages.Where(a => a.HasValue).Any()
                            ? Math.Round(ages.Where(a => a.HasValue).Average(a => a!.Value), 1)
                            : 0
                    };
                })
                .OrderByDescending(d => d.Total)
                .ToList();

            var report = new DemographicsReportDto
            {
                Total = emps.Count,
                Items = perDept
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Demographics",
                    new[] { "Phòng ban", "Tổng", "Nam", "Nữ", "Khác", "< 25", "25–34", "35–44", "45–54", "≥ 55", "Tuổi TB" },
                    ws =>
                    {
                        int row = 2;
                        foreach (var i in perDept)
                        {
                            ws.Cell(row, 1).Value = i.Department;
                            ws.Cell(row, 2).Value = i.Total;
                            ws.Cell(row, 3).Value = i.Male;
                            ws.Cell(row, 4).Value = i.Female;
                            ws.Cell(row, 5).Value = i.Other;
                            ws.Cell(row, 6).Value = i.Age_Under25;
                            ws.Cell(row, 7).Value = i.Age_25_34;
                            ws.Cell(row, 8).Value = i.Age_35_44;
                            ws.Cell(row, 9).Value = i.Age_45_54;
                            ws.Cell(row, 10).Value = i.Age_55Plus;
                            ws.Cell(row, 11).Value = i.AvgAge;
                            row++;
                        }
                    },
                    "demographics.xlsx");
            }

            return Ok(AppResponse<DemographicsReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Demographics failed");
            return StatusCode(500, AppResponse<DemographicsReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 5. CONTRACT / PROBATION EXPIRY — Sắp hết HĐ thử việc/chính thức
    // GET /api/reports/hr/contract-expiry?days=90&department=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("contract-expiry")]
    public async Task<IActionResult> GetContractExpiry(
        [FromQuery] int days = 90,
        [FromQuery] string? department = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var storeId = RequiredStoreId;
            var today = ReportHelpers.NowVn().Date;
            var cutoff = today.AddDays(Math.Max(1, days));

            var q = db.Employees.Where(e => e.StoreId == storeId && e.Deleted == null
                && e.WorkStatus == EmployeeWorkStatus.Active
                && e.ProbationEndDate != null
                && e.ProbationEndDate >= today && e.ProbationEndDate <= cutoff);
            if (!string.IsNullOrWhiteSpace(department))
                q = q.Where(e => e.Department != null && e.Department.Contains(department));

            var emps = await q
                .Select(e => new { e.Id, e.EmployeeCode, e.FirstName, e.LastName, e.Department, e.Position, e.JoinDate, e.ProbationEndDate, e.EmploymentType })
                .ToListAsync(ct);

            var items = emps.Select(e => new ContractExpiryItemDto
            {
                EmployeeId = e.Id,
                EmployeeCode = e.EmployeeCode,
                EmployeeName = ReportHelpers.FullName(e.LastName, e.FirstName),
                Department = e.Department ?? "N/A",
                Position = e.Position ?? "-",
                EmploymentType = e.EmploymentType.ToString(),
                JoinDate = e.JoinDate,
                ExpiryDate = e.ProbationEndDate!.Value,
                DaysRemaining = (int)(e.ProbationEndDate.Value.Date - today).TotalDays
            })
            .OrderBy(i => i.DaysRemaining)
            .ToList();

            var report = new ContractExpiryReportDto
            {
                Days = days,
                Total = items.Count,
                Urgent30 = items.Count(i => i.DaysRemaining <= 30),
                Soon60 = items.Count(i => i.DaysRemaining > 30 && i.DaysRemaining <= 60),
                Later90 = items.Count(i => i.DaysRemaining > 60 && i.DaysRemaining <= 90),
                Items = items
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Contract expiry",
                    new[] { "STT", "Mã NV", "Họ tên", "Phòng ban", "Chức danh", "Loại HĐ", "Vào làm", "Hết hạn", "Còn (ngày)" },
                    ws =>
                    {
                        int row = 2; int idx = 1;
                        foreach (var i in items)
                        {
                            ws.Cell(row, 1).Value = idx++;
                            ws.Cell(row, 2).Value = i.EmployeeCode;
                            ws.Cell(row, 3).Value = i.EmployeeName;
                            ws.Cell(row, 4).Value = i.Department;
                            ws.Cell(row, 5).Value = i.Position;
                            ws.Cell(row, 6).Value = i.EmploymentType;
                            ReportHelpers.DateCell(ws.Cell(row, 7), i.JoinDate);
                            ReportHelpers.DateCell(ws.Cell(row, 8), i.ExpiryDate);
                            ws.Cell(row, 9).Value = i.DaysRemaining;
                            row++;
                        }
                    },
                    $"contract-expiry-{days}d.xlsx");
            }

            return Ok(AppResponse<ContractExpiryReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Contract expiry failed");
            return StatusCode(500, AppResponse<ContractExpiryReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 6. BIRTHDAYS — Sinh nhật sắp tới trong N ngày
    // GET /api/reports/hr/birthdays?days=30&department=
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("birthdays")]
    public async Task<IActionResult> GetBirthdays(
        [FromQuery] int days = 30,
        [FromQuery] string? department = null,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var storeId = RequiredStoreId;
            var today = ReportHelpers.NowVn().Date;

            var q = db.Employees.Where(e => e.StoreId == storeId && e.Deleted == null
                && e.WorkStatus == EmployeeWorkStatus.Active
                && e.DateOfBirth != null);
            if (!string.IsNullOrWhiteSpace(department))
                q = q.Where(e => e.Department != null && e.Department.Contains(department));

            var emps = await q
                .Select(e => new { e.Id, e.EmployeeCode, e.FirstName, e.LastName, e.Department, e.DateOfBirth })
                .ToListAsync(ct);

            var items = new List<BirthdayItemDto>();
            foreach (var e in emps)
            {
                var dob = e.DateOfBirth!.Value;
                var nextBd = new DateTime(today.Year, dob.Month, Math.Min(dob.Day, DateTime.DaysInMonth(today.Year, dob.Month)));
                if (nextBd < today) nextBd = nextBd.AddYears(1);
                var daysTo = (int)(nextBd - today).TotalDays;
                if (daysTo > days) continue;

                var turningAge = nextBd.Year - dob.Year;
                items.Add(new BirthdayItemDto
                {
                    EmployeeId = e.Id,
                    EmployeeCode = e.EmployeeCode,
                    EmployeeName = ReportHelpers.FullName(e.LastName, e.FirstName),
                    Department = e.Department ?? "N/A",
                    DateOfBirth = dob,
                    NextBirthday = nextBd,
                    DaysUntil = daysTo,
                    TurningAge = turningAge
                });
            }
            items = items.OrderBy(i => i.DaysUntil).ToList();

            var report = new BirthdayReportDto { Days = days, Total = items.Count, Items = items };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Sinh nhật",
                    new[] { "STT", "Mã NV", "Họ tên", "Phòng ban", "Ngày sinh", "SN sắp tới", "Còn (ngày)", "Tròn tuổi" },
                    ws =>
                    {
                        int row = 2; int idx = 1;
                        foreach (var i in items)
                        {
                            ws.Cell(row, 1).Value = idx++;
                            ws.Cell(row, 2).Value = i.EmployeeCode;
                            ws.Cell(row, 3).Value = i.EmployeeName;
                            ws.Cell(row, 4).Value = i.Department;
                            ReportHelpers.DateCell(ws.Cell(row, 5), i.DateOfBirth);
                            ReportHelpers.DateCell(ws.Cell(row, 6), i.NextBirthday);
                            ws.Cell(row, 7).Value = i.DaysUntil;
                            ws.Cell(row, 8).Value = i.TurningAge;
                            row++;
                        }
                    },
                    $"birthdays-{days}d.xlsx");
            }

            return Ok(AppResponse<BirthdayReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Birthdays failed");
            return StatusCode(500, AppResponse<BirthdayReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 7. RETIREMENT — Sắp nghỉ hưu (nam 62, nữ 60 — VN)
    // GET /api/reports/hr/retirement?years=5
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("retirement")]
    public async Task<IActionResult> GetRetirement(
        [FromQuery] int years = 5,
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var storeId = RequiredStoreId;
            var today = ReportHelpers.NowVn().Date;

            var emps = await db.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null
                    && e.WorkStatus == EmployeeWorkStatus.Active
                    && e.DateOfBirth != null)
                .Select(e => new { e.Id, e.EmployeeCode, e.FirstName, e.LastName, e.Department, e.Gender, e.DateOfBirth })
                .ToListAsync(ct);

            var items = new List<RetirementItemDto>();
            foreach (var e in emps)
            {
                var isMale = e.Gender == "Male" || e.Gender == "Nam";
                var retAge = isMale ? 62 : 60;
                var dob = e.DateOfBirth!.Value.Date;
                var retDate = dob.AddYears(retAge);
                var yearsTo = (retDate - today).TotalDays / 365.25;
                if (yearsTo < 0 || yearsTo > years) continue;

                items.Add(new RetirementItemDto
                {
                    EmployeeId = e.Id,
                    EmployeeCode = e.EmployeeCode,
                    EmployeeName = ReportHelpers.FullName(e.LastName, e.FirstName),
                    Department = e.Department ?? "N/A",
                    Gender = e.Gender ?? "-",
                    DateOfBirth = dob,
                    RetirementDate = retDate,
                    YearsRemaining = Math.Round(yearsTo, 2)
                });
            }
            items = items.OrderBy(i => i.YearsRemaining).ToList();

            var report = new RetirementReportDto { Years = years, Total = items.Count, Items = items };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Nghỉ hưu",
                    new[] { "Mã NV", "Họ tên", "Phòng ban", "Giới tính", "Sinh nhật", "Ngày hưu", "Còn (năm)" },
                    ws =>
                    {
                        int row = 2;
                        foreach (var i in items)
                        {
                            ws.Cell(row, 1).Value = i.EmployeeCode;
                            ws.Cell(row, 2).Value = i.EmployeeName;
                            ws.Cell(row, 3).Value = i.Department;
                            ws.Cell(row, 4).Value = i.Gender;
                            ReportHelpers.DateCell(ws.Cell(row, 5), i.DateOfBirth);
                            ReportHelpers.DateCell(ws.Cell(row, 6), i.RetirementDate);
                            ws.Cell(row, 7).Value = i.YearsRemaining;
                            row++;
                        }
                    },
                    $"retirement-{years}y.xlsx");
            }

            return Ok(AppResponse<RetirementReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Retirement failed");
            return StatusCode(500, AppResponse<RetirementReportDto>.Fail(ex.Message));
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // 8. ORG HEADCOUNT — Headcount theo phòng ban + chi nhánh
    // GET /api/reports/hr/org-headcount
    // ═════════════════════════════════════════════════════════════════════
    [HttpGet("org-headcount")]
    public async Task<IActionResult> GetOrgHeadcount(
        [FromQuery] string? format = null,
        CancellationToken ct = default)
    {
        try
        {
            var storeId = RequiredStoreId;

            var emps = await db.Employees
                .Where(e => e.StoreId == storeId && e.Deleted == null
                    && e.WorkStatus == EmployeeWorkStatus.Active)
                .Select(e => new { e.Department, BranchName = e.Branch!.Name, e.Position, e.Level })
                .ToListAsync(ct);

            var byDept = emps
                .GroupBy(e => e.Department ?? "(Chưa phân PB)")
                .Select(g => new OrgHeadcountItemDto
                {
                    Key = "Phòng ban",
                    Name = g.Key,
                    Count = g.Count()
                })
                .OrderByDescending(g => g.Count).ToList();

            var byBranch = emps
                .GroupBy(e => e.BranchName ?? "(Chưa phân chi nhánh)")
                .Select(g => new OrgHeadcountItemDto { Key = "Chi nhánh", Name = g.Key, Count = g.Count() })
                .OrderByDescending(g => g.Count).ToList();

            var byLevel = emps
                .GroupBy(e => e.Level ?? "(Chưa phân cấp)")
                .Select(g => new OrgHeadcountItemDto { Key = "Cấp bậc", Name = g.Key, Count = g.Count() })
                .OrderByDescending(g => g.Count).ToList();

            var report = new OrgHeadcountReportDto
            {
                Total = emps.Count,
                ByDepartment = byDept,
                ByBranch = byBranch,
                ByLevel = byLevel
            };

            if (string.Equals(format, "excel", StringComparison.OrdinalIgnoreCase))
            {
                return ReportHelpers.ExcelFile("Org headcount",
                    new[] { "Nhóm", "Tên", "Số người" },
                    ws =>
                    {
                        int row = 2;
                        foreach (var list in new[] { byDept, byBranch, byLevel })
                            foreach (var i in list)
                            {
                                ws.Cell(row, 1).Value = i.Key;
                                ws.Cell(row, 2).Value = i.Name;
                                ws.Cell(row, 3).Value = i.Count;
                                row++;
                            }
                    },
                    "org-headcount.xlsx");
            }

            return Ok(AppResponse<OrgHeadcountReportDto>.Success(report));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Org headcount failed");
            return StatusCode(500, AppResponse<OrgHeadcountReportDto>.Fail(ex.Message));
        }
    }
}

// ══════════════════════════ DTOs (Cluster 3+4) ═══════════════════════════

public class HeadcountMovementReportDto
{
    public int Year { get; set; }
    public string? Department { get; set; }
    public int TotalHired { get; set; }
    public int TotalResigned { get; set; }
    public int YearEndHeadcount { get; set; }
    public List<HeadcountMovementItemDto> Items { get; set; } = new();
}
public class HeadcountMovementItemDto
{
    public int Year { get; set; }
    public int Month { get; set; }
    public int Hired { get; set; }
    public int Resigned { get; set; }
    public int EndingHeadcount { get; set; }
    public int NetChange { get; set; }
}

public class TurnoverReportDto
{
    public int Year { get; set; }
    public string GroupBy { get; set; } = "department";
    public List<TurnoverItemDto> Items { get; set; } = new();
}
public class TurnoverItemDto
{
    public string GroupName { get; set; } = string.Empty;
    public int HeadcountStart { get; set; }
    public int HeadcountEnd { get; set; }
    public int Resigned { get; set; }
    public double TurnoverRate { get; set; }
}

public class TenureDistributionReportDto
{
    public int Total { get; set; }
    public double AvgMonths { get; set; }
    public List<TenureBucketDto> Buckets { get; set; } = new();
}
public class TenureBucketDto
{
    public string Bucket { get; set; } = string.Empty;
    public int Count { get; set; }
    public double Percent { get; set; }
}

public class DemographicsReportDto
{
    public int Total { get; set; }
    public List<DemographicsItemDto> Items { get; set; } = new();
}
public class DemographicsItemDto
{
    public string Department { get; set; } = string.Empty;
    public int Total { get; set; }
    public int Male { get; set; }
    public int Female { get; set; }
    public int Other { get; set; }
    public int Age_Under25 { get; set; }
    public int Age_25_34 { get; set; }
    public int Age_35_44 { get; set; }
    public int Age_45_54 { get; set; }
    public int Age_55Plus { get; set; }
    public double AvgAge { get; set; }
}

public class ContractExpiryReportDto
{
    public int Days { get; set; }
    public int Total { get; set; }
    public int Urgent30 { get; set; }
    public int Soon60 { get; set; }
    public int Later90 { get; set; }
    public List<ContractExpiryItemDto> Items { get; set; } = new();
}
public class ContractExpiryItemDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public string Position { get; set; } = string.Empty;
    public string EmploymentType { get; set; } = string.Empty;
    public DateTime? JoinDate { get; set; }
    public DateTime ExpiryDate { get; set; }
    public int DaysRemaining { get; set; }
}

public class BirthdayReportDto
{
    public int Days { get; set; }
    public int Total { get; set; }
    public List<BirthdayItemDto> Items { get; set; } = new();
}
public class BirthdayItemDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public DateTime DateOfBirth { get; set; }
    public DateTime NextBirthday { get; set; }
    public int DaysUntil { get; set; }
    public int TurningAge { get; set; }
}

public class RetirementReportDto
{
    public int Years { get; set; }
    public int Total { get; set; }
    public List<RetirementItemDto> Items { get; set; } = new();
}
public class RetirementItemDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeCode { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string Department { get; set; } = string.Empty;
    public string Gender { get; set; } = string.Empty;
    public DateTime DateOfBirth { get; set; }
    public DateTime RetirementDate { get; set; }
    public double YearsRemaining { get; set; }
}

public class OrgHeadcountReportDto
{
    public int Total { get; set; }
    public List<OrgHeadcountItemDto> ByDepartment { get; set; } = new();
    public List<OrgHeadcountItemDto> ByBranch { get; set; } = new();
    public List<OrgHeadcountItemDto> ByLevel { get; set; } = new();
}
public class OrgHeadcountItemDto
{
    public string Key { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public int Count { get; set; }
}
