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
#
# 新方案：
#
# 不再编译：
#   songloft-org/songloft.git
#
# 不再使用：
#   songloft-2.11.3.tar.xz
#   cf3e19842080...
#
# 改为：
#   1. 从作者仓库只获取 luci-app-songloft
#   2. 官方 Releases 获取最新 ARM64 完整版二进制
#   3. 官方 checksums.txt 校验
#   4. 创建 package/songloft
#   5. 保留原来的 songloft.init / songloft.config
#
# WH3000 / WH3000 Pro：
#   MT7981 ARM64
#   使用 songloft-linux-arm64
#
# RE-SP-01B：
#   MT7621 MIPS
#   不安装 SongLoft
# ─────────────────────────────────────────────

echo ""
echo "========================================"
echo " SongLoft 官方最新二进制版"
echo "========================================"

SONGLOFT_ROUTER_DIR="/tmp/songloft-for-router"
SONGLOFT_PKG_DIR="package/songloft"

case "${DEVICE:-}" in

    wh3000|wh3000pro)

        echo ">>> 当前设备：${DEVICE}"
        echo ">>> 架构：ARM64"
        echo ">>> 使用官方最新完整版：songloft-linux-arm64"

        # ─────────────────────────────────────
        # 拉取官方 router 仓库
        #
        # 这里只获取 LuCI 插件和官方 init/config。
        # 不再复制作者的 package/songloft，
        # 避免进入旧的 2.11.3 Git 编译流程。
        # ─────────────────────────────────────

        rm -rf "$SONGLOFT_ROUTER_DIR"

        git clone --depth=1 \
            https://github.com/songloft-org/songloft-for-router.git \
            "$SONGLOFT_ROUTER_DIR"

        # ─────────────────────────────────────
        # 加入 LuCI 插件
        # ─────────────────────────────────────

        if [ -d "$SONGLOFT_ROUTER_DIR/openwrt/luci-app-songloft" ]; then

            cp -r \
                "$SONGLOFT_ROUTER_DIR/openwrt/luci-app-songloft" \
                package/luci-app-songloft

            echo ">>> luci-app-songloft 已加入"

        else

            echo "[ERROR] 找不到 luci-app-songloft"
            exit 1

        fi

        # ─────────────────────────────────────
        # 创建新的二进制 SongLoft package
        # ─────────────────────────────────────

        rm -rf "$SONGLOFT_PKG_DIR"

        mkdir -p \
            "$SONGLOFT_PKG_DIR/files" \
            "$SONGLOFT_PKG_DIR/files/usr/bin" \
            "$SONGLOFT_PKG_DIR/files/etc/init.d" \
            "$SONGLOFT_PKG_DIR/files/etc/config"

        # ─────────────────────────────────────
        # 保留作者官方 init/config
        #
        # 这样 LuCI 和启动逻辑仍然沿用作者方案。
        # ─────────────────────────────────────

        if [ -f "$SONGLOFT_ROUTER_DIR/openwrt/songloft/files/songloft.init" ]; then

            cp \
                "$SONGLOFT_ROUTER_DIR/openwrt/songloft/files/songloft.init" \
                "$SONGLOFT_PKG_DIR/files/etc/init.d/songloft"

        else

            echo "[ERROR] 找不到官方 songloft.init"
            exit 1

        fi

        if [ -f "$SONGLOFT_ROUTER_DIR/openwrt/songloft/files/songloft.config" ]; then

            cp \
                "$SONGLOFT_ROUTER_DIR/openwrt/songloft/files/songloft.config" \
                "$SONGLOFT_PKG_DIR/files/etc/config/songloft"

        else

            echo "[ERROR] 找不到官方 songloft.config"
            exit 1

        fi

        # ─────────────────────────────────────
        # 下载官方最新 ARM64 完整版
        #
        # 官方：
        # https://github.com/songloft-org/songloft
        #
        # latest/download 会自动指向最新 Release。
        # ─────────────────────────────────────

        SONGLOFT_BIN_URL="https://github.com/songloft-org/songloft/releases/latest/download/songloft-linux-arm64"
        SONGLOFT_CHECKSUM_URL="https://github.com/songloft-org/songloft/releases/latest/download/checksums.txt"

        SONGLOFT_BIN="$SONGLOFT_PKG_DIR/files/usr/bin/songloft"
        SONGLOFT_CHECKSUMS="/tmp/songloft-checksums.txt"

        echo ">>> 下载官方最新 SongLoft ARM64..."

        if command -v curl >/dev/null 2>&1; then

            curl -fL \
                --retry 5 \
                --retry-delay 3 \
                --connect-timeout 20 \
                --max-time 300 \
                "$SONGLOFT_BIN_URL" \
                -o "$SONGLOFT_BIN"

            curl -fL \
                --retry 5 \
                --retry-delay 3 \
                --connect-timeout 20 \
                --max-time 120 \
                "$SONGLOFT_CHECKSUM_URL" \
                -o "$SONGLOFT_CHECKSUMS"

        elif command -v wget >/dev/null 2>&1; then

            wget \
                --tries=5 \
                --timeout=30 \
                -O "$SONGLOFT_BIN" \
                "$SONGLOFT_BIN_URL"

            wget \
                --tries=5 \
                --timeout=30 \
                -O "$SONGLOFT_CHECKSUMS" \
                "$SONGLOFT_CHECKSUM_URL"

        else

            echo "[ERROR] 系统没有 curl 或 wget"
            exit 1

        fi

        # ─────────────────────────────────────
        # 检查二进制文件
        # ─────────────────────────────────────

        if [ ! -s "$SONGLOFT_BIN" ]; then

            echo "[ERROR] SongLoft ARM64 二进制下载失败"
            exit 1

        fi

        echo ">>> SongLoft ARM64 下载成功"

        # ─────────────────────────────────────
        # 官方 SHA256 校验
        # ─────────────────────────────────────

        echo ">>> 校验官方 SongLoft SHA256..."

        SONGLOFT_EXPECTED_SHA256="$(
            grep 'songloft-linux-arm64$' "$SONGLOFT_CHECKSUMS" \
                | awk '{print $1}' \
                | head -n 1
        )"

        if [ -z "$SONGLOFT_EXPECTED_SHA256" ]; then

            echo "[ERROR] checksums.txt 中找不到 songloft-linux-arm64"
            echo ">>> checksums.txt 内容："
            cat "$SONGLOFT_CHECKSUMS"
            exit 1

        fi

        SONGLOFT_ACTUAL_SHA256="$(
            sha256sum "$SONGLOFT_BIN" \
                | awk '{print $1}'
        )"

        echo ">>> 官方 SHA256：$SONGLOFT_EXPECTED_SHA256"
        echo ">>> 实际 SHA256：$SONGLOFT_ACTUAL_SHA256"

        if [ "$SONGLOFT_EXPECTED_SHA256" != "$SONGLOFT_ACTUAL_SHA256" ]; then

            echo "[ERROR] SongLoft SHA256 校验失败"
            exit 1

        fi

        echo ">>> SongLoft SHA256 校验通过"

        # ─────────────────────────────────────
        # 设置可执行权限
        # ─────────────────────────────────────

        chmod 0755 "$SONGLOFT_BIN"

        # ─────────────────────────────────────
        # 创建二进制版 package/songloft/Makefile
        #
        # 注意：
        # 包名仍然叫 songloft。
        #
        # 这样现有：
        #   luci-app-songloft
        #
        # 中的：
        #   LUCI_DEPENDS:=+songloft
        #
        # 无需修改。
        # ─────────────────────────────────────

                cat > "$SONGLOFT_PKG_DIR/Makefile" << 'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=songloft
