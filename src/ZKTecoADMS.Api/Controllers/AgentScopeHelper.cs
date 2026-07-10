using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

internal static class AgentScopeHelper
{
    private const string AgentNotFoundMessage = "Không tìm thấy thông tin đại lý";

    public static async Task<(Agent Agent, ActionResult? Error)> RequireAgentAsync(
        ZKTecoDbContext db,
        UserManager<ApplicationUser> userManager,
        Guid userId,
        ILogger? logger = null)
    {
        var agent = await ResolveAgentAsync(db, userManager, userId, logger);
        if (agent == null)
        {
            return (null!, new NotFoundObjectResult(
                AppResponse<object>.Fail(AgentNotFoundMessage)));
        }

        return (agent, null);
    }

    /// <summary>
    /// Tìm đại lý theo UserId, fallback email/username, tự gắn UserId khi dữ liệu cũ lệch.
    /// </summary>
    public static async Task<Agent?> ResolveAgentAsync(
        ZKTecoDbContext db,
        UserManager<ApplicationUser> userManager,
        Guid userId,
        ILogger? logger = null)
    {
        var agent = await db.Agents
            .FirstOrDefaultAsync(a => a.UserId == userId);

        if (agent != null)
            return agent;

        var user = await userManager.FindByIdAsync(userId.ToString());
        if (user == null)
            return null;

        var email = NormalizeEmail(user.Email);
        var userName = NormalizeEmail(user.UserName);

        if (!string.IsNullOrEmpty(email))
        {
            agent = await db.Agents
                .FirstOrDefaultAsync(a =>
                    a.Email != null && a.Email.ToLower() == email);

            if (agent != null)
            {
                await TryHealUserLinkAsync(db, agent, userId, "email", logger);
                return agent;
            }
        }

        if (!string.IsNullOrEmpty(userName) && userName != email)
        {
            agent = await db.Agents
                .FirstOrDefaultAsync(a =>
                    a.Email != null && a.Email.ToLower() == userName);

            if (agent != null)
            {
                await TryHealUserLinkAsync(db, agent, userId, "username", logger);
                return agent;
            }
        }

        // Legacy: nhiều tài khoản Agent nhưng chỉ 1 đại lý trên hệ thống.
        var activeAgents = await db.Agents
            .Where(a => a.IsActive)
            .ToListAsync();

        if (activeAgents.Count == 1)
        {
            agent = activeAgents[0];
            logger?.LogWarning(
                "Sole-agent fallback linked user {UserId} ({Email}) to agent {AgentId} ({Code})",
                userId, user.Email, agent.Id, agent.Code);
            await TryHealUserLinkAsync(db, agent, userId, "sole-agent", logger);
            return agent;
        }

        return null;
    }

    private static async Task TryHealUserLinkAsync(
        ZKTecoDbContext db,
        Agent agent,
        Guid userId,
        string reason,
        ILogger? logger)
    {
        if (agent.UserId == userId)
            return;

        if (agent.UserId != null && agent.UserId != userId)
        {
            logger?.LogWarning(
                "Re-linking agent {AgentId} UserId {OldUserId} -> {NewUserId} ({Reason})",
                agent.Id, agent.UserId, userId, reason);
        }

        agent.UserId = userId;
        agent.IsRegistrationCompleted = true;
        agent.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
    }

    private static string? NormalizeEmail(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim().ToLowerInvariant();

    public static async Task<List<Guid>> GetStoreIdsAsync(ZKTecoDbContext db, Guid agentId) =>
        await db.Stores.AsNoTracking()
            .Where(s => s.AgentId == agentId)
            .Select(s => s.Id)
            .ToListAsync();

    public static async Task<bool> StoreBelongsToAgentAsync(
        ZKTecoDbContext db,
        Guid agentId,
        Guid storeId) =>
        await db.Stores.AsNoTracking()
            .AnyAsync(s => s.Id == storeId && s.AgentId == agentId);

    public static async Task<bool> UserBelongsToAgentAsync(
        UserManager<ApplicationUser> userManager,
        Guid agentId,
        Guid userId)
    {
        var user = await userManager.Users
            .AsNoTracking()
            .Include(u => u.Store)
            .FirstOrDefaultAsync(u => u.Id == userId);
        return user?.Store?.AgentId == agentId;
    }
}
