using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Helpers;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Quá trình công tác của nhân viên — một dòng thời gian gộp:
/// vào làm / nghỉ việc, điều chuyển · bổ nhiệm · thăng chức, khen thưởng, kỷ luật (EmployeeCareerRecords),
/// thưởng / phạt tiền (Tài chính nhân sự), hợp đồng · quyết định (Hồ sơ giấy tờ), khen thưởng / kỷ luật nhập ở bản cũ.
/// </summary>
[ApiController]
[Route("api/employee-career")]
[Authorize]
public class EmployeeCareerController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    static readonly HashSet<string> RecordKinds = ["award", "discipline", "transfer", "appointment", "promotion"];

    static readonly Dictionary<HrDocumentType, string> DocKinds = new()
    {
        [HrDocumentType.Contract] = "contract",
        [HrDocumentType.Appointment] = "appointment",
        [HrDocumentType.SalaryAdjustment] = "salary",
        [HrDocumentType.Discipline] = "discipline",
        [HrDocumentType.Award] = "award",
        [HrDocumentType.Certificate] = "certificate",
        [HrDocumentType.Handover] = "handover",
    };

    /// <summary>Quản lý được xem / sửa mọi người; nhân viên chỉ xem của chính mình.</summary>
    async Task<(Employee? emp, bool own)> EmployeeAsync(Guid employeeId)
    {
        var storeId = RequiredStoreId;
        var emp = await db.Employees.AsNoTracking().FirstOrDefaultAsync(e => e.Id == employeeId && e.StoreId == storeId);
        return (emp, emp?.ApplicationUserId == CurrentUserId);
    }

    static List<string> Urls(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            return JsonSerializer.Deserialize<List<string>>(json) ?? [];
        }
        catch
        {
            return [];
        }
    }

    // ─── Dòng thời gian ──────────────────────────────────────────

    [HttpGet("{employeeId:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<object>>> Get(Guid employeeId)
    {
        var storeId = RequiredStoreId;
        var (emp, own) = await EmployeeAsync(employeeId);
        if (emp == null) return Ok(AppResponse<object>.Error("Không tìm thấy nhân viên"));
        if (!own && !IsManager) return Ok(AppResponse<object>.Error("Bạn chỉ xem được quá trình công tác của mình"));
        // Điều chuyển hẹn ngày đã tới hiệu lực → cập nhật hồ sơ trước khi hiển thị.
        if (await CareerMoveApplier.ApplyDueAsync(db, CareerMoveApplier.TodayVn, employeeId) > 0)
            (emp, _) = await EmployeeAsync(employeeId);
        emp = emp!;

        var events = new List<CareerEvent>();
        if (emp.JoinDate is DateTime jd)
            events.Add(new CareerEvent("join", "join", jd, "Vào làm", $"{emp.Position ?? "Nhân viên"}{(string.IsNullOrWhiteSpace(emp.Department) ? "" : " · " + emp.Department)}"));
        if (emp.ResignationDate is DateTime rd)
            events.Add(new CareerEvent("resign", "resign", rd, "Nghỉ việc", null));

        // Bản ghi quá trình công tác
        var records = await db.EmployeeCareerRecords.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.EmployeeId == employeeId)
            .ToListAsync();
        foreach (var r in records)
        {
            var sub = r.Kind is "transfer" or "appointment" or "promotion"
                ? string.Join("  ›  ", new[]
                {
                    string.Join(" · ", new[] { r.FromPosition, r.FromDepartment }.Where(x => !string.IsNullOrWhiteSpace(x))),
                    string.Join(" · ", new[] { r.ToPosition, r.ToDepartment }.Where(x => !string.IsNullOrWhiteSpace(x))),
                }.Where(x => x.Length > 0))
                : r.Form;
            events.Add(new CareerEvent($"rec:{r.Id}", r.Kind, r.EffectiveDate, r.Title, sub)
            {
                Source = "record",
                RecordId = r.Id,
                Form = r.Form,
                DecisionNumber = r.DecisionNumber,
                IssuedBy = r.IssuedBy,
                Amount = r.Amount,
                Note = r.Note,
                EndDate = r.EndDate,
                Attachments = Urls(r.AttachmentUrls),
                Editable = true,
            });
        }

        // Gán chức vụ / phòng ban (sơ đồ tổ chức) chưa có bản ghi điều chuyển tương ứng
        var linked = records.Where(r => r.OrgAssignmentId != null).Select(r => r.OrgAssignmentId!.Value).ToHashSet();
        var assigns = await db.OrgAssignments.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.EmployeeId == employeeId)
            .Select(a => new { a.Id, a.StartDate, a.EndDate, a.CreatedAt, Dept = a.Department.Name, Pos = a.Position.Name, a.IsPrimary })
            .ToListAsync();
        foreach (var a in assigns.Where(a => !linked.Contains(a.Id)))
        {
            events.Add(new CareerEvent($"asg:{a.Id}", "appointment", a.StartDate ?? a.CreatedAt,
                $"Giữ chức vụ {a.Pos}", $"{a.Dept}{(a.EndDate is DateTime e ? $" · đến {e:dd/MM/yyyy}" : "")}")
            {
                Source = "assignment",
                EndDate = a.EndDate,
            });
        }

        // Thưởng / phạt tiền (Tài chính nhân sự)
        var userId = emp.ApplicationUserId;
        var money = await db.PaymentTransactions.AsNoTracking()
            .Where(t => (t.Type == "Bonus" || t.Type == "Penalty")
                && (t.EmployeeId == employeeId || (t.EmployeeId == null && userId != null && t.EmployeeUserId == userId)))
            .Select(t => new { t.Id, t.Type, t.TransactionDate, t.Amount, t.Description, t.Note, t.Status })
            .ToListAsync();
        foreach (var t in money.Where(t => t.Status != "Cancelled"))
        {
            var bonus = t.Type == "Bonus";
            events.Add(new CareerEvent($"pay:{t.Id}", bonus ? "bonus" : "penalty", t.TransactionDate,
                string.IsNullOrWhiteSpace(t.Description) ? (bonus ? "Thưởng" : "Phạt") : t.Description!, t.Note)
            {
                Source = "finance",
                Amount = t.Amount,
            });
        }

        // Hồ sơ giấy tờ: hợp đồng, quyết định, khen thưởng / kỷ luật nhập ở bản cũ
        var docKeys = new List<Guid> { employeeId };
        if (userId != null) docKeys.Add(userId.Value);
        var docTypes = DocKinds.Keys.ToList();
        var docs = await db.HrDocuments.AsNoTracking()
            .Where(d => docKeys.Contains(d.EmployeeUserId) && docTypes.Contains(d.DocumentType))
            .Select(d => new { d.Id, d.DocumentType, d.Name, d.Description, d.EffectiveDate, d.ExpiryDate, d.DocumentNumber, d.IssuedBy, d.Notes, d.FilePath, d.CreatedAt })
            .ToListAsync();
        foreach (var d in docs)
        {
            var hasFile = !string.IsNullOrWhiteSpace(d.FilePath) && d.FilePath != "manual_entry";
            events.Add(new CareerEvent($"doc:{d.Id}", DocKinds[d.DocumentType], d.EffectiveDate ?? d.CreatedAt, d.Name, d.Description)
            {
                Source = "document",
                DocumentId = d.Id,
                DecisionNumber = d.DocumentNumber,
                IssuedBy = d.IssuedBy,
                Note = d.Notes,
                EndDate = d.ExpiryDate,
                Attachments = hasFile ? [d.FilePath] : [],
            });
        }

        var ordered = events.OrderByDescending(e => e.Date).ThenBy(e => e.Key).ToList();
        var deptName = emp.DepartmentId is Guid did
            ? await db.Departments.AsNoTracking().Where(d => d.Id == did).Select(d => d.Name).FirstOrDefaultAsync()
            : null;
        var branchName = emp.BranchId is Guid bid
            ? await db.Branches.AsNoTracking().Where(b => b.Id == bid).Select(b => b.Name).FirstOrDefaultAsync()
            : null;
        return Ok(AppResponse<object>.Success(new
        {
            employee = new
            {
                id = emp.Id,
                name = $"{emp.LastName} {emp.FirstName}".Trim(),
                code = emp.EmployeeCode,
                photoUrl = emp.PhotoUrl,
                position = emp.Position,
                department = deptName ?? emp.Department,
                departmentId = emp.DepartmentId,
                branch = branchName,
                joinDate = emp.JoinDate,
                contractEndDate = emp.ContractEndDate,
                resignationDate = emp.ResignationDate,
                workStatus = (int)emp.WorkStatus,
            },
            summary = new
            {
                moves = ordered.Count(e => e.Kind is "transfer" or "appointment" or "promotion"),
                awards = ordered.Count(e => e.Kind == "award"),
                disciplines = ordered.Count(e => e.Kind == "discipline"),
                bonusTotal = ordered.Where(e => e.Kind == "bonus" || (e.Kind == "award" && e.Source == "record")).Sum(e => e.Amount ?? 0),
                penaltyTotal = ordered.Where(e => e.Kind == "penalty" || (e.Kind == "discipline" && e.Source == "record")).Sum(e => e.Amount ?? 0),
            },
            canEdit = IsManager,
            events = ordered.Select(e => new
            {
                key = e.Key,
                kind = e.Kind,
                date = e.Date,
                title = e.Title,
                subtitle = e.Subtitle,
                source = e.Source,
                recordId = e.RecordId,
                documentId = e.DocumentId,
                form = e.Form,
                decisionNumber = e.DecisionNumber,
                issuedBy = e.IssuedBy,
                amount = e.Amount,
                note = e.Note,
                endDate = e.EndDate,
                attachments = e.Attachments,
                editable = e.Editable && IsManager,
            }),
        }));
    }

    sealed record CareerEvent(string Key, string Kind, DateTime Date, string Title, string? Subtitle)
    {
        public string Source { get; init; } = "profile";
        public Guid? RecordId { get; init; }
        public Guid? DocumentId { get; init; }
        public string? Form { get; init; }
        public string? DecisionNumber { get; init; }
        public string? IssuedBy { get; init; }
        public decimal? Amount { get; init; }
        public string? Note { get; init; }
        public DateTime? EndDate { get; init; }
        public List<string> Attachments { get; init; } = [];
        public bool Editable { get; init; }
    }

    // ─── Khen thưởng / kỷ luật ───────────────────────────────────

    public sealed class RecordRequest
    {
        public string Kind { get; set; } = "award";
        public string Title { get; set; } = string.Empty;
        public string? Form { get; set; }
        public string? DecisionNumber { get; set; }
        public DateTime EffectiveDate { get; set; }
        public DateTime? EndDate { get; set; }
        public string? IssuedBy { get; set; }
        public decimal? Amount { get; set; }
        public string? Note { get; set; }
        public List<string>? Attachments { get; set; }
    }

    static string? Cut(string? s, int max) => string.IsNullOrWhiteSpace(s) ? null : (s.Trim().Length > max ? s.Trim()[..max] : s.Trim());

    [HttpPost("{employeeId:guid}/records")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "Employee", "HrDocument")]
    public async Task<ActionResult<AppResponse<object>>> AddRecord(Guid employeeId, [FromBody] RecordRequest req)
    {
        var (emp, _) = await EmployeeAsync(employeeId);
        if (emp == null) return Ok(AppResponse<object>.Error("Không tìm thấy nhân viên"));
        if (req.Kind is not ("award" or "discipline")) return Ok(AppResponse<object>.Error("Loại ghi nhận không hợp lệ"));
        if (string.IsNullOrWhiteSpace(req.Title)) return Ok(AppResponse<object>.Error("Nhập nội dung"));
        if (req.Amount is < 0) return Ok(AppResponse<object>.Error("Số tiền không được âm"));
        var rec = new EmployeeCareerRecord
        {
            Id = Guid.NewGuid(),
            StoreId = RequiredStoreId,
            EmployeeId = employeeId,
            Kind = req.Kind,
            Title = Cut(req.Title, 500)!,
            Form = Cut(req.Form, 100),
            DecisionNumber = Cut(req.DecisionNumber, 100),
            EffectiveDate = req.EffectiveDate == default ? DateTime.UtcNow.Date : req.EffectiveDate,
            EndDate = req.EndDate,
            IssuedBy = Cut(req.IssuedBy, 200),
            Amount = req.Amount,
            Note = Cut(req.Note, 2000),
            AttachmentUrls = req.Attachments is { Count: > 0 } ? JsonSerializer.Serialize(req.Attachments) : null,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        db.EmployeeCareerRecords.Add(rec);
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id = rec.Id }));
    }

    [HttpPut("records/{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "Employee", "HrDocument")]
    public async Task<ActionResult<AppResponse<object>>> UpdateRecord(Guid id, [FromBody] RecordRequest req)
    {
        var rec = await db.EmployeeCareerRecords.AsTracking().FirstOrDefaultAsync(r => r.Id == id && r.StoreId == RequiredStoreId);
        if (rec == null) return Ok(AppResponse<object>.Error("Không tìm thấy bản ghi"));
        if (string.IsNullOrWhiteSpace(req.Title)) return Ok(AppResponse<object>.Error("Nhập nội dung"));
        rec.Title = Cut(req.Title, 500)!;
        rec.Form = Cut(req.Form, 100);
        rec.DecisionNumber = Cut(req.DecisionNumber, 100);
        if (req.EffectiveDate != default) rec.EffectiveDate = req.EffectiveDate;
        rec.EndDate = req.EndDate;
        rec.IssuedBy = Cut(req.IssuedBy, 200);
        if (rec.Kind is "award" or "discipline") rec.Amount = req.Amount;
        rec.Note = Cut(req.Note, 2000);
        if (req.Attachments != null) rec.AttachmentUrls = req.Attachments.Count > 0 ? JsonSerializer.Serialize(req.Attachments) : null;
        rec.UpdatedAt = DateTime.UtcNow;
        rec.UpdatedBy = CurrentUserEmail;
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id }));
    }

    /// <summary>Xóa bản ghi. Điều chuyển: chỉ xóa lịch sử, không đổi phòng ban / chức vụ hiện tại của nhân viên.</summary>
    [HttpDelete("records/{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Delete, "Employee", "HrDocument")]
    public async Task<ActionResult<AppResponse<object>>> DeleteRecord(Guid id)
    {
        var rec = await db.EmployeeCareerRecords.AsTracking().FirstOrDefaultAsync(r => r.Id == id && r.StoreId == RequiredStoreId);
        if (rec == null) return Ok(AppResponse<object>.Error("Không tìm thấy bản ghi"));
        db.EmployeeCareerRecords.Remove(rec);
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id }));
    }

    // ─── Điều chuyển / bổ nhiệm / thăng chức ─────────────────────

    public sealed class MoveRequest
    {
        /// <summary>transfer | appointment | promotion</summary>
        public string Kind { get; set; } = "transfer";
        public Guid? DepartmentId { get; set; }
        public string? Position { get; set; }
        public DateTime EffectiveDate { get; set; }
        public string? DecisionNumber { get; set; }
        public string? IssuedBy { get; set; }
        public string? Note { get; set; }
        public List<string>? Attachments { get; set; }
    }

    [HttpPost("{employeeId:guid}/move")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "Employee", "Department")]
    public async Task<ActionResult<AppResponse<object>>> Move(Guid employeeId, [FromBody] MoveRequest req)
    {
        var storeId = RequiredStoreId;
        var emp = await db.Employees.AsTracking().FirstOrDefaultAsync(e => e.Id == employeeId && e.StoreId == storeId);
        if (emp == null) return Ok(AppResponse<object>.Error("Không tìm thấy nhân viên"));
        if (req.Kind is not ("transfer" or "appointment" or "promotion")) return Ok(AppResponse<object>.Error("Loại quyết định không hợp lệ"));
        var deptId = req.DepartmentId ?? emp.DepartmentId;
        if (deptId == null) return Ok(AppResponse<object>.Error("Chọn phòng ban"));
        var dept = await db.Departments.AsNoTracking().FirstOrDefaultAsync(d => d.Id == deptId && d.StoreId == storeId);
        if (dept == null) return Ok(AppResponse<object>.Error("Không tìm thấy phòng ban"));
        var positionName = Cut(req.Position, 200) ?? emp.Position;
        if (string.IsNullOrWhiteSpace(positionName)) return Ok(AppResponse<object>.Error("Nhập chức vụ"));
        if (deptId == emp.DepartmentId && string.Equals(positionName, emp.Position, StringComparison.OrdinalIgnoreCase))
            return Ok(AppResponse<object>.Error("Phòng ban và chức vụ không thay đổi"));

        var effective = (req.EffectiveDate == default ? DateTime.UtcNow.Date : req.EffectiveDate.Date);
        var fromDept = emp.DepartmentId is Guid cur
            ? await db.Departments.AsNoTracking().Where(d => d.Id == cur).Select(d => d.Name).FirstOrDefaultAsync() ?? emp.Department
            : emp.Department;

        // Chức vụ trong sơ đồ tổ chức: tìm theo tên, chưa có thì tạo.
        var position = await db.OrgPositions.AsTracking()
            .FirstOrDefaultAsync(p => p.StoreId == storeId && p.Name.ToLower() == positionName.ToLower());
        if (position == null)
        {
            var codes = await db.OrgPositions.AsNoTracking().Where(p => p.StoreId == storeId).Select(p => p.Code).ToListAsync();
            var code = new string(positionName.Where(char.IsLetterOrDigit).Take(10).ToArray()).ToUpperInvariant();
            if (code.Length == 0) code = "CV";
            var baseCode = code;
            for (var i = 2; codes.Contains(code, StringComparer.OrdinalIgnoreCase); i++) code = $"{baseCode}{i}";
            position = new OrgPosition
            {
                Id = Guid.NewGuid(), StoreId = storeId, Name = positionName, Code = code, Level = 5, IsActive = true,
                CreatedBy = CurrentUserEmail,
            };
            db.OrgPositions.Add(position);
        }

        // Kết thúc chức vụ chính cũ, mở chức vụ mới.
        var olds = await db.OrgAssignments.AsTracking()
            .Where(a => a.EmployeeId == employeeId && a.IsPrimary && a.EndDate == null)
            .ToListAsync();
        foreach (var o in olds)
        {
            o.IsPrimary = false;
            o.EndDate = effective.AddDays(-1);
            o.IsActive = false;
            o.UpdatedAt = DateTime.UtcNow;
        }
        var assignment = new OrgAssignment
        {
            Id = Guid.NewGuid(), EmployeeId = employeeId, DepartmentId = dept.Id, PositionId = position.Id, IsPrimary = true,
            StartDate = effective, StoreId = storeId, IsActive = true, CreatedBy = CurrentUserEmail,
        };
        db.OrgAssignments.Add(assignment);

        var rec = new EmployeeCareerRecord
        {
            Id = Guid.NewGuid(), StoreId = storeId, EmployeeId = employeeId, Kind = req.Kind,
            Title = req.Kind switch
            {
                "promotion" => $"Thăng chức {positionName}",
                "appointment" => $"Bổ nhiệm {positionName}",
                _ => $"Điều chuyển sang {dept.Name}",
            },
            DecisionNumber = Cut(req.DecisionNumber, 100), IssuedBy = Cut(req.IssuedBy, 200), Note = Cut(req.Note, 2000),
            EffectiveDate = effective, OrgAssignmentId = assignment.Id,
            FromDepartment = Cut(fromDept, 200), ToDepartment = Cut(dept.Name, 200),
            FromPosition = Cut(emp.Position, 200), ToPosition = Cut(positionName, 200),
            AttachmentUrls = req.Attachments is { Count: > 0 } ? JsonSerializer.Serialize(req.Attachments) : null,
            CreatedBy = CurrentUserEmail,
        };
        // Hiệu lực từ hôm nay trở về trước → cập nhật hồ sơ ngay (phòng ban, chức danh dạng chữ);
        // hẹn ngày → chờ (IsActive = false), tự áp dụng khi tới ngày.
        var appliedNow = effective <= CareerMoveApplier.TodayVn;
        rec.IsActive = appliedNow;
        db.EmployeeCareerRecords.Add(rec);
        if (appliedNow)
        {
            emp.DepartmentId = dept.Id;
            emp.Department = dept.Name;
            emp.Position = positionName;
        }
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { id = rec.Id, appliedNow }));
    }
}