PKG_VERSION:=9999
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=songloft-for-router contributors

include $(INCLUDE_DIR)/package.mk

define Package/songloft
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Songloft official ARM64 binary
  URL:=https://github.com/songloft-org/songloft
  DEPENDS:=+ca-bundle
endef

define Package/songloft/description
  Songloft official prebuilt ARM64 binary.
endef

define Package/songloft/conffiles
/etc/config/songloft
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/songloft/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/songloft $(1)/usr/bin/songloft

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/songloft $(1)/etc/init.d/songloft

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/songloft $(1)/etc/config/songloft
endef

$(eval $(call BuildPackage,songloft))
EOF

        # ─────────────────────────────────────
        # 删除临时源码仓库
        # ─────────────────────────────────────

        rm -rf "$SONGLOFT_ROUTER_DIR"
        rm -f "$SONGLOFT_CHECKSUMS"

        echo ">>> SongLoft 官方最新 ARM64 二进制 package 已准备完成"

        ;;

    re-sp-01b)

        echo ">>> 当前设备：RE-SP-01B"
        echo ">>> 架构：MT7621 / MIPS"
        echo ">>> 官方 SongLoft 当前没有对应 MIPS 二进制"
        echo ">>> 跳过 SongLoft"

        rm -rf \
            package/songloft \
            package/luci-app-songloft

        ;;

    *)

        echo ">>> 当前 DEVICE=${DEVICE:-未设置}"
        echo ">>> 未启用 SongLoft ARM64 二进制"

        rm -rf \
            package/songloft \
            package/luci-app-songloft

        ;;

