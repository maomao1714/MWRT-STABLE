#!/bin/bash

DEVICE="${DEVICE:-wh3000pro}"

echo "========================================"
echo " DONGZAI 固件工厂 - DIY Part 2"
echo " 当前设备：$DEVICE"
echo "========================================"

mkdir -p files/etc/uci-defaults files/etc/config files/etc/init.d


# ════════════════════════════════════════════════════════════
# QModem Next
#
# 使用最新 QModem + luci-app-qmodem-next
#
# 不再使用旧版：
#   luci-app-qmodem
#   luci-app-qmodem-sms
#   luci-app-qmodem-ttl
#
# sms-forwarder-next 如果依赖 qmodem-sipd，
# 由 make defconfig 自动解决依赖。
# ════════════════════════════════════════════════════════════

echo ">>> [QModem] 配置最新 QModem Next..."

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
# QModem
# ============================================================

# QModem 核心
CONFIG_PACKAGE_qmodem=y

# 最新 QModem Next LuCI
CONFIG_PACKAGE_luci-app-qmodem-next=y

# SMS 转发
CONFIG_PACKAGE_sms-forwarder-next=y

# Quectel 5G/4G 拨号组件
CONFIG_PACKAGE_quectel-CM-5G-M=y

# 明确关闭旧版 QModem LuCI
# CONFIG_PACKAGE_luci-app-qmodem is not set

# 明确关闭旧版 SMS / TTL
# CONFIG_PACKAGE_luci-app-qmodem-sms is not set
# CONFIG_PACKAGE_luci-app-qmodem-ttl is not set

# 不主动强制 sipd
# 如果 sms-forwarder-next 需要，由依赖自动选入
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
# OpenVPN
#
# 不再修改 OpenVPN 源码。
#
# 当前 LEDE 使用什么 OpenVPN / DCO 组合，
# 交给当前源码和 make defconfig 自动处理。
#
# 原来的 Linux 6.18.49 专用 DCO 修复已经删除。
# ════════════════════════════════════════════════════════════

echo ">>> [OpenVPN] 保持 LEDE 当前 OpenVPN 配置"
echo ">>> [OpenVPN] 不再修改 feeds/packages/net/openvpn"


# ════════════════════════════════════════════════════════════
# 通用设置
# ════════════════════════════════════════════════════════════

case "$DEVICE" in
  wh3000)
    HOSTNAME="WH3000"
    ;;
  wh3000pro)
    HOSTNAME="WH3000-Pro"
    ;;
  re-sp-01b)
    HOSTNAME="RE-SP-01B"
    ;;
  *)
    HOSTNAME="MWRT"
    ;;
esac


cat > files/etc/uci-defaults/01-system << EOF
#!/bin/sh

uci set system.@system[0].hostname='${HOSTNAME}'
uci set system.@system[0].timezone='CST-8'
uci set system.@system[0].zonename='Asia/Shanghai'

uci commit system

exit 0
EOF

chmod +x files/etc/uci-defaults/01-system

echo ">>> [1] 主机名：${HOSTNAME}"


# ════════════════════════════════════════════════════════════
# LuCI Design 主题
# ════════════════════════════════════════════════════════════

if [ -f package/lean/default-settings/files/zzz-default-settings ]; then

    sed -i \
      's/luci-theme-bootstrap/luci-theme-design/g' \
      package/lean/default-settings/files/zzz-default-settings

fi

echo ">>> [2] 默认主题修改完成"


# ════════════════════════════════════════════════════════════
# Lucky 权限修复
# ════════════════════════════════════════════════════════════

find . -type f -name "lucky*" \
  -exec chmod +x {} \; \
  2>/dev/null || true

echo ">>> [3] Lucky 权限修复完成"


# ════════════════════════════════════════════════════════════
# SongLoft
# 修复 SongLoft 启动脚本
# ════════════════════════════════════════════════════════════

echo ">>> [3.5] 修复 SongLoft 启动脚本..."

cat > files/etc/init.d/songloft << 'EOF'
#!/bin/sh /etc/rc.common
# SPDX-License-Identifier: GPL-2.0-only

START=99
STOP=10
USE_PROCD=1

