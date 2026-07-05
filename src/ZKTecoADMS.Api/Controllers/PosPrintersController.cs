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
        int FeedBeforeCut, bool PartialCut, bool IsDefault, bool RequiresAgent,
        string HealthStatus, DateTime? LastSeenAt, string? LastErrorMessage,
        int SortOrder, bool IsActive, List<string> DocumentTypes, int DefaultCopies);

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
        bool IsDefault,
        int SortOrder,
        bool IsActive);

    public record RouteDto(string DocumentType, Guid PrinterId, int DefaultCopies);

    public record RoutesBulkDto(List<RouteDto> Routes);

    [HttpGet]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
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
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
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

    [HttpPost]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Create([FromBody] PrinterSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = MapNew(dto, storeId, CurrentUserId.ToString());
        if (dto.IsDefault)
            await ClearDefaultAsync(storeId);

        db.PosStorePrinters.Add(entity);
        await db.SaveChangesAsync();
        await dispatch.EnsureDefaultRoutesAsync(storeId);

        return Ok(AppResponse<object>.Success(ToDto(entity, [], 1)));
    }

    [HttpPut("{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Update(Guid id, [FromBody] PrinterSaveDto dto)
    {
        var storeId = RequiredStoreId;
        var entity = await db.PosStorePrinters
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (entity == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy máy in"));

        if (dto.IsDefault && !entity.IsDefault)
            await ClearDefaultAsync(storeId);

        ApplySave(entity, dto, CurrentUserId.ToString());
        await db.SaveChangesAsync();
        await dispatch.EnsureDefaultRoutesAsync(storeId);

        var routes = await db.PosPrinterDocumentRoutes.AsNoTracking()
            .Where(r => r.PrinterId == id && r.Deleted == null).ToListAsync();

        return Ok(AppResponse<object>.Success(ToDto(entity,
            routes.Select(r => r.DocumentType.ToString()).ToList(),
            routes.FirstOrDefault()?.DefaultCopies ?? 1)));
    }

    [HttpDelete("{id:guid}")]
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> Delete(Guid id)
    {
        var storeId = RequiredStoreId;
        var entity = await db.PosStorePrinters
            .FirstOrDefaultAsync(p => p.Id == id && p.StoreId == storeId && p.Deleted == null);
        if (entity == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy máy in"));

        entity.Deleted = DateTime.UtcNow;
        entity.DeletedBy = CurrentUserId.ToString();
        entity.IsActive = false;
        await db.SaveChangesAsync();
        await dispatch.EnsureDefaultRoutesAsync(storeId);
        return Ok(AppResponse<object>.Success(true));
    }

    [HttpGet("routes")]
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
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
    [RequireModulePermission("PosSell", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> SaveRoutes([FromBody] RoutesBulkDto dto)
    {
        var storeId = RequiredStoreId;
        var printerIds = dto.Routes.Select(r => r.PrinterId).Distinct().ToList();
        var validPrinters = await db.PosStorePrinters
            .Where(p => printerIds.Contains(p.Id) && p.StoreId == storeId && p.Deleted == null)
            .Select(p => p.Id).ToListAsync();

        var existing = await db.PosPrinterDocumentRoutes
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
    [RequireModulePermission("PosSell", ModulePermissionAction.View)]
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
        p.FeedBeforeCut, p.PartialCut, p.IsDefault, p.RequiresAgent,
        p.HealthStatus.ToString(), p.LastSeenAt, p.LastErrorMessage,
        p.SortOrder, p.IsActive, docTypes, copies);

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
        entity.IsDefault = dto.IsDefault;
        entity.RequiresAgent = true;
        entity.SortOrder = dto.SortOrder;
        entity.IsActive = dto.IsActive;
        entity.UpdatedAt = DateTime.UtcNow;
        entity.UpdatedBy = userId;
    }

    async Task ClearDefaultAsync(Guid storeId)
    {
        var defaults = await db.PosStorePrinters
            .Where(p => p.StoreId == storeId && p.IsDefault && p.Deleted == null).ToListAsync();
        foreach (var p in defaults) p.IsDefault = false;
    }
}
