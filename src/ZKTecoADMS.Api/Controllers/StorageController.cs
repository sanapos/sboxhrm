using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Models;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Thông tin lưu trữ file (chỉ local wwwroot).
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class StorageController : AuthenticatedControllerBase
{
    /// <summary>
    /// Lấy thông tin storage hiện tại.
    /// </summary>
    [HttpGet("info")]
    public ActionResult<AppResponse<object>> GetStorageInfo()
    {
        return Ok(AppResponse<object>.Success(new
        {
            storageType = "local",
            message = "Ảnh và file được lưu trên server (wwwroot)."
        }));
    }
}
