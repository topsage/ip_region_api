# IP Region API

本项目基于本地 `ip2region.xdb` 数据文件，提供一个可独立运行的 IP 归属地查询服务。

## Project Layout

```text
ip_region_api_project/
├─ src/
│  └─ ip_region_api/
│     ├─ __init__.py
│     ├─ app.py
│     └─ server.py
├─ tests/
│  └─ test_ip_region_api.py
├─ dist/
│  └─ ip_region_api_portable/
├─ build/
│  └─ ip_region_api_portable/
├─ ip2region.xdb
├─ requirements.txt
├─ run_ip_region_api.ps1
├─ build_ip_region_api.ps1
├─ ip_region_api_portable.spec
└─ README.md
```

## What Each Part Is For

- `src/ip_region_api/`: source code for the API service
- `tests/`: basic tests
- `ip2region.xdb`: local database used for IP lookup
- `run_ip_region_api.ps1`: run from source
- `build_ip_region_api.ps1`: build a portable package
- `dist/ip_region_api_portable/`: packaged standalone output for deployment
- `build/ip_region_api_portable/`: temporary build artifacts

## Run From Source

### 1. Install dependencies

```powershell
cd C:\Users\axeli\Documents\Playground\ip_region_api_project
python -m pip install -r requirements.txt
```

### 2. Start the service

```powershell
cd C:\Users\axeli\Documents\Playground\ip_region_api_project
.\run_ip_region_api.ps1
```

默认监听地址：

```text
http://127.0.0.1:8011
```

如需指定地址和端口：

```powershell
.\run_ip_region_api.ps1 -HostAddress 0.0.0.0 -Port 8011
```

## Run The Portable Package

如果需要在其他服务器独立运行，直接使用：

```powershell
cd C:\Users\axeli\Documents\Playground\ip_region_api_project\dist\ip_region_api_portable
.\start_ip_region_api.ps1
```

或双击：

- `start_ip_region_api.bat`

默认端口也是 `8011`。

## Build The Portable Package

```powershell
cd C:\Users\axeli\Documents\Playground\ip_region_api_project
.\build_ip_region_api.ps1
```

构建完成后，成品目录为：

```text
C:\Users\axeli\Documents\Playground\ip_region_api_project\dist\ip_region_api_portable
```

把整个 `ip_region_api_portable` 文件夹拷到目标服务器即可，不要只拷贝 exe。

## API Endpoints

### Health Check

```http
GET /health
```

示例：

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8011/health
```

### Lookup By GET

```http
GET /lookup?ip=1.1.1.1
```

示例：

```powershell
Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:8011/lookup?ip=1.1.1.1"
```

### Lookup By POST

```http
POST /lookup
Content-Type: application/json
```

请求体：

```json
{
  "ip": "1.1.1.1"
}
```

示例：

```powershell
Invoke-RestMethod -Method Post `
  -Uri "http://127.0.0.1:8011/lookup" `
  -ContentType "application/json" `
  -Body '{"ip":"1.1.1.1"}'
```

## Example Response

```json
{
  "ip": "1.1.1.1",
  "country": "中国",
  "province": "香港特别行政区",
  "city": "",
  "isp": "",
  "country_code": "CN",
  "region": "中国|香港特别行政区|0|0|CN"
}
```

## Notes

- 当前项目按 `IPv4 xdb` 方式运行
- 如果 `ip2region.xdb` 不在项目目录，服务无法启动
- 目标服务器只需要放行对应端口，不依赖当前电脑上的源码目录
