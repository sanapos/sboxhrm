using System.Globalization;
using System.Net;
using System.Text;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Tasks;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

public record TaskFormValuesDto(Dictionary<string, string?> Values);
public record TaskCheckInDto(double? Latitude, double? Longitude, string? Note);
public record TaskWorkspaceUpdateDto(string? IndustryKey, string? PhotoStorage, int? CheckInRadiusM);
public record TaskOnboardDto(string IndustryKey, bool EnableRecurring = true, List<Guid>? RecurringAssigneeIds = null);
public record TaskFromQuoteDto(string? IndustryKey, Guid? OwnerEmployeeId);

public class TaskWorkspaceDto
{
    public string? IndustryKey { get; set; }
    public string? IndustryName { get; set; }
    public string ProjectLabel { get; set; } = "Dự án";
    public string TaskLabel { get; set; } = "Công việc";
    public string PhotoStorage { get; set; } = "server";
    public bool DriveConfigured { get; set; }
    public bool DriveConnected { get; set; }
    public string? DriveAccountEmail { get; set; }
    public DateTime? DriveConnectedAt { get; set; }
    public string? DriveLastError { get; set; }
    public int CheckInRadiusM { get; set; } = 300;
    public bool Onboarded { get; set; }
}

public class TaskTimeLogDto
{
    public Guid Id { get; set; }
    public Guid? EmployeeId { get; set; }
    public string? EmployeeName { get; set; }
    public DateTime StartAt { get; set; }
    public DateTime? EndAt { get; set; }
    public int? StartDistanceM { get; set; }
    public int? EndDistanceM { get; set; }
    public double Hours { get; set; }
    public string? Note { get; set; }
}

public class TaskPersonStatDto
{
    public Guid EmployeeId { get; set; }
    public string EmployeeName { get; set; } = "—";
    public int Total { get; set; }
    public int Completed { get; set; }
    public int OnTime { get; set; }
    public int Overdue { get; set; }
    public int Rework { get; set; }
    public double OnTimeRate { get; set; }
    public double? AvgQuality { get; set; }
    public double LoggedHours { get; set; }
    public decimal PieceRateTotal { get; set; }
}

public class TaskDashboardDto
{
    public int Total { get; set; }
    public int Completed { get; set; }
    public int Overdue { get; set; }
    public double OnTimeRate { get; set; }
    public double ReworkRate { get; set; }
    public double AvgCycleHours { get; set; }
    public double? AvgQuality { get; set; }
    public double? AvgCustomerRating { get; set; }
    public double CheckInRate { get; set; }
    public decimal PieceRateTotal { get; set; }
    public Dictionary<string, int> ByType { get; set; } = new();
    public List<TaskPersonStatDto> People { get; set; } = new();
}

public class TaskPieceRateItemDto
{
    public Guid TaskId { get; set; }
    public string TaskCode { get; set; } = "";
    public string Title { get; set; } = "";
    public Guid? EmployeeId { get; set; }
    public string? EmployeeName { get; set; }
    public decimal Amount { get; set; }
    public DateTime? CompletedDate { get; set; }
    public bool Paid { get; set; }
}

/// <summary>
/// Công việc đa ngành: biểu mẫu riêng, ảnh / chữ ký lưu máy chủ hoặc Google Drive của khách,
/// check-in GPS + bấm giờ, khoán theo việc vào lương, phiếu hoàn thành PDF, bảng điều khiển, thiết lập theo ngành.
/// </summary>
public partial class TasksController
{
    TaskMediaService Media => ActivatorUtilities.CreateInstance<TaskMediaService>(HttpContext.RequestServices);

    static readonly HashSet<string> MediaCategories = ["report", "before", "after", "checklist", "signature", "comment", "file", "form"];

    static readonly Dictionary<string, string> AllowedTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        [".jpg"] = "image/jpeg", [".jpeg"] = "image/jpeg", [".png"] = "image/png", [".webp"] = "image/webp",
        [".heic"] = "image/heic", [".pdf"] = "application/pdf", [".mp4"] = "video/mp4",
        [".doc"] = "application/msword", [".docx"] = "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        [".xls"] = "application/vnd.ms-excel", [".xlsx"] = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    };

    // ─── Áp dữ liệu đa ngành khi tạo / sửa ────────────────────────

    /// <summary>Gắn biểu mẫu, khách hàng, chứng từ liên quan, toạ độ, khoán. Trả lỗi hoặc null.</summary>
    private async Task<string?> ApplyMultiIndustryAsync(WorkTask task,
        string? formSchema, Dictionary<string, string?>? formValues,
        Guid? customerId, string? customerName, string? customerPhone,
        string? relatedType, Guid? relatedId, string? relatedLabel,
        double? lat, double? lng, bool? requireCheckIn, decimal? pieceRate, bool isUpdate)
    {
        if (formSchema != null) task.FormSchema = TaskFormHelper.NormalizeSchema(formSchema);
        if (formValues is { Count: > 0 })
        {
            var (json, err) = TaskFormHelper.Merge(task.FormSchema, task.FormValues, formValues);
            if (err != null) return err;
            task.FormValues = json;
        }
        if (customerId.HasValue)
        {
            var c = await _dbContext.PosCustomers.AsNoTracking()
                .Where(x => x.Id == customerId && x.StoreId == RequiredStoreId)
                .Select(x => new { x.Id, x.Name, x.Phone, x.CompanyName })
                .FirstOrDefaultAsync();
            if (c == null) return "Không tìm thấy khách hàng";
            task.CustomerId = c.Id;
            task.CustomerName = string.IsNullOrWhiteSpace(customerName) ? (c.CompanyName ?? c.Name) : customerName.Trim();
            task.CustomerPhone = string.IsNullOrWhiteSpace(customerPhone) ? c.Phone : customerPhone.Trim();
        }
        else if (!isUpdate || customerName != null || customerPhone != null)
        {
            if (customerName != null) task.CustomerName = string.IsNullOrWhiteSpace(customerName) ? null : customerName.Trim();
            if (customerPhone != null) task.CustomerPhone = string.IsNullOrWhiteSpace(customerPhone) ? null : customerPhone.Trim();
            if (isUpdate && string.IsNullOrWhiteSpace(customerName) && customerName != null) task.CustomerId = null;
        }
        if (relatedType != null)
        {
            task.RelatedType = string.IsNullOrWhiteSpace(relatedType) ? null : relatedType.Trim().ToLowerInvariant();
            task.RelatedId = task.RelatedType == null ? null : relatedId;
            task.RelatedLabel = task.RelatedType == null || string.IsNullOrWhiteSpace(relatedLabel) ? null : relatedLabel.Trim();
        }
        if (lat.HasValue && lng.HasValue)
        {
            if (lat is < -90 or > 90 || lng is < -180 or > 180) return "Toạ độ không hợp lệ";
            task.Latitude = lat;
            task.Longitude = lng;
        }
        if (requireCheckIn.HasValue) task.RequireCheckIn = requireCheckIn.Value;
        if (pieceRate.HasValue)
        {
            if (pieceRate < 0) return "Tiền khoán không âm";
            if (task.PieceRateTransactionId == null) task.PieceRate = pieceRate == 0 ? null : pieceRate;
        }
        return null;
    }

    private void MapMultiIndustry(WorkTask task, WorkTaskDto dto)
    {
        dto.FormSchema = task.FormSchema;
        dto.FormValues = task.FormValues;
        dto.CustomerId = task.CustomerId;
        dto.CustomerName = task.CustomerName;
        dto.CustomerPhone = task.CustomerPhone;
        dto.RelatedType = task.RelatedType;
        dto.RelatedId = task.RelatedId;
        dto.RelatedLabel = task.RelatedLabel;
        dto.Latitude = task.Latitude;
        dto.Longitude = task.Longitude;
        dto.RequireCheckIn = task.RequireCheckIn;
        dto.PieceRate = task.PieceRate;
        dto.PieceRatePaid = task.PieceRateTransactionId != null;
        dto.ReworkCount = task.ReworkCount;
    }

