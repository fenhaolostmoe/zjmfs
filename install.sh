#!/usr/bin/env bash
# ============================================================
# ZJMF Cloud v3.9.22 · 一键安装脚本
#
# 流程: 源码 → sed patch 硬编码端点 → go build → 运行
#
# 两种模式:
#   HYBRID  (默认)  — 下载走官方 mirror.cloud.idcsmart.com, 授权走 Cloudflare Workers
#   OFFLINE         — 下载 + 授权 都走本地 HTTP server (mirror 由用户自建)
#
# 用法:
#   # 默认混合模式
#   ./install.sh -version 3.9.22 -l -nokernel
#
#   # 指定 Workers endpoint
#   ENDPOINT_HOST=myauth.workers.dev ./install.sh
#
#   # 完全离线模式
#   MIRROR_HOST=mirror.local:8080 ./install.sh
#
#   # 从远程源码 (Codeberg) 拉取
#   SOURCE_URL=https://codeberg.org/fenhaolost/zjmf/raw/main/install-zjmf-cloud_new.go ./install.sh
# ============================================================

set -euo pipefail

# ---------- 配置 ----------
HARDCODED_ENDPOINT_IP="154.7.178.154"
HARDCODED_MIRROR_HOST="mirror.cloud.idcsmart.com"
DEFAULT_ENDPOINT="zjmf-auth-api.fenhaolost.workers.dev"

ENDPOINT_HOST="${ENDPOINT_HOST:-$DEFAULT_ENDPOINT}"
MIRROR_HOST="${MIRROR_HOST:-}"  # 空 = 用官方 mirror (HYBRID 模式)
SOURCE_URL="${SOURCE_URL:-}"    # 空 = 用本地源码

INSTALL_ARGS=()
for arg in "$@"; do
  case "$arg" in
    ENDPOINT_HOST=*) ENDPOINT_HOST="${arg#ENDPOINT_HOST=}" ;;
    MIRROR_HOST=*)   MIRROR_HOST="${arg#MIRROR_HOST=}" ;;
    SOURCE_URL=*)    SOURCE_URL="${arg#SOURCE_URL=}" ;;
    *) INSTALL_ARGS+=("$arg") ;;
  esac
done

# ---------- 工具 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[i]${NC} $*"; }
ok()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[x]${NC} $*"; }

echo ""
echo "============================================================"
echo "  ZJMF Cloud v3.9.22 · Rebuilt Installer"
echo "============================================================"
echo "  Endpoint : http://${ENDPOINT_HOST}/app/api/"
if [ -n "$MIRROR_HOST" ]; then
  echo "  Mirror   : http://${MIRROR_HOST} (offline)"
else
  echo "  Mirror   : http://${HARDCODED_MIRROR_HOST} (official)"
fi
echo "============================================================"
echo ""

ORIG_DIR="$(pwd)"
TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" EXIT

# ============================================================
# Step 1: 获取 Go 环境
# ============================================================
info "Step 1/4: Go 环境检查 ..."
if command -v go &>/dev/null; then
  ok "Go $(go version | awk '{print $3}')"
else
  info "  → 安装 Go 1.22 ..."
  curl -sL "https://go.dev/dl/go1.22.0.linux-amd64.tar.gz" -o "$TMPDIR/go.tgz"
  rm -rf /usr/local/go && tar -C /usr/local -xzf "$TMPDIR/go.tgz"
  export PATH=$PATH:/usr/local/go/bin
  ok "Go $(go version | awk '{print $3}') installed"
fi

export PATH=$PATH:$(go env GOPATH)/bin

# ============================================================
# Step 2: 获取源码
# ============================================================
info "Step 2/4: 获取源码 ..."

if [ -n "$SOURCE_URL" ]; then
  # 从远程拉取
  SOURCE_GO="$TMPDIR/install-zjmf-cloud_new.go"
  wget -q --show-progress "$SOURCE_URL" -O "$SOURCE_GO"
  ok "源码下载完成: $(wc -l < "$SOURCE_GO") 行"
elif [ -f "$ORIG_DIR/install-zjmf-cloud_new.go" ]; then
  # 用本地源码
  SOURCE_GO="$ORIG_DIR/install-zjmf-cloud_new.go"
  ok "使用本地源码: $(wc -l < "$SOURCE_GO") 行"
else
  # 尝试远程仓库 (GitHub 主仓库)
  SOURCE_GO="$TMPDIR/install-zjmf-cloud_new.go"
  GITHUB_URL="https://raw.githubusercontent.com/fenhaolostmoe/zjmfs/main/install-zjmf-cloud_new.go"
  if wget -q --show-progress "$GITHUB_URL" -O "$SOURCE_GO" 2>/dev/null; then
    ok "GitHub 下载: $(wc -l < "$SOURCE_GO") 行"
  else
    err "找不到源码文件!"
    echo "  请把 install-zjmf-cloud_new.go 放到当前目录,"
    echo "  或设置 SOURCE_URL 指向源码地址"
    exit 1
  fi
fi

# ============================================================
# Step 3: Patch + Build
# ============================================================
info "Step 3/4: Patch + Build ..."

PATCHED_GO="$TMPDIR/install-zjmf-cloud_new.patched.go"
cp "$SOURCE_GO" "$PATCHED_GO"

