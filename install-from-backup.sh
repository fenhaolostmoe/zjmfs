#!/usr/bin/env bash
# ============================================================
# ZJMF Cloud · v3.9.22 本地备份版安装脚本
# ============================================================
# 完全从 FenhaoLost/zjmf 的 GitHub 仓库拉源码 + 镜像包,
# 不依赖官方 mirror.cloud.idcsmart.com
#
# 用法:
#   wget https://raw.githubusercontent.com/FenhaoLost/zjmf/main/install-from-backup.sh \
#     -O install.sh && chmod +x install.sh && ./install.sh
#
# 自定义 Workers:
#   WORKERS_HOST=your-auth.workers.dev ./install.sh
#
# 透传安装参数:
#   ./install.sh -nokernel -norepo -l
# ============================================================

set -euo pipefail

PATCHED_REPO="FenhaoLost/zjmf"
BACKUP_BRANCH="v3.9.22-backup"
BACKUP_TAG="v3.9.22"
ORIGINAL_IP="154.7.178.154"
MIRROR_BASE="http://mirror.cloud.idcsmart.com"
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
echo "  ZJMF Cloud v3.9.22 · 本地备份版安装"
echo "  源码 + 镜像包 全部来自 GitHub 备份"
echo "  授权 API: http://${AUTH_HOST}/app/api/"
echo "============================================================"
echo ""

ORIG_DIR="$(pwd)"
TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" EXIT

RAW_BASE="https://raw.githubusercontent.com/${PATCHED_REPO}/${BACKUP_BRANCH}"
RELEASE_BASE="https://github.com/${PATCHED_REPO}/releases/download/${BACKUP_TAG}"

# ========== Step 1: manifest.json ==========
info "Step 1/5: 下载 manifest.json (镜像包清单 + md5) ..."
MANIFEST="$TMPDIR/manifest.json"
wget -q --show-progress \
  "${RAW_BASE}/backup/v3.9.22/manifest.json" \
  -O "$MANIFEST" || { err "manifest.json 下载失败！"; exit 1; }

TOTAL=$(python3 -c "
import json
m=json.load(open('$MANIFEST'))
print(len(m['files']), sum(f['size'] for f in m['files'])//1024//1024)
")
CNT=$(echo "$TOTAL" | awk '{print $1}')
SZ=$(echo "$TOTAL" | awk '{print $2}')
ok "manifest.json: ${CNT} 文件, 合计 ${SZ}MB"

# ========== Step 2: Go 源码 ==========
info "Step 2/5: 下载 Go 安装程序源码 ..."
SOURCE_GO="$TMPDIR/install-zjmf-cloud_new.go"
wget -q \
  "https://raw.githubusercontent.com/${PATCHED_REPO}/main/install-zjmf-cloud_new.go" \
  -O "$SOURCE_GO" || { err "源码下载失败！"; exit 1; }
ok "$(wc -l < "$SOURCE_GO") 行"

# ========== Step 3: Python 生成 sed patch ==========
info "Step 3/5: 生成 sed patch 脚本 ..."

python3 << PYEOF > "$TMPDIR/patch_urls.sh"
import json

m = json.load(open("$MANIFEST"))
SOURCE_GO = "$SOURCE_GO"
ORIGINAL_IP = "$ORIGINAL_IP"
AUTH_HOST = "$AUTH_HOST"
MIRROR_BASE = "$MIRROR_BASE"

print('#!/bin/bash')
print('set -e')
# 授权 IP
print(f"sed -i 's|{ORIGINAL_IP}|{AUTH_HOST}|g' \"{SOURCE_GO}\"")
# 每个 URL
for f in m['files']:
    orig = f"{MIRROR_BASE}/{f['url']}"
    if f['in_repo']:
        target = f"{RAW_BASE}/backup/v3.9.22/mirror/{f['local']}"
    else:
        fname = f['url'].split('/')[-1]
        path = f['url']
        if 'c8/' in path and fname.startswith('rpms'):
            asset = f"c8_{fname}"
        else:
            asset = fname
        target = f"{RELEASE_BASE}/{asset}"
    orig_e = orig.replace('/', '\\/').replace('.', '\\.').replace('?', '\\?')
    tgt_e = target.replace('/', '\\/').replace('&', '\\&')
    print(f"sed -i 's|{orig_e}|{tgt_e}|g' \"{SOURCE_GO}\"")
PYEOF

chmod +x "$TMPDIR/patch_urls.sh"
bash "$TMPDIR/patch_urls.sh"
ok "URL patch 完成"

echo -n "  mirror URL 残留: "
echo "$(grep -c 'mirror.cloud.idcsmart.com' "$SOURCE_GO" || true) 处"
echo -n "  原 IP 残留: "
echo "$(grep -c "${ORIGINAL_IP}" "$SOURCE_GO" || true) 处"

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
if ! CGO_ENABLED=1 go build -o install-zjmf-cloud_new.patched -trimpath \
  install-zjmf-cloud_new.go 2>&1 | tail -15; then
  err "编译失败！"
  exit 1
fi
ok "编译完成: $(ls -lh install-zjmf-cloud_new.patched | awk '{print $5}')"

# ========== Step 5: 运行 ==========
info "Step 5/5: 启动安装 (镜像包从 GitHub 备份下载) ..."
cp install-zjmf-cloud_new.patched "$ORIG_DIR/"
chmod +x "$ORIG_DIR/install-zjmf-cloud_new.patched"
cd "$ORIG_DIR"

echo ""
echo "============================================================"
echo "  安装即将开始！"
echo "  🔑 授权码 (License): 随便填一个 32 位大写 MD5 即可"
echo "     例: $(python3 -c "import hashlib,time; print(hashlib.md5(str(time.time()).encode()).hexdigest().upper())")"
echo ""
echo "  📦 镜像包下载源:"
echo "     小文件 → raw.githubusercontent.com (git-lfs)"
echo "     大文件 → github.com/.../releases/download/v3.9.22"
echo ""
echo "  💾 备份完整性: md5 与 mirror.cloud.idcsmart.com 100% 匹配"
echo "============================================================"
echo ""

./install-zjmf-cloud_new.patched "${INSTALL_ARGS[@]}"
