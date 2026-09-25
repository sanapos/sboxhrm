# Build SBOX Print Agent (Windows) — một bản cho mỗi server.
#   .\build-agents.ps1              # cả hrm (sboxhrm.com) + pos (sboxpos.com)
#   .\build-agents.ps1 -Server pos
# Kết quả: dist\<server>\SboxPrintAgent.exe (+ server.txt để deploy kiểm tra)
param(
  [ValidateSet('hrm', 'pos', 'all')]
  [string]$Server = 'all'
)

$ErrorActionPreference = "Stop"
$project = Join-Path $PSScriptRoot "SboxPrintAgent\SboxPrintAgent.csproj"
$servers = if ($Server -eq 'all') { @('hrm', 'pos') } else { @($Server) }

foreach ($s in $servers) {
  $outDir = Join-Path $PSScriptRoot "dist\$s"
  Write-Host "==> Publish Print Agent for server '$s' -> $outDir"
  # Xóa obj để hằng số SBOX_SERVER_POS không bị dùng lại từ bản trước.
  Remove-Item -Recurse -Force (Join-Path $PSScriptRoot "SboxPrintAgent\obj") -ErrorAction SilentlyContinue
  dotnet publish $project -c Release "-p:SboxServer=$s" -o $outDir
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  Set-Content -Path (Join-Path $outDir "server.txt") -Value $s -NoNewline
}
