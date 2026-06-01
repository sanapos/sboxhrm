#!/bin/bash
# Use docker exec to run a dotnet command inside the API container
# Check if dotnet is available
docker exec zkteco_api dotnet --version 2>/dev/null || echo "dotnet not available in container"
# Try to use the API container to change password via a special endpoint
# First, check what endpoints exist for password reset
echo "--- Checking password reset endpoint ---"
curl -s https://sbox.sana.vn/api/auth/forgot-password -X OPTIONS | head -c 200 || true