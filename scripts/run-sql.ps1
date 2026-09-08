# Run a read-only SQL snippet on the production Postgres container (via plink).
param(
    [Parameter(Mandatory)][string]$Sql,
    [string]$Server = "103.133.224.176",
    [string]$User = "root",
    [string]$Password = $env:SBOX_DEPLOY_PASSWORD
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "deploy-ssh-helpers.ps1")

$plink = "C:\Program Files\PuTTY\plink.exe"
$pscp = "C:\Program Files\PuTTY\pscp.exe"
if (-not $Password) { Write-Error "Set SBOX_DEPLOY_PASSWORD env var" }

$script = @"
set -e
CID=`$(docker ps -qf name=zkteco_postgres | head -1)
if [ -z "`$CID" ]; then CID=`$(docker ps -qf name=postgres | head -1); fi
if [ -z "`$CID" ]; then echo "postgres container not found"; docker ps; exit 1; fi
docker exec -i "`$CID" psql -U postgres -d ZKTecoADMS -P pager=off <<'EOSQL'
$Sql
EOSQL
"@

Invoke-PuttySshScript -Plink $plink -Pscp $pscp -Password $Password -User $User -Server $Server `
    -Script $script -RemoteName "run-sql.sh"
