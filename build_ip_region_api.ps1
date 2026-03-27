param(
    [string]$PythonExe = "C:\Users\axeli\AppData\Local\Programs\Python\Python314\python.exe"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$distRoot = Join-Path $projectRoot "dist\ip_region_api_portable"
$buildRoot = Join-Path $projectRoot "build\ip_region_api_portable"
$specFile = Join-Path $projectRoot "ip_region_api_portable.spec"
$xdbPath = Join-Path $projectRoot "ip2region.xdb"

if (-not (Test-Path $xdbPath)) {
    throw "ip2region database file not found: $xdbPath"
}

if (Test-Path $distRoot) {
    Remove-Item -Recurse -Force $distRoot
}

if (Test-Path $buildRoot) {
    Remove-Item -Recurse -Force $buildRoot
}

if (Test-Path $specFile) {
    Remove-Item -Force $specFile
}

Push-Location $projectRoot
try {
    & $PythonExe -m PyInstaller `
        --name ip_region_api_portable `
        --onedir `
        --clean `
        --noconfirm `
        --paths "$projectRoot\src" `
        --collect-all ip2region `
        "$projectRoot\src\ip_region_api\server.py"

    Copy-Item $xdbPath (Join-Path $distRoot "ip2region.xdb") -Force

    @'
@echo off
setlocal
cd /d "%~dp0"
ip_region_api_portable.exe --host 0.0.0.0 --port 8011
'@ | Set-Content -Path (Join-Path $distRoot "start_ip_region_api.bat") -Encoding ASCII

    @'
param(
    [string]$HostAddress = "0.0.0.0",
    [int]$Port = 8011
)

$ErrorActionPreference = "Stop"
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $baseDir "ip_region_api_portable.exe") --host $HostAddress --port $Port
'@ | Set-Content -Path (Join-Path $distRoot "start_ip_region_api.ps1") -Encoding ASCII

    @'
Portable package contents:
- ip_region_api_portable.exe
- ip2region.xdb
- start_ip_region_api.bat
- start_ip_region_api.ps1

Default URL after startup:
http://127.0.0.1:8011/lookup?ip=1.1.1.1
'@ | Set-Content -Path (Join-Path $distRoot "README.txt") -Encoding ASCII
}
finally {
    Pop-Location
}
