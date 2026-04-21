# OpenClaw Docker 部署工具包

在 Docker 中运行 [OpenClaw](https://github.com/openclaw/openclaw) Gateway，`docker-compose.yml` 与[上游](https://github.com/openclaw/openclaw/blob/main/docker-compose.yml)对齐。官方文档：[Docker（中文）](https://docs.openclaw.ai/zh-CN/install/docker)。

## 新手快速上手（3 步）

1. 安装并启动 **Docker Desktop**。
2. 把离线镜像包放到以下任一位置：
   - `images/openclaw.tar.gz`
   - 仓库根目录 `openclaw.tar.gz`
3. 双击 `setup-openclaw.bat`，等待完成后访问：
   - <http://127.0.0.1:18789/>

> 停止服务：双击 `stop-openclaw.bat`  
> 重启服务：双击 `restart-openclaw.bat`

## 你最需要知道的 4 件事

- 配置文件只认 `openclaw/openclaw.json`（不要只留 `openclaw.json5`）。
- 默认端口是 `18789`（网关）和 `18790`（桥接）。
- 数据在 `openclaw/` 和 `workspace/`，`docker compose down` 不会删除它们。
- 本仓库走离线镜像流程，不依赖在线 `docker pull`。

## 目录

| 路径 | 说明 |
|------|------|
| `docker-compose.yml` | `openclaw-gateway` + `openclaw-cli` |
| `openclaw/`、`workspace/` | 主配置为 **`openclaw/openclaw.json`**（不要用 `openclaw.json5` 作唯一文件名）；工作区挂载 |
| `.env` | 密钥与变量（**勿提交**） |
| `images/` | 放置离线镜像 `openclaw.tar.gz`（见 `.gitignore`） |
| `setup-openclaw.bat` | 统一安装入口（10 秒默认 with-python） |
| `restart-openclaw.bat` | 统一重启入口（自动判断 with-python / without-python） |
| `stop-openclaw.bat` | 统一停止入口（自动判断 with-python / without-python） |
| `scripts/tools/setup-openclaw.ps1` | setup 核心逻辑（模式选择与分发） |
| `scripts/tools/restart-openclaw.ps1` | restart 核心逻辑（自动模式） |
| `scripts/tools/stop-openclaw.ps1` | stop 核心逻辑（自动模式） |
| `scripts/openclaw-ports.ps1` | 由其它脚本点选加载：端口检测与自动写入（一般不单独运行） |
| `tui-openclaw.bat` / `tui-openclaw.ps1` | 一键启动 TUI（默认带 **`--deliver`**，避免无对话输出；仍可直接 `docker compose run ... tui` 自建参数） |

## 常用命令（最小集合）

```powershell
docker compose logs -f openclaw-gateway
curl.exe -fsS http://127.0.0.1:18789/healthz
docker compose down
```

## 进阶说明（展开查看）

<details>
<summary>安装模式、.env 细节、故障排查、TUI、Skills 路径</summary>

### 统一安装入口（含 Python 方案）

`setup-openclaw.bat` 已合并模式选择：启动后 10 秒倒计时，默认 **with-python**；也可选择 **without-python**。

> `with-python` 模式使用仓库根目录的 `python-standalone/` 作为母版来源。该目录是**用户本地下载并解压**的运行时资源，已在 `.gitignore` 中忽略，不会提交到仓库。

1. 双击 **`setup-openclaw.bat`**，或：

   ```powershell
   cd <本仓库根目录>
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tools\setup-openclaw.ps1
   ```

2. 自定义离线镜像路径（与原安装脚本一致）：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tools\setup-openclaw.ps1 -ImageArchive "D:\openclaw-xxx.tar.gz"
   ```

3. 验证：

   ```powershell
   docker compose -f docker-compose.yml -f docker-compose.python.yml exec openclaw-gateway python3 --version
   docker compose -f docker-compose.yml -f docker-compose.python.yml exec openclaw-gateway pip --version
   ```

4. 常用维护：
   - 重置 Python 环境：`docker compose down && docker volume rm openclaw-docker_openclaw-python && docker compose -f docker-compose.yml -f docker-compose.python.yml up -d`
   - 查看网关日志：`docker compose -f docker-compose.yml -f docker-compose.python.yml logs -f openclaw-gateway`

## Windows 安装（离线镜像）

1. 安装并启动 **Docker Desktop**。
2. 将导出的 **`openclaw-*.tar.gz`** 放到 **`images\openclaw.tar.gz`**，或仓库根目录 **`openclaw.tar.gz`**。
3. 双击 **`setup-openclaw.bat`**，并在倒计时内选择 `without-python`，或：

   ```powershell
   cd <本仓库根目录>
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tools\setup-openclaw.ps1 -Mode without-python
   ```

4. 自定义离线包路径：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\tools\setup-openclaw.ps1 -Mode without-python -ImageArchive "D:\openclaw-xxx.tar.gz"
   ```

5. 编辑 **`.env`**：
   - 填写模型 API 等配置。
   - **必须手动填入你自己的 API Key**（例如 `OPENROUTER_API_KEY` / 其它你启用的 provider key）。
   - 若 API Key 为空或无效，常见现象是终端显示服务已启动，但网页打不开，且通常不会主动报明确错误。
   - 首次启动或重启后，通常还需要等待数秒，网页才会正常显示。
   - 把 **`OPENCLAW_IMAGE=`** 改成脚本输出的「已加载」镜像名。
   - 若 **`OPENCLAW_GATEWAY_TOKEN`** 为空（含模板里被注释那一行），一键脚本会自动生成：
     - 字符集仅字母、数字、连字符 `-`（避免 `+`/`=` 被误截断）
     - 以 UTF-8（带 BOM）保存，便于记事本正确显示中文注释
   - 终端会临时显示一次 Token。

若 **`.env` 中文乱码**：

- 用 VS Code / 记事本将文件另存为 UTF-8（带 BOM）。
- 或备份后删除 `.env`，重新运行一次安装脚本以从模板重建。

手动启动（已 `docker load` 且 `.env` 中 `OPENCLAW_IMAGE` 正确）：

```powershell
docker compose up -d
```

## 导出离线包并上传 OSS（可选）

仓库提供 [`.github/workflows/export-image.yml`](.github/workflows/export-image.yml)：在 Actions 中配置 Secrets `OSS_ACCESS_KEY_ID`、`OSS_ACCESS_KEY_SECRET`、`OSS_ENDPOINT`、`OSS_BUCKET`，手动运行 workflow 后从日志取 OSS 下载链接。本地验证上传见 `scripts/oss-local.env.example`。

### 常用命令（完整）

```powershell
docker compose logs -f openclaw-gateway
docker compose run --rm openclaw-cli dashboard --no-open
docker compose run --rm -it openclaw-cli tui
# 或一键：.\tui-openclaw.ps1（可跟参数：.\tui-openclaw.ps1 -- --help）
# Python 方案建议使用带覆盖文件的 compose 命令
docker compose -f docker-compose.yml -f docker-compose.python.yml ps
# PowerShell 中请用 curl.exe（curl 会当成 Invoke-WebRequest）
curl.exe -fsS http://127.0.0.1:18789/healthz
# 或：irm http://127.0.0.1:18789/healthz
docker compose down
# 或一键：.\stop-openclaw.bat
# 重启（等同 up -d）
# 或一键：.\restart-openclaw.bat
```

Control UI：<http://127.0.0.1:18789/>

### 配置与备份

修改 `openclaw/openclaw.json` 或 `.env` 后：`docker compose up -d`。备份建议打包 `openclaw/`、`workspace/`、`.env`。

### 故障排查

### Control UI 提示 Token 无效

- 本仓库采用“反向同步”策略：
  - `scripts/openclaw-token.ps1` 会在 `setup/restart` 前
  - 从 `openclaw/openclaw.json` 读取 `gateway.auth.token`
  - 回写 `.env` 的 `OPENCLAW_GATEWAY_TOKEN`
- 该过程不会改写 `openclaw.json` 排版。
- 若仍失配：先确认 `openclaw/openclaw.json` 里的 token，再执行对应 `restart` 触发同步。

### TUI 只有 `HEARTBEAT_OK`、`/status` 正常

- 官方说明：未开启 delivery 时，可能“消息发出但看不到助手回复”。
- 在 TUI 内执行 `/deliver on`，或直接用已默认 `--deliver` 的一键脚本。
- 若仍无输出：检查 Kimi/OpenRouter Key，并查看 `docker compose logs openclaw-gateway`。

### 同时存在 `workspace/` 与 `openclaw/workspace/`

- 以根目录 `workspace/` 为准（compose 挂载）。
- `openclaw/workspace/` 多为误建或历史残留，可先备份再删除，避免混淆。

### 网页聊天一直转圈，刷新后才出现回复

- 常见原因：流式输出结束后，前端未收到/未处理“完成”事件。
- 后端通常已写完，数据一般未丢，只是界面状态未刷新。
- 可尝试：
  - 无痕窗口
  - 更换浏览器
  - 关闭广告拦截
  - 查看 F12 控制台与 Network -> WS 报错
- 镜像可随上游更新。

### Skills 放在哪

- 扫描目录是工作区下 `skills/`：`workspace/skills/<技能名>/SKILL.md`。
- 不是把技能文件零散放在 `workspace/` 根目录。
- 也可使用 `~/.openclaw/skills`（本仓库对应 `openclaw/skills/`，可自行新建）。
- 详见[官方 Skills](https://docs.openclaw.ai/tools/skills)。

### 浏览器打开 127.0.0.1:18789 白屏 / `curl` 连不上

- 先确认配置文件名是 `openclaw/openclaw.json`（不是 `openclaw.json5`）。
- 使用 `curl.exe -fsS http://127.0.0.1:18789/healthz` 或 `irm` 测试。
- 在 `gateway` 下配置 `controlUi.allowedOrigins`（见 `defaults/openclaw.default.json`），然后 `docker compose up -d`。
- 若提示未授权/需配对，参见[官方说明](https://docs.openclaw.ai/install/docker#unauthorized-or-pairing-required-in-control-ui)。

### 设备/API

- 先确认 `.env` 已填写你自己的 provider API Key（如 `OPENROUTER_API_KEY`）。
- 未填写时常见现象是：终端显示服务已启动，但网页打不开，且日志不一定直观报错。
- 服务启动后通常需要等待数秒，再访问网页更稳定。
- 其他设备/API 说明见[官方文档](https://docs.openclaw.ai/)。

### 端口冲突

- 修改 `.env` 中 `OPENCLAW_GATEWAY_PORT` / `OPENCLAW_BRIDGE_PORT`。

### 同机多开注意事项（2 开、3 开或更多）

- 推荐目录命名示例（同级目录）：
  - `E:\Workspace\openclaw-a`
  - `E:\Workspace\openclaw-b`
  - `E:\Workspace\openclaw-c`
  - 建议每个目录内都保留一份独立 `.env` 与 `openclaw/openclaw.json`。
- 推荐端口对应示例：
  - `openclaw-a`：`18789/18790`
  - `openclaw-b`：`18791/18792`
  - `openclaw-c`：`18793/18794`
- 每个实例使用**独立目录**运行，不要在 A 目录管理 B 实例。
- 每个实例使用**唯一端口对**：
  - 例如 A: `18789/18790`，B: `18791/18792`，C: `18793/18794`（按 `+2` 递增）。
- 每个实例使用**独立 token**（`OPENCLAW_GATEWAY_TOKEN` 不能复用）。
- 每个实例分别执行自己的 `setup/restart/stop`，避免跨目录操作。
- 访问地址按网关端口区分：
  - `http://127.0.0.1:<OPENCLAW_GATEWAY_PORT>`
- 快速查看本机所有实例与端口映射：
  - `docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"`
- 若出现“能连端口但页面异常/未授权”，优先检查：
  1. 是否访问了错误实例的端口；
  2. 当前目录与目标实例是否一致；
  3. token 是否与该实例 `.env` 一致。

</details>

## 许可

OpenClaw 上游见 [文档](https://docs.openclaw.ai/)。
