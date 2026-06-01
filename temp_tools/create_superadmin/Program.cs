using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

var cli = args;
if (cli.Length >= 2 && cli[0] == "hash")
{
    var hash = new PasswordHasher<ApplicationUser>().HashPassword(new ApplicationUser(), cli[1]);
    Console.WriteLine(hash);
    return;
}

var connectionString = Environment.GetEnvironmentVariable("SBOX_DB_CONNECTION")
    ?? "Host=localhost;Database=workFina;Username=postgres;Password=123456;";

var options = new DbContextOptionsBuilder<ZKTecoDbContext>()
    .UseNpgsql(connectionString)
    .Options;

using var dbContext = new ZKTecoDbContext(options);

var store = new UserStore<ApplicationUser, IdentityRole<Guid>, ZKTecoDbContext, Guid>(dbContext);
var userManager = new UserManager<ApplicationUser>(
    store,
    Options.Create(new IdentityOptions()),
    new PasswordHasher<ApplicationUser>(),
    new IUserValidator<ApplicationUser>[] { new UserValidator<ApplicationUser>() },
    new IPasswordValidator<ApplicationUser>[] { new PasswordValidator<ApplicationUser>() },
    new UpperInvariantLookupNormalizer(),
    new IdentityErrorDescriber(),
    null,
    NullLogger<UserManager<ApplicationUser>>.Instance);

var email = cli.Length >= 3 && cli[0] == "reset" ? cli[1] : "sanapos.vn@gmail.com";
var password = cli.Length >= 3 && cli[0] == "reset" ? cli[2] : "123456aA@";
const string fullName = "Sanapos SuperAdmin";

var existing = await userManager.FindByEmailAsync(email);
if (existing != null)
{
    if (cli.Length >= 3 && cli[0] == "reset")
    {
        existing.LockoutEnd = null;
        existing.AccessFailedCount = 0;
        existing.IsActive = true;
        existing.EmailConfirmed = true;
        existing.Role = nameof(Roles.SuperAdmin);
        var token = await userManager.GeneratePasswordResetTokenAsync(existing);
        var reset = await userManager.ResetPasswordAsync(existing, token, password);
        if (!reset.Succeeded)
        {
            Console.WriteLine("RESET_FAIL|" + string.Join(";", reset.Errors.Select(e => e.Description)));
            return;
        }
        await userManager.UpdateAsync(existing);
        if (!await userManager.IsInRoleAsync(existing, nameof(Roles.SuperAdmin)))
            await userManager.AddToRoleAsync(existing, nameof(Roles.SuperAdmin));
        Console.WriteLine($"RESET_OK|{existing.Email}");
        return;
    }

    var roles = await userManager.GetRolesAsync(existing);
    Console.WriteLine($"EXISTS|{existing.Id}|{existing.Email}|roles={string.Join(',', roles)}");
    if (!roles.Contains(nameof(Roles.SuperAdmin)))
    {
        existing.Role = nameof(Roles.SuperAdmin);
        existing.IsActive = true;
        existing.EmailConfirmed = true;
        var addRole = await userManager.AddToRoleAsync(existing, nameof(Roles.SuperAdmin));
        var update = await userManager.UpdateAsync(existing);
        Console.WriteLine($"PROMOTED|addRole={addRole.Succeeded}|update={update.Succeeded}");
        if (!addRole.Succeeded) Console.WriteLine(string.Join(";", addRole.Errors.Select(e => e.Description)));
        if (!update.Succeeded) Console.WriteLine(string.Join(";", update.Errors.Select(e => e.Description)));
    }
    return;
}

var parts = fullName.Split(' ', StringSplitOptions.RemoveEmptyEntries);
var firstName = parts.LastOrDefault() ?? "SuperAdmin";
var lastName = parts.Length > 1 ? string.Join(' ', parts.Take(parts.Length - 1)) : "System";

var user = new ApplicationUser
{
    Id = Guid.NewGuid(),
    UserName = email,
    Email = email,
    FirstName = firstName,
    LastName = lastName,
    Role = nameof(Roles.SuperAdmin),
    IsActive = true,
    EmailConfirmed = true,
    PhoneNumberConfirmed = true,
    TwoFactorEnabled = false,
    LockoutEnabled = false,
    AccessFailedCount = 0,
    CreatedAt = DateTime.Now,
    CreatedBy = "manual-tool"
};

user.SecurityStamp = Guid.NewGuid().ToString();
user.ConcurrencyStamp = Guid.NewGuid().ToString();
user.PasswordHash = new PasswordHasher<ApplicationUser>().HashPassword(user, password);

var createResult = await userManager.CreateAsync(user);
Console.WriteLine($"CREATE|{createResult.Succeeded}");
if (!createResult.Succeeded)
{
    Console.WriteLine(string.Join(";", createResult.Errors.Select(e => e.Description)));
    return;
}

var roleResult = await userManager.AddToRoleAsync(user, nameof(Roles.SuperAdmin));
Console.WriteLine($"ROLE|{roleResult.Succeeded}");
if (!roleResult.Succeeded)
{
    Console.WriteLine(string.Join(";", roleResult.Errors.Select(e => e.Description)));
    return;
}

Console.WriteLine($"CREATED|{user.Id}|{user.Email}");
