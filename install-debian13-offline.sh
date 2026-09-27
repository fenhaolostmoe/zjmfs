#!/usr/bin/env bash
# ============================================================
# ZJMF Cloud · Debian 13 离线安装脚本 (hosts 劫持方案)
# ============================================================
# 原理:
#   1. 下载官方 Debian 版安装二进制 (install-zjmf-cloud-debian13)
#   2. 从本仓库拉全量 21 个镜像文件 (manifest.json 驱动)
#   3. 修改 /etc/hosts 把 mirror.cloud.idcsmart.com → 127.0.0.1
#   4. 启动 python3 HTTP server 指向本地备份 (80 端口)
#   5. 运行 Debian 版安装程序 —— 它访问 mirror.cloud.idcsmart.com 实际打到本地
#   6. 安装完成后恢复 /etc/hosts
#
# 和 CentOS 离线版的区别:
#   - CentOS 版有 Go 源码, 可以 sed 替换硬编码 URL
#   - Debian 版只有编译好的二进制 (UPX 加壳 + strip), URL 运行时拼接
#   - 所以改用 /etc/hosts + 本地 HTTP 劫持
#
# 前置条件:
#   - Debian 13 (trixie) 或兼容发行版
#   - 已安装 python3 (>= 3.8)
#   - 已安装 git + git-lfs (拉 Codeberg 仓库)
#   - 已有 cloudflare workers 部署好 (见 README)
#
# 用法:
#   wget https://raw.githubusercontent.com/fenhaolostmoe/zjmfs/main/install-debian13-offline.sh \
#     -O install.sh && chmod +x install.sh && ./install.sh
#
# 可选参数:
#   ENDPOINT_HOST=your.workers.dev          Workers API 地址 (默认 zjmf-auth-api.fenhaolost.workers.dev)
#   MIRROR_HOST=mirror.cloud.idcsmart.com   要劫持的域名
#   HTTP_PORT=80                              本地 HTTP 端口
#   NO_KERNEL=1                               跳过内核检查
#   VERSION=3.9.22                            安装版本
#   LICENSE_KEY=xxx                           license key
# ============================================================

set -euo pipefail

# ---------- 配置 ----------
REPO="fenhaolost/zjmf"
BRANCH="main"
# Codeberg 大文件走 LFS: 必须用 /media/branch/ 端点
# (/raw/ 只会返回 134B 的 LFS 指针, 不是真实文件)
RAW_BASE="https://codeberg.org/${REPO}/media/branch/${BRANCH}"
# 安装二进制不在 Codeberg(404), 走 GitHub 主仓库
SRC_BIN_URL="https://raw.githubusercontent.com/fenhaolostmoe/zjmfs/main/install-zjmf-cloud-debian13"
DEFAULT_ENDPOINT="zjmf-auth-api.fenhaolost.workers.dev"
ENDPOINT_HOST="${ENDPOINT_HOST:-$DEFAULT_ENDPOINT}"
VERSION="${VERSION:-3.9.22}"
MIRROR_HOST="${MIRROR_HOST:-mirror.cloud.idcsmart.com}"
HTTP_PORT="${HTTP_PORT:-80}"
NO_KERNEL="${NO_KERNEL:-0}"

INSTALL_ARGS=()
for arg in "$@"; do
  case "$arg" in
    ENDPOINT_HOST=*) ENDPOINT_HOST="${arg#ENDPOINT_HOST=}" ;;
    VERSION=*) VERSION="${arg#VERSION=}" ;;
    MIRROR_HOST=*) MIRROR_HOST="${arg#MIRROR_HOST=}" ;;
    HTTP_PORT=*) HTTP_PORT="${arg#HTTP_PORT=}" ;;
    NO_KERNEL=*) NO_KERNEL="${arg#NO_KERNEL=}" ;;
    LICENSE_KEY=*) INSTALL_ARGS+=("-license" "${arg#LICENSE_KEY=}") ;;
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
echo "  ZJMF Cloud · Debian 13 离线安装"
echo "  Endpoint  : http://${ENDPOINT_HOST}/app/api/"
echo "  劫持域名  : ${MIRROR_HOST} → 127.0.0.1:${HTTP_PORT}"
echo "  Version   : ${VERSION}"
echo "============================================================"
echo ""

# 必须 root
if [ "$(id -u)" -ne 0 ]; then
  err "需要 root 权限 (修改 /etc/hosts + 80 端口 HTTP server)"
  warn "sudo bash $0 $*"
  exit 1
fi

ORIG_DIR="$(pwd)"
TMPDIR="$(mktemp -d)"
LOCAL_MIRROR="$TMPDIR/mirror"
HOSTS_BAK="$TMPDIR/hosts.bak"
SERVER_PID=""
HOSTS_MODIFIED=0