# --- 规范化 ENDPOINT_HOST (去掉 https:// 前缀, 后面 sed 自动加) ---
ENDPOINT_HOST_CLEAN="${ENDPOINT_HOST#https://}"
ENDPOINT_HOST_CLEAN="${ENDPOINT_HOST_CLEAN#http://}"

# --- Patch endpoint IP → Workers (同时把协议从 http:// 改成 https://) ---
# 源码里: "http://154.7.178.154/app/api/ip"
# patch 后: "https://workers.example.com/app/api/ip"
# 为什么改协议? 因为源码里 curl 命令没有 -L 参数,不跟随 301 重定向
# Cloudflare Workers HTTP 80 端口返回 301 → HTTPS,curl 拿不到正确响应
if grep -q "${HARDCODED_ENDPOINT_IP}" "$PATCHED_GO"; then
  # 只替换 URL 里协议头 + IP 这一段
  sed -i "s|http://${HARDCODED_ENDPOINT_IP}|https://${ENDPOINT_HOST_CLEAN}|g" "$PATCHED_GO"
  ok "  Auth endpoint: http://${HARDCODED_ENDPOINT_IP} → https://${ENDPOINT_HOST_CLEAN}"
else
  ok "  Auth endpoint: 已是 patch 版本, 跳过"
fi

# --- Patch mirror (如果指定了本地 mirror, 协议保持 http://) ---
if [ -n "$MIRROR_HOST" ]; then
  # 规范化 MIRROR_HOST (用户可能带 http://)
  MIRROR_HOST_CLEAN="${MIRROR_HOST#http://}"
  MIRROR_HOST_CLEAN="${MIRROR_HOST_CLEAN#https://}"
  if grep -q "${HARDCODED_MIRROR_HOST}" "$PATCHED_GO"; then
    sed -i "s|${HARDCODED_MIRROR_HOST}|${MIRROR_HOST_CLEAN}|g" "$PATCHED_GO"
    ok "  Mirror: ${HARDCODED_MIRROR_HOST} → ${MIRROR_HOST_CLEAN} (offline, 协议保持 http://)"
  fi
else
  ok "  Mirror: 使用官方 ${HARDCODED_MIRROR_HOST} (HYBRID 模式)"
fi

# --- Patch 授权验证 URL → Workers (HYBRID 模式关键!) ---
# 源码里: "http://mirror.cloud.idcsmart.com/cloud/license/verify"
# 注意: 这个 host 同时用于 23 处包下载, 所以只替换「完整 license URL」,
#       不碰下载相关的 mirror 引用 (否则会导致包下载 404)
if [ -z "$MIRROR_HOST" ]; then
  if grep -q "http://${HARDCODED_MIRROR_HOST}/cloud/license/verify" "$PATCHED_GO"; then
    sed -i "s|http://${HARDCODED_MIRROR_HOST}/cloud/license/verify|https://${ENDPOINT_HOST_CLEAN}/app/api/auth|g" "$PATCHED_GO"
    ok "  授权验证: mirror/cloud/license/verify → https://${ENDPOINT_HOST_CLEAN}/app/api/auth"
  fi
else
  # OFFLINE 模式: mirror 整体替换后, license 也随本地 mirror 走
  ok "  授权验证: 随本地 mirror (offline)"
fi

# 创建 go.mod + 编译
cd "$TMPDIR"
cat > go.mod << GOMOD
module install-zjmf
go 1.20
require github.com/cavaliergopher/grab/v3 v3.0.1
GOMOD

info "  → go mod tidy ..."
go mod tidy 2>&1 | tail -3 || true

info "  → go build ..."
# CGO_ENABLED=0 → 静态二进制, 目标机无需 gcc / libc 头文件 (CentOS minimal 常缺)
if ! CGO_ENABLED=0 go build -o install-zjmf-cloud_new -trimpath \
  "$PATCHED_GO" 2>&1 | tail -15; then
  err "Build 失败!"
  exit 1
fi
ok "  编译完成: $(ls -lh install-zjmf-cloud_new | awk '{print $5}')"

# 验证 patch (使用 -F 固定字符串匹配,避免 . 被当作正则通配符)
echo ""
echo "  [验证]"
if strings install-zjmf-cloud_new 2>/dev/null | grep -Fq "$ENDPOINT_HOST"; then
  echo "    ✓ Endpoint 已 patch: $ENDPOINT_HOST"
else
  echo "    ✗ Endpoint patch 可能失败"
fi
if strings install-zjmf-cloud_new 2>/dev/null | grep -Fq "$HARDCODED_ENDPOINT_IP"; then
  echo "    ✗ 原 IP 仍残留: $HARDCODED_ENDPOINT_IP"
else
  echo "    ✓ 原 IP 已清除"
fi
if [ -n "$MIRROR_HOST" ]; then
  if strings install-zjmf-cloud_new 2>/dev/null | grep -Fq "$MIRROR_HOST"; then
    echo "    ✓ Mirror 已 patch: $MIRROR_HOST"
  fi
fi
echo ""

# ============================================================
# Step 4: 运行安装程序
# ============================================================
info "Step 4/4: 启动安装程序 ..."

cp install-zjmf-cloud_new "$ORIG_DIR/install-zjmf-cloud_new"
chmod +x "$ORIG_DIR/install-zjmf-cloud_new"
cd "$ORIG_DIR"

echo ""
echo "============================================================"
echo "  安装程序启动 (退出后临时文件自动清理)"
echo "============================================================"
echo ""

./install-zjmf-cloud_new "${INSTALL_ARGS[@]}"