PROG_DEFAULT=/usr/bin/songloft
WEB_DEFAULT=/usr/share/songloft/web-embedded
DB_DEFAULT=/etc/songloft/data
MUSIC_DEFAULT=/mnt/sda1/music

LOGGER="logger -t songloft"


start_instance() {

    local cfg="$1"

    local enabled
    local listen_port
    local db_path
    local base_path
    local admin_username
    local admin_password
    local bin_path
    local web_path
    local music_dir

    config_get_bool enabled "$cfg" "enabled" "0"
    config_get listen_port "$cfg" "listen_port" "58091"
    config_get db_path "$cfg" "db_path" "$DB_DEFAULT"
    config_get base_path "$cfg" "base_path" ""
    config_get admin_username "$cfg" "admin_username" ""
    config_get admin_password "$cfg" "admin_password" ""
    config_get bin_path "$cfg" "bin_path" "$PROG_DEFAULT"
    config_get web_path "$cfg" "web_path" "$WEB_DEFAULT"
    config_get music_dir "$cfg" "music_dir" "$MUSIC_DEFAULT"

    [ "$enabled" = "1" ] || return 0

    if [ ! -x "$bin_path" ]; then
        ${LOGGER} "未找到可执行文件: $bin_path"
        return 1
    fi

    mkdir -p "$db_path"

    if [ -d "$music_dir" ]; then

        if [ ! -e "$web_path/music" ]; then
            ln -sf "$music_dir" "$web_path/music"
            ${LOGGER} \
              "已创建软链接: $web_path/music -> $music_dir"
        fi

        if [ ! -e "$db_path/music" ]; then
            ln -sf "$music_dir" "$db_path/music"
            ${LOGGER} \
              "已创建软链接: $db_path/music -> $music_dir"
        fi

    fi

    procd_open_instance "songloft.$cfg"

    procd_set_param command "$bin_path"

    procd_set_param env \
      LISTEN_PORT="$listen_port"

    procd_set_param env \
      DB_PATH="$db_path"

    procd_set_param env \
      WEB_ROOT="$web_path"

    procd_set_param env \
      MUSIC_DIR="$music_dir"

    procd_set_param cwd "$web_path"

    [ -n "$base_path" ] && \
      procd_append_param env BASE_PATH="$base_path"

    [ -n "$admin_username" ] && \
      procd_append_param env ADMIN_USERNAME="$admin_username"

    [ -n "$admin_password" ] && \
      procd_append_param env ADMIN_PASSWORD="$admin_password"

    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1

    procd_close_instance
}


start_service() {

    config_load songloft

    config_foreach start_instance songloft
}


stop_service() {
    :
}


service_triggers() {
    procd_add_reload_trigger "songloft"
}


reload_service() {
    stop
    start
}

EOF

chmod +x files/etc/init.d/songloft

echo ">>> [3.5] SongLoft 启动脚本修复完成"


# ════════════════════════════════════════════════════════════
# SongLoft LuCI 增强
# ════════════════════════════════════════════════════════════

echo ">>> [3.6] 修改 luci-app-songloft..."

LUCI_SONGLOFT_DIR="package/luci-app-songloft"

if [ -d "$LUCI_SONGLOFT_DIR" ]; then

    FOUND=0

    for file in $(grep -rl \
        --include="*.lua" \
        'Map("songloft"' \
        "$LUCI_SONGLOFT_DIR" \
        2>/dev/null); do

        echo "  ✓ 找到并覆盖: $file"

        cat > "$file" << 'EOF'
local m, s, o

m = Map("songloft",
        translate("SongLoft 音乐服务"),
        translate("SongLoft 是一款轻量级自建音乐服务，支持本地音乐管理、网络歌曲、电台及歌单等功能。"))

local is_running =
    (luci.sys.call("pidof songloft >/dev/null 2>&1") == 0)

s = m:section(
    TypedSection,
    "songloft",
    translate("基础设置")
)

s.anonymous = true


o = s:option(
    DummyValue,
    "_status",
    translate("服务状态")
)

o.rawhtml = true

if is_running then

    o.value =
        '<span style="color: green; font-weight: bold;">SongLoft 运行中</span> ' ..
        '<a href="http://192.168.1.1:58091" target="_blank" ' ..
        'class="btn cbi-button cbi-button-apply" ' ..
        'style="padding: 5px 15px;">打开管理界面</a>'

