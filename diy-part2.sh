# ════════════════════════════════════════════════════════════
# QModem Next
#
# 目标：
# 1. 使用最新 QModem Next
# 2. 保留 QModem 核心拨号
# 3. 自动识别中国运营商 APN
# 4. 支持中国移动 / 联通 / 电信 / 广电
#
# 已验证的关键问题：
# Fibocom + MediaTek 平台中，
# modem_dial.sh 的 APN 自动填充逻辑原本被
# pdp_index=3 条件限制。
#
# WH3000 Pro 实际 pdp_index 可能为 0，
# 导致 APN 为空，自动拨号失败。
#
# 本补丁在 pdp_index 判断之前：
#   读取 IMSI
#   判断 MCC-MNC
#   自动填写 APN
# ════════════════════════════════════════════════════════════

echo ">>> [QModem] 配置最新 QModem Next..."

if [ ! -f .config ]; then
    echo "❌ ERROR：.config 不存在，无法修改 QModem"
    exit 1
fi

sed -i \
  -e '/^CONFIG_PACKAGE_qmodem=/d' \
  -e '/^CONFIG_PACKAGE_luci-app-qmodem=/d' \
  -e '/^CONFIG_PACKAGE_luci-app-qmodem-next=/d' \
  -e '/^CONFIG_PACKAGE_qmodem-sipd=/d' \
  -e '/^CONFIG_PACKAGE_qmodem-voip=/d' \
  -e '/^CONFIG_PACKAGE_luci-app-qmodem-sms=/d' \
  -e '/^CONFIG_PACKAGE_luci-app-qmodem-ttl=/d' \
  -e '/^CONFIG_PACKAGE_sms-forwarder-next=/d' \
  -e '/^CONFIG_PACKAGE_quectel-CM-5G-M=/d' \
  .config

cat >> .config << 'EOF'

# ============================================================
# QModem Next
# ============================================================

CONFIG_PACKAGE_qmodem=y
CONFIG_PACKAGE_luci-app-qmodem-next=y
CONFIG_PACKAGE_sms-forwarder-next=y
CONFIG_PACKAGE_quectel-CM-5G-M=y

# 明确关闭旧版
# CONFIG_PACKAGE_luci-app-qmodem is not set
# CONFIG_PACKAGE_luci-app-qmodem-sms is not set
# CONFIG_PACKAGE_luci-app-qmodem-ttl is not set

# sipd 由依赖自动解决
# CONFIG_PACKAGE_qmodem-sipd is not set

# 暂不启用 VOIP
# CONFIG_PACKAGE_qmodem-voip is not set

EOF

echo ">>> [QModem] 配置完成"

echo ">>> [QModem] 当前配置："

grep -E \
  '^CONFIG_PACKAGE_(qmodem|luci-app-qmodem|sms-forwarder-next|quectel-CM-5G-M)' \
  .config || true


# ════════════════════════════════════════════════════════════
# QModem APN 自动识别
# ════════════════════════════════════════════════════════════

echo ">>> [QModem] 开始安装 APN 自动识别补丁..."

if [ -d feeds ] || [ -d package ]; then

    _MODEM_DIAL=$(find feeds package \
        -path "*/qmodem/files/usr/share/qmodem/modem_dial.sh" \
        2>/dev/null | head -1)

else

    _MODEM_DIAL=""

fi


if [ -z "$_MODEM_DIAL" ]; then

    echo "❌ ERROR：没有找到 modem_dial.sh"
    echo "    无法安装 QModem APN 自动识别补丁"
    exit 1

fi


echo ">>> [QModem] 找到：$_MODEM_DIAL"


if ! command -v python3 >/dev/null 2>&1; then

    echo "❌ ERROR：系统没有 python3"
    echo "    无法安全修改 modem_dial.sh"
    exit 1

fi


# ------------------------------------------------------------
# 防止重复打补丁
# ------------------------------------------------------------

if grep -q "auto_detect_apn()" "$_MODEM_DIAL"; then

    echo ">>> [QModem] 已经存在 APN 自动识别函数"
    echo ">>> [QModem] 跳过重复修改"

else

    cat > /tmp/patch_modem_dial.py << 'PYEOF'

import sys

path = sys.argv[1]


