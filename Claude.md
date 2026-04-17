# OpenClaw Docker 工具包 — 协作备忘（Claude / AI 速览）

本文档提炼本仓库的**关键事实**与**已踩坑及对策**，便于延续上下文。详细步骤以 `README.md` 为准。

---

## 1. 项目是什么

- 用 **Docker Compose** 在本地跑 [OpenClaw](https://github.com/openclaw/openclaw) **Gateway**，`docker-compose.yml` 对齐上游（`openclaw-gateway` + `openclaw-cli`、`network_mode: service:openclaw-gateway`、健康检查）。
- **本仓库刻意不走在线 `docker pull`**：安装脚本只做 `docker load` 离线包 + `docker compose up -d`，适合网络差或内网分发。
- **镜像来源**：自行在 GitHub Actions（`.github/workflows/export-image.yml`）导出并可选上传阿里云 OSS；镜像名/tag 与 workflow 输入一致（如 `ghcr.io/openclaw/openclaw:2026.x.x-slim`）。

---

## 2. 关键路径与约定

| 项 | 说明 |
|----|------|
| 离线包位置 | `images/openclaw.tar.gz` 或根目录 `openclaw.tar.gz`；也可用 `setup-openclaw.ps1 -ImageArchive "路径"` |
| **主配置** | 必须是 **`openclaw/openclaw.json`**（映射到容器内 `~/.openclaw/openclaw.json`）。**不能**只放 `openclaw.json5` 而不提供 `openclaw.json`，否则网关认为无配置。 |
| `defaults/openclaw.default.json` | 首次安装且不存在 `openclaw.json` 时，由 `setup-openclaw.ps1` **复制**为 `openclaw/openclaw.json`；不是运行时读取的别名文件。 |
| `.env` | `OPENCLAW_IMAGE`、`OPENCLAW_GATEWAY_TOKEN`、端口、API Key 等；**勿提交**（已 `.gitignore`）。 |
| 数据 | `openclaw/`、`workspace/` 绑定挂载；`docker compose down` **默认不删** 这些目录。 |

---

## 3. 网关配置（必须满足当前 OpenClaw schema）

- **`gateway.mode`：必须为 `"local"`**（Docker 场景），否则日志反复：`Missing config. Run openclaw setup or set gateway.mode=local`。
- **根级 `providers`：无效**。自定义 OpenAI 兼容源、OpenRouter 等应放在 **`models.providers`**（并可配 `agents.defaults.model.primary`）；见仓库内 `openclaw/openclaw.json` 示例。
- **Control UI / 浏览器**：建议在 `gateway.controlUi.allowedOrigins` 中包含 `http://127.0.0.1:18789` 与 `http://localhost:18789`（与[官方 Docker 手动流程](https://docs.openclaw.ai/install/docker)一致）。
- **`OPENCLAW_GATEWAY_TOKEN`**：必须作为**唯一真源**；`openclaw.json` 里 **`gateway.auth.token` 应为 `${OPENCLAW_GATEWAY_TOKEN}`**（勿在 JSON 里再写另一串硬编码，否则网页显示 Token 无效）。首次安装脚本可自动生成 Token；Control UI 填与 `.env` 相同。
- **双份 workspace**：Compose 只挂载**仓库根目录的 `workspace/`**。若误存在 **`openclaw/workspace/`**，一般不会挂载进容器，易造成两套状态混淆；保留根目录 `workspace/`，多余目录可备份后删除。

---

## 4. 脚本一览

| 脚本 | 作用 |
|------|------|
| `setup-openclaw.ps1` / `.bat` | `docker load` → 创建目录/模板 → 补全 `.env` Token（若缺）→ `docker compose up -d`；启动前可按 `.env` 检测 **18789** 是否可能被占用并提示（含 WSL） |
| `stop-openclaw.ps1` / `.bat` | `docker compose down`；可选 `-RemoveVolumes` |
| `tui-openclaw.ps1` / `.bat` | `docker compose run ... openclaw-cli tui --deliver`（默认 **delivery**，否则常见仅 `HEARTBEAT_OK`）；见 [TUI 文档](https://docs.openclaw.ai/web/tui)「Sending + delivery」 |

---

## 5. CI / OSS（export-image）

- 使用 **ossutil** 的 **v1.7.18**（固定版本）：v1.7.19 在 GitHub Release 上 linux-amd64 zip 曾缺失/404。
- 解压 zip 后 **`ossutil64` 不一定在解压根目录**：Workflow 用 `find` 定位 `ossutil64` 或 `ossutil` 再 `chmod +x`。
- Actions Secrets：`OSS_ACCESS_KEY_ID`、`OSS_ACCESS_KEY_SECRET`、`OSS_ENDPOINT`、`OSS_BUCKET`。

---

## 6. 已遇到问题与精确对策

| 现象 | 原因 | 对策 |
|------|------|------|
| `chmod: cannot access 'ossutil64'`（CI） | ossutil zip 解压后二进制在子目录 | 已用子目录解压 + `find` 定位可执行文件（见 `export-image.yml`） |
| `Missing config` / 网关不起 | 仅有 **`openclaw.json5`** 文件名，网关只认 **`openclaw.json`** | 使用 **`openclaw/openclaw.json`** 作为主文件（内容可为 JSON5 语法） |
| `Unrecognized key: "providers"` | OpenClaw 新版本 schema 不收根级 `providers` | 改为 **`models.providers`** + 必要时的 `agents.defaults` |
| 浏览器白屏 / 健康检查不通 | 配置未生效或未完成启动 | 确认 `gateway.mode`、`controlUi.allowedOrigins`；用 `curl.exe` 测 `/healthz`（见下） |
| PowerShell 里 `curl -fsS` 报错 | **`curl` 是 `Invoke-WebRequest` 的别名** | 使用 **`curl.exe -fsS`** 或 **`irm`** |
| `curl: (7) Could not connect` | 容器在重启循环或未监听 | 先修配置再 `docker compose up -d --force-recreate`；看 `docker compose logs openclaw-gateway` |
| `stop-openclaw.ps1` 字符串未闭合、乱码 | **UTF-8 无 BOM** 时 PowerShell 5.1 误读中文 | **`stop-openclaw.ps1` 已改为英文输出**；若其他 `.ps1` 需中文，建议 **UTF-8 带 BOM** 保存 |
| 本机 Windows Docker 与 WSL 各跑一套 | 同端口 **18789** 冲突 | 停其一或改 `.env` 的 `OPENCLAW_GATEWAY_PORT`（并保证 `openclaw.json` 中网关相关一致） |
| `docker compose pull` 很慢 | 预期行为 | 本仓库以离线 `docker load` 为主，避免长链路拉取 |

---

## 7. 健康检查与 TUI

- 探活：`curl.exe -fsS http://127.0.0.1:18789/healthz`（端口以 `.env` 为准）。
- TUI：`docker compose run --rm -it openclaw-cli tui`

---

## 8. 外部文档

- OpenClaw Docker：<https://docs.openclaw.ai/install/docker>  
- 上游 compose：<https://github.com/openclaw/openclaw/blob/main/docker-compose.yml>

---

*若修改行为与本文冲突，以仓库内 `README.md`、`docker-compose.yml` 与脚本实行为准。*
