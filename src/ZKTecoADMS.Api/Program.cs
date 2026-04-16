using ZKTecoADMS.Api;
using ZKTecoADMS.Application;
using ZKTecoADMS.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddApi(builder.Configuration);
builder.Services.AddApplication(builder.Configuration);
builder.Services.AddInfrastructure(builder.Configuration);

var app = builder.Build();

await app.UseApiServicesAsync();

app.Run();