else

    o.value =
        '<span style="color: red; font-weight: bold;">SongLoft 未运行</span>'

end


o = s:option(
    Flag,
    "enabled",
    translate("启用")
)

o.rmempty = false


o = s:option(
    Value,
    "listen_port",
    translate("监听端口")
)

o.datatype = "port"
o.default = "58091"


o = s:option(
    Value,
    "db_path",
    translate("数据目录")
)

o.default = "/etc/songloft/data"

o.description =
    translate("SongLoft 的工作目录，用于存放数据库及音乐索引")


o = s:option(
    Value,
    "music_dir",
    translate("音乐库目录（绝对路径）")
)

o.default = "/mnt/sda1/music"
o.rmempty = false

o.description =
    translate("例如 /mnt/sda1/music，确保路径存在且可读")


o = s:option(
    Value,
    "base_path",
    translate("URL 基础路径")
)

o.rmempty = true


o = s:option(
    Value,
    "admin_username",
    translate("管理员用户名")
)

o.rmempty = true


o = s:option(
    Value,
    "admin_password",
    translate("管理员密码")
)

o.password = true
o.rmempty = true


o = s:option(
    Value,
    "bin_path",
    translate("程序路径")
)

o.default = "/usr/bin/songloft"
o.rmempty = true


o = s:option(
    Value,
    "web_path",
    translate("Web 界面目录")
)

o.default = "/usr/share/songloft/web-embedded"
o.rmempty = true


function m.on_after_commit(self)

    luci.sys.call(
        "/etc/init.d/songloft restart >/dev/null 2>&1"
    )

    luci.sys.exec("sleep 1")

end


return m

EOF

        FOUND=1

    done


    if [ "$FOUND" -eq 0 ]; then

        echo "  ⚠️ 未找到原始 config.lua，在 root/ 中创建..."

        mkdir -p \
          "$LUCI_SONGLOFT_DIR/root/usr/lib/lua/luci/model/cbi/songloft"

        cat > \
          "$LUCI_SONGLOFT_DIR/root/usr/lib/lua/luci/model/cbi/songloft/config.lua" \
          << 'EOF'

local m, s, o

m = Map(
    "songloft",
    translate("SongLoft 音乐服务"),
    translate("SongLoft 是一款轻量级自建音乐服务，支持本地音乐管理、网络歌曲、电台及歌单等功能。")
)

local is_running =
    (luci.sys.call("pidof songloft >/dev/null 2>&1") == 0)

s = m:section(
    TypedSection,
    "songloft",
    translate("基础设置")
)

s.anonymous = true


o = s:option(
    DummyValue,
    "_status",
    translate("服务状态")
)

o.rawhtml = true

if is_running then

    o.value =
        '<span style="color: green; font-weight: bold;">SongLoft 运行中</span> ' ..
        '<a href="http://192.168.1.1:58091" target="_blank" ' ..
        'class="btn cbi-button cbi-button-apply" ' ..
        'style="padding: 5px 15px;">打开管理界面</a>'

else

    o.value =
        '<span style="color: red; font-weight: bold;">SongLoft 未运行</span>'

end


o = s:option(
    Flag,
    "enabled",
    translate("启用")
)

o.rmempty = false


o = s:option(
    Value,
    "listen_port",
    translate("监听端口")
)

o.datatype = "port"
o.default = "58091"


o = s:option(
    Value,
    "db_path",
    translate("数据目录")
)

o.default = "/etc/songloft/data"


o = s:option(
    Value,
    "music_dir",
    translate("音乐库目录（绝对路径）")
)

o.default = "/mnt/sda1/music"
o.rmempty = false


o = s:option(
    Value,
    "base_path",
    translate("URL 基础路径")
)

o.rmempty = true


o = s:option(
    Value,
    "admin_username",
    translate("管理员用户名")
)

o.rmempty = true


o = s:option(
    Value,
    "admin_password",
    translate("管理员密码")
)

o.password = true
o.rmempty = true


o = s:option(
    Value,
    "bin_path",
    translate("程序路径")
)

o.default = "/usr/bin/songloft"
o.rmempty = true


o = s:option(
    Value,
    "web_path",
    translate("Web 界面目录")
)

