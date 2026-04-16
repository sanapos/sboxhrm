using ZKTecoADMS.Application.Behaviours;
using ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;
using ZKTecoADMS.Application.Commands.SalaryProfiles.AssignSalaryProfile.SalaryProfileStrategies;
using ZKTecoADMS.Application.Interfaces;
using Microsoft.Extensions.DependencyInjection;
using System.Reflection;
using FluentValidation;
using Microsoft.Extensions.Configuration;

namespace ZKTecoADMS.Application;

public static class DependencyInjectionExtensions
{
    public static void AddApplication(this IServiceCollection services, IConfiguration configuration)
    {
        TypeAdapterConfig.GlobalSettings.Scan(Assembly.GetExecutingAssembly());
        
        services.AddValidatorsFromAssembly(Assembly.GetExecutingAssembly());

        services.AddMediatR(cfg =>
        {
            cfg.RegisterServicesFromAssembly(Assembly.GetExecutingAssembly());
            cfg.AddOpenBehavior(typeof(LoggingBehaviour<,>));
            cfg.AddOpenBehavior(typeof(ValidationBehavior<,>));
            cfg.AddOpenBehavior(typeof(DeviceActiveCheckBehaviour<,>));
        });

        // Automatically register all IDeviceCommandStrategy implementations
        RegisterDeviceCommandStrategies(services);
        
        // Register the factory
        services.AddScoped<IDeviceCommandStrategyFactory, DeviceCommandStrategyFactory>();
        
        // Register Salary Profile Strategies
        RegisterSalaryProfileStrategies(services);
        services.AddScoped<BenefitAssignmentStrategyFactory>();
    }
    
    private static void RegisterDeviceCommandStrategies(IServiceCollection services)
    {
        var strategyType = typeof(IDeviceCommandStrategy);
        var strategies = Assembly.GetExecutingAssembly()
            .GetTypes()
            .Where(t => t.IsClass && !t.IsAbstract && strategyType.IsAssignableFrom(t));

        foreach (var strategy in strategies)
        {
            services.AddScoped(strategy);
        }
    }
    
    private static void RegisterSalaryProfileStrategies(IServiceCollection services)
    {
        var strategyType = typeof(IBenefitAssignmentStrategy);
        var strategies = Assembly.GetExecutingAssembly()
            .GetTypes()
            .Where(t => t.IsClass && !t.IsAbstract && strategyType.IsAssignableFrom(t));

        foreach (var strategy in strategies)
        {
            services.AddScoped(strategyType, strategy);
        }
    }
}