esac

# ─────────────────────────────────────────────
# SongLoft 最终检查
# ─────────────────────────────────────────────

if [ "${DEVICE:-}" = "wh3000" ] || \
   [ "${DEVICE:-}" = "wh3000pro" ]; then

    echo ""
    echo "========================================"
    echo " SongLoft 最终检查"
    echo "========================================"

    if [ ! -f "package/songloft/Makefile" ]; then
        echo "[ERROR] package/songloft/Makefile 不存在"
        exit 1
    fi

    if [ ! -x "package/songloft/files/usr/bin/songloft" ]; then
        echo "[ERROR] 官方 SongLoft ARM64 二进制不存在或不可执行"
        exit 1
    fi

    if [ ! -f "package/songloft/files/etc/init.d/songloft" ]; then
        echo "[ERROR] songloft.init 不存在"
        exit 1
    fi

    if [ ! -f "package/songloft/files/etc/config/songloft" ]; then
        echo "[ERROR] songloft.config 不存在"
        exit 1
    fi

    if [ ! -d "package/luci-app-songloft" ]; then
        echo "[ERROR] luci-app-songloft 不存在"
        exit 1
    fi

    echo "  ✓ songloft Makefile"
    echo "  ✓ 官方 ARM64 二进制"
    echo "  ✓ songloft init"
    echo "  ✓ songloft config"
    echo "  ✓ luci-app-songloft"

    echo ""
    echo ">>> SongLoft 已切换为官方最新 ARM64 二进制模式"
    echo ">>> 不再编译 songloft 2.11.3 Git 源码"

else

    echo ">>> 当前设备不启用 SongLoft ARM64"

fi

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

if [ "${DEVICE:-}" = "wh3000" ] || \
   [ "${DEVICE:-}" = "wh3000pro" ]; then

    [ -d package/songloft ] && \
        echo "  ✓ songloft（官方最新 ARM64 二进制）"

    [ -d package/luci-app-songloft ] && \
        echo "  ✓ luci-app-songloft"

else

    echo "  - songloft（当前设备不支持，已跳过）"
    echo "  - luci-app-songloft（当前设备不支持，已跳过）"

fi

[ -d package/luci-app-webdav ] && \
    echo "  ✓ luci-app-webdav"

echo ""
echo "========================================"
echo " DIY Part 1 全部完成"
echo "========================================"