o.default = "/usr/share/songloft/web-embedded"
o.rmempty = true


function m.on_after_commit(self)

    luci.sys.call(
        "/etc/init.d/songloft restart >/dev/null 2>&1"
    )

    luci.sys.exec("sleep 1")

end


return m

EOF

    fi

    echo ">>> [3.6] SongLoft LuCI 增强完成"

else

    echo "  ⚠️ 找不到 $LUCI_SONGLOFT_DIR"
    echo "  跳过 SongLoft LuCI 修改"

fi


# ════════════════════════════════════════════════════════════
# SongLoft 编译缓存清理
# ════════════════════════════════════════════════════════════

echo ">>> [3.7] 清理 SongLoft 编译缓存..."

find build_dir \
    -maxdepth 3 \
    -name "luci-app-songloft*" \
    -exec rm -rf {} + \
    2>/dev/null || true

find staging_dir \
    -maxdepth 3 \
    -name "luci-app-songloft*" \
    -exec rm -rf {} + \
    2>/dev/null || true

find tmp \
    -maxdepth 2 \
    -name "luci-app-songloft*" \
    -exec rm -rf {} + \
    2>/dev/null || true

echo ">>> [3.7] SongLoft 缓存清理完成"


# ════════════════════════════════════════════════════════════
# BBR / fq_codel
# ════════════════════════════════════════════════════════════

cat > files/etc/sysctl.conf << 'EOF'
net.core.default_qdisc=fq_codel
net.ipv4.tcp_congestion_control=bbr
EOF

echo ">>> [8] BBR / fq_codel 优化完成"


# ════════════════════════════════════════════════════════════
# MSD Lite / RTP2HTTPD
#
# type=0：
#   msd_lite
#
# type=1：
#   rtp2httpd
#
# 保留原来的双后端设计。
# ════════════════════════════════════════════════════════════

cat > files/etc/config/msd_lite << 'EOF'
config msd_lite 'config'
	option enable '0'
	option type '0'
	option source 'eth0'
	option port '7088'
	option threads '0'
	option buffer '16384'
	option rejointime '0'
EOF

echo ">>> [9-1] msd_lite UCI 配置写入完成"


cat > files/etc/init.d/msd_lite << 'INITEOF'
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1


start_service() {

    local enable
    local type
    local port
    local source
    local threads
    local buffer
    local rejointime
    local PROG

    config_load "msd_lite"

    config_get_bool \
        enable \
        "config" \
        "enable" \
        "0"

    [ "$enable" -eq 1 ] || return 0

    config_get \
        type \
        "config" \
        "type" \
        "0"

    config_get \
        port \
        "config" \
        "port" \
        "7088"

    config_get \
        source \
        "config" \
        "source" \
        "eth0"

    config_get \
        threads \
        "config" \
        "threads" \
        "0"

    config_get \
        buffer \
        "config" \
        "buffer" \
        "16384"

    config_get \
        rejointime \
        "config" \
        "rejointime" \
        "0"


    mkdir -p /var/etc


    if [ "$type" = "0" ]; then

        PROG="/usr/bin/msd_lite"

        cat > /var/etc/msd_lite.conf << XMLEOF
<?xml version="1.0" encoding="utf-8"?>

<msd>

  <log>
    <file>/var/log/msd_lite.log</file>
  </log>

  <threadPool>
    <threadsCountMax>${threads}</threadsCountMax>
    <fBindToCPU>yes</fBindToCPU>
  </threadPool>

  <HTTP>

    <bindList>
      <bind>
        <address>0.0.0.0:${port}</address>
      </bind>

      <bind>
        <address>[::]:${port}</address>
      </bind>
    </bindList>

    <hostnameList>
      <hostname>*</hostname>
    </hostnameList>

  </HTTP>

  <hubProfileList>

    <hubProfile>

      <fDropSlowClients>no</fDropSlowClients>

      <fSocketTCPNoDelay>yes</fSocketTCPNoDelay>

      <precache>${buffer}</precache>

      <ringBufSize>1024</ringBufSize>

      <headersList>

        <header>Pragma: no-cache</header>

        <header>Content-Type: video/mpeg</header>

      </headersList>

    </hubProfile>

  </hubProfileList>

  <sourceProfileList>

    <sourceProfile>

      <skt>
        <rcvBuf>512</rcvBuf>
        <rcvTimeout>2</rcvTimeout>
      </skt>

      <multicast>

        <ifName>${source}</ifName>

        <rejoinTime>${rejointime}</rejoinTime>

      </multicast>

    </sourceProfile>

  </sourceProfileList>

</msd>

XMLEOF

    else

        PROG="/usr/bin/rtp2httpd"

        cat > /var/etc/msd_lite.conf << RTPEOF

[global]

verbosity = 3

upstream-interface = ${source}

workers = ${threads}

buffer-pool-max-size = ${buffer}

mcast-rejoin-interval = ${rejointime}

zerocopy-on-send = yes


[bind]

* ${port}

RTPEOF

    fi


    procd_open_instance

    procd_set_param \
        command \
        "$PROG" \
        -c \
        /var/etc/msd_lite.conf

    procd_set_param respawn

    procd_set_param stderr 1

    procd_close_instance

}


