using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Public endpoints for agent self-registration
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class AgentRegistrationController : ControllerBase
{
    private readonly ZKTecoDbContext _dbContext;
    private readonly UserManager<ApplicationUser> _userManager;
    private readonly ISystemNotificationService _notificationService;
    private readonly ILogger<AgentRegistrationController> _logger;

    public AgentRegistrationController(
        ZKTecoDbContext dbContext,
        UserManager<ApplicationUser> userManager,
        ISystemNotificationService notificationService,
        ILogger<AgentRegistrationController> logger)
    {
        _dbContext = dbContext;
        _userManager = userManager;
        _notificationService = notificationService;
        _logger = logger;
    }

    /// <summary>
    /// Lấy thông tin đại lý theo token để hiển thị form đăng ký
    /// </summary>
    [HttpGet("{token}")]
    public async Task<ActionResult<AppResponse<AgentRegistrationInfoResponse>>> GetAgentByToken(string token)
    {
        try
        {
            var agent = await _dbContext.Agents
                .FirstOrDefaultAsync(a => a.RegistrationToken == token);

            if (agent == null)
            {
                return NotFound(AppResponse<AgentRegistrationInfoResponse>.Fail("Token không hợp lệ"));
            }

            if (agent.IsRegistrationCompleted)
            {
                return BadRequest(AppResponse<AgentRegistrationInfoResponse>.Fail("Đại lý đã hoàn tất đăng ký tài khoản"));
            }

            if (agent.RegistrationTokenExpiry.HasValue && agent.RegistrationTokenExpiry.Value < DateTime.UtcNow)
            {
                return BadRequest(AppResponse<AgentRegistrationInfoResponse>.Fail("Token đã hết hạn. Vui lòng liên hệ admin để được cấp token mới"));
            }

            var response = new AgentRegistrationInfoResponse(
                agent.Id,
                agent.Name,
                agent.Code,
                agent.Description,
                agent.Address,
                agent.Phone,
                agent.Email,
                true, // IsTokenValid
                agent.RegistrationTokenExpiry,
                "Token hợp lệ"
            );

            return Ok(AppResponse<AgentRegistrationInfoResponse>.Success(response));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting agent by token {Token}", token);
            return StatusCode(500, AppResponse<AgentRegistrationInfoResponse>.Fail("Có lỗi xảy ra"));
        }
    }

    /// <summary>
    /// Đại lý tự đăng ký tài khoản
    /// </summary>
    [HttpPost]
    public async Task<ActionResult<AppResponse<AgentSelfRegisterResponse>>> SelfRegister([FromBody] AgentSelfRegisterRequest request)
    {
        try
        {
            // Validate password confirmation
            if (request.Password != request.ConfirmPassword)
            {
                return BadRequest(AppResponse<AgentSelfRegisterResponse>.Fail("Mật khẩu xác nhận không khớp"));
            }

            // Validate token
            var agent = await _dbContext.Agents
                .AsTracking()
                .FirstOrDefaultAsync(a => a.RegistrationToken == request.RegistrationToken);

            if (agent == null)
            {
                return NotFound(AppResponse<AgentSelfRegisterResponse>.Fail("Token không hợp lệ"));
            }

            if (agent.IsRegistrationCompleted)
            {
                return BadRequest(AppResponse<AgentSelfRegisterResponse>.Fail("Đại lý đã hoàn tất đăng ký tài khoản"));
            }

            if (agent.RegistrationTokenExpiry.HasValue && agent.RegistrationTokenExpiry.Value < DateTime.UtcNow)
            {
                return BadRequest(AppResponse<AgentSelfRegisterResponse>.Fail("Token đã hết hạn. Vui lòng liên hệ admin để được cấp token mới"));
            }

            // Check email unique
            if (await _userManager.FindByEmailAsync(request.Email) != null)
            {
                return BadRequest(AppResponse<AgentSelfRegisterResponse>.Fail("Email đã được sử dụng"));
            }

            // Parse name for FirstName and LastName
            var nameParts = (request.FullName ?? agent.Name).Split(' ', 2);
            var firstName = nameParts.Length > 0 ? nameParts[0] : "Agent";
            var lastName = nameParts.Length > 1 ? nameParts[1] : agent.Code;

            // Create user account for agent
            var user = new ApplicationUser
            {
                Id = Guid.NewGuid(),
                UserName = request.Email,
                Email = request.Email,
                FirstName = firstName,
                LastName = lastName,
                PhoneNumber = agent.Phone,
                Role = nameof(Roles.Agent),
                EmailConfirmed = true, // Auto confirm since they have valid token
                CreatedAt = DateTime.UtcNow,
                CreatedBy = "Self-Registration"
            };
            UserPasswordVisibility.RememberPassword(user, request.Password);

            var userResult = await _userManager.CreateAsync(user, request.Password);
            if (!userResult.Succeeded)
            {
                var errors = string.Join(", ", userResult.Errors.Select(e => e.Description));
                _logger.LogWarning("Failed to create user for agent {AgentId}: {Errors}", agent.Id, errors);
                return BadRequest(AppResponse<AgentSelfRegisterResponse>.Fail(errors));
            }

            await _userManager.AddToRoleAsync(user, nameof(Roles.Agent));

            // Update agent with user account
            agent.UserId = user.Id;
            agent.IsRegistrationCompleted = true;
            agent.RegistrationToken = null; // Clear token after successful registration
            agent.RegistrationTokenExpiry = null;
            agent.LastModified = DateTime.UtcNow;
            agent.LastModifiedBy = "Self-Registration";

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("Agent {AgentId} completed self-registration with user {UserId}", agent.Id, user.Id);

            try
            {
                await SuperAdminNotificationHelper.NotifySuperAdminsAsync(
                    _notificationService,
                    _userManager,
                    NotificationType.Info,
                    "Đại lý hoàn tất đăng ký",
                    $"Đại lý '{agent.Name}' (Mã: {agent.Code}) vừa hoàn tất đăng ký tài khoản. Email: {request.Email}",
                    relatedUrl: SuperAdminNotificationHelper.AdminAgentsUrl,
                    relatedEntityId: agent.Id,
                    relatedEntityType: "Agent",
                    categoryCode: "agent");
            }
            catch (Exception notifyEx)
            {
                _logger.LogWarning(notifyEx, "Failed to notify SuperAdmins about agent registration {AgentId}", agent.Id);
            }

            var response = new AgentSelfRegisterResponse(
                true,
                "Đăng ký thành công! Bạn có thể đăng nhập bằng email và mật khẩu đã tạo.",
                agent.Id,
                user.Email!
            );

            return Ok(AppResponse<AgentSelfRegisterResponse>.Success(response));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error during agent self-registration");
            return StatusCode(500, AppResponse<AgentSelfRegisterResponse>.Fail("Có lỗi xảy ra trong quá trình đăng ký"));
        }
    }

    /// <summary>
    /// Kiểm tra token có hợp lệ không
    /// </summary>
    [HttpGet("validate/{token}")]
    public async Task<ActionResult<AppResponse<TokenValidationResponse>>> ValidateToken(string token)
    {
        try
        {
            var agent = await _dbContext.Agents
                .FirstOrDefaultAsync(a => a.RegistrationToken == token);

            if (agent == null)
            {
                return Ok(AppResponse<TokenValidationResponse>.Success(new TokenValidationResponse(false, "Token không hợp lệ", null)));
            }

            if (agent.IsRegistrationCompleted)
            {
                return Ok(AppResponse<TokenValidationResponse>.Success(new TokenValidationResponse(false, "Đại lý đã hoàn tất đăng ký", null)));
            }

            if (agent.RegistrationTokenExpiry.HasValue && agent.RegistrationTokenExpiry.Value < DateTime.UtcNow)
            {
                return Ok(AppResponse<TokenValidationResponse>.Success(new TokenValidationResponse(false, "Token đã hết hạn", agent.RegistrationTokenExpiry)));
            }

            return Ok(AppResponse<TokenValidationResponse>.Success(new TokenValidationResponse(true, "Token hợp lệ", agent.RegistrationTokenExpiry)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error validating token {Token}", token);
            return StatusCode(500, AppResponse<TokenValidationResponse>.Fail("Có lỗi xảy ra"));
        }
    }

    /// <summary>
    /// Public lookup: lấy thông tin tóm tắt của đại lý theo mã (dùng cho trang đăng ký cửa hàng có ?agentCode=)
    /// </summary>
    [HttpGet("lookup/{code}")]
    public async Task<ActionResult<AppResponse<object>>> LookupByCode(string code)
    {
        try
        {
            var normalized = (code ?? string.Empty).Trim().ToUpper();
            if (string.IsNullOrEmpty(normalized))
            {
                return BadRequest(AppResponse<object>.Fail("Thiếu mã đại lý"));
            }
            var agent = await _dbContext.Agents
                .FirstOrDefaultAsync(a => a.Code.ToUpper() == normalized && a.IsActive);
            if (agent == null)
            {
                return NotFound(AppResponse<object>.Fail("Không tìm thấy đại lý"));
            }
            return Ok(AppResponse<object>.Success(new
            {
                id = agent.Id,
                code = agent.Code,
                name = agent.Name,
                phone = agent.Phone,
                email = agent.Email,
                address = agent.Address,
                zaloUrl = BuildZaloUrl(agent.Phone),
                isActive = agent.IsActive
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error looking up agent by code {Code}", code);
            return StatusCode(500, AppResponse<object>.Fail("Có lỗi xảy ra"));
        }
    }

    /// <summary>
    /// Public: lấy thông tin liên hệ đại lý của cửa hàng (theo mã cửa hàng).
    /// Dùng trên màn đăng nhập để hiển thị Zalo hỗ trợ đại lý.
    /// </summary>
    [HttpGet("store-contact/{storeCode}")]
    public async Task<ActionResult<AppResponse<StoreAgentContactDto?>>> GetStoreAgentContact(string storeCode)
    {
        try
        {
            var normalized = (storeCode ?? string.Empty).Trim().ToLower();
            if (string.IsNullOrEmpty(normalized))
            {
                return BadRequest(AppResponse<StoreAgentContactDto?>.Fail("Thiếu mã cửa hàng"));
            }

            var store = await _dbContext.Stores
                .AsNoTracking()
                .Include(s => s.Agent)
                .FirstOrDefaultAsync(s => s.Code.ToLower() == normalized && s.IsActive);

            if (store?.Agent == null || !store.Agent.IsActive)
            {
                return Ok(AppResponse<StoreAgentContactDto?>.Success(null));
            }

            var agent = store.Agent;
            return Ok(AppResponse<StoreAgentContactDto?>.Success(MapAgentContact(agent)));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting store agent contact for {StoreCode}", storeCode);
            return StatusCode(500, AppResponse<StoreAgentContactDto?>.Fail("Có lỗi xảy ra"));
        }
    }

    private static StoreAgentContactDto MapAgentContact(Agent agent) => new(
        agent.Id,
        agent.Name,
        agent.Code,
        agent.Phone,
        agent.Email,
        agent.Address,
        BuildZaloUrl(agent.Phone)
    );

    private static string? BuildZaloUrl(string? phone)
    {
        if (string.IsNullOrWhiteSpace(phone)) return null;
        var digits = new string(phone.Where(char.IsDigit).ToArray());
        if (digits.StartsWith("84") && digits.Length > 10)
            digits = digits[2..];
        if (digits.StartsWith('0') && digits.Length > 9)
            digits = digits[1..];
        return string.IsNullOrEmpty(digits) ? null : $"https://zalo.me/{digits}";
    }
}

/// <summary>
/// Response for agent self-registration
/// </summary>
public record AgentSelfRegisterResponse(
    bool Success,
    string Message,
    Guid AgentId,
    string Email
);

/// <summary>
/// Response for token validation
/// </summary>
public record TokenValidationResponse(
    bool IsValid,
    string Message,
    DateTime? ExpiryDate
);
