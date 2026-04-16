using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

var connectionString = "Host=localhost;Database=workFina;Username=postgres;Password=123456;";

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

const string email = "sanapos.vn@gmail.com";
const string password = "123456a@";
const string fullName = "Sanapos SuperAdmin";

var existing = await userManager.FindByEmailAsync(email);
if (existing != null)
{
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
