param(
    [string]$HostAddress = "127.0.0.1",
    [int]$Port = 8011
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$srcDir = Join-Path $projectRoot "src"
$xdbPath = Join-Path $projectRoot "ip2region.xdb"

if (-not (Test-Path $srcDir)) {
    throw "Source directory not found: $srcDir"
}

if (-not (Test-Path $xdbPath)) {
    throw "ip2region database file not found: $xdbPath"
}

$env:PYTHONPATH = $srcDir
$env:IP2REGION_XDB_PATH = $xdbPath

Write-Host "Starting IP Region API..."
Write-Host "Source: $srcDir"
Write-Host "Database: $xdbPath"
Write-Host "URL: http://${HostAddress}:${Port}/lookup?ip=1.1.1.1"
Write-Host ""

python -m uvicorn ip_region_api.app:app --host $HostAddress --port $Port
