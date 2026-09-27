#!/usr/bin/env bash
# ============================================================
# ZJMF Cloud · Debian 13 离线安装脚本 v3
#
# 逆向分析 (install-zjmf-cloud-debian13 UPX unpacked, 17.9MB):
#   - mirror (HTTP): mirror.cloud.idcsmart.com / hkcloud.idcsmart.com (-dl 2)
#   - auth   (HTTPS): license.soft13.idcsmart.com:443/app/api/auth
#   - URL 存储: 运行时动态构造, 二进制里搜不到硬编码域名 (无法 sed patch)
#   - /cloud/test: mirror 连通性测试端点
#
# 劫持方案 (已验证 ✅):
#   1. 自签 CA + Server 证书 (SAN: license.soft13.idcsmart.com)
#   2. CA → /usr/local/share/ca-certificates/ + update-ca-certificates
#   3. /etc/hosts: license.soft13.idcsmart.com → 127.0.0.1
#   4. Python HTTPS server :443 返回 {"status":200,"msg":"ok",...}
#   5. Debian 版 Go HTTP client 验证证书 → 信任自签 CA → 接受 status:200
#
# 前置条件:
#   - Debian 13 (trixie) 纯净系统, root 权限
#   - python3 (>= 3.8), openssl
#   - 可用的 Debian 13 apt 源 (或传 -mirror https://mirrors.tuna.tsinghua.edu.cn/debian)
#
# 用法:
#   sudo bash install-debian13.sh -mirror https://mirrors.tuna.tsinghua.edu.cn/debian
#
# 可选环境变量:
#   VERSION=3.9.22          DL_SERVER=1|2
#   APT_MIRROR=...          LICENSE_KEY=任意字母数字 (必须传才能进入安装)
#   MIRROR_OFFLINE=1        劫持 mirror (需要 Codeberg 备份)
# ============================================================

set -euo pipefail

# ---------- 配置 ----------
VERSION="${VERSION:-3.9.22}"
DL_SERVER="${DL_SERVER:-1}"
APT_MIRROR="${APT_MIRROR:-}"
LICENSE_KEY="${LICENSE_KEY:-DEMOLICENSEKEY12345678}"  # 必须有值,才能触发授权请求
MIRROR_OFFLINE="${MIRROR_OFFLINE:-0}"

AUTH_HOST="license.soft13.idcsmart.com"
MIRROR_HOST_1="mirror.cloud.idcsmart.com"
MIRROR_HOST_2="hkcloud.idcsmart.com"
ALL_HOSTS=($AUTH_HOST $MIRROR_HOST_1 $MIRROR_HOST_2)

REPO="fenhaolost/zjmf"
BRANCH="main"
RAW_BASE="https://codeberg.org/${REPO}/raw/${BRANCH}"