FUNC = r'''
# ============================================================
# DONGZAI QModem APN 自动识别
# ============================================================

auto_detect_apn() {

    local at_port="$1"
    local imsi
    local mcc_mnc
    local apn
    local operator

    imsi=$(cmd_dial_command "$at_port" "AT+CIMI" \
        | grep -oE '[0-9]{14,15}' \
        | head -1)

    if [ -z "$imsi" ]; then

        m_debug \
            "auto_apn: IMSI读取失败，fallback cmnet"

        echo "cmnet"

        return

    fi


    mcc_mnc=$(echo "$imsi" | cut -c1-5)


    case "$mcc_mnc" in

        # 中国移动
        46000|46002|46007|46008)

            apn="cmnet"
            operator="中国移动"

            ;;

        # 中国联通
        46001|46006|46009)

            apn="3gnet"
            operator="中国联通"

            ;;

        # 中国电信
        46003|46005|46011)

            apn="ctnet"
            operator="中国电信"

            ;;

        # 中国广电
        46015)

            apn="cbnet"
            operator="中国广电"

            ;;

        # 未知运营商
        *)

            apn="cmnet"
            operator="未知运营商"

            m_debug \
                "auto_apn: 未知MCC-MNC=$mcc_mnc，fallback cmnet"

            ;;

    esac


    m_debug \
        "auto_apn: imsi=$imsi mcc_mnc=$mcc_mnc operator=$operator apn=$apn"


    echo "$apn"

}

# ============================================================
'''


APN_CHECK = r'''
                    # DONGZAI：
                    # APN 为 auto 或为空时自动识别
                    if [ "$apn" = "auto" ] || [ -z "$apn" ]; then
                        apn=$(auto_detect_apn "$at_port")
                    fi
'''


with open(path, "r") as f:

    content = f.read()


# ------------------------------------------------------------
# 1. 插入 auto_detect_apn()
# ------------------------------------------------------------

anchor1 = "at_dial()\n"

if anchor1 not in content:

    print(
        "ERROR: at_dial() 未找到",
        file=sys.stderr
    )

    sys.exit(2)


content = content.replace(
    anchor1,
    FUNC + anchor1,
    1
)


# ------------------------------------------------------------
# 2. 在 pdp_index=3 判断之前插入 APN 自动检测
# ------------------------------------------------------------

anchors = [
    'if [ "$pdp_index" = "3" ];then\n',
    'if [ "$pdp_index" = "3" ]; then\n',
]


found = False


for anchor2 in anchors:

    if anchor2 in content:

        content = content.replace(
            anchor2,
            APN_CHECK + anchor2,
            1
        )

        found = True

        break


if not found:

    print(
        "ERROR: pdp_index=3 判断未找到",
        file=sys.stderr
    )

    sys.exit(3)


# ------------------------------------------------------------
# 写回
# ------------------------------------------------------------

with open(path, "w") as f:

    f.write(content)


print(
    "APN AUTO PATCH OK:",
    path
)

PYEOF


    python3 \
        /tmp/patch_modem_dial.py \
        "$_MODEM_DIAL"


    rm -f /tmp/patch_modem_dial.py


fi


echo ">>> [QModem] APN 自动识别补丁完成"

# ----------------------------------------------------
# WH3000 PRO
# ----------------------------------------------------

wh3000pro)

    echo ">>> [11] 应用 WH3000 Pro 专属配置..."


    mkdir -p \
        files/etc/uci-defaults \
        files/etc/config


    # ====================================================
    # WiFi
    #
    # 重要：
    # 不再强制指定：
    #
    # platform/soc/18000000.wifi
    # platform/soc/18000000.wifi+1
    #
    # 交给当前 LEDE / wifi-scripts 自动识别。
    #
    # 这是 stable-wh3000pro-latest-7 已经实机验证
    # 可以正常默认启动 WiFi 的方案。
    # ====================================================

    cat > files/etc/uci-defaults/20-wifi-wh3000pro << 'EOF'

#!/bin/sh

# ====================================================
# WH3000 Pro WiFi 默认启动
#
# 不硬编码 radio path
# 不覆盖 LEDE wifi-scripts
# ====================================================


# 如果系统没有 wireless 配置，
# 让当前 LEDE 自己生成。
if [ ! -s /etc/config/wireless ]; then

    wifi config

fi


# ====================================================
# 2.4G
# ====================================================

if uci -q get wireless.radio0 >/dev/null 2>&1; then

    uci -q set wireless.radio0.disabled='0'

    uci -q set \
        wireless.default_radio0.ssid='Camera_mao'

    uci -q set \
        wireless.default_radio0.encryption='psk2'

fi


# ====================================================
# 5G
# ====================================================

if uci -q get wireless.radio1 >/dev/null 2>&1; then

    uci -q set wireless.radio1.disabled='0'

    uci -q set \
        wireless.default_radio1.ssid='栋仔_5G'

    uci -q set \
        wireless.default_radio1.encryption='psk2'

fi


uci commit wireless

exit 0

EOF


    chmod +x \
        files/etc/uci-defaults/20-wifi-wh3000pro


    # ====================================================
    # Docker
    # ====================================================

    cat > files/etc/uci-defaults/30-docker << 'EOF'

#!/bin/sh

mkdir -p /mnt/mmcblk0p7

mkdir -p /mnt/mmcblk0p7/docker


if uci -q get dockerd.globals >/dev/null 2>&1; then

    uci -q set \
        dockerd.globals.data_root='/mnt/mmcblk0p7/docker'

    uci commit dockerd

fi


if [ -x /etc/init.d/dockerd ]; then

    /etc/init.d/dockerd enable

