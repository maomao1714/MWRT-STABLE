#!/bin/bash

# DIY 脚本第一部分：添加自定义软件源
# 运行时机：在 MWRT 源码目录内，feeds update 执行之前

set -euo pipefail

echo "========================================"
echo " DONGZAI 固件工厂 - DIY Part 1"
echo " 添加自定义软件源 / 自定义软件包"
echo "========================================"

# ─────────────────────────────────────────────
# 自定义 Feeds
# ─────────────────────────────────────────────

echo ">>> 配置自定义 Feeds..."

# helloworld 已由 LEDE feeds.conf.default 提供
# 不重复添加

echo "src-git lucky https://github.com/gdy666/luci-app-lucky.git" \
    >> feeds.conf.default

# 最新 QModem
echo "src-git qmodem https://github.com/FUjr/QModem.git;main" \
    >> feeds.conf.default

# RTP2HTTPD
echo "src-git rtp2httpd https://github.com/stackia/rtp2httpd.git" \
    >> feeds.conf.default

echo ">>> 自定义 Feeds 添加完成"


# ─────────────────────────────────────────────
# msd_lite
# ─────────────────────────────────────────────

echo ">>> 加入 msd_lite..."

git clone --depth=1 \
    https://github.com/ximiTech/msd_lite \
    package/msd_lite

echo ">>> msd_lite 已加入"


# ─────────────────────────────────────────────
# IPTV 管理插件
# ─────────────────────────────────────────────

echo ">>> 加入 luci-app-iptv-manager..."

if [ -d "${GITHUB_WORKSPACE}/custom-packages/luci-app-iptv-manager" ]; then

    cp -r \
        "${GITHUB_WORKSPACE}/custom-packages/luci-app-iptv-manager" \
        package/luci-app-iptv-manager

    echo ">>> luci-app-iptv-manager 已加入"

else

    echo "[WARN] custom-packages/luci-app-iptv-manager 不存在"
    echo "[WARN] 跳过 IPTV Manager"

fi


# ─────────────────────────────────────────────
# OpenClash
# ─────────────────────────────────────────────

echo ">>> 加入 OpenClash..."

git clone --depth=1 \
    https://github.com/vernesong/OpenClash.git \
    /tmp/OpenClash

if [ -d "/tmp/OpenClash/luci-app-openclash" ]; then

    cp -r \
        /tmp/OpenClash/luci-app-openclash \
        package/

    echo ">>> OpenClash 已加入"

else

    echo "[WARN] OpenClash LuCI 目录不存在"

fi

rm -rf /tmp/OpenClash


# ─────────────────────────────────────────────
# SongLoft
# ─────────────────────────────────────────────

echo ">>> 加入 SongLoft..."

git clone --depth=1 \
    https://github.com/songloft-org/songloft-for-router.git \
    /tmp/songloft-for-router

if [ -d "/tmp/songloft-for-router/openwrt/songloft" ]; then

    cp -r \
        /tmp/songloft-for-router/openwrt/songloft \
        package/songloft

fi

if [ -d "/tmp/songloft-for-router/openwrt/luci-app-songloft" ]; then

    cp -r \
        /tmp/songloft-for-router/openwrt/luci-app-songloft \
        package/luci-app-songloft

fi

rm -rf /tmp/songloft-for-router

echo ">>> SongLoft 已加入"


# ─────────────────────────────────────────────
# luci-app-webdav
# ─────────────────────────────────────────────

echo ">>> 加入 luci-app-webdav..."

git clone --depth=1 \
    -b openwrt-24.10 \
    https://github.com/sbwml/luci-app-webdav.git \
    package/luci-app-webdav

echo ">>> luci-app-webdav 已加入"


# ─────────────────────────────────────────────
# RE-SP-01B：
# 扩展原厂 32MB SPI-NOR 可用固件空间
#
# 注意：
# 这个修改与 Linux 内核版本无关。
# 因此继续保留。
# ─────────────────────────────────────────────

echo ""
echo "========================================"
echo " RE-SP-01B 分区检查"
echo "========================================"

DTS="target/linux/ramips/dts/mt7621_jdcloud_re-sp-01b.dts"
MK="target/linux/ramips/image/mt7621.mk"

if [ "${DEVICE:-}" = "re-sp-01b" ]; then

    if [ ! -f "$DTS" ]; then

        echo "[WARN] DTS 不存在：$DTS"
        echo "[WARN] 跳过 RE-SP-01B 分区修改"

    elif [ ! -f "$MK" ]; then

        echo "[WARN] MK 不存在：$MK"
        echo "[WARN] 跳过 RE-SP-01B 分区修改"

    else

        python3 << 'PYEOF'

import re
import os

