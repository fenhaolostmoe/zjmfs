#!/usr/bin/env bash
# ============================================================
# ZJMF Cloud · v3.9.22 离线安装脚本 (全仓库自包含)
# ============================================================
# 所有资源从本仓库拉取, 完全不依赖官方 mirror.cloud.idcsmart.com
# 防官方 CDN 下线或更新后 URL 变化
#
# 流程:
#   1. 从 Codeberg 拉 Go 源码 + manifest.json
#   2. sed 替换 endpoint IP + mirror host → 本地 HTTP server
#   3. 从 Codeberg raw 拉全量 21 个镜像文件到临时目录
#   4. 启动 python3 HTTP server 指向本地文件
#   5. go build 编译并运行安装程序
#   6. 安装完成后清理临时 server
#
# 用法:
#   wget https://codeberg.org/fenhaolost/zjmf/raw/main/install-v3.9.22-offline.sh \
#     -O install.sh && chmod +x install.sh && ./install.sh
#
# 可选参数:
#   ENDPOINT_HOST=your-endpoint.workers.dev   指定 Workers API
#   NO_KERNEL=1                                跳过内核检查
#   INSTALL_VERSION=3.9.22                    安装版本 (默认 3.9.22)
# ============================================================

set -euo pipefail

# ---------- 配置 ----------
REPO="fenhaolost/zjmf"
BRANCH="main"
RAW_BASE="https://codeberg.org/${REPO}/raw/${BRANCH}"
DEFAULT_ENDPOINT="zjmf-auth-api.fenhaolost.workers.dev"
ENDPOINT_HOST="${ENDPOINT_HOST:-$DEFAULT_ENDPOINT}"
INSTALL_VERSION="${INSTALL_VERSION:-3.9.22}"
MIRROR_HOST="mirror.cloud.idcsmart.com"
HARDCODED_IP="154.7.178.154"
LOCAL_HTTP_PORT=18080
NO_KERNEL="${NO_KERNEL:-0}"

# 解析额外参数 (透传给安装程序)
INSTALL_ARGS=()
for arg in "$@"; do
  case "$arg" in
    ENDPOINT_HOST=*) ENDPOINT_HOST="${arg#ENDPOINT_HOST=}" ;;
    INSTALL_VERSION=*) INSTALL_VERSION="${arg#INSTALL_VERSION=}" ;;
    NO_KERNEL=*) NO_KERNEL="${arg#NO_KERNEL=}" ;;
    *) INSTALL_ARGS+=("$arg") ;;
  esac
done

# ---------- 工具函数 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[i]${NC} $*"; }
ok()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[x]${NC} $*"; }

echo ""
echo "============================================================"
echo "  ZJMF Cloud · v3.9.22 离线安装"
echo "  Endpoint  : http://${ENDPOINT_HOST}/app/api/"
echo "  Mirror    : 本地 HTTP (不连官方 CDN)"
echo "  Version   : ${INSTALL_VERSION}"
echo "============================================================"
echo ""

ORIG_DIR="$(pwd)"
TMPDIR="$(mktemp -d)"
LOCAL_MIRROR="$TMPDIR/mirror"
HTTP_LOG="$TMPDIR/http.log"
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# ---------- Step 1: 拉源码 + manifest ----------
info "Step 1/6: 从 Codeberg 拉源码 ..."

SOURCE_GO="$TMPDIR/install-zjmf-cloud_new.go"
MANIFEST="$TMPDIR/manifest.json"

if ! wget -q "${RAW_BASE}/install-zjmf-cloud_new.go" -O "$SOURCE_GO"; then
  err "源码下载失败"
  exit 1
fi
if ! wget -q "${RAW_BASE}/backup/v3.9.22/manifest.json" -O "$MANIFEST"; then
  err "manifest.json 下载失败"
  exit 1
fi

ok "源码 $(wc -l < "$SOURCE_GO") 行"
ok "manifest: $(python3 -c "import json; d=json.load(open('$MANIFEST')); print(f'{d[\"total_files\"]} files, {d[\"total_size_mb\"]} MB')" 2>/dev/null || echo "?")"

# ---------- Step 2: 下载全量镜像文件 ----------
info "Step 2/6: 下载全量镜像文件 ..."

# 从 manifest.json 读文件列表并下载
python3 << PYEOF
import json, os, sys, urllib.request, hashlib

manifest_path = "$MANIFEST"
mirror_dir    = "$LOCAL_MIRROR"
raw_base      = "${RAW_BASE}/backup/v3.9.22/mirror"

with open(manifest_path) as f:
    d = json.load(f)

ok_count = 0; fail_count = 0
for file in d["files"]:
    path = file["path"]
    size = file["size"]
    md5_expected = file["md5"]
    dest = os.path.join(mirror_dir, path)
    url  = f"{raw_base}/{path}"

    os.makedirs(os.path.dirname(dest), exist_ok=True)

    # 已存在且 md5 匹配就跳过
    if os.path.exists(dest) and os.path.getsize(dest) == size:
        with open(dest, 'rb') as f:
            md5 = hashlib.md5(f.read()).hexdigest()
        if md5 == md5_expected:
            print(f"  ✅ skip (cached)  {path}")
            ok_count += 1
            continue

    print(f"  ↓ {path} ({size/1024/1024:.1f}MB) ... ", end="", flush=True)
    try:
        urllib.request.urlretrieve(url, dest)
        with open(dest, 'rb') as f:
            md5 = hashlib.md5(f.read()).hexdigest()
        if md5 == md5_expected:
            print(f"ok  md5={md5[:10]}...")
            ok_count += 1
        else:
            print(f"⚠️  md5 mismatch: {md5[:10]}... expected {md5_expected[:10]}...")
            fail_count += 1
    except Exception as e:
        print(f"❌ {e}")
        fail_count += 1

