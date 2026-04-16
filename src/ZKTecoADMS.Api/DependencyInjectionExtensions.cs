using ZKTecoADMS.Application.Settings;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Api.Middlewares;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Api.Services;
using HealthChecks.UI.Client;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.OpenApi.Models;
using Microsoft.AspNetCore.ResponseCompression;
using System.IO.Compression;
using System.Threading.RateLimiting;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace ZKTecoADMS.Api;

public static class DependencyInjectionExtensions
{
    public static IServiceCollection AddApi(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddSettings(configuration);
        services.AddControllers()
            .AddJsonOptions(options =>
            {
                options.JsonSerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
                options.JsonSerializerOptions.PropertyNameCaseInsensitive = true;
                options.JsonSerializerOptions.ReferenceHandler = System.Text.Json.Serialization.ReferenceHandler.IgnoreCycles;
                options.JsonSerializerOptions.MaxDepth = 32;
                options.JsonSerializerOptions.Converters.Add(new System.Text.Json.Serialization.JsonStringEnumConverter());
            });
            
        services.AddEndpointsApiExplorer();
        var connStr = configuration.GetConnectionString("DefaultConnection") ?? "";
        var redisConnStr = configuration.GetConnectionString("Redis");
        services.AddHealthChecks()
            .AddNpgSql(connStr, name: "postgresql", tags: ["db", "ready"]);
        if (!string.IsNullOrEmpty(redisConnStr))
        {
            services.AddHealthChecks()
                .AddRedis(redisConnStr, name: "redis", tags: ["cache", "ready"], 
                    failureStatus: HealthStatus.Degraded);
        }
        
        // CORS configuration for Flutter Web and SignalR
        var allowedOrigins = configuration.GetSection("AllowedOrigins").Get<string[]>() 
            ?? ["http://localhost:8080", "http://localhost:3000", "http://localhost:3001"];
        services.AddCors(options =>
        {
            options.AddPolicy("corsPolicy", policy =>
            {
                policy.WithOrigins(allowedOrigins)
                      .AllowAnyMethod()
                      .AllowAnyHeader()
                      .AllowCredentials();
            });
        });
        
        // Add SignalR — use Redis backplane only when Redis is available
        var redisConnectionString = configuration.GetConnectionString("Redis");
        var signalRBuilder = services.AddSignalR()
            .AddJsonProtocol(options =>
            {
                options.PayloadSerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
                options.PayloadSerializerOptions.PropertyNameCaseInsensitive = true;
            });
        if (!string.IsNullOrEmpty(redisConnectionString))
        {
            try
            {
                var redis = StackExchange.Redis.ConnectionMultiplexer.Connect(
                    new StackExchange.Redis.ConfigurationOptions
                    {
                        EndPoints = { redisConnectionString },
                        AbortOnConnectFail = false,
                        ConnectTimeout = 3000
                    });
                if (redis.IsConnected)
                {
                    signalRBuilder.AddStackExchangeRedis(redisConnectionString, options =>
                    {
                        options.Configuration.ChannelPrefix = new StackExchange.Redis.RedisChannel("ZKTeco", StackExchange.Redis.RedisChannel.PatternMode.Literal);
                    });
                    Console.WriteLine("✅ SignalR: Redis backplane connected at {0}", redisConnectionString);
                }
                else
                {
                    redis.Dispose();
                    Console.WriteLine("⚠️ SignalR: Redis not available at {0}, using in-memory mode", redisConnectionString);
                }
            }
            catch
            {
                Console.WriteLine("⚠️ SignalR: Cannot connect to Redis at {0}, using in-memory mode", redisConnectionString);
            }
        }
        else
        {
            Console.WriteLine("ℹ️ SignalR: No Redis connection string configured, using in-memory mode");
        }

        // Memory cache for hot data (shifts, departments, settings)
        services.AddMemoryCache(options =>
        {
            options.SizeLimit = 10000; // Max 10000 cache entries for multi-store scale
            options.CompactionPercentage = 0.25; // Remove 25% when limit reached
            options.ExpirationScanFrequency = TimeSpan.FromMinutes(2);
        });
        services.AddSingleton<ICacheService, MemoryCacheService>();
        
        // Register face comparison service
        services.AddScoped<FaceComparisonService>();
        
        // Register notification services
        services.AddScoped<IAttendanceNotificationService, AttendanceNotificationService>();
        services.AddScoped<ISystemNotificationService, SystemNotificationService>();
        services.AddScoped<IDeviceStatusNotificationService, DeviceStatusNotificationService>();
        
        // Register Gemini AI service
        services.AddSingleton<IGeminiAiService, GeminiAiService>();
        
        // Register DeepSeek AI service
        services.AddSingleton<IDeepSeekAiService, DeepSeekAiService>();
        
        // Register background services
        services.AddHostedService<DeviceMonitorBackgroundService>();
        services.AddHostedService<KpiAutoSyncBackgroundService>();
        services.AddHostedService<PenaltyAutoApproveBackgroundService>();
        services.AddHostedService<NotificationCleanupBackgroundService>();
        
        services.AddSwaggerGen(config =>
        {
            config.CustomSchemaIds(x => x.FullName);
            config.SwaggerDoc("v1", new OpenApiInfo { Title = "ZKTecoADMS API", Version = "v1" });
            
            config.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
            {
                In = ParameterLocation.Header,
                Description = "Please enter token",
                Name = "Authorization",
                Type = SecuritySchemeType.Http,
                BearerFormat = "JWT",
                Scheme = "bearer"
            });
            config.AddSecurityRequirement(
                new OpenApiSecurityRequirement{
                    {
                        new OpenApiSecurityScheme
                        {
                            Reference = new OpenApiReference
                            {
                                Type=ReferenceType.SecurityScheme,
                                Id="Bearer"
                            }
                        },
                        Array.Empty<string>()
                    }
                });
        });
        // Register the global exception handler
        services.AddExceptionHandler<GlobalExceptionMiddleware>();
        services.AddProblemDetails();