cleanup() {
  RC=$?
  echo ""
  info "清理中 ..."

  # 恢复 /etc/hosts
  if [ "$HOSTS_MODIFIED" = "1" ] && [ -f "$HOSTS_BAK" ]; then
    cp "$HOSTS_BAK" /etc/hosts
    ok "/etc/hosts 已恢复"
  elif [ "$HOSTS_MODIFIED" = "1" ]; then
    # 没备份也手动清掉
    sed -i "/127\.0\.0\.1 ${MIRROR_HOST}/d" /etc/hosts
    ok "/etc/hosts 已清理"
  fi

  # 停 HTTP server
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    ok "本地 HTTP server 已停止 (pid $SERVER_PID)"
  fi

  # 删 iptables 重定向（如果加过）
  if command -v iptables &>/dev/null; then
    iptables -t nat -D OUTPUT -p tcp -d "${ENDPOINT_HOST}" --dport 80 -j DNAT --to-destination 127.0.0.1:18080 2>/dev/null || true
    iptables -t nat -D OUTPUT -p tcp -d "${ENDPOINT_HOST}" --dport 443 -j DNAT --to-destination 127.0.0.1:18443 2>/dev/null || true
  fi

  rm -rf "$TMPDIR" 2>/dev/null || true
  exit $RC
}
trap cleanup EXIT INT TERM

# ============================================================
# Step 1: 下载 Debian 版安装二进制
# ============================================================
info "Step 1/7: 下载 Debian 版安装二进制 ..."
DEB_BIN="$TMPDIR/install-zjmf-cloud-debian13"
ORIG_MIRROR="http://mirror.cloud.idcsmart.com"

# 下载链: 官方 mirror → GitHub 备份 → Codeberg LFS
if wget -q --show-progress --timeout=25 "${ORIG_MIRROR}/cloud/scripts/install-zjmf-cloud-debian13" -O "$DEB_BIN" 2>/dev/null; then
  ok "官方 mirror 下载成功"
elif wget -q --show-progress --timeout=25 "${SRC_BIN_URL}" -O "$DEB_BIN" 2>/dev/null; then
  ok "GitHub 备份下载成功"
elif wget -q --show-progress --timeout=25 "${RAW_BASE}/backup/v3.9.22/install-zjmf-cloud-debian13" -O "$DEB_BIN" 2>/dev/null; then
  ok "Codeberg 备份下载成功"
else
  err "安装二进制下载失败 (官方 mirror 和备份都不可达)"
  exit 1
fi

# 完整性校验: 真实二进制应 > 1MB, 防止误下到 LFS 指针(134B)或 404 页面
if [ "$(stat -c%s "$DEB_BIN" 2>/dev/null || echo 0)" -lt 1000000 ]; then
  err "下载文件异常 (小于 1MB, 疑似 LFS 指针或错误页)"
  ls -l "$DEB_BIN"; head -c 200 "$DEB_BIN"; echo
  exit 1
fi
chmod +x "$DEB_BIN"
ok "$(ls -lh "$DEB_BIN" | awk '{print $5}')"

# 显示 help
echo ""
"$DEB_BIN" -h 2>&1 || true
echo ""

# ============================================================
# Step 2: 下载全量镜像文件
# ============================================================
info "Step 2/7: 下载全量镜像文件 (Codeberg) ..."

MANIFEST="$TMPDIR/manifest.json"
wget -q "${RAW_BASE}/backup/v3.9.22/manifest.json" -O "$MANIFEST"
ok "manifest 下载完成"

python3 << PYEOF
import json, os, sys, urllib.request, hashlib, time

manifest_path = "$MANIFEST"
mirror_dir    = "$LOCAL_MIRROR"
raw_base      = "${RAW_BASE}/backup/v3.9.22/mirror"

with open(manifest_path) as f:
    d = json.load(f)

ok_count = 0; fail_count = 0
t0 = time.time()
for i, file in enumerate(d["files"], 1):
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
            print(f"  [{i}/{d['total_files']}] ✅ {path} (cached)")
            ok_count += 1
            continue

    print(f"  [{i}/{d['total_files']}] ↓ {path} ({size/1024/1024:.1f}MB) ... ", end="", flush=True)
    try:
        t1 = time.time()
        urllib.request.urlretrieve(url, dest)
        dt = time.time() - t1
        with open(dest, 'rb') as f:
            md5 = hashlib.md5(f.read()).hexdigest()
        if md5 == md5_expected:
            print(f"ok ({dt:.1f}s)")
            ok_count += 1
        else:
            print(f"⚠️  md5 mismatch")
            fail_count += 1
    except Exception as e:
        print(f"❌ {e}")
        fail_count += 1

print(f"\n  下载完成: {ok_count}/{d['total_files']} ok, {fail_count} fail, {time.time()-t0:.1f}s")
PYEOF

