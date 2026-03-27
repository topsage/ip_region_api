param(
    [string]$HostAddress = "0.0.0.0",
    [int]$Port = 8011
)

$ErrorActionPreference = "Stop"
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $baseDir "ip_region_api_portable.exe") --host $HostAddress --port $Port