        // Rate limiting — prevent API abuse at scale
        services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            // Global fixed window: 200 requests per 10 seconds per IP
            options.AddPolicy("fixed", httpContext =>
                RateLimitPartition.GetFixedWindowLimiter(
                    partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                    factory: _ => new FixedWindowRateLimiterOptions
                    {
                        PermitLimit = 200,
                        Window = TimeSpan.FromSeconds(10),
                        QueueLimit = 10,
                        QueueProcessingOrder = QueueProcessingOrder.OldestFirst
                    }));
            // Per-user sliding window: 100 requests per minute
            options.AddPolicy("per-user", httpContext =>
                RateLimitPartition.GetSlidingWindowLimiter(
                    partitionKey: httpContext.User?.Identity?.Name ?? httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                    factory: _ => new SlidingWindowRateLimiterOptions
                    {
                        PermitLimit = 100,
                        Window = TimeSpan.FromMinutes(1),
                        SegmentsPerWindow = 6,
                        QueueLimit = 5,
                        QueueProcessingOrder = QueueProcessingOrder.OldestFirst
                    }));
            // Login brute-force protection: 5 attempts per minute per IP
            options.AddPolicy("login", httpContext =>
                RateLimitPartition.GetFixedWindowLimiter(
                    partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                    factory: _ => new FixedWindowRateLimiterOptions
                    {
                        PermitLimit = 5,
                        Window = TimeSpan.FromMinutes(1),
                        QueueLimit = 0
                    }));
            // Device endpoints: 100 requests per 10 seconds per user (supports burst at shift change)
            options.AddPolicy("device", httpContext =>
                RateLimitPartition.GetSlidingWindowLimiter(
                    partitionKey: httpContext.User?.Identity?.Name ?? httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                    factory: _ => new SlidingWindowRateLimiterOptions
                    {
                        PermitLimit = 100,
                        Window = TimeSpan.FromSeconds(10),
                        SegmentsPerWindow = 5,
                        QueueLimit = 10,
                        QueueProcessingOrder = QueueProcessingOrder.OldestFirst
                    }));
        });

        // Response compression for reduced bandwidth
        services.AddResponseCompression(options =>
        {
            options.EnableForHttps = true;
            options.Providers.Add<BrotliCompressionProvider>();
            options.Providers.Add<GzipCompressionProvider>();
            options.MimeTypes = ResponseCompressionDefaults.MimeTypes.Concat(
                ["application/json", "application/octet-stream"]);
        });
        services.Configure<BrotliCompressionProviderOptions>(options =>
            options.Level = CompressionLevel.Fastest);
        services.Configure<GzipCompressionProviderOptions>(options =>
            options.Level = CompressionLevel.SmallestSize);

        return services;
    }

    public static async Task<WebApplication> UseApiServicesAsync(this WebApplication app)
    {
        AppContext.SetSwitch("Npgsql.EnableLegacyTimestampBehavior", true);

        if (app.Environment.IsDevelopment())
        {
            app.UseSwagger();
            app.UseSwaggerUI();

        }
        
        using (var scope = app.Services.CreateScope())
        {
            var initialiser = scope.ServiceProvider.GetRequiredService<ZKTecoDbInitializer>();
            await initialiser.InitialiseAsync();
            await initialiser.SeedAsync();
        }
        
        // Log ALL incoming requests — to diagnose new-gen ZKTeco devices using different paths
        app.Use(async (context, next) =>
        {
            var path = context.Request.Path.Value;
            var method = context.Request.Method;
            var qs = context.Request.QueryString.Value;
            var ip = context.Connection.RemoteIpAddress?.ToString();
            // Skip static files and health checks
            if (path != null && !path.StartsWith("/health") && !path.Contains('.'))
            {
                var logger = context.RequestServices.GetRequiredService<ILoggerFactory>()
                    .CreateLogger("RequestLogger");
                logger.LogWarning("[ALL REQUEST] {Method} {Path}{QS} from {IP}", method, path, qs, ip);
            }
            await next();
        });

        // Security headers
        app.Use(async (context, next) =>
        {
            context.Response.Headers.Append("X-Content-Type-Options", "nosniff");
            context.Response.Headers.Append("X-Frame-Options", "DENY");
            context.Response.Headers.Append("X-XSS-Protection", "0");
            context.Response.Headers.Append("Referrer-Policy", "strict-origin-when-cross-origin");
            context.Response.Headers.Append("Permissions-Policy", "camera=(self), microphone=(self), geolocation=(self)");
            await next();
        });

        app.UseExceptionHandler(options => { });

        // Forward headers from reverse proxy (nginx)
        app.UseForwardedHeaders(new Microsoft.AspNetCore.Builder.ForwardedHeadersOptions
        {
            ForwardedHeaders = Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedFor
                             | Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedProto
                             | Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedHost,
        });

        app.UseResponseCompression();
        app.UseCors("corsPolicy");
        app.UseRateLimiter();
        app.UseStaticFiles();
        // Enable WebSocket middleware (required for SignalR WebSocket transport in Docker/cloud)
        app.UseWebSockets();
        app.UseAuthentication();
        app.UseAuthorization();
        app.MapControllers().RequireRateLimiting("per-user");
        
        // Map SignalR hub for real-time attendance notifications (require authentication)
        app.MapHub<AttendanceHub>("/hubs/attendance").RequireAuthorization();

        // Health check — only expose status, not internal details
        app.UseHealthChecks("/health",
            new HealthCheckOptions
            {
                ResponseWriter = async (context, report) =>
                {
                    context.Response.ContentType = "application/json";
                    var result = new
                    {
                        status = report.Status.ToString(),
                        checks = report.Entries.Select(e => new
                        {
                            name = e.Key,
                            status = e.Value.Status.ToString()
                        })
                    };
                    await context.Response.WriteAsJsonAsync(result);
                }
            });

        return app;
    }

    private static IServiceCollection AddSettings(this IServiceCollection services, IConfiguration configuration)
    {
        var jwtSettings = configuration.GetSection("JwtSettings").Get<JwtSettings>() ?? null;
        ArgumentNullException.ThrowIfNull(jwtSettings, "JwtSettings was missed !");
        services.AddSingleton(jwtSettings);

        // Google Sheets settings
        services.Configure<GoogleSheetSettings>(configuration.GetSection(GoogleSheetSettings.SectionName));

        // Email settings
        services.Configure<EmailSettings>(configuration.GetSection(EmailSettings.SectionName));

        return services;
    }
}