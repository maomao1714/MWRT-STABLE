#!/bin/bash
set -e

URL="https://raw.githubusercontent.com/maomao1714/MWRT-STABLE/refs/tags/stable-wh3000pro-latest-6/diy-part2.sh"
INPUT="diy-part2-stable-wh3000pro-latest-6-original.sh"
OUTPUT="diy-part2-stable-wh3000pro-latest-6-no-wifi-wh3000-wh3000pro.sh"

echo "=============================================="
echo " DONGZAI DIY2 WiFi 自动删减工具"
echo "=============================================="
echo "源文件：stable-wh3000pro-latest-6/diy-part2.sh"
echo ""

if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 "$URL" -o "$INPUT"
elif command -v wget >/dev/null 2>&1; then
    wget -O "$INPUT" "$URL"
else
    echo "❌ 未找到 curl 或 wget"
    exit 1
fi

echo ">>> 已下载原始 DIY2：$INPUT"

cp "$INPUT" "$OUTPUT"

python3 - "$OUTPUT" <<'PY'
import re
import sys

path = sys.argv[1]

with open(path, "r", encoding="utf-8") as f:
    s = f.read()

patterns = [
    r"""(?ms)^[ \t]*mkdir -p files/etc/uci-defaults\n[ \t]*\n[ \t]*cat > files/etc/uci-defaults/20-wifi-wh3000 << 'EOF'\n.*?^[ \t]*EOF\n[ \t]*\n[ \t]*chmod \+x files/etc/uci-defaults/20-wifi-wh3000\n""",
    r"""(?ms)^[ \t]*mkdir -p files/etc/uci-defaults\n[ \t]*\n[ \t]*cat > files/etc/uci-defaults/20-wifi-wh3000pro << 'EOF'\n.*?^[ \t]*EOF\n[ \t]*\n[ \t]*chmod \+x files/etc/uci-defaults/20-wifi-wh3000pro\n""",
]

counts = []
for p in patterns:
    s, n = re.subn(p, "", s, count=1)
    counts.append(n)

if counts != [1, 1]:
    raise SystemExit(
        f"❌ 删除目标数量异常：WH3000={counts[0]}，WH3000 Pro={counts[1]}"
    )

# 安全校验：RE-SP-01B 和其它关键功能必须仍然存在。
required = [
    "20-wifi-resp01b",
    "30-docker",
    "files/etc/init.d/msd_lite",
    "SongLoft",
    "QModem",
    "最终配置检查",
]

for item in required:
    if item not in s:
        raise SystemExit(f"❌ 安全校验失败，缺少关键内容：{item}")

if "20-wifi-wh3000 <<" in s:
    raise SystemExit("❌ WH3000 WiFi 脚本仍然存在")
if "20-wifi-wh3000pro <<" in s:
    raise SystemExit("❌ WH3000 Pro WiFi 脚本仍然存在")

with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write(s)

print("")
print("==============================================")
print(" ✅ 处理完成")
print("==============================================")
print("已删除：")
print("  1. WH3000 20-wifi-wh3000")
print("  2. WH3000 Pro 20-wifi-wh3000pro")
print("")
print("已保留：")
print("  ✓ RE-SP-01B WiFi")
print("  ✓ Docker")
print("  ✓ fstab")
print("  ✓ QModem")
print("  ✓ SongLoft")
print("  ✓ MSD Lite / RTP2HTTPD")
print("  ✓ 最终配置检查")
print("")
print("最终文件：", path)
PY

chmod +x "$OUTPUT"

echo ""
echo "=============================================="
echo " 输出文件：$OUTPUT"
echo "=============================================="
echo "请把 OUTPUT 文件作为新的 diy-part2.sh 使用。"
