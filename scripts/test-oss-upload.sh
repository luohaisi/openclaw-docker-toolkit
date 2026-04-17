#!/usr/bin/env bash
# 本地验证 OSS 上传（Linux / macOS / WSL / Git Bash），逻辑与 CI 一致（ossutil v1.7.18 linux-amd64）
#
# 1) 复制 scripts/oss-local.env.example 为 scripts/oss-local.env，填写 OSS_ENDPOINT、OSS_BUCKET
# 2) 仅导出密钥：export OSS_ACCESS_KEY_ID=... OSS_ACCESS_KEY_SECRET=...
# 3) bash scripts/test-oss-upload.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LOCAL_ENV="$ROOT/scripts/oss-local.env"
if [ ! -f "$LOCAL_ENV" ]; then
  echo "未找到 scripts/oss-local.env，请复制 scripts/oss-local.env.example 后填写 OSS_ENDPOINT 与 OSS_BUCKET。" >&2
  exit 1
fi

while IFS= read -r line || [ -n "${line:-}" ]; do
  line="${line#"${line%%[![:space:]]*}"}"
  case "$line" in ''|'#'*) continue ;;
  esac
  key="${line%%=*}"
  val="${line#*=}"
  key="${key%"${key##*[![:space:]]}"}"
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%${val##*[![:space:]]}}"
  case "$key" in
    OSS_ENDPOINT) export OSS_ENDPOINT="$val" ;;
    OSS_BUCKET) export OSS_BUCKET="$val" ;;
  esac
done < "$LOCAL_ENV"

if [ -z "${OSS_ENDPOINT:-}" ] || [ -z "${OSS_BUCKET:-}" ]; then
  echo "请在 scripts/oss-local.env 中填写 OSS_ENDPOINT 与 OSS_BUCKET。" >&2
  exit 1
fi

if [ -z "${OSS_ACCESS_KEY_ID:-}" ] || [ -z "${OSS_ACCESS_KEY_SECRET:-}" ]; then
  echo "请设置环境变量 OSS_ACCESS_KEY_ID 与 OSS_ACCESS_KEY_SECRET（勿写入 oss-local.env）。" >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

OSSUTIL_VER="v1.7.18"
URL="https://github.com/aliyun/ossutil/releases/download/${OSSUTIL_VER}/ossutil-${OSSUTIL_VER}-linux-amd64.zip"
echo "下载 ossutil: $URL"
curl -fsSL --retry 5 --retry-delay 2 "$URL" -o "$TMP/ossutil.zip"
unzip -o -q "$TMP/ossutil.zip" -d "$TMP/extract"
OSSUTIL_BIN="$(find "$TMP/extract" -name ossutil64 -type f | head -1)"
if [ -z "$OSSUTIL_BIN" ]; then
  echo "解压后未找到 ossutil64" >&2
  exit 1
fi
chmod +x "$OSSUTIL_BIN"

TEST_FILE="$ROOT/scripts/.oss-test-upload.txt"
printf 'openclaw-docker-toolkit oss test %s\n' "$(date +"%Y-%m-%dT%H:%M:%S%z")" >"$TEST_FILE"
OBJECT_KEY="docker-images/oss-connection-test.txt"

"$OSSUTIL_BIN" config -e "$OSS_ENDPOINT" -i "$OSS_ACCESS_KEY_ID" -k "$OSS_ACCESS_KEY_SECRET"
"$OSSUTIL_BIN" cp "$TEST_FILE" "oss://${OSS_BUCKET}/${OBJECT_KEY}"
echo "上传成功: oss://${OSS_BUCKET}/${OBJECT_KEY}"