    TaskAttachmentDto ToMediaDto(TaskAttachment a, TaskMediaService media) => new()
    {
        Id = a.Id,
        TaskId = a.TaskId,
        UploadedById = a.UploadedById,
        UploadedByName = a.UploadedBy?.UserName,
        FileName = a.FileName,
        FilePath = a.StorageKind == "gdrive" ? "" : a.FilePath,
        ContentType = a.ContentType,
        FileSize = a.FileSize,
        CreatedAt = a.CreatedAt,
        Category = a.Category,
        ChecklistItemId = a.ChecklistItemId,
        Caption = a.Caption,
        Latitude = a.Latitude,
        Longitude = a.Longitude,
        StorageKind = a.StorageKind ?? "server",
        Url = media.Url(a),
    };

    // ─── Quy tắc khi báo xong / duyệt / làm lại ──────────────────

    /// <summary>Báo xong / gửi duyệt / hoàn thành: đủ trường bắt buộc của biểu mẫu và đã check-in (nếu bắt buộc).</summary>
    private async Task<string?> CompletionBlockerAsync(WorkTask task)
    {
        var missing = TaskFormHelper.MissingRequired(task.FormSchema, task.FormValues);
        if (missing.Count > 0) return "Còn thiếu: " + string.Join(", ", missing.Take(6)) + (missing.Count > 6 ? "…" : "");
        if (task.RequireCheckIn && !await _dbContext.TaskTimeLogs.AnyAsync(l => l.TaskId == task.Id))
            return "Việc này cần check-in tại địa điểm trước khi báo xong";
        return null;
    }

