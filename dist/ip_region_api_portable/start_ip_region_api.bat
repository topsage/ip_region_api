@echo off
setlocal
cd /d "%~dp0"
ip_region_api_portable.exe --host 0.0.0.0 --port 8011