reload_service() {

    stop
    start

}


service_triggers() {

    procd_add_reload_trigger "msd_lite"

}

INITEOF

chmod +x files/etc/init.d/msd_lite

echo ">>> [9-2] msd_lite 双后端 init.d 写入完成"
# ════════════════════════════════════════════════════════════
# 设备专属设置
# ════════════════════════════════════════════════════════════

case "$DEVICE" in

    # ════════════════════════════════════════════════════════
    # WH3000
    # ════════════════════════════════════════════════════════

    wh3000)

        echo ">>> [10] 应用 WH3000 专属配置..."

        # ----------------------------------------------------
        # MT7981 WiFi
        #
        # 不再下载旧版 OpenWrt v24.10.5
        # netifd-wireless.sh
        #
        # 直接使用当前 LEDE 自带的 wifi-scripts。
        # ----------------------------------------------------



        # ----------------------------------------------------
        # eMMC Docker 数据目录
        # ----------------------------------------------------

        cat > files/etc/uci-defaults/30-docker << 'EOF'
#!/bin/sh

mkdir -p /mnt/mmcblk0p7
mkdir -p /mnt/mmcblk0p7/docker

# 如果 dockerd 已安装，则设置数据目录
if uci -q get dockerd.globals >/dev/null 2>&1; then

    uci -q set dockerd.globals.data_root='/mnt/mmcblk0p7/docker'
    uci commit dockerd

fi

if [ -x /etc/init.d/dockerd ]; then

    /etc/init.d/dockerd enable

fi

exit 0

EOF

        chmod +x files/etc/uci-defaults/30-docker


        # ----------------------------------------------------
        # fstab
        # ----------------------------------------------------

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


        # ----------------------------------------------------
        # Banner
        # ----------------------------------------------------

        cat > files/etc/banner << 'EOF'
====================================================
        DONGZAI 固件工厂 · WH3000
====================================================
Platform : MediaTek MT7981
Arch     : ARM64
Firmware : LEDE
====================================================
EOF


        echo ">>> [10] WH3000 专属配置完成"

        ;;


    # ════════════════════════════════════════════════════════
    # WH3000 PRO
    # ════════════════════════════════════════════════════════

    wh3000pro)

        echo ">>> [11] 应用 WH3000 Pro 专属配置..."

        # ----------------------------------------------------
        # MT7981 WiFi
        # ----------------------------------------------------



        # ----------------------------------------------------
        # eMMC Docker 数据目录
        # ----------------------------------------------------

        cat > files/etc/uci-defaults/30-docker << 'EOF'
#!/bin/sh

mkdir -p /mnt/mmcblk0p7
mkdir -p /mnt/mmcblk0p7/docker

if uci -q get dockerd.globals >/dev/null 2>&1; then

    uci -q set dockerd.globals.data_root='/mnt/mmcblk0p7/docker'

    uci commit dockerd

fi

if [ -x /etc/init.d/dockerd ]; then

    /etc/init.d/dockerd enable

fi

exit 0

