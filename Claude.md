# OpenClaw Docker 工具包 — 离线优先协作备忘

本文档用于 AI/协作者快速对齐仓库原则。  
目标只有一个：**尽量离线安装 Docker OpenClaw 环境**。  
用户文档以 `README.md` 为准；本文件强调“决策与约束”。

---

## 1) 项目宗旨（必须优先满足）

### 离线优先

- 默认流程：`docker load` + `docker compose up -d`。
- 不依赖在线 `docker pull` 作为安装前提。
- 适配弱网、内网分发、可复用镜像包场景。

### 稳定优先

- 保持与上游 Compose 行为兼容（`docker-compose.yml` 基本对齐上游）。
- 脚本入口统一，减少手工步骤与环境差异。
- 关键配置自动校正（端口、token 同步、模式识别）。

### 数据安全优先

- `openclaw/`、`workspace/` 为持久数据目录。
- 常规停止（`docker compose down`）不应删除用户数据。

---

## 2) 操作优先级（协作时请遵守）

1. **先保离线可安装**：任何改动不能破坏离线镜像安装链路。
2. **再保可启动可探活**：`/healthz` 能通、Control UI 可访问。
3. **再谈功能增强**：with-python、TUI、OSS 上传等属于增强项。
4. **最后做美化**：排版、提示文案不应影响主流程。

---

## 3) 关键文件与事实

| 路径 | 作用 | 硬性约束 |
|---|---|---|
| `openclaw/openclaw.json` | 主配置文件 | 必须存在；不能仅有 `openclaw.json5` 文件名 |
| `.env` | 镜像名、端口、token、API Key | 不提交仓库（已忽略） |
| `defaults/openclaw.default.json` | 首次安装的配置模板 | 安装时复制成 `openclaw/openclaw.json` |
| `images/openclaw.tar.gz` / `openclaw.tar.gz` | 离线镜像包 | 安装脚本默认从这两处查找 |
| `workspace/` | 挂载工作区 | Compose 挂载的是根目录 `workspace/` |

---

## 4) 网关配置红线

- `gateway.mode` 必须是 `"local"`（Docker 场景）。
- 根级 `providers` 无效；应使用 `models.providers`。
- `OPENCLAW_GATEWAY_TOKEN` 使用“反向同步”：
  - 从 `openclaw/openclaw.json` 读取 `gateway.auth.token`
  - 回写 `.env` 的 `OPENCLAW_GATEWAY_TOKEN`
  - 避免改写 `openclaw.json` 排版
- `gateway.controlUi.allowedOrigins` 建议包含：
  - `http://127.0.0.1:18789`
  - `http://localhost:18789`

---

## 5) 脚本入口映射（统一走这些）

| 入口 | 用途 |
|---|---|
| `setup-openclaw.bat` | 安装（默认 with-python，倒计时可切换） |
| `restart-openclaw.bat` | 重启（自动判断模式） |
| `stop-openclaw.bat` | 停止（自动判断模式） |
| `tui-openclaw.bat` / `tui-openclaw.ps1` | 进入 TUI（默认 `--deliver`） |

内部实现：

- `scripts/tools/setup-openclaw.ps1`
- `scripts/tools/restart-openclaw.ps1`
- `scripts/tools/stop-openclaw.ps1`
- `scripts/openclaw-ports.ps1`
- `scripts/openclaw-token.ps1`

---

## 6) 常见故障速查（离线部署高频）

| 现象 | 首查点 | 快速处理 |
|---|---|---|
| `Missing config` / 网关不起 | 是否只有 `openclaw.json5` | 确保存在 `openclaw/openclaw.json` |
| `Unrecognized key: "providers"` | 配置层级错误 | 改到 `models.providers` |
| 浏览器白屏 / healthz 不通 | 端口与 `gateway.mode` | 先测 `curl.exe -fsS http://127.0.0.1:18789/healthz` |
| PowerShell 下 `curl -fsS` 报错 | 别名冲突 | 用 `curl.exe` 或 `irm` |
| `.ps1` 出现中文相关假语法错误 | 编码问题（PS 5.1） | 脚本文案尽量英文；中文请 UTF-8 BOM；或用 PS7 |
| with-python 启动 unhealthy | 入口脚本/权限/LF 行尾 | 检查 `entrypoint-python.sh`、volume 权限、LF |

---

## 7) CI 与离线包分发（可选）

- 镜像导出：`.github/workflows/export-image.yml`
- 可选上传 OSS（用于内网分发）
- 关键注意：
  - `ossutil` 固定使用可用版本（当前为 v1.7.18）
  - 解压后可执行文件路径可能在子目录，需定位后再执行

---

## 8) 验收最小清单（改动后自检）

- 能从离线包完成安装（不依赖在线 pull）。
- `docker compose up -d` 后网关可探活。
- `README.md` 的新手快速上手路径仍然可用。
- 未破坏 `setup/restart/stop` 三个统一入口。

---

## 9) 参考链接

- OpenClaw Docker：<https://docs.openclaw.ai/install/docker>
- 上游 compose：<https://github.com/openclaw/openclaw/blob/main/docker-compose.yml>

---

若与实现细节冲突，以 `README.md`、`docker-compose.yml` 与脚本实际行为为准。
