using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.Geofence;
using ZKTecoADMS.Application.DTOs;
using ZKTecoADMS.Application.Queries.Geofence;
using ZKTecoADMS.Application.Constants;

namespace ZKTecoADMS.Api.Controllers;

[Route("api/[controller]")]
[ApiController]
[Authorize]
public class GeofencesController : AuthenticatedControllerBase
{
    private readonly ISender _sender;

    public GeofencesController(ISender sender)
    {
        _sender = sender;
    }

    /// <summary>
    /// Get all geofences for the current store
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<IActionResult> GetGeofences([FromQuery] bool? activeOnly = null)
    {
        var storeId = CurrentStoreId;
        if (!storeId.HasValue || storeId.Value == Guid.Empty)
        {
            return BadRequest("Store ID is required");
        }

        var result = await _sender.Send(new GetGeofencesQuery(storeId.Value, activeOnly));
        return Ok(result);
    }

    /// <summary>
    /// Validate if a location is within any geofence
    /// </summary>
    [HttpPost("validate")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<IActionResult> ValidateLocation([FromBody] ValidateLocationDto dto)
    {
        var storeId = CurrentStoreId;
        if (!storeId.HasValue || storeId.Value == Guid.Empty)
        {
            return BadRequest("Store ID is required");
        }

        var result = await _sender.Send(new ValidateLocationQuery(dto.Latitude, dto.Longitude, storeId.Value));
        return Ok(result);
    }

    /// <summary>
    /// Create a new geofence
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<IActionResult> CreateGeofence([FromBody] CreateGeofenceDto dto)
    {
        var storeId = CurrentStoreId;
        if (!storeId.HasValue || storeId.Value == Guid.Empty)
        {
            return BadRequest("Store ID is required");
        }

        var result = await _sender.Send(new CreateGeofenceCommand(dto, storeId.Value));
        return Ok(result);
    }

    /// <summary>
    /// Update an existing geofence
    /// </summary>
    [HttpPut("{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<IActionResult> UpdateGeofence(Guid id, [FromBody] UpdateGeofenceDto dto)
    {
        var storeId = CurrentStoreId;
        if (!storeId.HasValue || storeId.Value == Guid.Empty)
        {
            return BadRequest("Store ID is required");
        }

        var result = await _sender.Send(new UpdateGeofenceCommand(id, dto, storeId.Value));
        return Ok(result);
    }

    /// <summary>
    /// Delete a geofence
    /// </summary>
    [HttpDelete("{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<IActionResult> DeleteGeofence(Guid id)
    {
        var storeId = CurrentStoreId;
        if (!storeId.HasValue || storeId.Value == Guid.Empty)
        {
            return BadRequest("Store ID is required");
        }

        var result = await _sender.Send(new DeleteGeofenceCommand(id, storeId.Value));
        return Ok(result);
    }
}