EOF

        chmod +x files/etc/uci-defaults/30-docker


        # ----------------------------------------------------
        # fstab
        # ----------------------------------------------------

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


        # ----------------------------------------------------
        # Banner
        # ----------------------------------------------------

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


    # ════════════════════════════════════════════════════════
    # RE-SP-01B
    # ════════════════════════════════════════════════════════

    re-sp-01b)

        echo ">>> [12] 应用 RE-SP-01B 专属配置..."


        # ----------------------------------------------------
        # WiFi
        # ----------------------------------------------------

        mkdir -p files/etc/uci-defaults

        cat > files/etc/uci-defaults/20-wifi-resp01b << 'EOF'
#!/bin/sh

# 等待无线驱动初始化
count=0

while [ "$count" -lt 20 ]; do

    if [ -d /sys/class/ieee80211/phy0 ]; then
        break
    fi

    sleep 1

    count=$((count + 1))

done


# 如果无线配置不存在，则自动生成
if [ ! -s /etc/config/wireless ]; then

    wifi config

fi


# 2.4G
if uci -q get wireless.radio0 >/dev/null 2>&1; then

    uci -q set wireless.radio0.disabled='0'

    uci -q set wireless.default_radio0.ssid='RE-SP-01B'

    uci -q set wireless.default_radio0.encryption='psk2'

fi


# 5G
if uci -q get wireless.radio1 >/dev/null 2>&1; then

    uci -q set wireless.radio1.disabled='0'

    uci -q set wireless.default_radio1.ssid='RE-SP-01B_5G'

    uci -q set wireless.default_radio1.encryption='psk2'

fi


uci commit wireless

exit 0

EOF

        chmod +x files/etc/uci-defaults/20-wifi-resp01b


        # ----------------------------------------------------
        # Banner
        # ----------------------------------------------------

        cat > files/etc/banner << 'EOF'
====================================================
       DONGZAI 固件工厂 · JDCloud RE-SP-01B
====================================================
Platform : MediaTek MT7621
Arch     : MIPS
Firmware : LEDE
====================================================
EOF


        echo ">>> [12] RE-SP-01B 专属配置完成"

        ;;


    *)
        echo "[WARN] 未识别设备：$DEVICE"
        ;;

esac


# ════════════════════════════════════════════════════════════
# 最终配置检查
# ════════════════════════════════════════════════════════════

echo ""
echo "========================================"
echo " DONGZAI DIY Part 2 最终检查"
echo "========================================"


# ------------------------------------------------------------
# QModem 检查
# ------------------------------------------------------------

echo ""
echo ">>> QModem 配置检查..."

grep -E \
    '^CONFIG_PACKAGE_(qmodem|luci-app-qmodem|sms-forwarder-next|quectel-CM-5G-M)' \
    .config || true


# ------------------------------------------------------------
# 确认旧版 QModem 没有被主动启用
# ------------------------------------------------------------

if grep -q '^CONFIG_PACKAGE_luci-app-qmodem=y' .config; then

    echo "❌ ERROR：检测到旧版 luci-app-qmodem"

    exit 1

fi


if grep -q '^CONFIG_PACKAGE_luci-app-qmodem-sms=y' .config; then

    echo "❌ ERROR：检测到旧版 luci-app-qmodem-sms"

    exit 1

fi


if grep -q '^CONFIG_PACKAGE_luci-app-qmodem-ttl=y' .config; then

    echo "❌ ERROR：检测到旧版 luci-app-qmodem-ttl"

    exit 1

fi


echo ">>> [OK] QModem Next 架构检查通过"


# ------------------------------------------------------------
# 检查历史 6.18 WED 强制删除是否存在
# ------------------------------------------------------------

if grep -R \
    -E \
    'patches-6\.18.*(941|942|943|944|945|946|947|948|949)' \
    diy-part1.sh \
    diy-part2.sh \
    2>/dev/null; then

    echo "❌ ERROR：检测到旧版 6.18 WED 修复逻辑"

    exit 1

fi

echo ">>> [OK] 未发现历史 WED 强制删除逻辑"


# ------------------------------------------------------------
# 检查旧 OpenWrt 24.10.5 wifi-scripts 下载
# ------------------------------------------------------------

if grep -R \
    -F \
    'openwrt/openwrt/v24.10.5/package/network/config/wifi-scripts' \
    diy-part1.sh \
    diy-part2.sh \
    2>/dev/null; then

    echo "❌ ERROR：检测到旧版 v24.10.5 wifi-scripts 下载逻辑"

    exit 1

