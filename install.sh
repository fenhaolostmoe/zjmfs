#!/usr/bin/env bash
# ============================================================
# ZJMF Cloud 安装脚本 · 标准版 (v3.9.22)
# ============================================================
# 流程：
#   1. 从 Codeberg 拉 install-zjmf-cloud_new.go (安装程序源码)
#   2. sed 替换硬编码的 endpoint host → ENDPOINT_HOST
#   3. go build 编译
#   4. 运行安装程序 (镜像包从官方 mirror.cloud.idcsmart.com 拉)
#
# 用法:
#   wget https://codeberg.org/fenhaolost/zjmf/raw/main/install.sh \
#     -O install.sh && chmod +x install.sh && ./install.sh
#
# 自定义 Workers endpoint:
#   ENDPOINT_HOST=your-endpoint.workers.dev ./install.sh
#
# 透传安装程序参数:
#   ./install.sh -nokernel -norepo -l
# ============================================================

set -euo pipefail

# ---------- 可配置项 ----------
REPO="fenhaolost/zjmf"                # Codeberg 仓库
BRANCH="main"                          # 分支
DEFAULT_ENDPOINT="zjmf-auth-api.fenhaolost.workers.dev"
ENDPOINT_HOST="${ENDPOINT_HOST:-$DEFAULT_ENDPOINT}"
HARDCODED_IP="154.7.178.154"           # Go 源码里的硬编码 IP
INSTALL_ARGS=()

for arg in "$@"; do
  case "$arg" in
    ENDPOINT_HOST=*) ENDPOINT_HOST="${arg#ENDPOINT_HOST=}" ;;
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
echo "  ZJMF Cloud · v3.9.22 安装脚本 (标准版)"
echo "  Endpoint : http://${ENDPOINT_HOST}/app/api/"
echo "  Mirror   : http://mirror.cloud.idcsmart.com"
echo "============================================================"
echo ""

ORIG_DIR="$(pwd)"
TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" EXIT

# ---------- Step 1: 拉源码 ----------
info "Step 1/4: 下载安装程序源码 ..."
SOURCE_GO="$TMPDIR/install-zjmf-cloud_new.go"
RAW_BASE="https://codeberg.org/${REPO}/raw/${BRANCH}"

if ! wget -q --show-progress "${RAW_BASE}/install-zjmf-cloud_new.go" -O "$SOURCE_GO"; then
  # fallback: 也试试 GitHub (如果恢复了)
  warn "Codeberg 拉取失败, 尝试 GitHub ..."
  wget -q --show-progress \
    "https://raw.githubusercontent.com/${REPO}/main/install-zjmf-cloud_new.go" \
    -O "$SOURCE_GO" || { err "源码下载失败!"; exit 1; }
fi
ok "$(wc -l < "$SOURCE_GO") 行"

# ---------- Step 2: 替换 endpoint ----------
info "Step 2/4: 替换 ${HARDCODED_IP} → ${ENDPOINT_HOST} ..."
if grep -q "${HARDCODED_IP}" "$SOURCE_GO"; then
  sed -i "s|${HARDCODED_IP}|${ENDPOINT_HOST}|g" "$SOURCE_GO"
  ok "sed done"
else
  ok "源码已是 patch 版本"
fi
echo -n "  原 IP 残留: "; grep -c "${HARDCODED_IP}" "$SOURCE_GO" || echo 0
echo -n "  新 endpoint 匹配: "; grep -c "${ENDPOINT_HOST}" "$SOURCE_GO" || echo 0

# ---------- Step 3: 编译 ----------
info "Step 3/4: 编译 ..."
if ! command -v go &>/dev/null; then
  info "  → 安装 Go 1.20.11 ..."
  curl -sL "https://go.dev/dl/go1.20.11.linux-amd64.tar.gz" -o "$TMPDIR/go.tgz"
  rm -rf /usr/local/go && tar -C /usr/local -xzf "$TMPDIR/go.tgz"
fi
export PATH=$PATH:/usr/local/go/bin
ok "Go $(go version | awk '{print $3}')"

cd "$TMPDIR"
cat > go.mod << 'GOMOD'
module install-zjmf
go 1.20
require github.com/cavaliergopher/grab/v3 v3.0.1
GOMOD

info "  → go mod tidy ..."
go mod tidy 2>&1 | tail -3 || true

info "  → go build ..."
if ! CGO_ENABLED=1 go build -o install-zjmf-cloud_new.rebuilt -trimpath \
  install-zjmf-cloud_new.go 2>&1 | tail -15; then
  err "Build failed!"; exit 1
fi
ok "Built: $(ls -lh install-zjmf-cloud_new.rebuilt | awk '{print $5}')"

# 验证编译后的二进制
HOST_COUNT=$(strings install-zjmf-cloud_new.rebuilt 2>/dev/null | grep -c "${ENDPOINT_HOST}" || true)
IP_COUNT=$(strings install-zjmf-cloud_new.rebuilt 2>/dev/null | grep -c "${HARDCODED_IP}" || true)
ok "Endpoint check: ${ENDPOINT_HOST} × ${HOST_COUNT} / ${HARDCODED_IP} × ${IP_COUNT}"

# ---------- Step 4: 运行 ----------
info "Step 4/4: 启动安装程序 ..."
cp install-zjmf-cloud_new.rebuilt "$ORIG_DIR/"
chmod +x "$ORIG_DIR/install-zjmf-cloud_new.rebuilt"
cd "$ORIG_DIR"

echo ""
echo "============================================================"
echo "  安装程序启动. 按提示操作即可."
echo "============================================================"
echo ""

./install-zjmf-cloud_new.rebuilt "${INSTALL_ARGS[@]}"