fi


exit 0

EOF


    chmod +x \
        files/etc/uci-defaults/30-docker


    # ====================================================
    # eMMC
    # ====================================================

    cat > files/etc/config/fstab << 'EOF'

config global automount
    option from_fstab '1'
    option anon_mount '1'

config global autoswap
    option from_fstab '1'
    option anon_swap '0'

config mount
    option target '/mnt/mmcblk0p7'
    option device '/dev/mmcblk0p7'
    option fstype 'ext4'
    option options 'rw,sync'
    option enabled '1'
    option enabled_fsck '0'

EOF


    # ====================================================
    # Banner
    # ====================================================

    cat > files/etc/banner << 'EOF'

====================================================
 DONGZAI 固件工厂 · Huasifei WH3000 Pro
====================================================
 Platform : MediaTek MT7981
 Arch     : ARM64
 Firmware : LEDE
====================================================

EOF


    echo ">>> [11] WH3000 Pro 专属配置完成"

    ;;
# ============================================================
# QModem APN 自动识别最终检查
# ============================================================

echo ""
echo ">>> QModem APN 自动识别最终检查..."


if [ -z "$_MODEM_DIAL_CHECK" ]; then

    if [ -d feeds ] || [ -d package ]; then

        _MODEM_DIAL_CHECK=$(find feeds package \
            -path "*/qmodem/files/usr/share/qmodem/modem_dial.sh" \
            2>/dev/null | head -1)

    fi

fi


if [ -z "$_MODEM_DIAL_CHECK" ]; then

    echo "❌ ERROR：最终检查没有找到 modem_dial.sh"

    exit 1

fi


echo ">>> 检查文件：$_MODEM_DIAL_CHECK"


# ------------------------------------------------------------
# 1. auto_detect_apn
# ------------------------------------------------------------

if ! grep -q "auto_detect_apn()" \
    "$_MODEM_DIAL_CHECK"; then

    echo "❌ ERROR：缺少 auto_detect_apn()"

    exit 1

fi


# ------------------------------------------------------------
# 2. AT+CIMI
# ------------------------------------------------------------

if ! grep -q 'AT+CIMI' \
    "$_MODEM_DIAL_CHECK"; then

    echo "❌ ERROR：缺少 AT+CIMI IMSI 检测"

    exit 1

fi


# ------------------------------------------------------------
# 3. APN 调用
# ------------------------------------------------------------

if ! grep -q \
    'apn=$(auto_detect_apn "$at_port")' \
    "$_MODEM_DIAL_CHECK"; then

    echo "❌ ERROR：没有找到 APN 自动调用逻辑"

    exit 1

fi


# ------------------------------------------------------------
# 4. 中国移动
# ------------------------------------------------------------

if ! grep -q '46000|46002|46007|46008' \
    "$_MODEM_DIAL_CHECK"; then

    echo "❌ ERROR：中国移动 MCC-MNC 映射缺失"

    exit 1

fi


if ! grep -q 'apn="cmnet"' \
    "$_MODEM_DIAL_CHECK"; then

    echo "❌ ERROR：中国移动 cmnet 映射缺失"

    exit 1

fi


# ------------------------------------------------------------
# 5. 中国联通
# ------------------------------------------------------------

if ! grep -q '46001|46006|46009' \
    "$_MODEM_DIAL_CHECK"; then

    echo "❌ ERROR：中国联通 MCC-MNC 映射缺失"

    exit 1

fi


if ! grep -q 'apn="3gnet"' \
    "$_MODEM_DIAL_CHECK"; then

    echo "❌ ERROR：中国联通 3gnet 映射缺失"

    exit 1

fi


# ------------------------------------------------------------
# 6. 中国电信
# ------------------------------------------------------------

if ! grep -q '46003|46005|46011' \
    "$_MODEM_DIAL_CHECK"; then

    echo "❌ ERROR：中国电信 MCC-MNC 映射缺失"

    exit 1

fi


if ! grep -q 'apn="ctnet"' \
    "$_MODEM_DIAL_CHECK"; then

    echo "❌ ERROR：中国电信 ctnet 映射缺失"

    exit 1

fi


# ------------------------------------------------------------
# 7. 中国广电
# ------------------------------------------------------------

if ! grep -q '46015' \
    "$_MODEM_DIAL_CHECK"; then

    echo "❌ ERROR：中国广电 46015 映射缺失"

    exit 1

fi


if ! grep -q 'apn="cbnet"' \
    "$_MODEM_DIAL_CHECK"; then

    echo "❌ ERROR：中国广电 cbnet 映射缺失"

    exit 1

fi


echo ">>> [OK] QModem APN 自动识别完整检查通过"

echo ">>> [OK] 中国移动  → cmnet"
echo ">>> [OK] 中国联通  → 3gnet"
echo ">>> [OK] 中国电信  → ctnet"
echo ">>> [OK] 中国广电  → cbnet"