fi

echo ">>> [OK] 未发现旧版 v24.10.5 wifi-scripts 下载"


# ------------------------------------------------------------
# 检查 OpenVPN DCO 强制源码修改
# ------------------------------------------------------------

if grep -E \
    -n \
    'ovpn-dco|ENABLE_DCO|disable.*DCO' \
    diy-part1.sh \
    diy-part2.sh \
    2>/dev/null; then

    echo "⚠️ 检测到 OpenVPN DCO 相关文字。"
    echo "⚠️ 如果只是注释/检查信息则继续。"

fi


# ------------------------------------------------------------
# WH3000 / WH3000 Pro
# ------------------------------------------------------------

if [ "$DEVICE" = "wh3000" ] || [ "$DEVICE" = "wh3000pro" ]; then

    echo ""
    echo ">>> MT7981 WiFi 检查..."

    grep -E \
        '^CONFIG_PACKAGE_(kmod-mac80211|kmod-cfg80211|kmod-mt76-core|kmod-mt76-connac|kmod-mt7915e|kmod-mt7981-firmware|mt7981-wo-firmware|wireless-regdb|iwinfo|rpcd-mod-iwinfo)=' \
        .config || true

    echo ""
    echo ">>> 检查 LEDE 当前 wifi-scripts..."

    if [ -f \
        package/network/config/wifi-scripts/files/lib/netifd/netifd-wireless.sh \
    ]; then

        echo ">>> [OK] 当前 LEDE wifi-scripts 存在"

    else

        echo "⚠️ 当前源码中未找到 netifd-wireless.sh"

    fi

fi


# ------------------------------------------------------------
# RE-SP-01B
# ------------------------------------------------------------

if [ "$DEVICE" = "re-sp-01b" ]; then

    echo ""
    echo ">>> RE-SP-01B 配置检查..."

    grep -E \
        '^CONFIG_TARGET_ramips_mt7621_DEVICE_jdcloud_re-sp-01b=y' \
        .config || true

    echo ">>> [OK] RE-SP-01B 检查完成"

fi


# ------------------------------------------------------------
# IPTV
# ------------------------------------------------------------

echo ""
echo ">>> IPTV / MSD / RTP2HTTPD 检查..."

[ -d package/msd_lite ] && \
    echo "  ✓ msd_lite"

[ -d package/luci-app-iptv-manager ] && \
    echo "  ✓ luci-app-iptv-manager"

[ -d feeds/rtp2httpd ] && \
    echo "  ✓ rtp2httpd feed"


# ------------------------------------------------------------
# Docker
# ------------------------------------------------------------

if [ "$DEVICE" = "wh3000" ] || [ "$DEVICE" = "wh3000pro" ]; then

    echo ""
    echo ">>> Docker 配置检查..."

    grep -E \
        '^CONFIG_PACKAGE_(dockerd|docker|docker-compose|luci-app-dockerman)=' \
        .config || true

fi


# ------------------------------------------------------------
# 自定义软件包
# ------------------------------------------------------------

echo ""
echo ">>> 自定义软件包检查..."

[ -d package/msd_lite ] && \
    echo "  ✓ msd_lite"

[ -d package/luci-app-iptv-manager ] && \
    echo "  ✓ luci-app-iptv-manager"

[ -d package/luci-app-openclash ] && \
    echo "  ✓ OpenClash"

[ -d package/songloft ] && \
    echo "  ✓ SongLoft"

[ -d package/luci-app-songloft ] && \
    echo "  ✓ luci-app-songloft"

[ -d package/luci-app-webdav ] && \
    echo "  ✓ WebDAV"


# ════════════════════════════════════════════════════════════
# 完成
# ════════════════════════════════════════════════════════════

echo ""
echo "========================================"
echo " ✅ DIY Part 2 全部完成"
echo "========================================"
echo " 当前设备 : $DEVICE"
echo " QModem   : qmodem + luci-app-qmodem-next"
echo " SMS      : sms-forwarder-next"
echo " 拨号工具 : quectel-CM-5G-M"
echo " IPTV     : msd_lite + rtp2httpd"
echo " WiFi     : 当前 LEDE"
echo " OpenVPN  : 当前 LEDE 原生配置"
echo "========================================"