# ---------- 工具 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}[i]${NC} $*"; }
ok()    { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[x]${NC} $*"; }

echo ""
echo "============================================================"
echo "  ZJMF Cloud · Debian 13 离线安装 v3"
echo "============================================================"
echo "  Version      : ${VERSION}"
echo "  下载站       : ${DL_SERVER}"
echo "  License      : ${LICENSE_KEY:0:16}..."
echo "  授权劫持     : ${AUTH_HOST} → 127.0.0.1:443 (自签证书)"
echo "  Mirror 劫持  : $([ "$MIRROR_OFFLINE" = "1" ] && echo "ON" || echo "OFF (官方 mirror)")"
echo "  APT Mirror   : ${APT_MIRROR:-节点已有}"
echo "============================================================"
echo ""

if [ "$(id -u)" -ne 0 ]; then
  err "需要 root 权限"
  warn "sudo bash $0"
  exit 1
fi

ORIG_DIR="$(pwd)"
TMPDIR="$(mktemp -d)"
LOCAL_MIRROR="$TMPDIR/mirror"
HOSTS_BAK="$TMPDIR/hosts.bak"
CA_COPY="/usr/local/share/ca-certificates/zjmf-local-ca.crt"
HTTPS_PID=""
HTTP_PID=""
CA_INSTALLED=0
HOSTS_MODIFIED=0

cleanup() {
  RC=$?
  echo ""
  info "清理中 ..."

  # 停 HTTPS server
  if [ -n "$HTTPS_PID" ] && kill -0 "$HTTPS_PID" 2>/dev/null; then
    kill "$HTTPS_PID" 2>/dev/null || true
    sleep 0.3
    ok "HTTPS server stopped (pid $HTTPS_PID)"
  fi

  # 停 HTTP server
  if [ -n "$HTTP_PID" ] && kill -0 "$HTTP_PID" 2>/dev/null; then
    kill "$HTTP_PID" 2>/dev/null || true
    ok "HTTP server stopped (pid $HTTP_PID)"
  fi

  # 恢复 /etc/hosts
  if [ "$HOSTS_MODIFIED" = "1" ]; then
    if [ -f "$HOSTS_BAK" ]; then
      cp "$HOSTS_BAK" /etc/hosts
      ok "/etc/hosts restored"
    else
      for h in "${ALL_HOSTS[@]}"; do sed -i "/127\.0\.0\.1 ${h}/d" /etc/hosts 2>/dev/null || true; done
      ok "/etc/hosts cleaned"
    fi
  fi

  # 移除自签 CA
  if [ "$CA_INSTALLED" = "1" ] && [ -f "$CA_COPY" ]; then
    rm -f "$CA_COPY"
    update-ca-certificates 2>/dev/null || true
    ok "自签 CA 已移除"
  fi

  rm -rf "$TMPDIR" 2>/dev/null || true
  exit $RC
}
trap cleanup EXIT INT TERM

# ============================================================
# Step 1: 下载 Debian 版安装二进制
# ============================================================
info "Step 1/6: 下载 Debian 版安装二进制 ..."
DEB_BIN="$TMPDIR/install-zjmf-cloud-debian13"
ORIG_MIRROR="http://mirror.cloud.idcsmart.com"

if ! wget -q "${ORIG_MIRROR}/cloud/scripts/install-zjmf-cloud-debian13" -O "$DEB_BIN" 2>/dev/null; then
  wget -q --show-progress "${RAW_BASE}/cloud/scripts/install-zjmf-cloud-debian13" -O "$DEB_BIN" 2>/dev/null || \
  wget -q --show-progress "${ORIG_MIRROR}/cloud/scripts/install-zjmf-cloud" -O "$DEB_BIN"
fi
chmod +x "$DEB_BIN"
ok "install-zjmf-cloud-debian13 ($(ls -lh $DEB_BIN | awk '{print $5}'))"

# ============================================================
# Step 2: 生成自签 CA + Server 证书
# ============================================================
info "Step 2/6: 生成自签证书 → ${AUTH_HOST} ..."

openssl genrsa -out "$TMPDIR/ca.key" 2048 2>/dev/null
openssl req -x509 -new -nodes -key "$TMPDIR/ca.key" -sha256 -days 3650 \
  -out "$TMPDIR/ca.crt" -subj "/CN=ZJMF Local CA" 2>/dev/null

openssl genrsa -out "$TMPDIR/server.key" 2048 2>/dev/null
openssl req -new -key "$TMPDIR/server.key" -out "$TMPDIR/server.csr" \
  -subj "/CN=${AUTH_HOST}" 2>/dev/null

openssl x509 -req -in "$TMPDIR/server.csr" \
  -CA "$TMPDIR/ca.crt" -CAkey "$TMPDIR/ca.key" -CAcreateserial \
  -out "$TMPDIR/server.crt" -days 365 -sha256 \
  -extfile <(echo -e "subjectAltName=DNS:${AUTH_HOST}") 2>/dev/null

# 验证
if openssl verify -CAfile "$TMPDIR/ca.crt" "$TMPDIR/server.crt" 2>/dev/null | grep -q OK; then
  ok "自签证书验证通过"
else
  err "自签证书生成失败"
  exit 1
fi

# ============================================================
# Step 3: CA 加入系统信任
# ============================================================
info "Step 3/6: 自签 CA → 系统信任库 ..."
cp "$TMPDIR/ca.crt" "$CA_COPY"
if update-ca-certificates 2>&1 | tail -1 | grep -q "certificates added"; then
  CA_INSTALLED=1
  ok "自签 CA 已加入系统信任"
else
  CA_INSTALLED=1
  warn "update-ca-certificates 无输出, 继续"
fi

# ============================================================
# Step 4: hosts 劫持 + HTTPS server (License)
# ============================================================
info "Step 4/6: hosts 劫持 + 自签 HTTPS server ..."

cp /etc/hosts "$HOSTS_BAK"
HOSTS_MODIFIED=1

for host in "${ALL_HOSTS[@]}"; do
  if ! grep -q "127\.0\.0\.1 ${host}" /etc/hosts; then
    echo "127.0.0.1 ${host}" >> /etc/hosts
  fi
done
ok "/etc/hosts: ${AUTH_HOST} → 127.0.0.1"

# 清 DNS 缓存
for c in systemd-resolve resolvectl nscd; do $c --flush-caches 2>/dev/null || true; done

# Python HTTPS server
cat > "$TMPDIR/srv_auth.py" << 'PYEOF'
import http.server, ssl, json, time, sys

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, f, *a): 
        p = self.path.split('?')[0]
        print(f"  ✅ {self.command} {p} → 200", flush=True)
    def _ok(self, d):
        b = json.dumps(d).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)
    def _dispatch(self):
        p = self.path.split("?")[0]
        if "/app/api/auth" in p or "/cloud/license/verify" in p:
            self._ok({
                "status": 200, "msg": "ok", "professional": True,
                "version": "3.9.22", "last_version": "3.9.22",
                "release_version": "3.9.22",
                "remote_ip": self.client_address[0],
                "auth_time": time.strftime("%Y-%m-%d %H:%M:%S"),
                "auth_due_time": "2039-12-31 23:59:59",
                "node_num": 0, "max_node": 9999, "type": "cloud",
            })
        elif "/app/api/ip" in p:
            self._ok({"status": 200, "msg": "ok", "ip": self.client_address[0]})
        else:
            self._ok({"status": 200, "msg": "ok"})
    do_GET = _dispatch; do_POST = _dispatch

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(f"{sys.argv[1]}/server.crt", f"{sys.argv[1]}/server.key")
srv = http.server.HTTPServer(("0.0.0.0", 443), H)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
print("🎯 fake HTTPS :443", flush=True)
srv.serve_forever()
PYEOF

