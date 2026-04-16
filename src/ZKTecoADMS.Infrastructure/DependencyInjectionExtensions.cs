using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure.Interceptors;
using ZKTecoADMS.Infrastructure.Services.Auth;
using ZKTecoADMS.Application.Interfaces.Auth;
using ZKTecoADMS.Application.Settings;
using System.Text;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Infrastructure.Repositories;
using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Core.Services;
using ZKTecoADMS.Infrastructure.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Core.Services.DeviceOperations;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services.DeviceOperations;

namespace ZKTecoADMS.Infrastructure;

public static class DependencyInjectionExtensions
{
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        var connectionString = configuration.GetConnectionString("DefaultConnection");
        // Append connection pool sizing if not already configured
        if (!string.IsNullOrEmpty(connectionString) && !connectionString.Contains("Maximum Pool Size", StringComparison.OrdinalIgnoreCase))
        {
            connectionString += "Maximum Pool Size=1000;Minimum Pool Size=50;Connection Idle Lifetime=600;Connection Pruning Interval=10;";
        }
        var jwtSettings = configuration.GetSection("JwtSettings").Get<JwtSettings>();
        ArgumentNullException.ThrowIfNull(jwtSettings, "JwtSettings was missed !");

        services.AddScoped<ZKTecoDbInitializer>();

        // Redis distributed cache for cross-instance data sharing
        var redisConnectionString = configuration.GetConnectionString("Redis") ?? "localhost:6379";
        services.AddStackExchangeRedisCache(options =>
        {
            options.Configuration = redisConnectionString;
            options.InstanceName = "ZKTeco_";
        });

        // Add services to the container.
        services.AddScoped<AuditableEntityInterceptor>();
        services.AddDbContext<ZKTecoDbContext>((sp, options) =>
        {
            var auditableInterceptor = sp.GetRequiredService<AuditableEntityInterceptor>();
            
            options.UseNpgsql(connectionString, builder =>
                {
                    builder.MigrationsAssembly(typeof(ZKTecoDbContext).Assembly.GetName().Name);
                    builder.UseQuerySplittingBehavior(QuerySplittingBehavior.SplitQuery);
                    builder.MaxBatchSize(100);
                    builder.CommandTimeout(120);
                })
                .AddInterceptors(auditableInterceptor)
                .UseQueryTrackingBehavior(QueryTrackingBehavior.NoTracking);
        });
        services.AddScoped<DbContext>(sp => sp.GetRequiredService<ZKTecoDbContext>());
        services.AddAppIdentity();
        services.AddJwtConfiguration(jwtSettings);
        services.AddApplicationServices();
        services.AddCorsPolicy(jwtSettings);

