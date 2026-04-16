using MediatR;
using Microsoft.Extensions.Logging;
using System.Diagnostics;
using System.Text.Json;

namespace ZKTecoADMS.Application.Behaviours;

public class LoggingBehaviour<TRequest, TResponse>(ILogger<TRequest> logger) : IPipelineBehavior<TRequest, TResponse> where TRequest : IRequest<TResponse>
{
    private static readonly HashSet<string> ExcludedRequests = new()
    {
        "GetRequestQuery"
    };

    public async Task<TResponse> Handle(TRequest request, RequestHandlerDelegate<TResponse> next, CancellationToken cancellationToken)
    {
        var requestName = typeof(TRequest).Name;
        var shouldLog = !ExcludedRequests.Contains(requestName);

        if (shouldLog)
        {
            var requestData = JsonSerializer.Serialize(request, new JsonSerializerOptions 
            { 
                WriteIndented = false,
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });
            
            logger.LogInformation("[START] Handle request={Request} - Response={Response} - RequestData={RequestData}",
                requestName, typeof(TResponse).Name, requestData);
        }

        var timer = new Stopwatch();
        timer.Start();

        var response = await next();

        timer.Stop();

        var timeTaken = timer.Elapsed;
        if (timeTaken.Seconds > 3) // if the request is greater than 3 seconds, then log the warnings
            logger.LogWarning("[PERFORMANCE] The request {Request} took {TimeTaken} seconds.",
                requestName, timeTaken.Seconds);

        if (shouldLog)
        {
            logger.LogInformation("[END] Handled {Request} with {Response}", requestName, typeof(TResponse).Name);
        }

        return response;
    }
}