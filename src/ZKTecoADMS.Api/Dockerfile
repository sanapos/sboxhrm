# See https://aka.ms/customizecontainer to learn how to customize your debug container and how Visual Studio uses this Dockerfile to build your images for faster debugging.

# NOTE: We use the Debian-based (glibc) images, NOT Alpine (musl). The
# Microsoft.ML.OnnxRuntime NuGet package ships a glibc-linked
# libonnxruntime.so; loading it on Alpine fails with "symbol not found"
# because musl does not provide the _chk variants glibc exposes.
# This stage is used when running from VS in fast mode (Default for Debug configuration)
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS base
USER $APP_UID
WORKDIR /app
EXPOSE 7070
EXPOSE 7071


# This stage is used to build the service project
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
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

# Create wwwroot directories with proper permissions for file uploads.
# Production compose mounts a volume over /app/wwwroot — keep a copy of the
# guest menu outside that mount so /o/{token} still works.
USER root
RUN mkdir -p /app/wwwroot/uploads /app/wwwroot/stores /app/guest \
    && if [ -f /app/wwwroot/qr-order.html ]; then cp /app/wwwroot/qr-order.html /app/guest/qr-order.html; fi \
    && if [ -f /app/wwwroot/assets/sbox-pos-logo.png ]; then cp /app/wwwroot/assets/sbox-pos-logo.png /app/guest/sbox-pos-logo.png; fi \
    && chown -R $APP_UID:$APP_UID /app/wwwroot /app/guest
USER $APP_UID

ENTRYPOINT ["dotnet", "ZKTecoADMS.Api.dll"]