        return services;
    }

    private static IServiceCollection AddJwtConfiguration(this IServiceCollection services, JwtSettings jwtSettings)
    {

        services.AddAuthentication(options =>
                {
                    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
                    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
                    options.DefaultScheme = JwtBearerDefaults.AuthenticationScheme;
                    options.DefaultForbidScheme = JwtBearerDefaults.AuthenticationScheme;
                })
                .AddJwtBearer(options =>
                {
                    options.UseSecurityTokenValidators = true;
                    options.TokenValidationParameters = new TokenValidationParameters
                    {
                        ValidateIssuerSigningKey = true,
                        ValidateIssuer = true,
                        ValidateAudience = true,
                        ValidateLifetime = true,
                        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSettings.AccessTokenSecret)),
                        ValidIssuer = jwtSettings.Issuer,
                        ValidAudience = jwtSettings.Audience,
                        ClockSkew = TimeSpan.Zero,
                        RoleClaimType = ClaimTypes.Role
                    };

                    // SignalR sends JWT via query string "access_token" for WebSocket connections
                    options.Events = new JwtBearerEvents
                    {
                        OnMessageReceived = context =>
                        {
                            var accessToken = context.Request.Query["access_token"];
                            var path = context.HttpContext.Request.Path;
                            if (!string.IsNullOrEmpty(accessToken) && path.StartsWithSegments("/hubs"))
                            {
                                context.Token = accessToken;
                            }
                            return Task.CompletedTask;
                        },
                        OnAuthenticationFailed = context =>
                        {
                            var path = context.HttpContext.Request.Path;
                            if (path.StartsWithSegments("/hubs"))
                            {
                                var logger = context.HttpContext.RequestServices
                                    .GetRequiredService<ILoggerFactory>()
                                    .CreateLogger("SignalR.Auth");
                                logger.LogWarning("📡 SignalR auth failed for {Path}: {Error}", 
                                    path, context.Exception?.Message);
                            }
                            return Task.CompletedTask;
                        }
                    };
                });

        services.AddAuthorization(options =>
        {
            options.AddPolicy(PolicyNames.AdminOnly,
                    policy => policy.RequireRole(nameof(Roles.Admin), nameof(Roles.SuperAdmin), nameof(Roles.Agent)));

            options.AddPolicy(PolicyNames.AtLeastAdmin,
                    policy => policy.RequireRole(nameof(Roles.Admin), nameof(Roles.SuperAdmin), nameof(Roles.Agent)));

            options.AddPolicy(PolicyNames.AtLeastManager,
                    policy => policy.RequireRole(nameof(Roles.Admin), nameof(Roles.Manager), nameof(Roles.SuperAdmin), nameof(Roles.Agent), nameof(Roles.DepartmentHead)));
            
            options.AddPolicy(PolicyNames.AtLeastEmployee,
                policy => policy.RequireRole(nameof(Roles.Admin), nameof(Roles.Manager), nameof(Roles.Employee), nameof(Roles.SuperAdmin), nameof(Roles.Agent), nameof(Roles.DepartmentHead), nameof(Roles.Accountant)));

            options.AddPolicy(PolicyNames.HourlyEmployeeOnly,
                policy => policy.RequireAssertion(context =>
                {
                    var employmentTypeClaim = context.User.FindFirst(c => c.Type == "employeeType");
                    return employmentTypeClaim != null && employmentTypeClaim.Value == EmploymentType.Hourly.ToString();
                }).RequireRole(nameof(Roles.Employee)));
        });

        services.AddAuthorizationBuilder()
                .SetDefaultPolicy(new AuthorizationPolicyBuilder()
                .RequireAuthenticatedUser()
                .AddAuthenticationSchemes(JwtBearerDefaults.AuthenticationScheme)
                .Build());

        return services;
    }

    private static IServiceCollection AddAppIdentity(this IServiceCollection services)
    {
        services.AddIdentity<ApplicationUser, IdentityRole<Guid>>(options =>
                {
                    // Configuration for authentication fields
                    options.SignIn.RequireConfirmedEmail = true;
                    options.Password.RequireDigit = false;
                    options.Password.RequiredLength = 6;
                    options.Password.RequireNonAlphanumeric = false;
                    options.Password.RequireUppercase = false;
                    options.Password.RequireLowercase = false;
                    // Account lockout configuration
                    options.Lockout.MaxFailedAccessAttempts = 5;
                    options.Lockout.DefaultLockoutTimeSpan = TimeSpan.FromMinutes(15);
                    options.Lockout.AllowedForNewUsers = true;
                })
                .AddEntityFrameworkStores<ZKTecoDbContext>()
                .AddDefaultTokenProviders()
                .AddRoles<IdentityRole<Guid>>()
                .AddSignInManager<SignInManager<ApplicationUser>>()
                .AddUserManager<UserManager<ApplicationUser>>()
                .AddEntityFrameworkStores<ZKTecoDbContext>()
                .AddTokenProvider<DataProtectorTokenProvider<ApplicationUser>>("Default");

        return services;
    }

    private static IServiceCollection AddApplicationServices(this IServiceCollection services)
    {
        // services.AddScoped<IZKTecoDbContext>(provider => provider.GetRequiredService<ZKTecoDbContext>());
        services.AddScoped<IAuthenticateService, AuthenticateService>();
        services.AddScoped<ITokenGeneratorService, TokenGeneratorService>();
        services.AddScoped<IAccessTokenService, AccessTokenService>();
        services.AddScoped<IRefreshTokenService, RefreshTokenService>();
        services.AddScoped<IRefreshTokenValidatorService, RefreshTokenService>();

        services.AddScoped<IDeviceService, DeviceService>();
        services.AddScoped<IDeviceUserService, DeviceUserService>();
        services.AddScoped<IAttendanceService, AttendanceService>();
        services.AddScoped<IDeviceCmdService, DeviceCmdService>();
        services.AddScoped<IDeviceUserOperationService, EmployeeOperationService>();
        services.AddScoped<IAttendanceOperationService, AttendanceOperationService>();
        services.AddScoped<IShiftService, ShiftService>();
        services.AddScoped<IDataScopeService, DataScopeService>();
        services.AddScoped<IMealRecordService, MealRecordService>();
        
        // Repository registration
        services.AddScoped(typeof(IRepositoryPagedQuery<>), typeof(PagedQueryRepository<>));
        services.AddScoped(typeof(IRepository<>), typeof(EfRepository<>));
        services.AddScoped(typeof(Repository<>), typeof(EfRepository<>));
        
        // Salary profile repositories
        services.AddScoped<IEmployeeSalaryProfileRepository, EmployeeSalaryProfileRepository>();
        services.AddScoped<IPayslipRepository, PayslipRepository>();

        // File Storage
        services.AddScoped<LocalFileStorageService>();
        services.AddScoped<GoogleDriveStorageService>();
        services.AddScoped<IFileStorageService, FileStorageResolver>();
        services.AddHttpContextAccessor();

        // Multi-tenant provider — resolves StoreId from JWT on each request
        services.AddScoped<ITenantProvider, TenantProvider>();

        // OCR Service
        services.AddScoped<CccdOcrService>();

        // Google Sheets Integration
        services.AddSingleton<IGoogleSheetService, GoogleSheetService>();
        services.AddScoped<IKpiGoogleSheetService, KpiGoogleSheetService>();
        
        // Email Service
        services.AddScoped<IEmailService, EmailService>();
        
        return services;
    }

    private static IServiceCollection AddCorsPolicy(this IServiceCollection services, JwtSettings jwtSettings)
    {
        services.AddCors(options =>
        {
            options.AddPolicy("corsPolicy", builder =>
            {
                // Allow any origin for development (Flutter web uses dynamic ports)
                builder.SetIsOriginAllowed(_ => true)
                       .AllowAnyMethod()
                       .AllowAnyHeader()
                       .AllowCredentials();
            });
        });

        return services;
    }
}