DTS = 'target/linux/ramips/dts/mt7621_jdcloud_re-sp-01b.dts'
MK  = 'target/linux/ramips/image/mt7621.mk'


# ─────────────────────────────────────────────
# DTS
# ─────────────────────────────────────────────

print(">>> 检查 RE-SP-01B DTS...")

with open(DTS, 'r', encoding='utf-8') as f:
    src = f.read()

orig = src

# firmware 分区扩大到完整 32MB 可用空间
src = src.replace(
    'reg = <0x50000 0x1ab0000>',
    'reg = <0x50000 0x1fb0000>'
)

# 删除 mini 分区
src = re.sub(
    r'\n\s*partition@1b00000\s*\{[^}]*\}\s*;',
    '',
    src,
    flags=re.DOTALL
)

# 删除 OEM 分区
src = re.sub(
    r'\n\s*partition@1f00000\s*\{[^}]*\}\s*;',
    '',
    src,
    flags=re.DOTALL
)

if src != orig:

    with open(DTS, 'w', encoding='utf-8') as f:
        f.write(src)

    print("  ✓ DTS 分区已经扩展")

else:

    print("  [OK] DTS 无需修改")


# ─────────────────────────────────────────────
# mt7621.mk
# ─────────────────────────────────────────────

print(">>> 检查 RE-SP-01B IMAGE_SIZE...")

with open(MK, 'r', encoding='utf-8') as f:
    src = f.read()

orig = src

new = re.sub(
    r'(define Device/jdcloud_re-sp-01b.*?^endef)',
    lambda m:
        m.group(0).replace(
            'IMAGE_SIZE := 27328k',
            'IMAGE_SIZE := 32448k'
        ),
    src,
    flags=re.DOTALL | re.MULTILINE
)

if new != orig:

    with open(MK, 'w', encoding='utf-8') as f:
        f.write(new)

    print("  ✓ IMAGE_SIZE：27328k → 32448k")

else:

    print("  [OK] IMAGE_SIZE 无需修改")


print(">>> RE-SP-01B 分区处理完成")

PYEOF

    fi

else

    echo ">>> 当前设备不是 RE-SP-01B"
    echo ">>> 跳过 RE-SP-01B 分区修改"

fi


# ─────────────────────────────────────────────
# 不再进行 Linux 6.18 WED patch 暴力删除
#
# 原来的 Fix-1 已取消。
#
# 原因：
# 当前使用 LEDE master，
# 内核版本应该由 LEDE target 自己决定。
#
# 不应该再删除：
# target/linux/mediatek/patches-6.18/
# 中的 941~949 patch。
# ─────────────────────────────────────────────

echo ""
echo ">>> 跳过历史 Linux 6.18 WED patch 清理"
echo ">>> 使用 LEDE 当前 target/kernel 组合"


# ─────────────────────────────────────────────
# 不再强制修改 QMI WWAN 驱动源码
#
# 原来的 Fix-3 已取消。
#
# 原因：
# 不能因为旧的 6.17/6.18 编译错误，
# 永久修改当前 LEDE / QModem WWAN 驱动源码。
#
# 当前内核由 LEDE 自己选择。
# 如果真正出现 QMI 编译错误，再针对实际错误修复。
# ─────────────────────────────────────────────

echo ">>> 跳过历史 QMI WWAN 源码兼容补丁"


# ─────────────────────────────────────────────
# 不再修改 crypto.mk
#
# 原来的 Fix-4 针对 Linux 6.18.49+
# libpoly1305.ko 打包问题。
#
# 当前不预先修改 LEDE crypto.mk。
# 如果当前稳定内核真实出现该问题，
# 再根据实际日志进行精确修复。
# ─────────────────────────────────────────────

echo ">>> 跳过历史 libpoly1305.ko 补丁"


# ─────────────────────────────────────────────
# 完成
# ─────────────────────────────────────────────

echo ""
echo "========================================"
echo " ✅ DIY Part 1 完成"
echo "========================================"

echo ""
echo "=== 当前 feeds.conf.default ==="
echo ""

cat feeds.conf.default

echo ""
echo "========================================"
echo " 自定义软件包检查"
echo "========================================"

[ -d package/msd_lite ] && \
    echo "  ✓ msd_lite"

[ -d package/luci-app-iptv-manager ] && \
    echo "  ✓ luci-app-iptv-manager"

[ -d package/luci-app-openclash ] && \
    echo "  ✓ luci-app-openclash"

[ -d package/songloft ] && \
    echo "  ✓ songloft"

[ -d package/luci-app-songloft ] && \
    echo "  ✓ luci-app-songloft"

[ -d package/luci-app-webdav ] && \
    echo "  ✓ luci-app-webdav"

echo ""
echo "========================================"
echo " DIY Part 1 全部完成"
echo "========================================"
