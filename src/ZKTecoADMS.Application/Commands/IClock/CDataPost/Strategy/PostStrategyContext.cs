using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Commands.IClock.CDataPost.Strategy;

public class PostStrategyContext
{
    private readonly IPostStrategy _strategy;
    private readonly ILogger<PostStrategyContext> _logger;
    private readonly string _table;
    
    public PostStrategyContext(IServiceProvider serviceProvider, string table)
    {
        _table = table;
        _logger = serviceProvider.GetRequiredService<ILogger<PostStrategyContext>>();
        
        _strategy = table switch
        {
            "ATTLOG" => new PostAttendancesStrategy(serviceProvider),
            "OPERLOG" => new OperLogStrategy(serviceProvider),
            "USERINFO" => new OperLogStrategy(serviceProvider), // Some devices use USERINFO table
            "FINGERTMP" => new PostBiometricStrategy(serviceProvider), // Fingerprint templates
            "BIODATA" => new PostBiometricStrategy(serviceProvider),   // Biometric data (face/fingerprint)
            "OPTIONS" => new PostOptionsStrategy(serviceProvider),     // Device info from PUSH devices
            _ => new PostBiometricStrategy(serviceProvider)
        };
        
        _logger.LogInformation("[PostStrategy] Table={Table}, Strategy={Strategy}", 
            table, _strategy.GetType().Name);
    }

    public async Task<string> ExecuteAsync(Device device, string body)
    {
        _logger.LogInformation("[PostStrategy] Executing for Device {DeviceId}, Table={Table}", 
            device.Id, _table);
        return await _strategy.ProcessDataAsync(device, body);
    }
}