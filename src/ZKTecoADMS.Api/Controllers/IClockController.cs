using System.Text;
using ZKTecoADMS.Application.Commands.IClock.CDataPost;
using ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand;
using ZKTecoADMS.Application.Queries.IClock.CDataGet;
using ZKTecoADMS.Application.Queries.IClock.GetRequest;
using Microsoft.AspNetCore.RateLimiting;

namespace ZKTecoADMS.API.Controllers;

[ApiController]
[Route("iclock")]
[EnableRateLimiting("device")]
public class ClockController(
    ILogger<ClockController> logger,
    IMediator bus)
    : ControllerBase
{
    /// <summary>
    /// Device registration and heartbeat endpoint
    /// Called by device: GET /iclock/cdata?SN=XXX&options=all&pushver=2.2.2&language=69
    /// </summary>
    [HttpGet("cdata")]
    public async Task<IActionResult> CData([FromQuery] string SN, [FromQuery] string? options, 
        [FromQuery] string? pushver, [FromQuery] string? language, [FromQuery] string? type)
    {
        var clientIp = HttpContext.Connection.RemoteIpAddress?.ToString();
        logger.LogWarning("[ICLOCK IN] GET /iclock/cdata SN={SN} IP={IP} options={Options} type={Type}", SN, clientIp, options, type);
        
        var query = new CDataGetQuery(SN, options, pushver, language, type);
        var response = await bus.Send(query);
        
        logger.LogWarning("[ICLOCK OUT] SN={SN} Response length={Length}", SN, response?.Length ?? 0);
        return Content(response, "text/plain");
    }

    /// <summary>
    /// Receive attendance data from device
    /// POST /iclock/cdata?SN=XXX&table=ATTLOG&Stamp=9999
    /// Body: PIN\tDateTime\tVerifyType\tVerifyState\tWorkCode\n
    /// </summary>
    [HttpPost("cdata")]
    public async Task<IActionResult> PostCData([FromQuery] string SN, [FromQuery] string table, 
        [FromQuery] string? Stamp)
    {
        var clientIp = HttpContext.Connection.RemoteIpAddress?.ToString();
        logger.LogWarning("[ICLOCK IN] POST /iclock/cdata SN={SN} IP={IP} Table={Table} Stamp={Stamp}", SN, clientIp, table, Stamp);
        
        using var reader = new StreamReader(Request.Body, Encoding.UTF8);
        var body = await reader.ReadToEndAsync();
        
        logger.LogInformation("CDataPost receiving data from device {SerialNumber}, Table: {Table}, Stamp: {Stamp}", 
            SN, table, Stamp);

        var command = new CDataPostCommand(SN, table, Stamp, body);
        var response = await bus.Send(command);
        
        return Content(response, "text/plain");
    }

    /// <summary>
    /// Device queries for new data/commands
    /// GET /iclock/getrequest?SN=XXX
    /// </summary>
    [HttpGet("getrequest")]
    public async Task<IActionResult> GetRequest([FromQuery] string SN, [FromQuery] string? INFO)
    {
        var clientIp = HttpContext.Connection.RemoteIpAddress?.ToString();
        logger.LogWarning("[ICLOCK IN] GET /iclock/getrequest SN={SN} IP={IP}", SN, clientIp);
        
        var command = new GetRequestQuery(SN, INFO);
        var response = await bus.Send(command);
        
        // Log lệnh gửi về cho máy
        if (!string.IsNullOrEmpty(response) && response != "OK")
        {
            logger.LogInformation("[MCC POLL] Sending command to device {SN}: {Response}", SN, response);
        }
        
        return Content(response, "text/plain");
    }

    /// <summary>
    /// Device reports command execution result
    /// POST /iclock/devicecmd?SN=XXX&ID=123
    /// </summary>
    [HttpPost("devicecmd")]
    public async Task<IActionResult> DeviceCmd([FromQuery] string SN)
    {
        using var reader = new StreamReader(Request.Body, Encoding.UTF8);
        var body = await reader.ReadToEndAsync();
        
        logger.LogInformation("DeviceCmd receiving data from {SerialNumber}", SN);
        var response = await bus.Send(new DeviceCmdCommand(SN, body));
            
        return Content(response, "text/plain");
    }

}
