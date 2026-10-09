using ZKTecoADMS.Application.Settings;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;
using ZKTecoADMS.Api.Middlewares;
using ZKTecoADMS.Api.Controllers.Filters;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Api.Services.PaymentGateway;
using HealthChecks.UI.Client;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.OpenApi.Models;
using Microsoft.AspNetCore.ResponseCompression;
using System.IO.Compression;
using System.Threading.RateLimiting;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Http.Features;

namespace ZKTecoADMS.Api;

public static class DependencyInjectionExtensions
{
    public static IServiceCollection AddApi(this IServiceCollection services, IConfiguration configuration)
    {
        services.AddSettings(configuration);
        services.AddScoped<SystemAdminAgentScopeFilter>();
        services.Configure<FormOptions>(o =>
        {
            o.MultipartBodyLengthLimit = ServerOpsService.MaxUploadBytes;
            o.ValueLengthLimit = int.MaxValue;
        });
        services.AddControllers(o =>
            {
                o.Filters.Add<Controllers.Filters.AgentApiScopeFilter>();
                o.Filters.Add<Controllers.Filters.PagingGuardFilter>();
                // Hàng hóa / tồn / giá đổi → báo các máy bán đồng bộ danh mục ngay.
                o.Filters.Add<Controllers.Filters.PosCatalogChangedFilter>();
                // Lịch sử thao tác của cửa hàng (ai thêm / sửa / xóa gì, lúc nào).
                o.Filters.Add<Controllers.Filters.ActivityAuditFilter>();
            })
            .AddJsonOptions(options =>
            {
                options.JsonSerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
                options.JsonSerializerOptions.PropertyNameCaseInsensitive = true;
                options.JsonSerializerOptions.ReferenceHandler = System.Text.Json.Serialization.ReferenceHandler.IgnoreCycles;
                options.JsonSerializerOptions.MaxDepth = 32;
                options.JsonSerializerOptions.Converters.Add(new System.Text.Json.Serialization.JsonStringEnumConverter());
                options.JsonSerializerOptions.Converters.Add(new Serialization.UtcDateTimeJsonConverter());
                options.JsonSerializerOptions.Converters.Add(new Serialization.NullableUtcDateTimeJsonConverter());
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
            // Chuỗi dạng "host:6379,password=..." → Parse (không nhét cả chuỗi vào EndPoints).
            // Log chỉ ghi host — không in mật khẩu Redis.
            var redisHost = redisConnectionString.Split(',')[0];
            try
            {
                var redisOptions = StackExchange.Redis.ConfigurationOptions.Parse(redisConnectionString);
                redisOptions.AbortOnConnectFail = false;
                redisOptions.ConnectTimeout = 3000;
                using var redis = StackExchange.Redis.ConnectionMultiplexer.Connect(redisOptions);
                if (redis.IsConnected)
                {
                    signalRBuilder.AddStackExchangeRedis(redisConnectionString, options =>
                    {
                        options.Configuration.ChannelPrefix = new StackExchange.Redis.RedisChannel("ZKTeco", StackExchange.Redis.RedisChannel.PatternMode.Literal);
                        options.Configuration.AbortOnConnectFail = false;
                    });
                    Console.WriteLine("✅ SignalR: Redis backplane connected at {0}", redisHost);
                    // Màn hình khách dùng chung trạng thái qua Redis khi chạy nhiều instance.
                    Services.PosCustomerDisplayStateStore.UseDistributed = true;
                }
                else
                {
                    Console.WriteLine("⚠️ SignalR: Redis not available at {0}, using in-memory mode", redisHost);
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("⚠️ SignalR: Cannot connect to Redis at {0} ({1}), using in-memory mode", redisHost, ex.GetType().Name);
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
        // Register ONNX embedding service as singleton so the InferenceSession
        // is loaded once and reused across requests (heavy init).
        services.AddSingleton<FaceDetectorService>();
        services.AddSingleton<FaceAntiSpoofService>();
        services.AddHttpClient("viettel-sinvoice", client =>
        {
            client.Timeout = TimeSpan.FromSeconds(90);
        });
        services.AddHttpClient("easy-invoice", client =>
        {
            client.Timeout = TimeSpan.FromSeconds(90);
        });
        services.AddHttpClient("misa-meinvoice", client =>
        {
            client.Timeout = TimeSpan.FromSeconds(90);
        });
        services.AddHttpClient("vnpt-invoice", client =>
        {
            client.Timeout = TimeSpan.FromSeconds(90);
        });
        services.AddScoped<ZKTecoADMS.Api.Services.EInvoice.ViettelSInvoiceClient>();
        services.AddScoped<ZKTecoADMS.Api.Services.EInvoice.MisaMeInvoiceClient>();
        services.AddScoped<ZKTecoADMS.Api.Services.EInvoice.VnptInvoiceClient>();
        services.AddScoped<ZKTecoADMS.Api.Services.EInvoice.EasyInvoiceClient>();
        services.AddScoped<ZKTecoADMS.Api.Services.EInvoice.PosEInvoiceService>();
        services.AddSingleton<ZKTecoADMS.Api.Services.EInvoice.PosEInvoiceAutoIssuer>();
        services.AddHttpClient("shipping-ghn", c => c.Timeout = TimeSpan.FromSeconds(60));
        services.AddHttpClient("shipping-ghtk", c => c.Timeout = TimeSpan.FromSeconds(60));
        services.AddHttpClient("shipping-viettelpost", c => c.Timeout = TimeSpan.FromSeconds(60));
        services.AddHttpClient("shipping-ahamove", c => c.Timeout = TimeSpan.FromSeconds(60));
        services.AddHttpClient("shipping-spx", c => c.Timeout = TimeSpan.FromSeconds(60));
        services.AddHttpClient("shipping-geocode", c =>
        {
            c.Timeout = TimeSpan.FromSeconds(20);
            c.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "SBOX-POS-Shipping/1.0");
        });
        services.AddScoped<ZKTecoADMS.Api.Services.Shipping.IShippingCarrierClient,
            ZKTecoADMS.Api.Services.Shipping.GhnShippingClient>();
        services.AddScoped<ZKTecoADMS.Api.Services.Shipping.IShippingCarrierClient,
            ZKTecoADMS.Api.Services.Shipping.GhtkShippingClient>();
        services.AddScoped<ZKTecoADMS.Api.Services.Shipping.IShippingCarrierClient,
            ZKTecoADMS.Api.Services.Shipping.ViettelPostShippingClient>();
        services.AddScoped<ZKTecoADMS.Api.Services.Shipping.IShippingCarrierClient,
            ZKTecoADMS.Api.Services.Shipping.AhamoveShippingClient>();
        services.AddScoped<ZKTecoADMS.Api.Services.Shipping.IShippingCarrierClient,
            ZKTecoADMS.Api.Services.Shipping.SpxShippingClient>();
        services.AddScoped<ZKTecoADMS.Api.Services.Shipping.PosShippingService>();
        services.AddScoped<PosQrMenuService>();
        services.AddSingleton<IPaymentWebhookProvider, TingeePaymentWebhookProvider>(); // không trạng thái — registry singleton giữ được
        services.AddSingleton<IPaymentWebhookProviderRegistry, PaymentWebhookProviderRegistry>();
        services.AddScoped<IPosNotificationCreditService, PosNotificationCreditService>();
        services.AddScoped<IPosPlatformNotificationCreditService, PosPlatformNotificationCreditService>();
        services.AddScoped<IPosPlatformTingeeSettingService, PosPlatformTingeeSettingService>();
        services.AddScoped<ITingeeOpenApiClient, TingeeOpenApiClient>();
        services.AddScoped<ITingeeMerchantProvisioningService, TingeeMerchantProvisioningService>();
        services.AddScoped<IPosPaymentGatewayService, PosPaymentGatewayService>();
        services.AddScoped<IPosTingeePaidOrderService, PosTingeePaidOrderService>();
        services.AddHttpClient("tingee-open-api", (sp, client) =>
        {
            var cfg = sp.GetRequiredService<IConfiguration>();
            var env = cfg["Tingee:Environment"] ?? "Production";
            var baseUrl = env.Equals("UAT", StringComparison.OrdinalIgnoreCase)
                ? cfg["Tingee:UatApiBaseUrl"] ?? "https://uat-open-api.tingee.vn/v1"
                : cfg["Tingee:ProductionApiBaseUrl"] ?? "https://open-api.tingee.vn/v1";
            client.BaseAddress = new Uri(baseUrl.TrimEnd('/') + "/");
            client.Timeout = TimeSpan.FromSeconds(60);
        });
        services.AddHttpClient("face-sidecar");
        services.AddSingleton<OnnxFaceEmbeddingService>();
        
        // Register notification services
        services.AddScoped<IAttendanceNotificationService, AttendanceNotificationService>();
        services.AddScoped<IGymRealtimeNotifier, ZKTecoADMS.Api.Services.GymRealtimeNotifier>();
        services.AddScoped<ISystemNotificationService, SystemNotificationService>();
        services.AddScoped<ZKTecoADMS.Application.Interfaces.IAnnualLeaveBalanceService,
            ZKTecoADMS.Application.Leaves.AnnualLeaveBalanceService>();
        services.AddScoped<IDeviceStatusNotificationService, DeviceStatusNotificationService>();
        services.AddScoped<IPosPrintDispatchService, PosPrintDispatchService>();

        // FCM push notifications
        services.AddSingleton<ZKTecoADMS.Infrastructure.Services.Push.FirebaseInitializer>();
        services.AddScoped<ZKTecoADMS.Infrastructure.Services.Push.IPushNotificationService, ZKTecoADMS.Infrastructure.Services.Push.PushNotificationService>();

        // SuperAdmin announcements (Phase 1)
        services.AddScoped<IAudienceResolver, AudienceResolver>();
        services.AddScoped<IAnnouncementService, AnnouncementService>();
        services.AddScoped<IRenewalNotificationService, RenewalNotificationService>();

        // SuperAdmin maintenance (Phase 2)
        services.AddScoped<IMaintenanceService, MaintenanceService>();

        // Phase 3 — channel providers (Email/SMS/Push)
        services.AddScoped<INotificationChannelProvider, ZKTecoADMS.Infrastructure.Services.Channels.EmailChannelProvider>();
        services.AddScoped<INotificationChannelProvider, ZKTecoADMS.Infrastructure.Services.Channels.SmsChannelProvider>();
        services.AddScoped<INotificationChannelProvider, ZKTecoADMS.Infrastructure.Services.Channels.PushChannelProvider>();
        services.AddScoped<IMarketingService, MarketingService>();
        
        // Gemini AI: per-store config from AppSettings (scoped per request)
        services.AddScoped<TenantScopedGeminiAiService>();
        services.AddScoped<IGeminiAiService>(sp => sp.GetRequiredService<TenantScopedGeminiAiService>());
        services.AddScoped<AiAssistantActions>();
        services.AddScoped<AiVoiceService>();
        services.AddScoped<AiAssistantAgent>();
        services.AddScoped<PosAiMenuService>();
        services.AddScoped<PosDocxTemplateAiService>();
        services.AddSingleton<OfficePdfConverter>();
        
        // Register DeepSeek AI service
        services.AddSingleton<IDeepSeekAiService, DeepSeekAiService>();

        // Load AI keys from DB (AppSettings) at startup so they survive container restart
        services.AddHostedService<AiConfigLoaderHostedService>();

        // Register background services
        services.AddHostedService<DeviceMonitorBackgroundService>();
        services.AddHostedService<KpiAutoSyncBackgroundService>();
        services.AddHostedService<PenaltyAutoApproveBackgroundService>();
        services.AddHostedService<TaskRecurrenceBackgroundService>();
        services.AddHostedService<CommScheduleBackgroundService>();
        services.AddHostedService<AttendanceEvidencePurgeBackgroundService>();
        services.AddHostedService<NotificationCleanupBackgroundService>();
        services.AddHostedService<ZKTecoADMS.Api.Services.PosReservedStockReconcileBackgroundService>();
        services.AddHostedService<ActivityLogCleanupService>();
        services.AddHostedService<RawAttendanceCleanupBackgroundService>();
        services.AddHostedService<PackageDataRetentionBackgroundService>();
        services.AddHostedService<FieldDataCleanupBackgroundService>();

        // Phase 2 jobs
        services.AddHostedService<ScheduledAnnouncementBackgroundService>();
        services.AddHostedService<RenewalReminderBackgroundService>();
        services.AddHostedService<RenewalStaleCleanupBackgroundService>();
        services.AddHostedService<MaintenanceNotifierBackgroundService>();
        services.AddHostedService<BirthdayNotifierBackgroundService>();
        services.AddHostedService<PosStockAlertBackgroundService>();
        services.AddHostedService<ZKTecoADMS.Api.Services.GymAccessSyncBackgroundService>();
        services.AddHostedService<PosQrMaintenanceBackgroundService>();
        services.AddHostedService<PosPrintJobCleanupBackgroundService>();
        services.AddHostedService<PosPrintJobSweepBackgroundService>();
        services.AddHostedService<StoreNotificationScheduleBackgroundService>();
        services.AddSingleton<ServerMetricsState>();
        services.AddSingleton<ServerOpsService>();
        services.AddHostedService<ServerMetricsBackgroundService>();
        
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
            // Global fixed window: 1000 requests per 10 seconds per IP
            options.AddPolicy("fixed", httpContext =>
                RateLimitPartition.GetFixedWindowLimiter(
                    partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                    factory: _ => new FixedWindowRateLimiterOptions
                    {
                        PermitLimit = 1000,
                        Window = TimeSpan.FromSeconds(10),
                        QueueLimit = 50,
                        QueueProcessingOrder = QueueProcessingOrder.OldestFirst
                    }));
            // Mặc định mọi API controller: 1000 request / phút theo người dùng (chưa đăng nhập → theo IP).
            // Dùng GlobalLimiter thay cho MapControllers().RequireRateLimiting("per-user"): quy ước đó gắn
            // metadata SAU [EnableRateLimiting] của action nên đè mất «login» (20/phút) → không còn chống dò mật khẩu.
            // Endpoint có chính sách riêng (login, device, public-form…) chỉ dùng chính sách đó.
            options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(httpContext =>
            {
                var ep = httpContext.GetEndpoint();
                if (ep?.Metadata.GetMetadata<Microsoft.AspNetCore.Mvc.Controllers.ControllerActionDescriptor>() == null
                    || ep.Metadata.GetMetadata<Microsoft.AspNetCore.RateLimiting.EnableRateLimitingAttribute>() != null
                    || ep.Metadata.GetMetadata<Microsoft.AspNetCore.RateLimiting.DisableRateLimitingAttribute>() != null)
                    return RateLimitPartition.GetNoLimiter("_");
                return RateLimitPartition.GetSlidingWindowLimiter(
                    partitionKey: httpContext.User?.Identity?.IsAuthenticated == true
                        ? "u:" + (httpContext.User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value ?? httpContext.User.Identity.Name)
                        : "ip:" + (httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown"),
                    factory: _ => new SlidingWindowRateLimiterOptions
                    {
                        PermitLimit = 1000,
                        Window = TimeSpan.FromMinutes(1),
                        SegmentsPerWindow = 6,
                        QueueLimit = 50,
                        QueueProcessingOrder = QueueProcessingOrder.OldestFirst
                    });
            });
            // Chống dò mật khẩu theo IP: 60 lần / phút (văn phòng chung IP đăng nhập đầu ca vẫn đủ).
            // Lớp thứ hai: mỗi tài khoản khoá 15 phút sau 5 lần sai (Identity Lockout).
            options.AddPolicy("login", httpContext =>
                RateLimitPartition.GetFixedWindowLimiter(
                    partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                    factory: _ => new FixedWindowRateLimiterOptions
                    {
                        PermitLimit = 60,
                        Window = TimeSpan.FromMinutes(1),
                        QueueLimit = 0
                    }));
            // Tra cứu khi đang gõ (mã cửa hàng / email ở màn đăng nhập, đăng ký) — tách khỏi «login»
            // để không làm hết lượt đăng nhập của cả văn phòng dùng chung IP.
            options.AddPolicy("auth-lookup", httpContext =>
                RateLimitPartition.GetFixedWindowLimiter(
                    partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                    factory: _ => new FixedWindowRateLimiterOptions
                    {
                        PermitLimit = 90,
                        Window = TimeSpan.FromMinutes(1),
                        QueueLimit = 0
                    }));
            // Public forms: keep anonymous lead capture usable but throttle bursts/spam
            options.AddPolicy("public-form", httpContext =>
                RateLimitPartition.GetFixedWindowLimiter(
                    partitionKey: httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                    factory: _ => new FixedWindowRateLimiterOptions
                    {
                        PermitLimit = 5,
                        Window = TimeSpan.FromMinutes(1),
                        QueueLimit = 0
                    }));
            // Device endpoints: 500 requests per 10 seconds per user (supports burst at shift change)
            options.AddPolicy("device", httpContext =>
                RateLimitPartition.GetSlidingWindowLimiter(
                    partitionKey: httpContext.User?.Identity?.Name ?? httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                    factory: _ => new SlidingWindowRateLimiterOptions
                    {
                        PermitLimit = 500,
                        Window = TimeSpan.FromSeconds(10),
                        SegmentsPerWindow = 5,
                        QueueLimit = 50,
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

    /// <summary>Proxy tin cậy: loopback + dải private (nginx trên host đi vào qua gateway Docker).</summary>
    internal static readonly (string Prefix, int Length)[] TrustedProxyNetworks =
    [
        ("127.0.0.0", 8), ("::1", 128),
        ("10.0.0.0", 8), ("172.16.0.0", 12), ("192.168.0.0", 16),
        ("::ffff:127.0.0.0", 104), ("::ffff:10.0.0.0", 104), ("::ffff:172.16.0.0", 108), ("::ffff:192.168.0.0", 112),
    ];

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
            // Bài viết SEO mẫu (/bai-viet) — mỗi bài nạp một lần, Super Admin sửa / xóa thoải mái.
            await Seo.SeoArticleSeeder.SeedAsync(
                scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>(),
                scope.ServiceProvider.GetRequiredService<ILoggerFactory>().CreateLogger("SeoArticleSeeder"));
        }
        
        // Sau nginx: lấy IP thật từ X-Forwarded-For. Phải chạy trước mọi middleware đọc IP
        // (log, rate limit, audit). Chỉ tin proxy trong mạng nội bộ / Docker — request đi thẳng
        // từ Internet không giả được IP. Thiếu cấu hình này thì mọi request mang IP gateway Docker
        // và giới hạn đăng nhập theo IP thành giới hạn chung toàn hệ thống.
        var forwarded = new Microsoft.AspNetCore.Builder.ForwardedHeadersOptions
        {
            ForwardedHeaders = Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedFor
                             | Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedProto
                             | Microsoft.AspNetCore.HttpOverrides.ForwardedHeaders.XForwardedHost,
            ForwardLimit = 1,
        };
        forwarded.KnownNetworks.Clear();
        forwarded.KnownProxies.Clear();
        foreach (var (prefix, len) in TrustedProxyNetworks)
            forwarded.KnownNetworks.Add(new Microsoft.AspNetCore.HttpOverrides.IPNetwork(System.Net.IPAddress.Parse(prefix), len));
        app.UseForwardedHeaders(forwarded);

        // Log request để chẩn đoán máy chấm công đời mới dùng đường dẫn khác. Chỉ /iclock ở mức
        // Information; còn lại Debug (trước đây Warning mọi request → log container phình hàng trăm MB).
        // Không ghi query string ngoài /iclock vì có thể chứa access_token (SignalR) / chữ ký link ảnh.
        var requestLogger = app.Services.GetRequiredService<ILoggerFactory>().CreateLogger("RequestLogger");
        app.Use(async (context, next) =>
        {
            var path = context.Request.Path.Value;
            // Skip static files and health checks
            if (path != null && !path.StartsWith("/health") && !path.Contains('.'))
            {
                var method = context.Request.Method;
                var ip = context.Connection.RemoteIpAddress?.ToString();
                if (path.StartsWith("/iclock", StringComparison.OrdinalIgnoreCase))
                    requestLogger.LogInformation("[ALL REQUEST] {Method} {Path}{QS} from {IP}", method, path, context.Request.QueryString.Value, ip);
                else if (requestLogger.IsEnabled(LogLevel.Debug))
                    requestLogger.LogDebug("[ALL REQUEST] {Method} {Path} from {IP}", method, path, ip);
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

        app.UseResponseCompression();
        app.UseCors("corsPolicy");
        app.UseDefaultFiles();
        var contentTypes = new Microsoft.AspNetCore.StaticFiles.FileExtensionContentTypeProvider();
        contentTypes.Mappings[".apk"] = "application/vnd.android.package-archive";
        contentTypes.Mappings[".exe"] = "application/vnd.microsoft.portable-executable";
        contentTypes.Mappings[".json"] = "application/json";
        app.UseStaticFiles(new StaticFileOptions
        {
            ContentTypeProvider = contentTypes,
            ServeUnknownFileTypes = false,
        });
        // Enable WebSocket middleware (required for SignalR WebSocket transport in Docker/cloud)
        app.UseWebSockets();
        app.UseAuthentication();
        // Sau xác thực: giới hạn theo người dùng thật (trước đây chạy trước → mọi request tính theo IP).
        app.UseRateLimiter();
        app.UseAuthorization();
        app.UseMaintenanceMode();
        app.UseStoreLicenseCheck();
        app.UseStorePackageModuleCheck();
        app.UseBranchContext();
        app.MapControllers();
        
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