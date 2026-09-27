#!/usr/bin/env python3

# 源码 / 二进制来自主仓库: https://github.com/fenhaolostmoe/zjmfs
# 注意: 二进制 patch 有长度限制 (原 IP 字段仅 13 字节).
#       长域名请改用 rebuild.sh 或 install.sh (直接改源码后重编译).

"""
ELF Patch 脚本：替换 Go 安装程序里硬编码的授权 IP
用法: python3 patch_installer.py <二进制文件> <你的 Workers 域名或 IP>
示例: python3 patch_installer.py install-zjmf-cloud_new "auth.yourdomain.com"

原硬编码字符串:
  http://154.7.178.154////////////////app/api/ip
  http://154.7.178.154////////////////app/api/auth?time=

替换规则:
  直接替换 IP 部分（13 字节）为目标域名，剩余字节填 \\x00
  目标域名长度必须 ≤ 13 字节（IP 格式或短域名）
  如果用长域名，可以修改整个 URL 段（最长 13 字节替换 13 字节）
"""

import sys
import os
import struct

ORIG_IP = b"154.7.178.154"

def patch_elf(input_path: str, target: str) -> None:
    if not os.path.isfile(input_path):
        print(f"[错误] 文件不存在: {input_path}")
        sys.exit(1)

    orig_size = os.path.getsize(input_path)
    print(f"[信息] 原文件大小: {orig_size:,} bytes")

    # 备份
    backup_path = input_path + ".bak"
    if not os.path.exists(backup_path):
        import shutil
        shutil.copy2(input_path, backup_path)
        print(f"[备份] 已创建备份: {backup_path}")

    with open(input_path, "rb") as f:
        data = bytearray(f.read())

    target_bytes = target.encode("ascii")
    target_len = len(target_bytes)
    orig_len = len(ORIG_IP)

    print(f"[原] {ORIG_IP.decode()} ({orig_len} bytes)")
    print(f"[新] {target} ({target_len} bytes)")

    if target_len > orig_len:
        # 尝试替换整个 URL 段，找完整 http://154.7.178.154 这样的字符串
        full_pattern = b"http://154.7.178.154"
        full_target = f"http://{target}".encode("ascii")
        if len(full_target) <= len(full_pattern):
            print(f"[替换整个 URL 头] {full_pattern.decode()} -> {full_target.decode()}")
            data = data.replace(full_pattern, full_target.ljust(len(full_pattern), b'\x00'))
        else:
            print(f"[错误] 域名太长 ({target_len} bytes > {orig_len} bytes)")
            print("       解决方案:")
            print("         1. 使用短域名 (如 auth.your.com)")
            print("         2. 用 sed 直接替换原始 Go 源码里的字符串，重新编译")
            print("         3. 在 /etc/hosts 劫持 (只对域名有效)")
            sys.exit(1)
    else:
        # 直接替换 IP 部分
        pad = b"\x00" * (orig_len - target_len)
        new_bytes = target_bytes + pad
        data = data.replace(ORIG_IP, new_bytes)

    patched_size = os.path.getsize(input_path)
    with open(input_path, "wb") as f:
        f.write(data)
    patched_size = os.path.getsize(input_path)

    print(f"[完成] 已写入 {patched_size:,} bytes")

    # 验证
    remaining_ips = data.count(ORIG_IP)
    new_count = data.count(target_bytes) if target_len > 0 else 0
    print(f"[验证] 残留原 IP 出现次数: {remaining_ips}")
    print(f"[验证] 新域名出现次数: {new_count}")

    # 找完整 URL 验证
    import re
    for m in re.finditer(rb'http://[a-zA-Z0-9.\-_/]+app/api/(auth|ip)', data):
        print(f"  最终 URL: {m.group().decode()}")

    print("\n[提示] 记得 chmod +x 后再运行")
    print(f"       chmod +x {input_path}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    patch_elf(sys.argv[1], sys.argv[2])