# ============================================================
# Step 3: 修改 /etc/hosts 劫持 mirror
# ============================================================
info "Step 3/7: 修改 /etc/hosts 劫持 ${MIRROR_HOST} → 127.0.0.1 ..."

# 备份
cp /etc/hosts "$HOSTS_BAK"

# 加劫持记录
echo "127.0.0.1 ${MIRROR_HOST}" >> /etc/hosts
HOSTS_MODIFIED=1

# 验证
if grep -q "${MIRROR_HOST}" /etc/hosts; then
  ok "/etc/hosts 已添加劫持记录"
else
  err "/etc/hosts 修改失败"
  exit 1
fi

# 清除 DNS 缓存
if command -v systemd-resolve &>/dev/null; then
  systemd-resolve --flush-caches 2>/dev/null || true
fi
if command -v resolvectl &>/dev/null; then
  resolvectl flush-caches 2>/dev/null || true
fi

ok "DNS 缓存已清除"

# ============================================================
# Step 4: 启动本地 HTTP server
# ============================================================
info "Step 4/7: 启动本地 HTTP server on :${HTTP_PORT} ..."

# 检查 80 端口是否被占
if lsof -i ":${HTTP_PORT}" &>/dev/null 2>&1 || ss -tlnp 2>/dev/null | grep -q ":${HTTP_PORT}"; then
  # 杀掉占用进程 (可能是之前装过的 nginx/apache)
  warn "端口 ${HTTP_PORT} 被占用, 尝试停止 ..."
  systemctl stop nginx apache2 httpd 2>/dev/null || true
  pkill -f "http.server.*${HTTP_PORT}" 2>/dev/null || true
  sleep 1
fi

cd "$LOCAL_MIRROR"
python3 -m http.server "${HTTP_PORT}" > /dev/null 2>&1 &
SERVER_PID=$!
cd "$TMPDIR"

# 等 server 起来
for i in $(seq 1 20); do
  if curl -sI --max-time 2 "http://${MIRROR_HOST}:${HTTP_PORT}/cloud/packages/c7/python2-packages.tar.gz" 2>/dev/null | grep -q "200 OK"; then
    ok "HTTP server on :${HTTP_PORT} (pid $SERVER_PID)"
    ok "劫持验证: curl http://${MIRROR_HOST}/ → $(curl -sI --max-time 3 "http://${MIRROR_HOST}/cloud/packages/c7/python2-packages.tar.gz" | head -1)"
    break
  fi
  sleep 0.5
done

# ============================================================
# Step 5: 劫持 Worker DNS (让 Debian 版访问我们的 Workers)
# ============================================================
info "Step 5/7: Worker endpoint 配置 ..."

# Debian 版二进制里的授权 API URL 是运行时拼接的, 大概率硬编码 IP + 路径
# 因为 CentOS 版是 154.7.178.154
# 我们加 iptables 把发往 154.7.178.154:80/443 的流量 redirect 到 Workers
if command -v iptables &>/dev/null; then
  info "  → 加 iptables DNAT 规则 (如果 Debian 版走 154.7.178.154)"
  # 先解析 ENDPOINT_HOST 的 IP
  WORKER_IP=$(getent ahostsv4 "${ENDPOINT_HOST}" 2>/dev/null | head -1 | awk '{print $1}')
  if [ -n "${WORKER_IP:-}" ]; then
    ok "${ENDPOINT_HOST} → ${WORKER_IP}"
    # 把 154.7.178.154 的流量转到 Workers
    iptables -t nat -C OUTPUT -p tcp -d 154.7.178.154 -j DNAT --to-destination "${WORKER_IP}" 2>/dev/null || \
    iptables -t nat -A OUTPUT -p tcp -d 154.7.178.154 -j DNAT --to-destination "${WORKER_IP}"
    ok "iptables 规则已添加"
  else
    warn "解析 ${ENDPOINT_HOST} 失败, 跳过 iptables 劫持"
  fi
fi

# ============================================================
# Step 6: 运行安装程序
# ============================================================
info "Step 6/7: 启动 Debian 13 安装程序 ..."

FINAL_ARGS=("-version" "${VERSION}")
[ "$NO_KERNEL" = "1" ] && FINAL_ARGS+=("-nokernel")
FINAL_ARGS+=("-norepo" "-yes")
FINAL_ARGS+=("${INSTALL_ARGS[@]}")

echo ""
echo "============================================================"
echo "  安装程序启动"
echo "  退出后 hosts + HTTP server 会自动清理"
echo "============================================================"
echo ""

cd "$ORIG_DIR"
"$DEB_BIN" "${FINAL_ARGS[@]}"

echo ""
echo "============================================================"
echo "  安装程序退出"
echo "============================================================"
