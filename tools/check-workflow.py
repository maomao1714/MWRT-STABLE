#!/usr/bin/env python3
"""
tools/check-workflow.py

校验并自动修复 GitHub Actions 工作流 YAML 的缩进问题。

用法：
    python3 tools/check-workflow.py <file.yml>           # 只检查
    python3 tools/check-workflow.py <file.yml> --fix     # 检查并修复

退出码：
    0 = 有效或已成功修复
    1 = 仍有错误无法修复
    2 = 文件不存在
"""

import argparse
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("错误：需要 PyYAML。请运行：pip install pyyaml\n")
    sys.exit(2)


# ---------- YAML 解析 ----------

def parse_status(content):
    try:
        yaml.safe_load(content)
        return True, None, None
    except yaml.YAMLError as e:
        mark = getattr(e, 'problem_mark', None)
        if mark is None:
            mark = getattr(e, 'context_mark', None)
        line = mark.line if mark is not None else None
        return False, str(e), line


# ---------- run 块检测 ----------

RUN_BLOCK_RE = re.compile(r'^(\s*)run:\s*[|>]')


def find_run_block_above(lines, before_idx):
    for i in range(before_idx, -1, -1):
        m = RUN_BLOCK_RE.match(lines[i])
        if m:
            return i, len(m.group(1))
    return None


def is_block_terminator(line, base_indent):
    indent = len(line) - len(line.lstrip())
    if indent > base_indent:
        return False
    s = line.strip()
    if not s:
        return False
    if re.match(r'^-\s+[\w\'"]', s):
        return True
    if indent == base_indent and re.match(r'^[\w\'"\-]+\s*:', s):
        return True
    return False


# ---------- 单次修复 ----------

def apply_one_fix(content):
    ok, _, err_line = parse_status(content)
    if ok:
        return content, False, "文件已经是有效的 YAML"
    if err_line is None:
        return content, False, "无法定位错误行"

    lines = content.split('\n')
    if err_line >= len(lines):
        return content, False, f"错误行 {err_line} 越界"

    block = find_run_block_above(lines, err_line)
    if block is None:
        return content, False, f"第 {err_line + 1} 行有错误，上方没有 run 块"

    start_idx, base = block
    want = base + 2

    changed = False
    i = start_idx + 1
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
            continue
        indent = len(line) - len(line.lstrip())
        if indent > base:
            i += 1
            continue
        if is_block_terminator(line, base):
            break
        if indent < want:
            lines[i] = ' ' * (want - indent) + line
            changed = True
        i += 1

    if not changed:
        return content, False, f"第 {err_line + 1} 行附近没有可修复的缩进"

    return '\n'.join(lines), True, f"修复了第 {err_line + 1} 行附近的缩进"


def fix_all(content, max_passes=100):
    notes = []
    for _ in range(max_passes):
        ok, _, _ = parse_status(content)
        if ok:
            return content, True, notes
        new_content, changed, msg = apply_one_fix(content)
        if not changed or new_content == content:
            notes.append(msg)
            return content, False, notes
        content = new_content
        notes.append(msg)
    notes.append("达到最大修复次数")
    return content, False, notes


# ---------- 主流程 ----------

def main():
    parser = argparse.ArgumentParser(
        description="校验并自动修复 GitHub Actions 工作流 YAML"
    )
    parser.add_argument("file", help="要处理的 YAML 文件")
    parser.add_argument("--fix", action="store_true", help="自动修复缩进问题")
    args = parser.parse_args()

    path = Path(args.file)
    if not path.exists():
        print(f"❌ 文件不存在：{path}")
        return 2

    content = path.read_text(encoding="utf-8")

    print("=" * 64)
    print(f"检查文件：{path}")
    print("=" * 64)

    ok, err, err_line = parse_status(content)

    if ok:
        print("✅ YAML 语法正确")
        return 0

    print("❌ YAML 语法错误")
    if err_line is not None:
        print(f"   位置：第 {err_line + 1} 行")
        lines = content.split("\n")
        lo = max(0, err_line - 3)
        hi = min(len(lines), err_line + 4)
        for i in range(lo, hi):
            marker = ">>>" if i == err_line else "   "
            print(f"   {marker} {i + 1:4d} | {lines[i]}")
    if err:
        first_line = err.splitlines()[0] if err else "未知错误"
        print(f"   详情：{first_line}")
    print()

    if not args.fix:
        print("提示：加上 --fix 参数可尝试自动修复")
        return 1

    print("正在尝试自动修复...")
    fixed, success, notes = fix_all(content)
    for msg in notes:
        print(f"   • {msg}")
    print()

    if not success:
        print("❌ 无法自动修复，请手动检查")
        return 1

    ok2, err2, _ = parse_status(fixed)
    if not ok2:
        print("❌ 修复后仍无法通过校验")
        if err2:
            print(f"   {err2.splitlines()[0]}")
        return 1

    path.write_text(fixed, encoding="utf-8", newline="\n")
    print("✅ 修复成功，文件已写入")
    return 0


if __name__ == "__main__":
    sys.exit(main())