print(f"\n  下载完成: {ok_count}/{len(d['files'])} ok, {fail_count} fail")
sys.exit(0 if fail_count == 0 else 1)
PYEOF

# ---------- Step 3: sed 替换源码 ----------
info "Step 3/6: 替换源码中的镜像和 endpoint host ..."
LOCAL_BASE="http://127.0.0.1:${LOCAL_HTTP_PORT}"

# 3a: 替换 23 处 mirror.cloud.idcsmart.com → 本地 server
MIRROR_COUNT=$(grep -c "${MIRROR_HOST}" "$SOURCE_GO" || echo 0)
sed -i "s|${MIRROR_HOST}|127.0.0.1:${LOCAL_HTTP_PORT}|g" "$SOURCE_GO"
ok "mirror.cloud.idcsmart.com → 127.0.0.1:${LOCAL_HTTP_PORT} ($MIRROR_COUNT 处)"

# 3b: 替换 154.7.178.154 → ENDPOINT_HOST
IP_COUNT=$(grep -c "${HARDCODED_IP}" "$SOURCE_GO" || echo 0)
sed -i "s|${HARDCODED_IP}|${ENDPOINT_HOST}|g" "$SOURCE_GO"
ok "${HARDCODED_IP} → ${ENDPOINT_HOST} ($IP_COUNT 处)"

# 3c: 强制 DefaultRepo 使用 HTTP (源码里有 http:// 前缀, sed 只改 host)
# 确保所有拼接出来的 URL 指向本地
# (上一步已经全替换了, 验证一下)
echo -n "  mirror 残留: "; grep -c "${MIRROR_HOST}" "$SOURCE_GO" || echo 0
echo -n "  IP 残留:     "; grep -c "${HARDCODED_IP}" "$SOURCE_GO" || echo 0

# ---------- Step 4: 启动本地 HTTP server ----------
info "Step 4/6: 启动本地 HTTP server ..."

cd "$LOCAL_MIRROR"
# python3 http.server 默认会把请求路径中的 cloud/packages/... 映射到 mirror/cloud/packages/...
# 这正好是我们的目录结构!
python3 -m http.server "${LOCAL_HTTP_PORT}" > "$HTTP_LOG" 2>&1 &
SERVER_PID=$!
cd "$TMPDIR"

# 等 server 起来
for i in $(seq 1 10); do
  if curl -sI "http://127.0.0.1:${LOCAL_HTTP_PORT}/cloud/packages/c7/python2-packages.tar.gz" 2>/dev/null | grep -q "200 OK"; then
    ok "HTTP server on :${LOCAL_HTTP_PORT} (pid $SERVER_PID)"
    break
  fi
  sleep 0.5
done

# ---------- Step 5: Go 编译 ----------
info "Step 5/6: 编译安装程序 ..."

if ! command -v go &>/dev/null; then
  info "  → 安装 Go 1.20.11 ..."
  curl -sL "https://go.dev/dl/go1.20.11.linux-amd64.tar.gz" -o "$TMPDIR/go.tgz"
  rm -rf /usr/local/go && tar -C /usr/local -xzf "$TMPDIR/go.tgz"
fi
export PATH=$PATH:/usr/local/go/bin
ok "Go $(go version | awk '{print $3}')"

cat > go.mod << 'GOMOD'
module install-zjmf
go 1.20
require github.com/cavaliergopher/grab/v3 v3.0.1
GOMOD

info "  → go mod tidy ..."
go mod tidy 2>&1 | tail -2 || true

info "  → go build ..."
if ! CGO_ENABLED=1 go build -o install-zjmf-cloud_new.offline -trimpath \
  install-zjmf-cloud_new.go 2>&1 | tail -10; then
  err "Build failed!"; exit 1
fi
ok "Built: $(ls -lh install-zjmf-cloud_new.offline | awk '{print $5}')"

# 验证
echo -n "  二进制 mirror 残留: "; strings install-zjmf-cloud_new.offline 2>/dev/null | grep -c "${MIRROR_HOST}" || echo 0
echo -n "  二进制 IP 残留:     "; strings install-zjmf-cloud_new.offline 2>/dev/null | grep -c "${HARDCODED_IP}" || echo 0
echo -n "  二进制本地 host:    "; strings install-zjmf-cloud_new.offline 2>/dev/null | grep -c "127.0.0.1:${LOCAL_HTTP_PORT}" || echo 0
echo -n "  二进制 Workers:      "; strings install-zjmf-cloud_new.offline 2>/dev/null | grep -c "${ENDPOINT_HOST}" || echo 0

# ---------- Step 6: 运行 ----------
info "Step 6/6: 启动离线安装程序 ..."

cp install-zjmf-cloud_new.offline "$ORIG_DIR/"
chmod +x "$ORIG_DIR/install-zjmf-cloud_new.offline"
cd "$ORIG_DIR"

# 构建安装程序参数
FINAL_ARGS=()
if [ "$NO_KERNEL" = "1" ]; then
  FINAL_ARGS+=("-nokernel")
fi
FINAL_ARGS+=("-norepo")  # 不需要官方 repo
FINAL_ARGS+=("-version" "$INSTALL_VERSION")
FINAL_ARGS+=("${INSTALL_ARGS[@]}")

echo ""
echo "============================================================"
echo "  安装程序启动. 按提示操作即可."
echo "  (临时 HTTP server pid=$SERVER_PID 将在脚本退出后自动清理)"
echo "============================================================"
echo ""

"$ORIG_DIR/install-zjmf-cloud_new.offline" "${FINAL_ARGS[@]}"

echo ""
echo "============================================================"
echo "  安装程序退出. 正在清理临时文件 ..."
echo "============================================================"
