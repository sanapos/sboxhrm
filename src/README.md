# ============================================
# SQL Server 2022 Docker Setup
# ============================================

# 1. Pull SQL Server 2022 image (recommended)
docker pull mcr.microsoft.com/mssql/server:2022-latest

# 2. Run SQL Server container
docker run -e "ACCEPT_EULA=Y" \
  -e "MSSQL_SA_PASSWORD=YourStrong!Password123" \
  -e "MSSQL_PID=Developer" \
  -p 1433:1433 \
  --name sqlserver2022 \
  --hostname sqlserver \
  -d mcr.microsoft.com/mssql/server:2022-latest

# ============================================
# Alternative: SQL Server 2019 (if needed)
# ============================================

# Pull and run SQL Server 2019
docker run -e "ACCEPT_EULA=Y" \
  -e "MSSQL_SA_PASSWORD=YourStrong!Password123" \
  -e "MSSQL_PID=Developer" \
  -p 1433:1433 \
  --name sqlserver2019 \
  -d mcr.microsoft.com/mssql/server:2019-latest

# ============================================
# With Volume for Data Persistence
# ============================================

# Create a volume for persistent data
docker volume create sqlserver_data

# Run with volume mounted
docker run -e "ACCEPT_EULA=Y" \
  -e "MSSQL_SA_PASSWORD=YourStrong!Password123" \
  -e "MSSQL_PID=Developer" \
  -p 1433:1433 \
  --name sqlserver2022 \
  --hostname sqlserver \
  -v sqlserver_data:/var/opt/mssql \
  -d mcr.microsoft.com/mssql/server:2022-latest

# ============================================
# Using Docker Compose (Recommended)
# ============================================

# Create a file named: docker-compose.yml
# Then run: docker-compose up -d

# ============================================
# Useful Docker Commands
# ============================================

# Check if container is running
docker ps

# View container logs
docker logs sqlserver2022

# Stop the container
docker stop sqlserver2022

# Start the container
docker start sqlserver2022

# Remove the container
docker rm sqlserver2022

# Connect to SQL Server bash
docker exec -it sqlserver2022 /bin/bash

# ============================================
# Connect to SQL Server using sqlcmd
# ============================================

# From inside the container
docker exec -it sqlserver2022 /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P "YourStrong!Password123"

# From host machine (if sqlcmd is installed)
sqlcmd -S localhost,1433 -U sa -P "YourStrong!Password123"

# ============================================
# Create Database
# ============================================

# Execute SQL command to create database
docker exec -it sqlserver2022 /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P "YourStrong!Password123" \
  -Q "CREATE DATABASE ZKTecoIntegration"

# ============================================
# Connection Strings for .NET
# ============================================

# Standard connection string:
# Server=localhost,1433;Database=ZKTecoIntegration;User Id=sa;Password=YourStrong!Password123;TrustServerCertificate=True;

# For Docker container name (when API is also in Docker):
# Server=sqlserver2022,1433;Database=ZKTecoIntegration;User Id=sa;Password=YourStrong!Password123;TrustServerCertificate=True;

# ============================================
# Troubleshooting
# ============================================

# If port 1433 is already in use, use different port:
# -p 1434:1433 
# Then connection string: Server=localhost,1434;...

# Check container status
docker inspect sqlserver2022

# View SQL Server error logs
docker exec -it sqlserver2022 cat /var/opt/mssql/log/errorlog