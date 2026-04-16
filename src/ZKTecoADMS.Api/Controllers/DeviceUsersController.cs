using Mapster;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.DeviceUsers.Create;
using ZKTecoADMS.Application.Commands.DeviceUsers.Delete;
using ZKTecoADMS.Application.Commands.DeviceUsers.MapEmployee;
using ZKTecoADMS.Application.Commands.DeviceUsers.Update;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.DeviceUsers;
using ZKTecoADMS.Application.DTOs.Employees;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Application.Queries.DeviceUsers.GetDeviceUserDevices;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.API.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize(Policy = PolicyNames.AtLeastManager)]
public class DeviceUsersController(IMediator bus, ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    [HttpPost("devices")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<IEnumerable<DeviceUserDto>>> GetDeviceUsersByDevices([FromBody] GetDeviceUsersByDevicesRequest request)
    {
        var query = request.Adapt<GetDeviceUserDevicesQuery>();
        
        return Ok(await bus.Send(query));
    }

    [HttpPost]
    public async Task<ActionResult<AppResponse<DeviceUserDto>>> CreateDeviceUser([FromBody] CreateDeviceUserRequest request)
    {
        // Log request data for debugging
        Console.WriteLine($"[CreateDeviceUser] Received: PIN={request.Pin}, Name={request.Name}, Privilege={request.Privilege}, DeviceId={request.DeviceId}, Card={request.CardNumber}");
        
        var command = request.Adapt<CreateDeviceUserCommand>();
        var created = await bus.Send(command);

        return Ok(created);
    }

    [HttpPut("{deviceUserId}")]
    public async Task<IActionResult> UpdateDeviceUser(Guid deviceUserId, [FromBody] UpdateDeviceUserRequest request)
    {
        var cmd = new UpdateDeviceUserCommand(
            deviceUserId,
            request.PIN,
            request.Name,
            request.CardNumber,
            request.Password,
            request.Privilege,
            request.Email,
            request.PhoneNumber,
            request.Department,
            request.DeviceId);
        
        return Ok(await bus.Send(cmd));
    }

    [HttpDelete("{deviceUserId}")]
    public async Task<IActionResult> DeleteDeviceUser(Guid deviceUserId)
    {
        var cmd = new DeleteDeviceUserCommand(deviceUserId);

        return Ok(await bus.Send(cmd));
    }

    [HttpPost("{deviceUserId}/map-employee/{employeeId}")]
    public async Task<ActionResult<AppResponse<EmployeeDto>>> MapDeviceUserToEmployee(Guid deviceUserId, Guid employeeId)
    {
        var cmd = new MapDeviceUserToEmployeeCommand(deviceUserId, employeeId);
        return Ok(await bus.Send(cmd));
    }

    /// <summary>
    /// Lấy danh sách vân tay đã đăng ký cho device user
    /// </summary>
    [HttpGet("{deviceUserId}/fingerprints")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<IEnumerable<FingerprintDto>>>> GetFingerprints(Guid deviceUserId)
    {
        try
        {
            var fingerprints = await dbContext.FingerprintTemplates
                .Where(f => f.EmployeeId == deviceUserId)
                .Select(f => new FingerprintDto
                {
                    Id = f.Id,
                    FingerIndex = f.FingerIndex,
                    HasTemplate = true,
                    Quality = f.Quality,
                    CreatedAt = f.CreatedAt
                })
                .ToListAsync();

            return Ok(AppResponse<IEnumerable<FingerprintDto>>.Success(fingerprints));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<IEnumerable<FingerprintDto>>.Fail($"Lỗi lấy vân tay: {ex.Message}"));
        }
    }

    /// <summary>
    /// Lấy danh sách khuôn mặt đã đăng ký cho device user
    /// </summary>
    [HttpGet("{deviceUserId}/faces")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<IEnumerable<FaceDto>>>> GetFaces(Guid deviceUserId)
    {
        try
        {
            var faces = await dbContext.FaceTemplates
                .Where(f => f.EmployeeId == deviceUserId)
                .Select(f => new FaceDto
                {
                    Id = f.Id,
                    FaceIndex = f.FaceIndex,
                    HasTemplate = !string.IsNullOrEmpty(f.Template),
                    Version = f.Version,
                    CreatedAt = f.CreatedAt
                })
                .ToListAsync();

            return Ok(AppResponse<IEnumerable<FaceDto>>.Success(faces));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<IEnumerable<FaceDto>>.Fail($"Lỗi lấy khuôn mặt: {ex.Message}"));
        }
    }
}

public record FingerprintDto
{
    public Guid Id { get; init; }
    public int FingerIndex { get; init; }
    public bool HasTemplate { get; init; }
    public int? Quality { get; init; }
    public DateTime CreatedAt { get; init; }
}

public record FaceDto
{
    public Guid Id { get; init; }
    public int FaceIndex { get; init; }
    public bool HasTemplate { get; init; }
    public int Version { get; init; }
    public DateTime CreatedAt { get; init; }
}
