# Linux Shell IP Region API

这个子目录提供一个不依赖 Python 的 Linux shell 版本，直接复用项目根目录的 `ip2region.xdb`。

## 目录说明

```text
linux_shell/
├─ bin/
│  ├─ http_handler.sh
│  ├─ lookup.sh
│  └─ serve.sh
├─ lib/
│  └─ ip2region.sh
└─ tests/
   └─ test_linux_shell_api.sh
```

## 依赖

- `bash`
- `od`
- `dd`
- `sed`
- `mktemp`
- `nc` / `netcat` / `ncat`（只在启动 HTTP 服务时需要）

## 使用方式

### 1. 给脚本执行权限

```bash
chmod +x linux_shell/bin/*.sh linux_shell/tests/*.sh
```

### 2. 命令行查询

```bash
./linux_shell/bin/lookup.sh 1.1.1.1
```

默认会读取项目根目录的 `ip2region.xdb`。如果你把数据库放在别处，可以这样指定：

```bash
IP2REGION_XDB_PATH=/opt/ip-region/ip2region.xdb ./linux_shell/bin/lookup.sh 8.8.8.8
```

也可以直接这样写：

```bash
./linux_shell/bin/lookup.sh --xdb-path /opt/ip-region/ip2region.xdb 8.8.8.8
```

### 3. 启动 HTTP 服务

```bash
./linux_shell/bin/serve.sh --host 0.0.0.0 --port 8011
```

如果数据库不放在项目根目录，启动时把绝对路径带上：

```bash
./linux_shell/bin/serve.sh --host 0.0.0.0 --port 8011 --xdb-path /opt/ip-region/ip2region.xdb
```

如果你是远程访问这台机器，记得提前放行服务端口，不然服务启动了也连不上。

Ubuntu / Debian 常见写法：

```bash
sudo ufw allow 8011/tcp
sudo ufw reload
```

CentOS / RHEL / Rocky / AlmaLinux 这类系统更常见的是 `firewalld`，可以这样写：

```bash
sudo firewall-cmd --permanent --add-port=8011/tcp
sudo firewall-cmd --reload
```

## 数据库放哪

最省事的放法有两种：

1. 把 `ip2region.xdb` 放在项目根目录，也就是和 `linux_shell/` 同一级。
2. 放到你自己的固定路径，比如 `/opt/ip-region/ip2region.xdb`，然后启动时用 `--xdb-path` 或环境变量指定。

如果你准备长期跑服务，我建议用第二种，路径固定，systemd 也更好写。

可用接口和原项目保持一致：

- `GET /health`
- `GET /lookup?ip=1.1.1.1`
- `POST /lookup`

POST 请求体示例：

```json
{"ip":"1.1.1.1"}
```

## 测试

```bash
./linux_shell/tests/test_linux_shell_api.sh
```

## systemd

我已经放了一个模板文件在：

- `linux_shell/systemd/ip-region-api.service`

你只要把里面这几处改成你机器上的真实路径和用户：

- `User=`
- `Group=`
- `WorkingDirectory=`
- `Environment=IP2REGION_XDB_PATH=`
- `ExecStart=`

一个常见放法是：

- 项目目录：`/opt/ip_region_api_project`
- 数据库文件：`/opt/ip_region_api_project/ip2region.xdb`

部署步骤示例：

```bash
sudo cp linux_shell/systemd/ip-region-api.service /etc/systemd/system/ip-region-api.service
sudo systemctl daemon-reload
sudo systemctl enable --now ip-region-api.service
sudo systemctl status ip-region-api.service
```

如果这台机器需要被别的机器访问，别忘了同时放行你配置的端口。不同系统常见写法如下。

Ubuntu / Debian：

```bash
sudo ufw allow 8011/tcp
```

CentOS / RHEL / Rocky / AlmaLinux：

```bash
sudo firewall-cmd --permanent --add-port=8011/tcp
sudo firewall-cmd --reload
```

测试覆盖：

- 命令行查询结果是否和现有服务样本一致
- IPv4 数据库对 IPv6 的拒绝
- `/health`
- `GET /lookup`
- `POST /lookup`
- 非法 IP 的错误返回