    /// <summary>Gọi khi trạng thái đổi: đếm làm lại, tạo / huỷ khoản khoán cộng lương.</summary>
    private async Task OnStatusChangedAsync(WorkTask task, WorkTaskStatus oldStatus)
    {
        if (oldStatus == WorkTaskStatus.InReview && task.Status is WorkTaskStatus.InProgress or WorkTaskStatus.Todo)
            task.ReworkCount++;

        if (task.Status == WorkTaskStatus.Completed && task.PieceRate is > 0 && task.PieceRateTransactionId == null && task.AssigneeId.HasValue)
        {
            var emp = await _dbContext.Employees.AsNoTracking()
                .Where(e => e.Id == task.AssigneeId)
                .Select(e => new { e.Id, e.ApplicationUserId })
                .FirstOrDefaultAsync();
            if (emp != null)
            {
                var done = (task.CompletedDate ?? DateTime.Now);
                var tx = new PaymentTransaction
                {
                    Id = Guid.NewGuid(),
                    EmployeeId = emp.Id,
                    EmployeeUserId = emp.ApplicationUserId,
                    Type = "Bonus",
                    ForMonth = done.Month,
                    ForYear = done.Year,
                    TransactionDate = DateTime.UtcNow,
                    Amount = task.PieceRate.Value,
                    Description = $"Khoán việc {task.TaskCode}: {(task.Title.Length > 80 ? task.Title[..80] : task.Title)}",
                    Status = "Completed",
                    PerformedById = CurrentUserId,
                    Source = "task",
                    Settlement = "salary",
                    Note = "Tự động khi việc được duyệt hoàn thành",
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                };
                _dbContext.PaymentTransactions.Add(tx);
                task.PieceRateTransactionId = tx.Id;
                _dbContext.TaskHistories.Add(CreateHistory(task.Id, "PieceRate", null,
                    $"Cộng khoán {task.PieceRate.Value.ToString("#,##0", CultureInfo.GetCultureInfo("vi-VN"))} đ vào lương tháng {done:MM/yyyy}"));
            }
        }
        else if (oldStatus == WorkTaskStatus.Completed && task.Status != WorkTaskStatus.Completed && task.PieceRateTransactionId is Guid txId)
        {
            // Mở lại việc đã duyệt: huỷ khoản khoán nếu chưa vào phiếu lương.
            var tx = await _dbContext.PaymentTransactions.AsTracking().FirstOrDefaultAsync(t => t.Id == txId);
            if (tx != null && tx.PayslipId == null)
            {
                tx.Deleted = DateTime.UtcNow;
                tx.DeletedBy = CurrentUserEmail;
                tx.IsActive = false;
                task.PieceRateTransactionId = null;
                _dbContext.TaskHistories.Add(CreateHistory(task.Id, "PieceRate", null, "Huỷ khoán do mở lại việc"));
            }
        }
    }

    // ─── Biểu mẫu ────────────────────────────────────────────────

    [HttpPut("{id}/form")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<WorkTaskDto>>> SaveFormValues(Guid id, [FromBody] TaskFormValuesDto request)
    {
        var task = await _dbContext.WorkTasks.AsTracking().FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId);
        if (task == null) return Ok(AppResponse<WorkTaskDto>.Error("Không tìm thấy công việc"));
        if (!await TaskWorkflowHelper.CanModifyTaskAsync(_dbContext, task, CurrentUserId, RequiredStoreId, User))
            return Ok(AppResponse<WorkTaskDto>.Error("Bạn không có quyền cập nhật công việc này"));
        var (json, err) = TaskFormHelper.Merge(task.FormSchema, task.FormValues, request.Values ?? new());
        if (err != null) return Ok(AppResponse<WorkTaskDto>.Error(err));
        task.FormValues = json;
        if (task.Status is WorkTaskStatus.Todo or WorkTaskStatus.Assigned)
        {
            task.Status = WorkTaskStatus.InProgress;
            task.AcceptedAt ??= DateTime.Now;
            task.ActualStartDate ??= DateTime.Now;
        }
        task.UpdatedAt = DateTime.Now;
        task.UpdatedBy = CurrentUserEmail;
        _dbContext.TaskHistories.Add(CreateHistory(task.Id, "FormUpdated", null, "Cập nhật biểu mẫu"));
        await _dbContext.SaveChangesAsync();
        return Ok(AppResponse<WorkTaskDto>.Success(await ReloadDtoAsync(task.Id)));
    }

    async Task<WorkTaskDto> ReloadDtoAsync(Guid id)
    {
        var t = await _dbContext.WorkTasks
            .Include(x => x.Assignee).Include(x => x.AssignedBy).Include(x => x.Project)
            .FirstAsync(x => x.Id == id);
        return MapToDto(t);
    }

    // ─── Ảnh / chữ ký / file ─────────────────────────────────────

    /// <summary>
    /// Tải ảnh / chữ ký / file báo cáo của việc lên nơi lưu của cửa hàng (máy chủ hoặc Google Drive).
    /// checklistItemId → gắn ảnh cho mục checklist; fieldKey → điền vào trường ảnh / chữ ký của biểu mẫu.
    /// </summary>
    [HttpPost("{id}/media")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    [RequestSizeLimit(25_000_000)]
    [RequestFormLimits(MultipartBodyLengthLimit = 25_000_000)]
    public async Task<ActionResult<AppResponse<TaskAttachmentDto>>> UploadMedia(
        Guid id, IFormFile file,
        [FromForm] string? category, [FromForm] string? checklistItemId, [FromForm] string? fieldKey,
        [FromForm] string? caption, [FromForm] double? latitude, [FromForm] double? longitude,
        CancellationToken ct)
    {
        var task = await _dbContext.WorkTasks.AsTracking().FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId, ct);
        if (task == null) return Ok(AppResponse<TaskAttachmentDto>.Error("Không tìm thấy công việc"));
        if (!await TaskWorkflowHelper.CanModifyTaskAsync(_dbContext, task, CurrentUserId, RequiredStoreId, User))
            return Ok(AppResponse<TaskAttachmentDto>.Error("Bạn không có quyền cập nhật công việc này"));
        if (file == null || file.Length == 0) return Ok(AppResponse<TaskAttachmentDto>.Error("Chưa chọn file"));
        if (file.Length > 20_000_000) return Ok(AppResponse<TaskAttachmentDto>.Error("File tối đa 20 MB"));
        var ext = Path.GetExtension(file.FileName);
        if (string.IsNullOrEmpty(ext) || !AllowedTypes.TryGetValue(ext, out var mime))
            return Ok(AppResponse<TaskAttachmentDto>.Error("Chỉ nhận ảnh, PDF, Word, Excel hoặc video MP4"));
        var cat = (category ?? "report").Trim().ToLowerInvariant();
        if (!MediaCategories.Contains(cat)) cat = "report";

        byte[] bytes;
        using (var ms = new MemoryStream())
        {
            await file.CopyToAsync(ms, ct);
            bytes = ms.ToArray();
        }
        var stamp = DateTime.UtcNow.AddHours(7).ToString("yyyyMMdd-HHmmss");
        var niceName = $"{task.TaskCode}_{cat}_{stamp}{ext.ToLowerInvariant()}";
        var media = Media;
        var stored = await media.SaveBytesAsync(task, bytes, niceName, mime, ct);

        var att = new TaskAttachment
        {
            Id = Guid.NewGuid(),
            TaskId = task.Id,
            UploadedById = CurrentUserId,
            FileName = niceName,
            FilePath = stored.FilePath,
            ContentType = mime,
            FileSize = bytes.Length,
            Category = cat,
            ChecklistItemId = string.IsNullOrWhiteSpace(checklistItemId) ? null : checklistItemId.Trim(),
            Caption = string.IsNullOrWhiteSpace(caption) ? null : caption.Trim()[..Math.Min(caption.Trim().Length, 300)],
            Latitude = latitude,
            Longitude = longitude,
            StorageKind = stored.StorageKind,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = CurrentUserEmail,
        };
        _dbContext.TaskAttachments.Add(att);
        var url = media.Url(att);

        if (att.ChecklistItemId != null)
        {
            var items = TaskV2Helper.ParseChecklist(task.Checklist);
            var item = items.FirstOrDefault(i => i.Id == att.ChecklistItemId);
            if (item != null)
            {
                item.PhotoUrl = url;
                task.Checklist = TaskV2Helper.SerializeChecklist(items);
            }
        }
        if (!string.IsNullOrWhiteSpace(fieldKey))
        {
            var (json, err) = TaskFormHelper.Merge(task.FormSchema, task.FormValues,
                new Dictionary<string, string?> { [fieldKey.Trim()] = url });
            if (err == null) task.FormValues = json;
        }
        task.UpdatedAt = DateTime.Now;
        task.UpdatedBy = CurrentUserEmail;
        _dbContext.TaskHistories.Add(CreateHistory(task.Id, "MediaAdded", null,
            cat == "signature" ? "Ký xác nhận" : $"Thêm {(mime.StartsWith("image/") ? "ảnh" : "file")} ({cat})"));
        await _dbContext.SaveChangesAsync(ct);
        var dto = ToMediaDto(att, media);
        dto.Warning = stored.Warning;
        return Ok(AppResponse<TaskAttachmentDto>.Success(dto));
    }

    [HttpGet("{id}/media")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<TaskAttachmentDto>>>> ListMedia(Guid id)
    {
        if (!await _dbContext.WorkTasks.AnyAsync(t => t.Id == id && t.StoreId == RequiredStoreId))
            return Ok(AppResponse<List<TaskAttachmentDto>>.Error("Không tìm thấy công việc"));
        var media = Media;
        var list = await _dbContext.TaskAttachments.AsNoTracking().Include(a => a.UploadedBy)
            .Where(a => a.TaskId == id).OrderByDescending(a => a.CreatedAt).ToListAsync();
        return Ok(AppResponse<List<TaskAttachmentDto>>.Success(list.Select(a => ToMediaDto(a, media)).ToList()));
    }

    [HttpDelete("{id}/media/{attachmentId}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteMedia(Guid id, Guid attachmentId, CancellationToken ct)
    {
        var task = await _dbContext.WorkTasks.AsNoTracking().FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId, ct);
        if (task == null) return Ok(AppResponse<bool>.Error("Không tìm thấy công việc"));
        var a = await _dbContext.TaskAttachments.AsTracking().FirstOrDefaultAsync(x => x.Id == attachmentId && x.TaskId == id, ct);
        if (a == null) return Ok(AppResponse<bool>.Error("Không tìm thấy file"));
        if (a.UploadedById != CurrentUserId && !IsManager)
            return Ok(AppResponse<bool>.Error("Chỉ người tải lên hoặc quản lý được xoá"));
        if (task.Status == WorkTaskStatus.Completed && !IsManager)
            return Ok(AppResponse<bool>.Error("Việc đã hoàn thành — không xoá ảnh báo cáo"));
        await Media.DeleteAsync(a, RequiredStoreId, ct);
        _dbContext.TaskAttachments.Remove(a);
        _dbContext.TaskHistories.Add(CreateHistory(id, "MediaRemoved", a.FileName, null));
        await _dbContext.SaveChangesAsync(ct);
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>Xem ảnh lưu trên Google Drive qua máy chủ — link có chữ ký, không cần đăng nhập Google.</summary>
    [HttpGet("media/{attachmentId}/content")]
    [AllowAnonymous]
    public async Task<IActionResult> MediaContent(Guid attachmentId, [FromQuery] long exp, [FromQuery] string? sig, CancellationToken ct)
    {
        var media = Media;
        if (!media.VerifySignature(attachmentId, exp, sig)) return NotFound();
        var a = await _dbContext.TaskAttachments.AsNoTracking().IgnoreQueryFilters().FirstOrDefaultAsync(x => x.Id == attachmentId, ct);
        if (a == null) return NotFound();
        var storeId = await _dbContext.WorkTasks.AsNoTracking().IgnoreQueryFilters()
            .Where(t => t.Id == a.TaskId).Select(t => t.StoreId).FirstOrDefaultAsync(ct);
        var opened = await media.OpenAsync(a, storeId, ct);
        if (opened == null) return NotFound();
        Response.Headers.CacheControl = "private, max-age=86400";
        return File(opened.Value.Stream, opened.Value.ContentType, a.FileName);
    }

    // ─── Check-in GPS / bấm giờ ──────────────────────────────────

    static int Distance(double lat1, double lng1, double lat2, double lng2)
    {
        const double R = 6371000;
        double Rad(double d) => d * Math.PI / 180;
        var dLat = Rad(lat2 - lat1);
        var dLng = Rad(lng2 - lng1);
        var h = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(Rad(lat1)) * Math.Cos(Rad(lat2)) * Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        return (int)Math.Round(2 * R * Math.Asin(Math.Sqrt(h)));
    }

    async Task<int> RadiusAsync() =>
        await _dbContext.TaskWorkspaceSettings.AsNoTracking().Where(s => s.StoreId == RequiredStoreId)
            .Select(s => (int?)s.CheckInRadiusM).FirstOrDefaultAsync() ?? 300;

    [HttpPost("{id}/check-in")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TaskTimeLogDto>>> CheckIn(Guid id, [FromBody] TaskCheckInDto request)
    {
        var task = await _dbContext.WorkTasks.AsTracking().FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId);
        if (task == null) return Ok(AppResponse<TaskTimeLogDto>.Error("Không tìm thấy công việc"));
        if (!await TaskWorkflowHelper.CanModifyTaskAsync(_dbContext, task, CurrentUserId, RequiredStoreId, User))
            return Ok(AppResponse<TaskTimeLogDto>.Error("Bạn không có quyền cập nhật công việc này"));
        if (task.Status is WorkTaskStatus.Completed or WorkTaskStatus.Cancelled)
            return Ok(AppResponse<TaskTimeLogDto>.Error("Việc đã kết thúc"));
        if (await _dbContext.TaskTimeLogs.AnyAsync(l => l.TaskId == id && l.UserId == CurrentUserId && l.EndAt == null))
            return Ok(AppResponse<TaskTimeLogDto>.Error("Bạn đang check-in việc này — hãy check-out trước"));

        int? dist = null;
        if (request.Latitude.HasValue && request.Longitude.HasValue)
        {
            if (task.Latitude.HasValue && task.Longitude.HasValue)
            {
                dist = Distance(task.Latitude.Value, task.Longitude.Value, request.Latitude.Value, request.Longitude.Value);
                var radius = await RadiusAsync();
                if (task.RequireCheckIn && dist > radius && !IsManager)
                    return Ok(AppResponse<TaskTimeLogDto>.Error($"Bạn đang cách địa điểm {dist:N0} m (cho phép {radius:N0} m)"));
            }
            else
            {
                // Việc chưa có toạ độ → lấy vị trí check-in đầu tiên làm địa điểm.
                task.Latitude = request.Latitude;
                task.Longitude = request.Longitude;
                dist = 0;
            }
        }
        else if (task.RequireCheckIn && !IsManager)
        {
            return Ok(AppResponse<TaskTimeLogDto>.Error("Cần bật định vị (GPS) để check-in việc này"));
        }

        var emp = await TaskWorkflowHelper.GetEmployeeForUserAsync(_dbContext, RequiredStoreId, CurrentUserId);
        var log = new TaskTimeLog
        {
            Id = Guid.NewGuid(),
            TaskId = id,
            StoreId = RequiredStoreId,
            EmployeeId = emp?.Id,
            UserId = CurrentUserId,
            StartAt = DateTime.Now,
            StartLat = request.Latitude,
            StartLng = request.Longitude,
            StartDistanceM = dist,
            Note = string.IsNullOrWhiteSpace(request.Note) ? null : request.Note.Trim(),
            CreatedAt = DateTime.UtcNow,
            CreatedBy = CurrentUserEmail,
        };
        _dbContext.TaskTimeLogs.Add(log);
        var oldStatus = task.Status;
        if (task.Status is WorkTaskStatus.Todo or WorkTaskStatus.Assigned or WorkTaskStatus.OnHold)
        {
            task.Status = WorkTaskStatus.InProgress;
            task.AcceptedAt ??= DateTime.Now;
            task.ActualStartDate ??= DateTime.Now;
        }
        task.UpdatedAt = DateTime.Now;
        _dbContext.TaskHistories.Add(CreateHistory(id, "CheckIn", null,
            dist.HasValue ? $"Check-in (cách địa điểm {dist:N0} m)" : "Check-in"));
        if (oldStatus != task.Status)
            _dbContext.TaskHistories.Add(CreateHistory(id, "StatusChanged", oldStatus.ToString(), task.Status.ToString()));
        await _dbContext.SaveChangesAsync();
        return Ok(AppResponse<TaskTimeLogDto>.Success(ToLogDto(log, emp == null ? null : $"{emp.LastName} {emp.FirstName}".Trim())));
    }

    [HttpPost("{id}/check-out")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TaskTimeLogDto>>> CheckOut(Guid id, [FromBody] TaskCheckInDto request)
    {
        var task = await _dbContext.WorkTasks.AsTracking().FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId);
        if (task == null) return Ok(AppResponse<TaskTimeLogDto>.Error("Không tìm thấy công việc"));
        var log = await _dbContext.TaskTimeLogs.AsTracking()
            .FirstOrDefaultAsync(l => l.TaskId == id && l.UserId == CurrentUserId && l.EndAt == null);
        if (log == null) return Ok(AppResponse<TaskTimeLogDto>.Error("Bạn chưa check-in việc này"));
        log.EndAt = DateTime.Now;
        log.EndLat = request.Latitude;
        log.EndLng = request.Longitude;
        if (request.Latitude.HasValue && request.Longitude.HasValue && task.Latitude.HasValue && task.Longitude.HasValue)
            log.EndDistanceM = Distance(task.Latitude.Value, task.Longitude.Value, request.Latitude.Value, request.Longitude.Value);
        if (!string.IsNullOrWhiteSpace(request.Note)) log.Note = request.Note.Trim();
        log.UpdatedAt = DateTime.UtcNow;
        await _dbContext.SaveChangesAsync();

        // Giờ thực tế = tổng các lượt check-in / check-out.
        var logs = await _dbContext.TaskTimeLogs.AsNoTracking().Where(l => l.TaskId == id && l.EndAt != null)
            .Select(l => new { l.StartAt, l.EndAt }).ToListAsync();
        task.ActualHours = Math.Round((decimal)logs.Sum(l => (l.EndAt!.Value - l.StartAt).TotalHours), 2);
        task.UpdatedAt = DateTime.Now;
        _dbContext.TaskHistories.Add(CreateHistory(id, "CheckOut", null,
            $"Check-out · {(log.EndAt.Value - log.StartAt).TotalHours:0.##} giờ"));
        await _dbContext.SaveChangesAsync();
        return Ok(AppResponse<TaskTimeLogDto>.Success(ToLogDto(log, null)));
    }

    [HttpGet("{id}/time-logs")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<TaskTimeLogDto>>>> TimeLogs(Guid id)
    {
        var rows = await _dbContext.TaskTimeLogs.AsNoTracking()
            .Where(l => l.TaskId == id && l.StoreId == RequiredStoreId)
            .OrderByDescending(l => l.StartAt).Take(100).ToListAsync();
        var empIds = rows.Where(r => r.EmployeeId.HasValue).Select(r => r.EmployeeId!.Value).Distinct().ToList();
        var names = await _dbContext.Employees.AsNoTracking().Where(e => empIds.Contains(e.Id))
            .ToDictionaryAsync(e => e.Id, e => $"{e.LastName} {e.FirstName}".Trim());
        return Ok(AppResponse<List<TaskTimeLogDto>>.Success(rows
            .Select(r => ToLogDto(r, r.EmployeeId is Guid g ? names.GetValueOrDefault(g) : null)).ToList()));
    }

    static TaskTimeLogDto ToLogDto(TaskTimeLog l, string? name) => new()
    {
        Id = l.Id,
        EmployeeId = l.EmployeeId,
        EmployeeName = name,
        StartAt = l.StartAt,
        EndAt = l.EndAt,
        StartDistanceM = l.StartDistanceM,
        EndDistanceM = l.EndDistanceM,
        Hours = l.EndAt == null ? 0 : Math.Round((l.EndAt.Value - l.StartAt).TotalHours, 2),
        Note = l.Note,
    };

    // ─── Thiết lập theo ngành + Google Drive ─────────────────────

    async Task<TaskWorkspaceDto> WorkspaceDtoAsync()
    {
        var s = await _dbContext.TaskWorkspaceSettings.AsNoTracking().FirstOrDefaultAsync(x => x.StoreId == RequiredStoreId);
        var pack = TaskIndustryPacks.Find(s?.IndustryKey);
        var media = Media;
        return new TaskWorkspaceDto
        {
            IndustryKey = pack?.Key ?? s?.IndustryKey,
            IndustryName = pack?.Name,
            ProjectLabel = pack?.ProjectLabel ?? "Dự án",
            TaskLabel = pack?.TaskLabel ?? "Công việc",
            PhotoStorage = s?.PhotoStorage ?? "server",
            DriveConfigured = media.DriveConfigured,
            DriveConnected = !string.IsNullOrEmpty(s?.DriveRefreshTokenEnc),
            DriveAccountEmail = s?.DriveAccountEmail,
            DriveConnectedAt = s?.DriveConnectedAt,
            DriveLastError = s?.DriveLastError,
            CheckInRadiusM = s?.CheckInRadiusM ?? 300,
            Onboarded = s?.OnboardedAt != null,
        };
    }

    [HttpGet("workspace")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<TaskWorkspaceDto>>> GetWorkspace() =>
        Ok(AppResponse<TaskWorkspaceDto>.Success(await WorkspaceDtoAsync()));

    [HttpPut("workspace")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TaskWorkspaceDto>>> UpdateWorkspace([FromBody] TaskWorkspaceUpdateDto request, CancellationToken ct)
    {
        var s = await Media.GetOrCreateSettingsAsync(RequiredStoreId, ct);
        if (request.IndustryKey != null)
        {
            var pack = TaskIndustryPacks.Find(request.IndustryKey);
            if (pack == null && request.IndustryKey.Length > 0) return Ok(AppResponse<TaskWorkspaceDto>.Error("Ngành không hợp lệ"));
            s.IndustryKey = pack?.Key;
        }
        if (request.PhotoStorage != null)
        {
            var v = request.PhotoStorage.Trim().ToLowerInvariant();
            if (v is not ("server" or "gdrive")) return Ok(AppResponse<TaskWorkspaceDto>.Error("Nơi lưu ảnh không hợp lệ"));
            if (v == "gdrive" && string.IsNullOrEmpty(s.DriveRefreshTokenEnc))
                return Ok(AppResponse<TaskWorkspaceDto>.Error("Hãy kết nối Google Drive trước"));
            s.PhotoStorage = v;
        }
        if (request.CheckInRadiusM.HasValue) s.CheckInRadiusM = Math.Clamp(request.CheckInRadiusM.Value, 30, 5000);
        s.UpdatedAt = DateTime.UtcNow;
        s.UpdatedBy = CurrentUserEmail;
        await _dbContext.SaveChangesAsync(ct);
        return Ok(AppResponse<TaskWorkspaceDto>.Success(await WorkspaceDtoAsync()));
    }

    /// <summary>Lần đầu dùng: chọn ngành → cài gói ngành (giai đoạn, mẫu việc, biểu mẫu, việc định kỳ).</summary>
    [HttpPost("workspace/onboard")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<TaskWorkspaceDto>>> Onboard([FromBody] TaskOnboardDto request, CancellationToken ct)
    {
        var pack = TaskIndustryPacks.Find(request.IndustryKey);
        if (pack == null) return Ok(AppResponse<TaskWorkspaceDto>.Error("Ngành không hợp lệ"));
        var (_, err) = await TaskPackInstaller.InstallAsync(_dbContext, RequiredStoreId, pack,
            request.EnableRecurring, request.RecurringAssigneeIds, CurrentUserEmail, ct);
        if (err != null) return Ok(AppResponse<TaskWorkspaceDto>.Error(err));
        var s = await Media.GetOrCreateSettingsAsync(RequiredStoreId, ct);
        s.IndustryKey = pack.Key;
        s.OnboardedAt ??= DateTime.UtcNow;
        s.UpdatedAt = DateTime.UtcNow;
        await _dbContext.SaveChangesAsync(ct);
        return Ok(AppResponse<TaskWorkspaceDto>.Success(await WorkspaceDtoAsync()));
    }

    [HttpGet("drive/connect-url")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public ActionResult<AppResponse<string>> DriveConnectUrl()
    {
        var media = Media;
        if (!media.DriveConfigured)
            return Ok(AppResponse<string>.Error("Máy chủ chưa cấu hình Google Drive (GoogleDrive:ClientId / ClientSecret) — liên hệ SBOX."));
        return Ok(AppResponse<string>.Success(media.AuthUrl(Request, media.BuildState(RequiredStoreId, CurrentUserId))));
    }

    /// <summary>Google gọi lại sau khi khách cấp quyền.</summary>
    [HttpGet("drive/callback")]
    [AllowAnonymous]
    public async Task<ContentResult> DriveCallback([FromQuery] string? code, [FromQuery] string? state, [FromQuery] string? error, CancellationToken ct)
    {
        static ContentResult Page(bool ok, string message) => new()
        {
            ContentType = "text/html; charset=utf-8",
            Content = "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\">" +
                      "<title>SBOX — Google Drive</title></head><body style=\"font-family:system-ui;padding:32px;text-align:center\">" +
                      $"<h2 style=\"color:{(ok ? "#16A34A" : "#DC2626")}\">{(ok ? "Đã kết nối Google Drive" : "Chưa kết nối được")}</h2>" +
                      $"<p>{WebUtility.HtmlEncode(message)}</p><p>Bạn có thể đóng trang này và quay lại SBOX.</p></body></html>",
        };
        var media = Media;
        if (!string.IsNullOrEmpty(error)) return Page(false, "Bạn đã huỷ cấp quyền.");
        var st = media.ReadState(state);
        if (st == null || string.IsNullOrEmpty(code)) return Page(false, "Liên kết đã hết hạn — bấm «Kết nối Google Drive» lại.");
        try
        {
            var err = await media.CompleteConnectAsync(Request, st.Value.StoreId, code, ct);
            return err == null
                ? Page(true, $"Ảnh báo cáo công việc sẽ lưu vào thư mục «{TaskMediaService.RootFolderName}» trên Google Drive của bạn.")
                : Page(false, err);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return Page(false, "Google báo lỗi: " + ex.Message);
        }
    }

    [HttpPost("drive/disconnect")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<TaskWorkspaceDto>>> DriveDisconnect(CancellationToken ct)
    {
        var s = await Media.GetOrCreateSettingsAsync(RequiredStoreId, ct);
        s.DriveRefreshTokenEnc = null;
        s.DriveRootFolderId = null;
        s.DriveConnectedAt = null;
        s.DriveLastError = null;
        s.PhotoStorage = "server";
        s.UpdatedAt = DateTime.UtcNow;
        await _dbContext.SaveChangesAsync(ct);
        return Ok(AppResponse<TaskWorkspaceDto>.Success(await WorkspaceDtoAsync()));
    }

    [HttpPost("drive/test")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> DriveTest(CancellationToken ct)
    {
        var err = await Media.TestDriveAsync(RequiredStoreId, ct);
        return Ok(err == null ? AppResponse<bool>.Success(true) : AppResponse<bool>.Error(err));
    }

    // ─── Khách hàng / chứng từ liên quan ─────────────────────────

    [HttpGet("by-customer/{customerId}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<WorkTaskDto>>>> ByCustomer(Guid customerId)
    {
        var q = _dbContext.WorkTasks.AsNoTracking().Include(t => t.Assignee).Include(t => t.Project)
            .Where(t => t.StoreId == RequiredStoreId && t.IsActive && t.CustomerId == customerId);
        q = await TaskWorkflowHelper.ApplyViewerScopeAsync(q, _dbContext, RequiredStoreId, CurrentUserId, User);
        var list = await q.OrderByDescending(t => t.CreatedAt).Take(200).ToListAsync();
        return Ok(AppResponse<List<WorkTaskDto>>.Success(list.Select(t => MapToDto(t)).ToList()));
    }

    [HttpGet("by-related/{relatedType}/{relatedId}")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<WorkTaskDto>>>> ByRelated(string relatedType, Guid relatedId)
    {
        var type = relatedType.Trim().ToLowerInvariant();
        var q = _dbContext.WorkTasks.AsNoTracking().Include(t => t.Assignee).Include(t => t.Project)
            .Where(t => t.StoreId == RequiredStoreId && t.IsActive && t.RelatedType == type && t.RelatedId == relatedId);
        q = await TaskWorkflowHelper.ApplyViewerScopeAsync(q, _dbContext, RequiredStoreId, CurrentUserId, User);
        var list = await q.OrderBy(t => t.StartDate ?? t.CreatedAt).Take(200).ToListAsync();
        return Ok(AppResponse<List<WorkTaskDto>>.Success(list.Select(t => MapToDto(t)).ToList()));
    }

    /// <summary>
    /// Hợp đồng / báo giá → công trình + các hạng mục theo gói ngành (mặc định Xây dựng), gắn khách và báo giá.
    /// Gọi lại lần nữa → trả công trình đã tạo (không tạo trùng).
    /// </summary>
    [HttpPost("from-quote/{quoteId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<TaskProjectDto>>> FromQuote(Guid quoteId, [FromBody] TaskFromQuoteDto? request, CancellationToken ct)
    {
        var quote = await _dbContext.PosQuotes.AsNoTracking()
            .FirstOrDefaultAsync(q => q.Id == quoteId && q.StoreId == RequiredStoreId && q.Deleted == null, ct);
        if (quote == null) return Ok(AppResponse<TaskProjectDto>.Error("Không tìm thấy báo giá"));
        if (quote.Status is PosQuoteStatus.Rejected or PosQuoteStatus.Cancelled or PosQuoteStatus.Expired)
            return Ok(AppResponse<TaskProjectDto>.Error("Báo giá đã dừng (từ chối / huỷ / hết hạn) — không tạo công trình"));
        var pack = TaskIndustryPacks.Find(request?.IndustryKey ?? "construction") ?? TaskIndustryPacks.Find("construction")!;
        var label = $"{quote.ContractNo ?? quote.QuoteNo}";
        var existing = await _dbContext.WorkTasks.AsNoTracking()
            .Where(t => t.StoreId == RequiredStoreId && t.RelatedType == "quote" && t.RelatedId == quoteId && t.ProjectId != null)
            .Select(t => t.ProjectId).FirstOrDefaultAsync(ct);
        if (existing != null)
        {
            var p0 = await _dbContext.TaskProjects.AsNoTracking().FirstAsync(p => p.Id == existing, ct);
            var n0 = await _dbContext.WorkTasks.CountAsync(t => t.ProjectId == p0.Id && t.IsActive, ct);
            return Ok(AppResponse<TaskProjectDto>.Success(new TaskProjectDto { Id = p0.Id, Code = p0.Code, Name = p0.Name, TaskCount = n0 }));
        }
        var project = new TaskProject
        {
            Id = Guid.NewGuid(),
            StoreId = RequiredStoreId,
            Code = await TaskV2Helper.GenerateProjectCodeAsync(_dbContext, RequiredStoreId),
            Name = $"{pack.ProjectLabel} {quote.CustomerName ?? label}".Trim(),
            Description = $"Từ {(quote.ContractNo != null ? "hợp đồng " + quote.ContractNo : "báo giá " + quote.QuoteNo)}",
            IndustryKey = pack.Key,
            Color = pack.Color,
            Status = TaskProjectStatus.Active,
            OwnerEmployeeId = request?.OwnerEmployeeId,
            CustomerName = quote.CustomerName,
            CustomerPhone = quote.CustomerPhone,
            Address = quote.CustomerAddress,
            Budget = quote.Total,
            StartDate = quote.ContractSignedAt ?? DateTime.Now,
            DueDate = quote.HandoverDueAt,
            Stages = TaskV2Helper.SerializeStages(pack.Stages),
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };
        _dbContext.TaskProjects.Add(project);
        var i = 0;
        foreach (var t in pack.Templates.Where(t => t.Recurrence == TaskRecurrenceType.None))
        {
            var task = new WorkTask
            {
                Id = Guid.NewGuid(),
                TaskCode = await TaskWorkflowHelper.GenerateTaskCodeAsync(_dbContext, RequiredStoreId, i++),
                Title = t.Name,
                Description = t.Description,
                TaskType = t.Type,
                Priority = t.Priority,
                Status = WorkTaskStatus.Todo,
                StoreId = RequiredStoreId,
                AssignedById = CurrentUserId,
                AssigneeId = request?.OwnerEmployeeId,
                EstimatedHours = t.Hours,
                Checklist = TaskIndustryPacks.ChecklistJson(t),
                FormSchema = TaskIndustryPacks.FormJson(t),
                ProgressMode = TaskProgressMode.Checklist,
                ProjectId = project.Id,
                StageKey = t.StageKey,
                RequireCheckIn = t.RequireCheckIn,
                PieceRate = t.PieceRate,
                CustomerId = quote.CustomerId,
                CustomerName = quote.CustomerName,
                CustomerPhone = quote.CustomerPhone,
                Location = quote.CustomerAddress,
                RelatedType = "quote",
                RelatedId = quote.Id,
                RelatedLabel = label,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            };
            task.Progress = TaskV2Helper.AutoProgress(task) ?? 0;
            _dbContext.WorkTasks.Add(task);
            if (request?.OwnerEmployeeId is Guid owner)
                await TaskWorkflowHelper.SyncAssigneesAsync(_dbContext, task.Id, owner, new List<Guid> { owner });
        }
        await _dbContext.SaveChangesAsync(ct);
        return Ok(AppResponse<TaskProjectDto>.Success(new TaskProjectDto { Id = project.Id, Code = project.Code, Name = project.Name, TaskCount = i }));
    }

    // ─── Bảng điều khiển + khoán ─────────────────────────────────

    [HttpGet("dashboard")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<TaskDashboardDto>>> Dashboard(
        [FromQuery] DateTime? from = null, [FromQuery] DateTime? to = null, [FromQuery] Guid? projectId = null)
    {
        var now = DateTime.Now;
        var f = (from ?? now.Date.AddDays(-29)).Date;
        var t = (to ?? now).Date.AddDays(1);
        var q = _dbContext.WorkTasks.AsNoTracking().Where(x => x.StoreId == RequiredStoreId && x.IsActive && x.Status != WorkTaskStatus.Cancelled);
        q = await TaskWorkflowHelper.ApplyViewerScopeAsync(q, _dbContext, RequiredStoreId, CurrentUserId, User);
        if (projectId.HasValue) q = q.Where(x => x.ProjectId == projectId);
        q = q.Where(x => (x.CreatedAt >= f && x.CreatedAt < t) || (x.CompletedDate >= f && x.CompletedDate < t) ||
                         (x.Status != WorkTaskStatus.Completed && x.CreatedAt < t));
        var rows = await q.Select(x => new
        {
            x.Id, x.AssigneeId, x.Status, x.DueDate, x.CompletedDate, x.CreatedAt, x.ReworkCount, x.TaskType,
            x.PieceRate, Paid = x.PieceRateTransactionId != null, x.FormSchema, x.FormValues, x.RequireCheckIn,
        }).ToListAsync();
        var ids = rows.Select(r => r.Id).ToList();
        var evals = await _dbContext.TaskEvaluations.AsNoTracking().Where(e => ids.Contains(e.TaskId))
            .Select(e => new { e.TaskId, e.OverallScore }).ToListAsync();
        var logs = await _dbContext.TaskTimeLogs.AsNoTracking().Where(l => ids.Contains(l.TaskId) && l.EndAt != null)
            .Select(l => new { l.TaskId, l.EmployeeId, l.StartAt, l.EndAt }).ToListAsync();
        var checkedIn = logs.Select(l => l.TaskId).ToHashSet();

        var dto = new TaskDashboardDto();
        var done = rows.Where(r => r.Status == WorkTaskStatus.Completed && r.CompletedDate >= f && r.CompletedDate < t).ToList();
        dto.Total = rows.Count;
        dto.Completed = done.Count;
        dto.Overdue = rows.Count(r => r.Status != WorkTaskStatus.Completed && r.DueDate < now);
        dto.OnTimeRate = done.Count == 0 ? 0 : Math.Round(done.Count(d => d.DueDate == null || d.CompletedDate <= d.DueDate) * 100.0 / done.Count, 1);
        dto.ReworkRate = done.Count == 0 ? 0 : Math.Round(done.Count(d => d.ReworkCount > 0) * 100.0 / done.Count, 1);
        dto.AvgCycleHours = done.Count == 0 ? 0 : Math.Round(done.Average(d => (d.CompletedDate!.Value - d.CreatedAt).TotalHours), 1);
        var evalById = evals.GroupBy(e => e.TaskId).ToDictionary(g => g.Key, g => g.Average(x => x.OverallScore));
        dto.AvgQuality = evalById.Count == 0 ? null : Math.Round(evalById.Values.Average(), 2);
        var ratings = new List<double>();
        foreach (var r in done)
        {
            var schema = TaskFormHelper.ParseSchema(r.FormSchema);
            var values = TaskFormHelper.ParseValues(r.FormValues);
            foreach (var fld in schema.Where(x => x.Type == "rating"))
                if (int.TryParse(values.GetValueOrDefault(fld.Key), out var v)) ratings.Add(v);
        }
        dto.AvgCustomerRating = ratings.Count == 0 ? null : Math.Round(ratings.Average(), 2);
        var needCheck = done.Where(d => d.RequireCheckIn).ToList();
        dto.CheckInRate = needCheck.Count == 0 ? 100 : Math.Round(needCheck.Count(d => checkedIn.Contains(d.Id)) * 100.0 / needCheck.Count, 1);
        dto.PieceRateTotal = done.Where(d => d.Paid).Sum(d => d.PieceRate ?? 0);
        foreach (var g in rows.GroupBy(r => r.TaskType)) dto.ByType[g.Key.ToString()] = g.Count();

        var people = new Dictionary<Guid, TaskPersonStatDto>();
        foreach (var r in rows.Where(r => r.AssigneeId.HasValue))
        {
            var id = r.AssigneeId!.Value;
            if (!people.TryGetValue(id, out var p)) people[id] = p = new TaskPersonStatDto { EmployeeId = id };
            p.Total++;
            if (r.Status == WorkTaskStatus.Completed && r.CompletedDate >= f && r.CompletedDate < t)
            {
                p.Completed++;
                if (r.DueDate == null || r.CompletedDate <= r.DueDate) p.OnTime++;
                if (r.ReworkCount > 0) p.Rework++;
                if (r.Paid) p.PieceRateTotal += r.PieceRate ?? 0;
            }
            else if (r.Status != WorkTaskStatus.Completed && r.DueDate < now) p.Overdue++;
        }
        foreach (var l in logs.Where(l => l.EmployeeId.HasValue))
            if (people.TryGetValue(l.EmployeeId!.Value, out var p))
                p.LoggedHours += Math.Round((l.EndAt!.Value - l.StartAt).TotalHours, 2);
        var evalByPerson = rows.Where(r => r.AssigneeId.HasValue && evalById.ContainsKey(r.Id))
            .GroupBy(r => r.AssigneeId!.Value).ToDictionary(g => g.Key, g => g.Average(r => evalById[r.Id]));
        var empIds = people.Keys.ToList();
        var names = await _dbContext.Employees.AsNoTracking().Where(e => empIds.Contains(e.Id))
            .ToDictionaryAsync(e => e.Id, e => $"{e.LastName} {e.FirstName}".Trim());
        foreach (var p in people.Values)
        {
            p.EmployeeName = names.GetValueOrDefault(p.EmployeeId) ?? "—";
            p.OnTimeRate = p.Completed == 0 ? 0 : Math.Round(p.OnTime * 100.0 / p.Completed, 1);
            p.AvgQuality = evalByPerson.TryGetValue(p.EmployeeId, out var q2) ? Math.Round(q2, 2) : null;
            p.LoggedHours = Math.Round(p.LoggedHours, 1);
        }
        dto.People = people.Values.OrderByDescending(p => p.Completed).ThenBy(p => p.Overdue).ToList();
        return Ok(AppResponse<TaskDashboardDto>.Success(dto));
    }

    [HttpGet("piece-rates")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<List<TaskPieceRateItemDto>>>> PieceRates([FromQuery] int? month = null, [FromQuery] int? year = null)
    {
        var now = DateTime.Now;
        var m = month ?? now.Month;
        var y = year ?? now.Year;
        var start = new DateTime(y, m, 1);
        var end = start.AddMonths(1);
        var rows = await _dbContext.WorkTasks.AsNoTracking().Include(t => t.Assignee)
            .Where(t => t.StoreId == RequiredStoreId && t.IsActive && t.PieceRate > 0 &&
                        t.Status == WorkTaskStatus.Completed && t.CompletedDate >= start && t.CompletedDate < end)
            .OrderBy(t => t.CompletedDate).ToListAsync();
        return Ok(AppResponse<List<TaskPieceRateItemDto>>.Success(rows.Select(t => new TaskPieceRateItemDto
        {
            TaskId = t.Id,
            TaskCode = t.TaskCode,
            Title = t.Title,
            EmployeeId = t.AssigneeId,
            EmployeeName = t.Assignee == null ? null : $"{t.Assignee.LastName} {t.Assignee.FirstName}".Trim(),
            Amount = t.PieceRate ?? 0,
            CompletedDate = t.CompletedDate,
            Paid = t.PieceRateTransactionId != null,
        }).ToList()));
    }

    // ─── Phiếu hoàn thành (HTML / PDF) ───────────────────────────

    async Task<string?> ImageDataUriAsync(TaskAttachment a, CancellationToken ct)
    {
        try
        {
            byte[]? bytes = null;
            if (a.StorageKind == "gdrive")
            {
                var o = await Media.OpenAsync(a, RequiredStoreId, ct);
                if (o != null)
                {
                    using var ms = new MemoryStream();
                    await o.Value.Stream.CopyToAsync(ms, ct);
                    bytes = ms.ToArray();
                }
            }
            else
            {
                var env = HttpContext.RequestServices.GetRequiredService<IWebHostEnvironment>();
                var full = Path.Combine(env.ContentRootPath, "wwwroot", a.FilePath.TrimStart('/').Replace('/', Path.DirectorySeparatorChar));
                if (System.IO.File.Exists(full)) bytes = await System.IO.File.ReadAllBytesAsync(full, ct);
            }
            return bytes == null ? null : $"data:{a.ContentType ?? "image/jpeg"};base64,{Convert.ToBase64String(bytes)}";
        }
        catch (Exception)
        {
            return null;
        }
    }

    async Task<string> BuildReportHtmlAsync(WorkTask task, CancellationToken ct)
    {
        string E(string? s) => WebUtility.HtmlEncode(s ?? "");
        var vn = CultureInfo.GetCultureInfo("vi-VN");
        var store = await _dbContext.Stores.AsNoTracking().Where(s => s.Id == task.StoreId).Select(s => s.Name).FirstOrDefaultAsync(ct);
        var media = await _dbContext.TaskAttachments.AsNoTracking()
            .Where(a => a.TaskId == task.Id && a.ContentType != null && a.ContentType.StartsWith("image/"))
            .OrderBy(a => a.CreatedAt).Take(24).ToListAsync(ct);
        var dataUris = new Dictionary<Guid, string>();
        foreach (var a in media)
            if (await ImageDataUriAsync(a, ct) is string d) dataUris[a.Id] = d;
        var media2 = Media;
        var urlToId = media.ToDictionary(a => media2.Url(a), a => a.Id);
        var logs = await _dbContext.TaskTimeLogs.AsNoTracking().Where(l => l.TaskId == task.Id).OrderBy(l => l.StartAt).ToListAsync(ct);

        var sb = new StringBuilder();
        sb.Append("<!doctype html><html><head><meta charset=\"utf-8\"><style>")
          .Append("body{font-family:'Times New Roman',serif;font-size:13px;color:#111}h1{font-size:18px;text-align:center;margin:4px 0}")
          .Append("table{width:100%;border-collapse:collapse;margin:6px 0}td,th{border:1px solid #999;padding:4px 6px;vertical-align:top;text-align:left}")
          .Append("th{background:#f1f5f9;width:32%}.g{display:flex;flex-wrap:wrap;gap:6px}.g div{width:31%;text-align:center;font-size:11px}")
          .Append(".g img{width:100%;height:150px;object-fit:cover;border:1px solid #ccc}.sig{height:90px}</style></head><body>");
        sb.Append($"<div style=\"text-align:center;font-weight:bold\">{E(store)}</div>");
        sb.Append($"<h1>PHIẾU HOÀN THÀNH CÔNG VIỆC</h1><div style=\"text-align:center\">Số: <b>{E(task.TaskCode)}</b></div>");
        sb.Append("<table>");
        void Row(string k, string? v) { if (!string.IsNullOrWhiteSpace(v)) sb.Append($"<tr><th>{E(k)}</th><td>{v}</td></tr>"); }
        Row("Công việc", E(task.Title));
        Row("Khách hàng", E(string.Join(" · ", new[] { task.CustomerName, task.CustomerPhone }.Where(x => !string.IsNullOrWhiteSpace(x)))));
        Row("Địa điểm", E(task.Location));
        Row("Chứng từ liên quan", E(task.RelatedLabel));
        var assignee = task.AssigneeId == null ? null : await _dbContext.Employees.AsNoTracking()
            .Where(e => e.Id == task.AssigneeId).Select(e => e.LastName + " " + e.FirstName).FirstOrDefaultAsync(ct);
        Row("Người thực hiện", E(assignee));
        Row("Bắt đầu", task.ActualStartDate?.ToString("HH:mm dd/MM/yyyy", vn));
        Row("Hoàn thành", task.CompletedDate?.ToString("HH:mm dd/MM/yyyy", vn));
        if (task.ActualHours is > 0) Row("Thời gian làm", $"{task.ActualHours:0.##} giờ");
        if (logs.Count > 0)
            Row("Check-in", string.Join("<br>", logs.Select(l =>
                $"{l.StartAt:HH:mm dd/MM} → {(l.EndAt.HasValue ? l.EndAt.Value.ToString("HH:mm") : "…")}" +
                (l.StartDistanceM.HasValue ? $" (cách địa điểm {l.StartDistanceM:N0} m)" : ""))));
        sb.Append("</table>");

        var schema = TaskFormHelper.ParseSchema(task.FormSchema);
        var values = TaskFormHelper.ParseValues(task.FormValues);
        var signatures = new List<(string Label, string Img)>();
        if (schema.Count > 0)
        {
            sb.Append("<h3>Thông tin công việc</h3><table>");
            foreach (var f in schema)
            {
                var v = values.GetValueOrDefault(f.Key);
                if (string.IsNullOrWhiteSpace(v)) continue;
                if (f.Type is "photo" or "signature")
                {
                    var img = urlToId.TryGetValue(v, out var aid) && dataUris.TryGetValue(aid, out var d) ? d : null;
                    if (img == null) continue;
                    if (f.Type == "signature") { signatures.Add((f.Label, img)); continue; }
                    Row(f.Label, $"<img src=\"{img}\" style=\"max-height:160px\"/>");
                    continue;
                }
                var shown = f.Type switch
                {
                    "money" => decimal.TryParse(v, NumberStyles.Number, CultureInfo.InvariantCulture, out var n) ? n.ToString("#,##0", vn) + " đ" : v,
                    "number" => v + (f.Unit != null ? " " + f.Unit : ""),
                    "checkbox" => v == "true" ? "Có" : "Không",
                    "rating" => new string('★', int.TryParse(v, out var r) ? r : 0) + new string('☆', 5 - (int.TryParse(v, out var r2) ? r2 : 0)),
                    "date" => DateTime.TryParse(v, out var dt) ? dt.ToString(dt.TimeOfDay == TimeSpan.Zero ? "dd/MM/yyyy" : "HH:mm dd/MM/yyyy", vn) : v,
                    _ => v,
                };
                Row(f.Label, E(shown).Replace("\n", "<br>"));
            }
            sb.Append("</table>");
        }

        var checklist = TaskV2Helper.ParseChecklist(task.Checklist);
        if (checklist.Count > 0)
        {
            sb.Append("<h3>Checklist</h3><table>");
            foreach (var c in checklist)
                sb.Append($"<tr><td style=\"width:24px\">{(c.Done ? "✔" : "☐")}</td><td>{E(c.Text)}" +
                          $"{(c.DoneBy != null ? $"<div style=\"font-size:11px;color:#555\">{E(c.DoneBy)} · {c.DoneAt:HH:mm dd/MM}</div>" : "")}</td></tr>");
            sb.Append("</table>");
        }

        var photos = media.Where(a => a.Category != "signature" && dataUris.ContainsKey(a.Id)).ToList();
        if (photos.Count > 0)
        {
            sb.Append("<h3>Hình ảnh</h3><div class=\"g\">");
            foreach (var p in photos)
            {
                var cap = p.Category switch { "before" => "Trước", "after" => "Sau", "checklist" => "Checklist", _ => "" };
                sb.Append($"<div><img src=\"{dataUris[p.Id]}\"/><br>{E(string.Join(" · ", new[] { cap, p.Caption, p.CreatedAt.AddHours(7).ToString("HH:mm dd/MM") }.Where(x => !string.IsNullOrWhiteSpace(x))))}</div>");
            }
            sb.Append("</div>");
        }
        if (!string.IsNullOrWhiteSpace(task.CompletionNotes))
            sb.Append($"<h3>Ghi chú hoàn thành</h3><p>{E(task.CompletionNotes).Replace("\n", "<br>")}</p>");

        sb.Append("<table style=\"border:none;margin-top:16px\"><tr>");
        sb.Append($"<td style=\"border:none;text-align:center;width:50%\"><b>Người thực hiện</b><br><br><br><b>{E(assignee)}</b></td>");
        sb.Append("<td style=\"border:none;text-align:center\"><b>Khách hàng xác nhận</b><br>");
        if (signatures.Count > 0) sb.Append($"<img class=\"sig\" src=\"{signatures[0].Img}\"/><br>");
        else sb.Append("<br><br><br>");
        sb.Append($"<b>{E(task.CustomerName)}</b></td></tr></table>");
        sb.Append("</body></html>");
        return sb.ToString();
    }

    [HttpGet("{id}/report")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<string>>> ReportHtml(Guid id, CancellationToken ct)
    {
        var task = await _dbContext.WorkTasks.AsNoTracking().FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId, ct);
        if (task == null) return Ok(AppResponse<string>.Error("Không tìm thấy công việc"));
        return Ok(AppResponse<string>.Success(await BuildReportHtmlAsync(task, ct)));
    }

    [HttpGet("{id}/report.pdf")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    [RequireModulePermission("Task", ModulePermissionAction.View)]
    public async Task<IActionResult> ReportPdf(Guid id, CancellationToken ct)
    {
        var task = await _dbContext.WorkTasks.AsNoTracking().FirstOrDefaultAsync(t => t.Id == id && t.StoreId == RequiredStoreId, ct);
        if (task == null) return NotFound();
        var html = await BuildReportHtmlAsync(task, ct);
        try
        {
            var converter = HttpContext.RequestServices.GetRequiredService<OfficePdfConverter>();
            return File(await converter.HtmlToPdfAsync(html, ct), "application/pdf", $"PhieuHoanThanh_{task.TaskCode}.pdf");
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { message = ex.Message });
        }
    }
}
