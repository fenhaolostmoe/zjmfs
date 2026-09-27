#!/usr/bin/env bash

# ==========================================
# ZJMF Cloud 安装程序 · 源码修改 + 重编译
# ==========================================
# 源码来自主仓库: https://github.com/fenhaolostmoe/zjmfs
# (源码文件: install-zjmf-cloud_new.go)
#
# 用法:
#   ./rebuild.sh <你的授权API域名或IP>
#   ./rebuild.sh zjmf-auth-api.fenhaolost.workers.dev
# ==========================================

set -e

NEW_AUTH_HOST="${1:-zjmf-auth-api.fenhaolost.workers.dev}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SRC="$REPO_DIR/install-zjmf-cloud_new.go"
OUT="$REPO_DIR/install-zjmf-cloud_new.patched"

echo "=============================================="
echo " ZJMF Cloud 安装程序重编译"
echo "=============================================="
echo " 原源码: $SRC"
echo " 输出:   $OUT"
echo " 新授权域名: $NEW_AUTH_HOST"
echo ""

# 检查 Go 环境
if ! command -v go &>/dev/null; then
  echo "[安装] 正在安装 Go 1.20 ..."
  curl -sL https://go.dev/dl/go1.20.11.linux-amd64.tar.gz -o /tmp/go.tgz
  rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tgz
  export PATH=$PATH:/usr/local/go/bin
fi

echo "[源码] 修改硬编码 IP 为 $NEW_AUTH_HOST ..."

# 方法1: sed 改源码里的所有硬编码 URL
# 1731 行: "http://154.7.178.154/app/api/ip"
# 可能还有其他我们没逆向出来的 auth URL，用 sed 全局替换 IP 即可
cp "$SRC" "${SRC}.bak"
sed -i "s|154\.7\.178\.154|${NEW_AUTH_HOST}|g" "$SRC"

echo "[源码] 替换完成，检查一下 ..."
grep -n "154.7.178.154\|${NEW_AUTH_HOST}" "$SRC" | head -5

echo ""
echo "[编译] Go build ..."
cd "$REPO_DIR"

# CGO_ENABLED=0 → 静态二进制, 目标机无需 gcc / libc 头文件
CGO_ENABLED=0 go build -o "$OUT" -trimpath ./install-zjmf-cloud_new.go

echo ""
echo "[验证] 检查新二进制 ..."
ls -lh "$OUT"
echo ""
strings "$OUT" | grep -oE "http://${NEW_AUTH_HOST}[a-zA-Z0-9/_?=&.%\-]*" | sort -u | head -5

echo ""
echo "=============================================="
echo " ✅ 编译完成！"
echo " 输出: $OUT"
echo ""
echo " 使用:"
echo "   chmod +x $OUT"
echo "   $OUT -nokernel -norepo -l -license YOUR_LICENSE"
echo "=============================================="
