using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/pos/printers")]
[Authorize]
public partial class PosPrintersController(
    ZKTecoDbContext db,
    IPosPrintDispatchService dispatch) : AuthenticatedControllerBase
{
    public record PrinterDto(
        Guid Id, string Name, string ConnectionType, string? PrinterBrand, string PaperSize,
        string? TextMode, string? BluetoothAddress, string? BluetoothName,
        string? LanHost, int LanPort, string? UsbDeviceName,
        int FeedBeforeCut, bool PartialCut, bool OpenCashDrawer, bool OpenDrawerCashOnly,
        bool BeepOnPrint, bool IsDefault, bool RequiresAgent,
        bool IsDeviceLocal, string? OwnerDeviceId,
        string HealthStatus, DateTime? LastSeenAt, string? LastErrorMessage,
        int SortOrder, bool IsActive, List<string> DocumentTypes, int DefaultCopies,
        bool CutPerItem);

    public record PrinterSaveDto(
        string Name,
        PosPrinterConnectionType ConnectionType,
        string? PrinterBrand,
        string PaperSize,
        string? TextMode,
        string? BluetoothAddress,
        string? BluetoothName,
        string? LanHost,
        int LanPort,
        string? UsbDeviceName,
        int FeedBeforeCut,
        bool PartialCut,
        bool? OpenCashDrawer,
        bool? OpenDrawerCashOnly,
        bool? BeepOnPrint,
        bool IsDefault,
        int SortOrder,
        bool IsActive,
        bool? CutPerItem);

    /// <summary>Đồng bộ máy in nội bộ từ thiết bị POS → danh sách cửa hàng (để gán món).</summary>
    public record DeviceLocalPrinterUpsertDto(
        Guid? Id,
        string OwnerDeviceId,
        string Name,
        PosPrinterConnectionType ConnectionType,
        string? PrinterBrand,
        string PaperSize,
        string? TextMode,
        string? BluetoothAddress,
        string? BluetoothName,
        string? LanHost,
        int LanPort,
        string? UsbDeviceName,
        int FeedBeforeCut,
        bool PartialCut,
        bool? OpenCashDrawer,
        bool? OpenDrawerCashOnly,
        bool? BeepOnPrint,
        bool IsActive,
        List<string>? DocumentTypes,
        bool? CutPerItem);

    public record RouteDto(string DocumentType, Guid PrinterId, int DefaultCopies);

    public record RoutesBulkDto(List<RouteDto> Routes);

    [HttpGet]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List()
    {
        var storeId = RequiredStoreId;
        await dispatch.EnsureDefaultRoutesAsync(storeId);

        var printers = await db.PosStorePrinters.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null)
            .OrderBy(p => p.SortOrder).ThenBy(p => p.Name)
            .ToListAsync();

        var routes = await db.PosPrinterDocumentRoutes.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.IsActive)
            .ToListAsync();

        var items = printers.Select(p =>
        {
            var types = routes.Where(r => r.PrinterId == p.Id).Select(r => r.DocumentType.ToString()).ToList();
            var copies = routes.FirstOrDefault(r => r.PrinterId == p.Id)?.DefaultCopies ?? 1;
            return ToDto(p, types, copies);
        }).ToList();

        return Ok(AppResponse<object>.Success(items));
    }

    [HttpGet("{id:guid}")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Get(Guid id)
    {
        var storeId = RequiredStoreId;
        var p = await db.PosStorePrinters.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId && x.Deleted == null);
        if (p == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy máy in"));

        var routes = await db.PosPrinterDocumentRoutes.AsNoTracking()
            .Where(r => r.PrinterId == id && r.Deleted == null).ToListAsync();

        return Ok(AppResponse<object>.Success(ToDto(p,
            routes.Select(r => r.DocumentType.ToString()).ToList(),
            routes.FirstOrDefault()?.DefaultCopies ?? 1)));
    }

    /// <summary>
    /// «VID:PID:serial» của USB — bỏ /dev/bus/usb/… vì đổi mỗi lần cắm lại.
    /// </summary>
    static string UsbIdentity(string? raw)
    {
        var t = (raw ?? "").Trim();
        if (t.Length == 0) return "";
        var pipe = t.IndexOf('|');
        return (pipe > 0 ? t[..pipe] : t).ToLowerInvariant();
    }

    /// <summary>
    /// Máy in cloud đã có cùng cổng vật lý. Cắm lại USB làm đổi đường dẫn bus
    /// nên app từng tạo thêm bản ghi trùng tên: chip Agent trỏ bản cũ, món gán
    /// bản mới → job Queued tới hết hạn, không ra phiếu. Tái dùng bản ghi cũ.
    /// </summary>
    async Task<PosStorePrinter?> FindSamePhysicalPrinterAsync(
        Guid storeId, PrinterSaveDto dto)
    {
        // AsTracking: caller ghi đè bản ghi tìm được rồi SaveChanges.
        var candidates = await db.PosStorePrinters.AsTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null
                && !p.IsDeviceLocal && p.ConnectionType == dto.ConnectionType)
            .ToListAsync();
        if (candidates.Count == 0) return null;

        switch (dto.ConnectionType)
        {
            case PosPrinterConnectionType.Usb:
                var usb = UsbIdentity(dto.UsbDeviceName);
                if (usb.Length == 0) return null;
                return candidates.FirstOrDefault(p => UsbIdentity(p.UsbDeviceName) == usb);
            case PosPrinterConnectionType.Lan:
                var host = (dto.LanHost ?? "").Trim();
                if (host.Length == 0) return null;
                return candidates.FirstOrDefault(p =>
                    string.Equals((p.LanHost ?? "").Trim(), host, StringComparison.OrdinalIgnoreCase)
                    && p.LanPort == dto.LanPort);
            case PosPrinterConnectionType.Bluetooth:
                var bt = (dto.BluetoothAddress ?? "").Trim();
                if (bt.Length == 0) return null;
                return candidates.FirstOrDefault(p =>
                    string.Equals((p.BluetoothAddress ?? "").Trim(), bt, StringComparison.OrdinalIgnoreCase));
            case PosPrinterConnectionType.Sunmi:
                return candidates.FirstOrDefault();
            default:
                return null;
        }
    }

    [HttpPost]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Create([FromBody] PrinterSaveDto dto)
    {
        var storeId = RequiredStoreId;
        if (dto.IsDefault)
            await ClearDefaultAsync(storeId);

        var existing = await FindSamePhysicalPrinterAsync(storeId, dto);
        if (existing != null)
        {
            ApplySave(existing, dto, CurrentUserId.ToString());
            await db.SaveChangesAsync();
            await dispatch.EnsureDefaultRoutesAsync(storeId);

            var types = await db.PosPrinterDocumentRoutes.AsNoTracking()
                .Where(r => r.PrinterId == existing.Id && r.Deleted == null && r.IsActive)
                .Select(r => r.DocumentType.ToString())
                .ToListAsync();
            return Ok(AppResponse<object>.Success(ToDto(existing, types, 1)));
        }

        var entity = MapNew(dto, storeId, CurrentUserId.ToString());
        db.PosStorePrinters.Add(entity);
        await db.SaveChangesAsync();
        await dispatch.EnsureDefaultRoutesAsync(storeId);

        return Ok(AppResponse<object>.Success(ToDto(entity, [], 1)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Update(Guid id, [FromBody] PrinterSaveDto dto)
    {
        var storeId = RequiredStoreId;
        // AsTracking bắt buộc: DbContext chạy NoTracking toàn cục nên thiếu nó là
        // SaveChanges không ghi gì — sửa tên/IP/khổ giấy báo OK mà không lưu.
        var entity = await db.PosStorePrinters.AsTracking()
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (entity == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy máy in"));

        if (dto.IsDefault && !entity.IsDefault)
            await ClearDefaultAsync(storeId);

        var wasActive = entity.IsActive;
        ApplySave(entity, dto, CurrentUserId.ToString());
        await db.SaveChangesAsync();
        await dispatch.EnsureDefaultRoutesAsync(storeId);

        // Tắt «Hoạt động» làm máy in biến mất khỏi cấu hình app, nhưng gán SP
        // vẫn trỏ vào đó: món ra lệnh in cho một máy không tồn tại, chỉ rơi vào
        // hàng chờ chứ không ai in. Gỡ gán như khi xóa máy để món về máy mặc định.
        if (wasActive && !entity.IsActive)
            await ClearProductAssignmentsAsync(storeId, id);

        var routes = await db.PosPrinterDocumentRoutes.AsNoTracking()
            .Where(r => r.PrinterId == id && r.Deleted == null).ToListAsync();

        return Ok(AppResponse<object>.Success(ToDto(entity,
            routes.Select(r => r.DocumentType.ToString()).ToList(),
            routes.FirstOrDefault()?.DefaultCopies ?? 1)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var now = DateTime.UtcNow;
        var by = CurrentUserId.ToString();

        // ExecuteUpdate + IgnoreQueryFilters — tránh soft-delete filter / tracker
        // khiến SaveChanges không ghi Deleted (list vẫn còn máy sau khi báo OK).
        var affected = await db.PosStorePrinters
            .IgnoreQueryFilters()
            .Where(p => p.Id == id && p.StoreId == storeId && p.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.Deleted, now)
                .SetProperty(p => p.DeletedBy, by)
                .SetProperty(p => p.IsActive, false)
                .SetProperty(p => p.IsDefault, false)
                .SetProperty(p => p.UpdatedAt, now)
                .SetProperty(p => p.UpdatedBy, by));

        if (affected == 0)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy máy in"));

        // Gỡ route chứng từ gắn máy.
        await db.PosPrinterDocumentRoutes
            .IgnoreQueryFilters()
            .Where(r => r.PrinterId == id && r.StoreId == storeId && r.Deleted == null)
            .ExecuteUpdateAsync(s => s
                .SetProperty(x => x.Deleted, now)
                .SetProperty(x => x.DeletedBy, by)
                .SetProperty(x => x.IsActive, false)
                .SetProperty(x => x.UpdatedAt, now)
                .SetProperty(x => x.UpdatedBy, by));

        await ClearProductAssignmentsAsync(storeId, id);

        // Detach tracker — tránh query sau vẫn «nhìn» entity cũ.
        foreach (var entry in db.ChangeTracker.Entries<PosStorePrinter>()
                     .Where(e => e.Entity.Id == id).ToList())
            entry.State = EntityState.Detached;

        await dispatch.EnsureDefaultRoutesAsync(storeId);
        return Ok(AppResponse<object>.Success(true));
    }

    /// <summary>
    /// Bỏ gán DefaultPrinter / DefaultLabelPrinter trên SP + nhóm hàng khi máy in
    /// không còn phục vụ được (xóa hoặc tắt hoạt động). Còn gán thì phiếu bếp/tem
    /// của các món đó chạy vào một máy app không thấy — chỉ nằm hàng chờ.
    /// </summary>
    async Task ClearProductAssignmentsAsync(Guid storeId, Guid printerId)
    {
        var now = DateTime.UtcNow;

        await db.PosProducts
            .IgnoreQueryFilters()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.DefaultPrinterId == printerId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.DefaultPrinterId, (Guid?)null)
                .SetProperty(p => p.UpdatedAt, now));

        await db.PosProducts
            .IgnoreQueryFilters()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.DefaultLabelPrinterId == printerId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(p => p.DefaultLabelPrinterId, (Guid?)null)
                .SetProperty(p => p.UpdatedAt, now));

        await db.PosProductCategories
            .IgnoreQueryFilters()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.DefaultPrinterId == printerId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(c => c.DefaultPrinterId, (Guid?)null)
                .SetProperty(c => c.UpdatedAt, now));

        await db.PosProductCategories
            .IgnoreQueryFilters()
            .Where(c => c.StoreId == storeId && c.Deleted == null && c.DefaultLabelPrinterId == printerId)
            .ExecuteUpdateAsync(s => s
                .SetProperty(c => c.DefaultLabelPrinterId, (Guid?)null)
                .SetProperty(c => c.UpdatedAt, now));
    }

    [HttpGet("routes")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> GetRoutes()
    {
        var storeId = RequiredStoreId;
        await dispatch.EnsureDefaultRoutesAsync(storeId);

        var routes = await db.PosPrinterDocumentRoutes.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.IsActive)
            .Select(r => new RouteDto(r.DocumentType.ToString(), r.PrinterId, r.DefaultCopies))
            .ToListAsync();

        return Ok(AppResponse<object>.Success(routes));
    }

    [HttpPut("routes")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SaveRoutes([FromBody] RoutesBulkDto dto)
    {
        var storeId = RequiredStoreId;
        var printerIds = dto.Routes.Select(r => r.PrinterId).Distinct().ToList();
        var validPrinters = await db.PosStorePrinters
            .Where(p => printerIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .Select(p => p.Id).ToListAsync();

        // AsTracking: bên dưới sửa/soft-delete các route cũ rồi SaveChanges.
        var existing = await db.PosPrinterDocumentRoutes.AsTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null).ToListAsync();

        var incoming = new HashSet<(PosPrintDocumentType DocumentType, Guid PrinterId)>();
        foreach (var r in dto.Routes)
        {
            if (!validPrinters.Contains(r.PrinterId)) continue;
            if (!Enum.TryParse<PosPrintDocumentType>(r.DocumentType, out var dt)) continue;

            incoming.Add((dt, r.PrinterId));
            var row = existing.FirstOrDefault(x => x.DocumentType == dt && x.PrinterId == r.PrinterId);
            if (row == null)
            {
                db.PosPrinterDocumentRoutes.Add(new PosPrinterDocumentRoute
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    PrinterId = r.PrinterId,
                    DocumentType = dt,
                    DefaultCopies = Math.Clamp(r.DefaultCopies, 1, 10),
                    IsActive = true,
                    CreatedAt = DateTime.UtcNow,
                    CreatedBy = CurrentUserId.ToString(),
                });
            }
            else
            {
                row.DefaultCopies = Math.Clamp(r.DefaultCopies, 1, 10);
                row.IsActive = true;
                row.UpdatedAt = DateTime.UtcNow;
                row.UpdatedBy = CurrentUserId.ToString();
            }
        }

        var now = DateTime.UtcNow;
        foreach (var row in existing)
        {
            if (incoming.Contains((row.DocumentType, row.PrinterId))) continue;
            row.Deleted = now;
            row.DeletedBy = CurrentUserId.ToString();
            row.UpdatedAt = now;
            row.UpdatedBy = CurrentUserId.ToString();
        }

        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(true));
    }

    [HttpPost("{id:guid}/health")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> ReportHealth(
        Guid id, [FromBody] HealthReportDto dto)
    {
        if (!Enum.TryParse<PosPrinterHealthStatus>(dto.Status, true, out var status))
            return BadRequest(AppResponse<object>.Fail("Trạng thái không hợp lệ"));

        var storeId = RequiredStoreId;
        var exists = await db.PosStorePrinters.AnyAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (!exists) return NotFound(AppResponse<object>.Fail("Không tìm thấy máy in"));

        await dispatch.SetPrinterHealthAsync(id, status, dto.ErrorMessage);
        return Ok(AppResponse<object>.Success(true));
    }

    public record HealthReportDto(string Status, string? ErrorMessage);

    static PrinterDto ToDto(PosStorePrinter p, List<string> docTypes, int copies) => new(
        p.Id, p.Name, p.ConnectionType.ToString(), p.PrinterBrand, p.PaperSize,
        p.TextMode, p.BluetoothAddress, p.BluetoothName, p.LanHost, p.LanPort, p.UsbDeviceName,
        p.FeedBeforeCut, p.PartialCut, p.OpenCashDrawer, p.OpenDrawerCashOnly, p.BeepOnPrint,
        p.IsDefault, p.RequiresAgent,
        p.IsDeviceLocal, p.OwnerDeviceId,
        p.HealthStatus.ToString(), p.LastSeenAt, p.LastErrorMessage,
        p.SortOrder, p.IsActive, docTypes, copies, p.CutPerItem);

    [HttpPost("device-local")]
    [RequireModulePermission("PosPrinters", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> UpsertDeviceLocal(
        [FromBody] DeviceLocalPrinterUpsertDto dto)
    {
        var storeId = RequiredStoreId;
        var owner = (dto.OwnerDeviceId ?? "").Trim();
        if (string.IsNullOrWhiteSpace(owner))
            return BadRequest(AppResponse<object>.Fail("Thiếu OwnerDeviceId"));
        if (string.IsNullOrWhiteSpace(dto.Name))
            return BadRequest(AppResponse<object>.Fail("Thiếu tên máy in"));

        PosStorePrinter? entity = null;
        if (dto.Id is Guid id)
        {
            entity = await db.PosStorePrinters.AsTracking()
                .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
            // Không biến máy cloud/Agent thành device-local (chip Agent từng ghi đè storePrinterId).
            // Mọi máy không phải device-local → tạo bản ghi mới thay vì hijack.
            if (entity != null && !entity.IsDeviceLocal)
                entity = null;
        }

        if (entity == null)
        {
            entity = new PosStorePrinter
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = CurrentUserId.ToString(),
            };
            db.PosStorePrinters.Add(entity);
        }

        entity.Name = dto.Name.Trim();
        entity.ConnectionType = dto.ConnectionType;
        entity.PrinterBrand = dto.PrinterBrand;
        entity.PaperSize = string.IsNullOrWhiteSpace(dto.PaperSize) ? "K80" : dto.PaperSize;
        entity.TextMode = dto.TextMode;
        entity.BluetoothAddress = dto.BluetoothAddress;
        entity.BluetoothName = dto.BluetoothName;
        entity.LanHost = dto.LanHost;
        entity.LanPort = dto.LanPort <= 0 ? 9100 : dto.LanPort;
        entity.UsbDeviceName = dto.UsbDeviceName;
        entity.FeedBeforeCut = dto.FeedBeforeCut <= 0 ? 1 : dto.FeedBeforeCut;
        entity.PartialCut = dto.PartialCut;
        entity.CutPerItem = dto.CutPerItem ?? entity.CutPerItem;
        entity.OpenCashDrawer = dto.OpenCashDrawer ?? false;
        entity.OpenDrawerCashOnly = dto.OpenDrawerCashOnly ?? true;
        entity.BeepOnPrint = dto.BeepOnPrint ?? false;
        entity.IsActive = dto.IsActive;
        entity.IsDeviceLocal = true;
        entity.OwnerDeviceId = owner;
        entity.RequiresAgent = false;
        entity.IsDefault = false;
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = CurrentUserId.ToString();

        await db.SaveChangesAsync();

        var wanted = new HashSet<PosPrintDocumentType>();
        foreach (var raw in dto.DocumentTypes ?? [])
        {
            if (Enum.TryParse<PosPrintDocumentType>(raw, true, out var dt))
                wanted.Add(dt);
        }

        var existingRoutes = await db.PosPrinterDocumentRoutes
            .AsTracking()
            .IgnoreQueryFilters()
            .Where(r => r.PrinterId == entity.Id && r.StoreId == storeId)
            .ToListAsync();
        var now = DateTime.UtcNow;
        var by = CurrentUserId.ToString();
        foreach (var row in existingRoutes)
        {
            if (wanted.Contains(row.DocumentType))
            {
                row.Deleted = null;
                row.DeletedBy = null;
                row.IsActive = true;
                row.UpdatedAt = now;
                row.UpdatedBy = by;
                wanted.Remove(row.DocumentType);
                continue;
            }
            if (row.Deleted == null)
            {
                row.Deleted = now;
                row.DeletedBy = by;
                row.IsActive = false;
                row.UpdatedAt = now;
                row.UpdatedBy = by;
            }
        }
        foreach (var dt in wanted)
        {
            db.PosPrinterDocumentRoutes.Add(new PosPrinterDocumentRoute
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                PrinterId = entity.Id,
                DocumentType = dt,
                DefaultCopies = 1,
                IsActive = true,
                CreatedAt = now,
                CreatedBy = by,
            });
        }
        await db.SaveChangesAsync();

        var types = (dto.DocumentTypes ?? [])
            .Where(t => Enum.TryParse<PosPrintDocumentType>(t, true, out _))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        return Ok(AppResponse<object>.Success(ToDto(entity, types, 1)));
    }

    static PosStorePrinter MapNew(PrinterSaveDto dto, Guid storeId, string? userId)
    {
        var requiresAgent = true;
        return new PosStorePrinter
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = dto.Name.Trim(),
            ConnectionType = dto.ConnectionType,
            PrinterBrand = dto.PrinterBrand,
            PaperSize = dto.PaperSize,
            TextMode = dto.TextMode,
            BluetoothAddress = dto.BluetoothAddress,
            BluetoothName = dto.BluetoothName,
            LanHost = dto.LanHost,
            LanPort = dto.LanPort,
            UsbDeviceName = dto.UsbDeviceName,
            FeedBeforeCut = dto.FeedBeforeCut,
            PartialCut = dto.PartialCut,
            CutPerItem = dto.CutPerItem ?? false,
            OpenCashDrawer = dto.OpenCashDrawer ?? false,
            OpenDrawerCashOnly = dto.OpenDrawerCashOnly ?? true,
            BeepOnPrint = dto.BeepOnPrint ?? false,
            IsDefault = dto.IsDefault,
            RequiresAgent = requiresAgent,
            SortOrder = dto.SortOrder,
            IsActive = dto.IsActive,
            HealthStatus = PosPrinterHealthStatus.Unknown,
            CreatedAt = DateTime.UtcNow,
            CreatedBy = userId,
        };
    }

    static void ApplySave(PosStorePrinter entity, PrinterSaveDto dto, string? userId)
    {
        entity.Name = dto.Name.Trim();
        entity.ConnectionType = dto.ConnectionType;
        entity.PrinterBrand = dto.PrinterBrand;
        entity.PaperSize = dto.PaperSize;
        entity.TextMode = dto.TextMode;
        entity.BluetoothAddress = dto.BluetoothAddress;
        entity.BluetoothName = dto.BluetoothName;
        entity.LanHost = dto.LanHost;
        entity.LanPort = dto.LanPort;
        entity.UsbDeviceName = dto.UsbDeviceName;
        entity.FeedBeforeCut = dto.FeedBeforeCut;
        entity.PartialCut = dto.PartialCut;
        entity.CutPerItem = dto.CutPerItem ?? false;
        entity.OpenCashDrawer = dto.OpenCashDrawer ?? false;
        entity.OpenDrawerCashOnly = dto.OpenDrawerCashOnly ?? true;
        entity.BeepOnPrint = dto.BeepOnPrint ?? false;
        entity.IsDefault = dto.IsDefault;
        entity.RequiresAgent = true;
        entity.SortOrder = dto.SortOrder;
        entity.IsActive = dto.IsActive;
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = userId;
    }

    async Task ClearDefaultAsync(Guid storeId)
    {
        await db.PosStorePrinters
            .Where(p => p.StoreId == storeId && p.IsDefault && p.Deleted == null)
            .ExecuteUpdateAsync(s => s.SetProperty(p => p.IsDefault, false));
    }
}
