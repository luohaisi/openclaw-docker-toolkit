# OpenClaw Docker 部署工具包

在 Docker 中运行 [OpenClaw](https://github.com/openclaw/openclaw) Gateway，`docker-compose.yml` 与[上游](https://github.com/openclaw/openclaw/blob/main/docker-compose.yml)对齐。官方文档：[Docker（中文）](https://docs.openclaw.ai/zh-CN/install/docker)。

## 要点

- **网关配置**：只读取 **`openclaw/openclaw.json`**（不可用 `openclaw.json5` 作为唯一配置文件名，否则等同「无配置」）。须含 **`gateway.mode: "local"`**。模型与第三方 API 须写在当前 schema 允许的键下（例如 **`models.providers`**），根级 **`providers` 会被判为非法键而导致网关无法启动；见仓库内示例 `openclaw/openclaw.json`。
- **镜像**：仅支持**离线包** `docker load` 后启动，不执行在线 `docker pull`（见下节）。
- **数据**：`openclaw/` → 容器内 `~/.openclaw`；`workspace/` → `~/.openclaw/workspace`。
- **Gateway**：`bind` 使用 `lan`（见 `openclaw/openclaw.json`），端口默认 18789/18790。安装脚本会按 `.env` 里的 `OPENCLAW_GATEWAY_PORT` **检测端口占用**并提示（含 WSL 里已跑 OpenClaw 时常出现冲突）；可先在 WSL 停服务，或改 `.env` 端口。
- **后台运行**：`docker compose up -d` 后容器由 **Docker 守护进程**维护，**关掉安装脚本的窗口不会停止容器**。
- **停止本项目**：双击 **`stop-openclaw.bat`**，或 PowerShell 执行 `.\stop-openclaw.ps1`（等同于 `docker compose down`，**不删** `openclaw/`、`workspace/` 数据）。**退出 Docker 全盘**：系统托盘右键 **Docker Desktop → Quit Docker Desktop**（会停掉所有用 Docker 的应用容器）。

## 目录

| 路径 | 说明 |
|------|------|
| `docker-compose.yml` | `openclaw-gateway` + `openclaw-cli` |
| `openclaw/`、`workspace/` | 主配置为 **`openclaw/openclaw.json`**（不要用 `openclaw.json5` 作唯一文件名）；工作区挂载 |
| `.env` | 密钥与变量（**勿提交**） |
| `images/` | 放置离线镜像 `openclaw.tar.gz`（见 `.gitignore`） |
| `setup-openclaw.bat` / `setup-openclaw.ps1` | 加载离线镜像并 `docker compose up -d` |
| `restart-openclaw.bat` / `restart-openclaw.ps1` | 一键重启（执行 `docker compose up -d`） |
| `stop-openclaw.bat` / `stop-openclaw.ps1` | 停止本项目的容器（`docker compose down`） |
| `tui-openclaw.bat` / `tui-openclaw.ps1` | 一键启动 TUI（默认带 **`--deliver`**，避免无对话输出；仍可直接 `docker compose run ... tui` 自建参数） |

## Windows 安装（离线镜像）

1. 安装并启动 **Docker Desktop**。
2. 将导出的 **`openclaw-*.tar.gz`** 放到 **`images\openclaw.tar.gz`**，或仓库根目录 **`openclaw.tar.gz`**。
3. 双击 **`setup-openclaw.bat`**，或：

   ```powershell
   cd <本仓库根目录>
   powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-openclaw.ps1
   ```

4. 自定义离线包路径：

   ```powershell
   .\setup-openclaw.ps1 -ImageArchive "D:\openclaw-xxx.tar.gz"
   ```

5. 编辑 **`.env`**：填写模型 API 等；把 **`OPENCLAW_IMAGE=`** 改成脚本输出的「已加载」镜像名。**`OPENCLAW_GATEWAY_TOKEN`** 若为空（含模板里被注释那一行），一键脚本会**自动生成**（仅字母、数字、连字符 `-`，避免 `+`/`=` 等被误截断）并 **UTF-8 带 BOM 保存**，便于记事本正确显示中文注释。终端会临时显示一次 Token。

若 **`.env` 中文乱码**：用 VS Code / 记事本将文件 **另存为 UTF-8（带 BOM）**，或备份后删除 `.env` 重新运行一次安装脚本以从模板重建。

手动启动（已 `docker load` 且 `.env` 中 `OPENCLAW_IMAGE` 正确）：

```powershell
docker compose up -d
```

## 导出离线包并上传 OSS（可选）

仓库提供 [`.github/workflows/export-image.yml`](.github/workflows/export-image.yml)：在 Actions 中配置 Secrets `OSS_ACCESS_KEY_ID`、`OSS_ACCESS_KEY_SECRET`、`OSS_ENDPOINT`、`OSS_BUCKET`，手动运行 workflow 后从日志取 OSS 下载链接。本地验证上传见 `scripts/oss-local.env.example`。

## 常用命令

```powershell
docker compose logs -f openclaw-gateway
docker compose run --rm openclaw-cli dashboard --no-open
docker compose run --rm -it openclaw-cli tui
# 或一键：.\tui-openclaw.ps1（可跟参数：.\tui-openclaw.ps1 -- --help）
# PowerShell 中请用 curl.exe（curl 会当成 Invoke-WebRequest）
curl.exe -fsS http://127.0.0.1:18789/healthz
# 或：irm http://127.0.0.1:18789/healthz
docker compose down
# 或一键：.\stop-openclaw.ps1
# 重启（等同 up -d）
# 或一键：.\restart-openclaw.ps1
```

Control UI：<http://127.0.0.1:18789/>

## 配置与备份

修改 `openclaw/openclaw.json` 或 `.env` 后：`docker compose up -d`。备份建议打包 `openclaw/`、`workspace/`、`.env`。

## 故障排查

- **Control UI 提示 Token 无效**：`openclaw.json` 中 **`gateway.auth.token`** 须为 **`${OPENCLAW_GATEWAY_TOKEN}`**，与 **`.env` 唯一一致**；勿在 JSON 里另写死一串。改完后 `docker compose up -d`。
- **TUI 只有 `HEARTBEAT_OK`、`/status` 正常**：官方说明默认 **未开启 delivery 时可能发出去但看不到助手回复**；在 TUI 内执行 **`/deliver on`**，或一键脚本已默认 **`--deliver`**。若仍无输出，查 Kimi/OpenRouter Key 与 `docker compose logs openclaw-gateway`。
- **仓库里同时有 `workspace/` 与 `openclaw/workspace/`**：以根目录 **`workspace/`** 为准（compose 挂载），`openclaw/workspace/` 一般为误建或历史残留，可备份后删除以免混淆。
- **网页聊天一直转圈，刷新后才出现回复**：多为 **流式输出结束时前端未收到/未处理「完成」事件**，后端其实已写完；可试无痕窗口、换浏览器、关广告拦截、看 F12 控制台与 Network → WS 是否报错；镜像可随上游更新。数据一般未丢，仅界面状态未刷新。
- **Skills 放在哪**：会扫描的是**工作区下的 `skills/` 目录**（每个技能为子文件夹 + `SKILL.md`），即 **`workspace/skills/<技能名>/SKILL.md`**，不是零散丢在 `workspace/` 根目录。亦可用 `~/.openclaw/skills`（本仓库即 `openclaw/skills/`，若自行新建）。详见 [官方 Skills](https://docs.openclaw.ai/tools/skills)。
- **浏览器打开 127.0.0.1:18789 白屏 / `curl` 连不上**：确认配置名为 **`openclaw/openclaw.json`**（不是 `openclaw.json5`）。用 `curl.exe -fsS http://127.0.0.1:18789/healthz` 或 `irm` 测试；再在 `gateway` 下配置 `controlUi.allowedOrigins`（见 `defaults/openclaw.default.json`），`docker compose up -d`。若提示未授权/需配对，见[官方说明](https://docs.openclaw.ai/install/docker#unauthorized-or-pairing-required-in-control-ui)。
- **设备/API**：见[官方文档](https://docs.openclaw.ai/)。
- **端口冲突**：改 `.env` 中 `OPENCLAW_GATEWAY_PORT` / `OPENCLAW_BRIDGE_PORT`。

## 许可

OpenClaw 上游见 [文档](https://docs.openclaw.ai/)。
