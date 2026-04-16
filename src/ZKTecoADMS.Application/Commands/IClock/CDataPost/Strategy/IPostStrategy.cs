using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Commands.IClock.CDataPost.Strategy;

public interface IPostStrategy
{
    Task<string> ProcessDataAsync(Device device, string body);
}