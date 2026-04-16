# See https://aka.ms/customizecontainer to learn how to customize your debug container and how Visual Studio uses this Dockerfile to build your images for faster debugging.

# This stage is used when running from VS in fast mode (Default for Debug configuration)
FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine AS base
USER $APP_UID
WORKDIR /app
EXPOSE 7070
EXPOSE 7071


# This stage is used to build the service project
FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src
COPY ["ZKTecoADMS.Api/ZKTecoADMS.Api.csproj", "ZKTecoADMS.Api/"]
COPY ["ZKTecoADMS.Application/ZKTecoADMS.Application.csproj", "ZKTecoADMS.Application/"]
COPY ["ZKTecoADMS.Domain/ZKTecoADMS.Domain.csproj", "ZKTecoADMS.Domain/"]
COPY ["ZKTecoADMS.Infrastructure/ZKTecoADMS.Infrastructure.csproj", "ZKTecoADMS.Infrastructure/"]
RUN dotnet restore "./ZKTecoADMS.Api/ZKTecoADMS.Api.csproj"
COPY . .
WORKDIR "/src/ZKTecoADMS.Api"
RUN dotnet build "./ZKTecoADMS.Api.csproj" -c $BUILD_CONFIGURATION -o /app/build

# This stage is used to publish the service project to be copied to the final stage
FROM build AS publish
ARG BUILD_CONFIGURATION=Release
RUN dotnet publish "./ZKTecoADMS.Api.csproj" -c $BUILD_CONFIGURATION -o /app/publish /p:UseAppHost=false

# This stage is used in production or when running from VS in regular mode (Default when not using the Debug configuration)
FROM base AS final
WORKDIR /app
COPY --from=publish /app/publish .

# Create wwwroot/uploads with proper permissions for file uploads
USER root
RUN mkdir -p /app/wwwroot/uploads && chown -R $APP_UID:$APP_UID /app/wwwroot
USER $APP_UID

ENTRYPOINT ["dotnet", "ZKTecoADMS.Api.dll"]