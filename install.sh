#!/usr/bin/env bash
# ============================================================
# ZJMF Cloud 一键安装脚本 (FenhaoLost/zjmf 版)
# ============================================================
# Downloads source, replaces hardcoded HTTP endpoint host, builds and runs
#
# 用法:
#   wget https://raw.githubusercontent.com/FenhaoLost/zjmf/main/install.sh \
#     -O install.sh && chmod +x install.sh && ./install.sh
#
# 自定义 Workers:
#   WORKERS_HOST=your-endpoint.workers.dev ./install.sh
#
# 透传安装参数:
#   ./install.sh -nokernel -norepo -l -license YOUR_LICENSE
# ============================================================

set -euo pipefail

SOURCE_REPO="FenhaoLost/zjmf"
DEFAULT_ENDPOINT_HOST="zjmf-auth-api.fenhaolost.workers.dev"
ENDPOINT_HOST="${WORKERS_HOST:-$DEFAULT_ENDPOINT_HOST}"
ORIGINAL_IP="154.7.178.154"

INSTALL_ARGS=()
for arg in "$@"; do
  case "$arg" in
    WORKERS_HOST=*) ENDPOINT_HOST="${arg#WORKERS_HOST=}" ;;
    *) INSTALL_ARGS+=("$arg") ;;
  esac
done

# 彩色
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[i]${NC} $*"; }
ok()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[x]${NC} $*"; }

echo ""
echo "============================================================"
echo "  ZJMF Cloud 一键安装 (FenhaoLost/zjmf)"
echo "  endpoint: http://${ENDPOINT_HOST}/app/api/"
echo "============================================================"
echo ""

# 存原目录
ORIG_DIR="$(pwd)"
TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" EXIT

# Step 1: 下载源码
info "Step 1/4: 下载 Go 安装程序源码 ..."
SOURCE_GO="$TMPDIR/install-zjmf-cloud_new.go"
wget -q --show-progress \
  "https://raw.githubusercontent.com/${SOURCE_REPO}/main/install-zjmf-cloud_new.go" \
  -O "$SOURCE_GO" || { err "源码下载失败！"; exit 1; }
ok "$(wc -l < "$SOURCE_GO") 行"

# Step 2: sed
info "Step 2/4: ${ORIGINAL_IP} → ${ENDPOINT_HOST} ..."
if grep -q "${ORIGINAL_IP}" "$SOURCE_GO"; then
  sed -i "s|${ORIGINAL_IP}|${ENDPOINT_HOST}|g" "$SOURCE_GO"
  ok "replaces hardcoded host完成"
else
  ok "源码已是 Patch 版本 ✅"
fi
REMAINING=$(grep -c "${ORIGINAL_IP}" "$SOURCE_GO" || true)
[ "$REMAINING" = "0" ] && ok "原 IP 零残留 ✅" || warn "残留 ${REMAINING} 处"

# Step 3: 编译
info "Step 3/4: 编译 Go 安装程序 ..."
if ! command -v go &>/dev/null; then
  info "  → 下载 Go 1.20.11 ..."
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
  err "编译失败！"
  exit 1
fi

ok "编译完成: $(ls -lh install-zjmf-cloud_new.rebuilt | awk '{print $5}')"
HOST_COUNT=$(strings install-zjmf-cloud_new.rebuilt | grep -c "${ENDPOINT_HOST}" || true)
IP_COUNT=$(strings install-zjmf-cloud_new.rebuilt | grep -c "${ORIGINAL_IP}" || true)
ok "Endpoint check: ${ENDPOINT_HOST} × ${HOST_COUNT} / ${ORIGINAL_IP} × ${IP_COUNT}"

# Step 4: 运行
info "Step 4/4: 启动安装 ..."
cp install-zjmf-cloud_new.rebuilt "$ORIG_DIR/"
chmod +x "$ORIG_DIR/install-zjmf-cloud_new.rebuilt"
cd "$ORIG_DIR"

echo ""
echo "============================================================"
echo "  Installer ID: any 32-char uppercase hex string works"
echo "  例: $(python3 -c "import hashlib,time; print(hashlib.md5(str(time.time()).encode()).hexdigest().upper())")"
echo "============================================================"
echo ""

./install-zjmf-cloud_new.rebuilt "${INSTALL_ARGS[@]}"
