#!/usr/bin/env bash
# ============================================================
# ZJMF Cloud · v3.9.22 备份源安装脚本
# ============================================================
# 所有资源均来自自建备份, 不依赖官方 mirror.cloud.idcsmart.com:
#   源码   → GitHub  fenhaolostmoe/zjmfs
#   镜像包 → Codeberg LFS  /media/branch/main/...  (大文件走 LFS)
#
# 原理: 直接把源码里的官方 mirror URL 改写成 Codeberg 备份 URL,
#       然后 go build 出完整安装程序 (无需先把 1.2GB 下到本地)
#
# 用法:
#   wget https://raw.githubusercontent.com/fenhaolostmoe/zjmfs/main/install-from-backup.sh \
#     -O install.sh && chmod +x install.sh && ./install.sh
#
# 自定义 Workers:
#   WORKERS_HOST=your-auth.workers.dev ./install.sh
#
# 透传安装参数:
#   ./install.sh -nokernel -norepo -l
# ============================================================

set -euo pipefail

GITHUB_REPO="fenhaolostmoe/zjmfs"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
CODEBERG_MEDIA="https://codeberg.org/fenhaolost/zjmf/media/branch/main"
MIRROR_MEDIA="${CODEBERG_MEDIA}/backup/v3.9.22/mirror"

ORIGINAL_IP="154.7.178.154"
ORIGINAL_MIRROR="http://mirror.cloud.idcsmart.com"
DEFAULT_AUTH_HOST="zjmf-auth-api.fenhaolost.workers.dev"
AUTH_HOST="${WORKERS_HOST:-$DEFAULT_AUTH_HOST}"

INSTALL_ARGS=()
for arg in "$@"; do
  case "$arg" in
    WORKERS_HOST=*) AUTH_HOST="${arg#WORKERS_HOST=}" ;;
    *) INSTALL_ARGS+=("$arg") ;;
  esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[i]${NC} $*"; }
ok()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[x]${NC} $*"; }

echo ""
echo "============================================================"
echo "  ZJMF Cloud v3.9.22 · 备份源安装"
echo "  源码   : GitHub ${GITHUB_REPO}"
echo "  镜像包 : Codeberg LFS (/media/branch/main)"
echo "  授权API: https://${AUTH_HOST}/app/api/"
echo "============================================================"
echo ""

ORIG_DIR="$(pwd)"
TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" EXIT

# ========== Step 1: manifest.json (清单 + md5) ==========
info "Step 1/5: 下载 manifest.json ..."
MANIFEST="$TMPDIR/manifest.json"
wget -q --show-progress \
  "${CODEBERG_MEDIA}/backup/v3.9.22/manifest.json" \
  -O "$MANIFEST" || { err "manifest.json 下载失败 (Codeberg /media 端点)"; exit 1; }

TOTAL=$(python3 -c "
import json
m=json.load(open('$MANIFEST'))
print(len(m['files']), m.get('total_size_mb', sum(f['size'] for f in m['files'])//1024//1024))
")
CNT=$(echo "$TOTAL" | awk '{print $1}')
SZ=$(echo "$TOTAL" | awk '{print $2}')
ok "manifest.json: ${CNT} 文件, 合计 ${SZ}MB"

# ========== Step 2: Go 源码 ==========
info "Step 2/5: 下载 Go 安装程序源码 ..."
SOURCE_GO="$TMPDIR/install-zjmf-cloud_new.go"
wget -q \
  "${GITHUB_RAW}/install-zjmf-cloud_new.go" \
  -O "$SOURCE_GO" || { err "源码下载失败 (GitHub)"; exit 1; }
ok "$(wc -l < "$SOURCE_GO") 行"

# ========== Step 3: URL 改写 ==========
info "Step 3/5: 改写源码内的端点 URL ..."

# 3a. 授权验证 → Workers (必须先于 mirror 改写, 否则会被一起改掉)
LIC_COUNT=$(grep -c "${ORIGINAL_MIRROR}/cloud/license/verify" "$SOURCE_GO" || echo 0)
sed -i "s|${ORIGINAL_MIRROR}/cloud/license/verify|https://${AUTH_HOST}/app/api/auth|g" "$SOURCE_GO"
ok "授权验证 URL → Workers (${LIC_COUNT} 处)"

# 3b. 硬编码 IP → Workers
IP_COUNT=$(grep -c "${ORIGINAL_IP}" "$SOURCE_GO" || echo 0)
sed -i "s|http://${ORIGINAL_IP}|https://${AUTH_HOST}|g" "$SOURCE_GO"
ok "硬编码 IP ${ORIGINAL_IP} → https://${AUTH_HOST} (${IP_COUNT} 处)"

# 3c. 官方 mirror → Codeberg LFS (一次性覆盖全部 23 处, 含 %s 版本模板)
MIR_COUNT=$(grep -c "http://${ORIGINAL_MIRROR#http://}" "$SOURCE_GO" || echo 0)
sed -i "s|${ORIGINAL_MIRROR}|${MIRROR_MEDIA}|g" "$SOURCE_GO"
ok "官方 mirror → ${MIRROR_MEDIA} (${MIR_COUNT} 处)"

echo ""
echo -n "  残留官方 mirror URL: "; grep -c 'mirror\.cloud\.idcsmart\.com' "$SOURCE_GO" || true
echo -n "  残留原 IP:           "; grep -c "${ORIGINAL_IP}" "$SOURCE_GO" || true
echo -n "  Codeberg 备份 URL:   "; grep -c 'codeberg.org/fenhaolost/zjmf/media' "$SOURCE_GO" || true
echo -n "  Workers 授权 URL:    "; grep -c "${AUTH_HOST}" "$SOURCE_GO" || true

# ========== Step 4: Go build ==========
info "Step 4/5: 编译 Go 安装程序 ..."

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
# CGO_ENABLED=0 → 静态二进制, 目标机无需 gcc
if ! CGO_ENABLED=0 go build -o install-zjmf-cloud_new.patched -trimpath \
  install-zjmf-cloud_new.go 2>&1 | tail -15; then
  err "编译失败！"
  exit 1
fi
ok "编译完成: $(ls -lh install-zjmf-cloud_new.patched | awk '{print $5}')"

# ========== Step 5: 运行 ==========
info "Step 5/5: 启动安装 (镜像包从 Codeberg 备份下载) ..."
cp install-zjmf-cloud_new.patched "$ORIG_DIR/"
chmod +x "$ORIG_DIR/install-zjmf-cloud_new.patched"
cd "$ORIG_DIR"

echo ""
echo "============================================================"
echo "  安装即将开始！"
echo "  🔑 授权码 (License): 随便填一个 32 位大写 MD5 即可"
echo "     例: $(python3 -c "import hashlib,time; print(hashlib.md5(str(time.time()).encode()).hexdigest().upper())" 2>/dev/null || echo "AAAA...")"
echo ""
echo "  📦 镜像包来源: Codeberg LFS (/media/branch/main)"
echo "  🔐 授权验证源: https://${AUTH_HOST}"
echo ""
echo "  💾 备份完整性: md5 与 mirror.cloud.idcsmart.com 一致 (见 manifest.json)"
echo "============================================================"
echo ""

./install-zjmf-cloud_new.patched "${INSTALL_ARGS[@]}"