# 杀占用 443 的进程
if ss -tlnp 2>/dev/null | grep -q ":443 "; then
  PIDS=$(ss -tlnp 2>/dev/null | grep ":443 " | grep -oP 'pid=\K[0-9]+' | head -1)
  [ -n "$PIDS" ] && kill "$PIDS" 2>/dev/null || true
  sleep 1
fi

python3 "$TMPDIR/srv_auth.py" "$TMPDIR" > "$TMPDIR/auth.log" 2>&1 &
HTTPS_PID=$!
sleep 1

if ! kill -0 "$HTTPS_PID" 2>/dev/null; then
  err "HTTPS server 启动失败"
  cat "$TMPDIR/auth.log"
  exit 1
fi

# curl 验证 (关键!)
if echo | openssl s_client -connect "${AUTH_HOST}:443" \
    -servername "${AUTH_HOST}" 2>/dev/null | openssl x509 -noout 2>/dev/null | grep -q .; then
  ok "HTTPS server :443 (证书有效)"
else
  err "HTTPS 证书握手失败"
  exit 1
fi

CURL_AUTH=$(/usr/bin/curl -s --connect-timeout 3 "https://${AUTH_HOST}/app/api/auth" 2>/dev/null)
echo "$CURL_AUTH" | grep -q '"status": 200' && ok "GET /app/api/auth → status:200 ✅" || { warn "Auth 响应: $CURL_AUTH"; }

# ============================================================
# Step 5: 下载 mirror 文件 + 启动 HTTP server (可选)
# ============================================================
if [ "$MIRROR_OFFLINE" = "1" ]; then
  info "Step 5/6: 下载 mirror 文件 + 启动 HTTP server (offline mode) ..."
  MANIFEST="$TMPDIR/manifest.json"
  wget -q "${RAW_BASE}/backup/v3.9.22/manifest.json" -O "$MANIFEST" 2>/dev/null || \
    wget -q "https://raw.githubusercontent.com/${REPO}/main/backup/v3.9.22/manifest.json" -O "$MANIFEST" 2>/dev/null

  if [ -f "$MANIFEST" ]; then
    python3 << PYEOF
import json, os, urllib.request, hashlib, time
with open("$MANIFEST") as f: d = json.load(f)
for i, file in enumerate(d["files"], 1):
    path, size, md5 = file["path"], file["size"], file["md5"]
    dest = os.path.join("$LOCAL_MIRROR", path)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest) and os.path.getsize(dest) == size:
        with open(dest, 'rb') as f: h = hashlib.md5(f.read()).hexdigest()
        if h == md5: continue
    print(f"  [{i}/{d['total_files']}] ↓ {path} ({size/1024/1024:.1f}MB)", flush=True)
    urllib.request.urlretrieve("${RAW_BASE}/backup/v3.9.22/mirror/" + path, dest)
PYEOF
    cd "$LOCAL_MIRROR"
    python3 -m http.server 80 --bind 0.0.0.0 > /dev/null 2>&1 &
    HTTP_PID=$!
    cd "$TMPDIR"
    ok "HTTP server :80 (mirror offline)"
  else
    warn "manifest 下载失败, 跳过 mirror 离线"
  fi
else
  info "Step 5/6: Mirror 劫持 OFF — 使用官方 mirror"
fi

# ============================================================
# Step 6: 运行安装程序
# ============================================================
info "Step 6/6: 启动 Debian 13 安装程序 ..."

FINAL_ARGS=("-yes" "-l" "-dl" "${DL_SERVER}" "-nokernel" "-norepo" \
            "-version" "${VERSION}" "-license" "${LICENSE_KEY}")
[ -n "${APT_MIRROR}" ] && FINAL_ARGS+=("-mirror" "${APT_MIRROR}")

echo ""
echo "============================================================"
echo "  参数: ${FINAL_ARGS[*]}"
echo "============================================================"
echo ""

cd "$ORIG_DIR"
"$DEB_BIN" "${FINAL_ARGS[@]}"
RC=$?

echo ""
[ $RC -eq 0 ] && ok "安装程序退出 (rc=0)" || warn "退出 (rc=$RC)"

echo ""
echo "============================================================"
echo "  📊 本脚本实现的劫持:"
echo "  ✅ ${AUTH_HOST}:443  → 本地自签 HTTPS (status:200)"
echo "  $([ "$MIRROR_OFFLINE" = "1" ] && echo "✅ mirror.cloud.idcsmart.com:80 → 本地 Python HTTP" || echo "⏭ mirror.cloud.idcsmart.com:80 → 官方 (未劫持)")"
echo "============================================================"

exit $RC
