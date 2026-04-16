using System.Text.Json.Serialization;
using ZKTecoADMS.Application.Behaviours;

namespace ZKTecoADMS.Application.Queries.IClock.GetRequest;

public record GetRequestQuery(string SN, string Info) : ICommand<string>, IIClockRequest;