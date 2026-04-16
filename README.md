# OpenClaw Docker 部署工具包

本仓库在 Docker 中运行 [OpenClaw](https://github.com/openclaw/openclaw) Gateway，**`docker-compose.yml` 与官方仓库结构对齐**（`openclaw-gateway` + `openclaw-cli`、健康检查、双卷挂载）。官方说明见：[Docker（中文）](https://docs.openclaw.ai/zh-CN/install/docker)、上游 [`docker-compose.yml`](https://github.com/openclaw/openclaw/blob/main/docker-compose.yml)、预构建镜像 [GHCR `openclaw`](https://github.com/openclaw/openclaw/pkgs/container/openclaw)。

## 与官方一致的要点

- **镜像**：默认 `OPENCLAW_IMAGE=ghcr.io/openclaw/openclaw:latest`（可在 `.env` 中改为固定版本或 `*-slim` 等标签）。
- **数据目录**：`OPENCLAW_CONFIG_DIR` → 容器内 `/home/node/.openclaw`（含 `openclaw.json5`、智能体状态等）；`OPENCLAW_WORKSPACE_DIR` → `/home/node/.openclaw/workspace`。
- **Gateway 启动参数**：`gateway --bind ${OPENCLAW_GATEWAY_BIND:-lan} --port 18789`。文档要求 **`gateway.bind` 使用 `lan` / `loopback` 等模式**，不要写成 `0.0.0.0` 这类主机别名；本仓库的 `openclaw/openclaw.json5` 中已使用 `bind: "lan"`。
- **CLI**：`openclaw-cli` 使用 `network_mode: service:openclaw-gateway`，日常通过 `docker compose run --rm openclaw-cli …` 执行子命令（与官方一致）。
- **健康检查**：`GET /healthz`、`/readyz`（参见官方文档）。

## 第三方教程（补充）

图文步骤可参考：[OpenClaw Docker 部署完整教程](https://oepnclaw.com/tutorials/openclaw-docker-deploy.html)。其中旧式单容器、`./config` 挂载到 `/root/.config/openclaw` 的写法**已被本仓库弃用**，请以**官方文档 + 本仓库目录**为准。

---

## 本仓库目录说明

| 路径 | 说明 |
|------|------|
| `docker-compose.yml` | 官方风格：`openclaw-gateway`、`openclaw-cli`、健康检查、端口 18789/18790 |
| `openclaw/` | 状态与主配置（对应容器内 `~/.openclaw`，主文件为 `openclaw.json5`） |
| `workspace/` | 工作区（挂载到 `~/.openclaw/workspace`） |
| `.env` | `OPENCLAW_*`、模型 API 等（**已加入 `.gitignore`，勿提交**） |
| `setup-openclaw.bat` / `setup-openclaw.ps1` | Windows 一键创建目录、模板与 `docker compose up -d` |

---

## 本地执行方式

### 方式一：Windows 一键脚本（推荐）

1. 安装并**启动 Docker Desktop**。
2. 进入本仓库根目录，**双击** `setup-openclaw.bat`，或执行：

   ```powershell
   cd E:\Workspace\openclaw-docker-toolkit
   powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-openclaw.ps1
   ```

3. 编辑 **`.env`**：至少配置模型相关变量（与 `openclaw/openclaw.json5` 中 `${变量名}` 一致）；按需设置 **`OPENCLAW_GATEWAY_TOKEN`**（Control UI 鉴权，官方 setup 也会写入）。

跳过拉取镜像仅启动：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup-openclaw.ps1 -SkipPull
```

### 方式二：手动 Docker Compose

```powershell
docker compose pull
docker compose up -d
docker compose ps
```

---

## 常用命令

```powershell
# Gateway 日志
docker compose logs -f openclaw-gateway

# 官方推荐：CLI 一次性容器（与网关同网络）
docker compose run --rm openclaw-cli dashboard --no-open

# 存活探测
curl -fsS http://127.0.0.1:18789/healthz

# 停止（不删除卷数据）
docker compose down
```

浏览器打开 Control UI：**<http://127.0.0.1:18789/>**。

---

## 配置与备份

- 修改 **`openclaw/openclaw.json5`** 或 **`.env`** 后执行：`docker compose up -d`。
- 备份建议打包 **`openclaw/`、`workspace/`、`.env`**（注意密钥）。

---

## 故障排查简要

- **Unauthorized / 设备配对**：参见官方文档「故障排除」；可尝试 `docker compose run --rm openclaw-cli devices list` 等。
- **API 报错**：核对 `.env` 与 `openclaw.json5` 中的 `${...}` 变量名是否一致。
- **端口冲突**：修改 `.env` 中 `OPENCLAW_GATEWAY_PORT` / `OPENCLAW_BRIDGE_PORT`，并保证与 Gateway 配置一致。

---

## 许可与上游

OpenClaw 为开源项目，许可与更新见上游仓库与 [文档](https://docs.openclaw.ai/)。
