#!/usr/bin/env python3
"""
tools/check-workflow.py

校验并自动修复 GitHub Actions 工作流 YAML。

覆盖两类问题：
  1. YAML 语法错误（会导致 yaml.safe_load 抛异常）
  2. run: | / run: > 块内缩进不一致
     —— 内容行和注释行都检查
     —— GitHub Actions 编辑器会对不一致缩进画红线，
        但 YAML 解析器不会报错，因此必须单独处理

用法：
    python3 tools/check-workflow.py <file.yml>           # 只检查
    python3 tools/check-workflow.py <file.yml> --fix     # 检查并修复

退出码：
    0 = 有效或已成功修复
    1 = 仍有错误无法修复
    2 = 文件不存在或环境错误
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


RUN_BLOCK_RE = re.compile(r'^(\s*)run:\s*[|>][-+]?\s*$')
STEP_START_RE = re.compile(r'^(\s*)-\s+(name|uses|id|if|with|env|shell|working-directory|continue-on-error|timeout-minutes|run)\s*:')
KEY_LINE_RE = re.compile(r'^(\s*)([A-Za-z_][\w\-]*)\s*:')


# ---------- 基础 ----------

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


def leading_spaces(line):
    return len(line) - len(line.lstrip(' '))


# ---------- 找到所有 run 块 ----------

def find_run_blocks(lines):
    """
    返回 [(start_idx, base_indent), ...]
    start_idx: 'run: |' 所在行的索引
    base_indent: 'run:' 前导空格数
    """
    blocks = []
    for i, line in enumerate(lines):
        m = RUN_BLOCK_RE.match(line)
        if m:
            blocks.append((i, len(m.group(1))))
    return blocks


def find_block_end(lines, start_idx, base_indent):
    """
    从 start_idx 之后找到 run 块的结束行索引（不含）。
    结束条件：出现缩进 <= base_indent 的非空行
    """
    i = start_idx + 1
    while i < len(lines):
        line = lines[i]
        if line.strip() == '':
            i += 1
            continue
        if leading_spaces(line) <= base_indent:
            return i
        i += 1
    return len(lines)


# ---------- 规范 run 块缩进 ----------

def normalize_run_block(lines, start_idx, base_indent):
    """
    将 run 块内所有非空行的缩进统一为 base_indent + 2。
    - 内容行和注释行都处理
    - 空行保留
    返回 (changed, notes)
    """
    want = base_indent + 2
    end = find_block_end(lines, start_idx, base_indent)

    changed = False
    notes = []
    for i in range(start_idx + 1, end):
        line = lines[i]
        if line.strip() == '':
            continue
        cur = leading_spaces(line)
        if cur != want:
            lines[i] = ' ' * want + line.lstrip(' ')
            changed = True
            notes.append(
                f"   • 行 {i + 1}: 缩进 {cur} -> {want}"
            )
    return changed, notes


def normalize_all_run_blocks(content):
    lines = content.split('\n')
    blocks = find_run_blocks(lines)

    any_changed = False
    all_notes = []
    # 从后往前改，避免索引失效
    for start_idx, base in reversed(blocks):
        changed, notes = normalize_run_block(lines, start_idx, base)
        if changed:
            any_changed = True
            all_notes = notes + all_notes

    return '\n'.join(lines), any_changed, all_notes


# ---------- YAML 语法修复（局部） ----------

def apply_one_fix(content):
    ok, _, err_line = parse_status(content)
    if ok:
        return content, False, "文件已经是有效的 YAML"
    if err_line is None:
        return content, False, "无法定位错误行"

    lines = content.split('\n')
    if err_line >= len(lines):
        return content, False, f"错误行 {err_line} 越界"

    # 找 err_line 上方最近的 run 块
    target_block = None
    for start_idx, base in find_run_blocks(lines):
        if start_idx < err_line:
            target_block = (start_idx, base)
        else:
            break

    if target_block is None:
        return content, False, f"第 {err_line + 1} 行有错误，上方没有 run 块"

    changed, _ = normalize_run_block(lines, target_block[0], target_block[1])
    if not changed:
        return content, False, f"第 {err_line + 1} 行附近无可修复内容"

    return '\n'.join(lines), True, f"修正第 {err_line + 1} 行附近 run 块缩进"


def fix_all(content, max_passes=200):
    notes = []

    # 第一步：规范化所有 run 块（包含注释行）
    content, changed, notes1 = normalize_all_run_blocks(content)
    if changed:
        notes.append(">>> 规范化 run 块缩进")
        notes.extend(notes1)

    # 第二步：若仍有 YAML 语法错误，逐次修复
    for _ in range(max_passes):
        ok, _, _ = parse_status(content)
        if ok:
            return content, True, notes
        new_content, c, msg = apply_one_fix(content)
        if not c or new_content == content:
            notes.append(f"   • {msg}")
            break
        content = new_content
        notes.append(f"   • {msg}")

    ok, err, err_line = parse_status(content)
    if ok:
        return content, True, notes

    if err_line is not None:
        notes.append(f"   • 仍无法修复，问题在第 {err_line + 1} 行")
    if err:
        notes.append(f"   • {err.splitlines()[0]}")
    return content, False, notes


# ---------- 主流程 ----------

def print_error_context(content, err_line):
    lines = content.split('\n')
    lo = max(0, err_line - 3)
    hi = min(len(lines), err_line + 4)
    for i in range(lo, hi):
        marker = ">>>" if i == err_line else "   "
        print(f"   {marker} {i + 1:4d} | {lines[i]}")


def main():
    parser = argparse.ArgumentParser(
        description="校验并自动修复 GitHub Actions 工作流 YAML"
    )
    parser.add_argument("file", help="要处理的 YAML 文件")
    parser.add_argument("--fix", action="store_true",
                        help="自动修复缩进和语法问题")
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

    # 检测 run 块是否需要规范化
    _, need_norm, _ = normalize_all_run_blocks(content)

    if ok and not need_norm:
        print("✅ YAML 语法正确，run 块缩进一致")
        return 0

    if not ok:
        print("❌ YAML 语法错误")
        if err_line is not None:
            print(f"   位置：第 {err_line + 1} 行")
            print_error_context(content, err_line)
        if err:
            first_line = err.splitlines()[0] if err else "未知错误"
            print(f"   详情：{first_line}")

    if need_norm:
        print("⚠️ run 块内缩进不一致（GitHub 编辑器会画红线）")

    print()

    if not args.fix:
        print("提示：加上 --fix 参数可尝试自动修复")
        return 1

    print("正在尝试自动修复...")
    fixed, success, notes = fix_all(content)
    for msg in notes:
        print(msg)
    print()

    ok2, err2, err_line2 = parse_status(fixed)
    _, need_norm2, _ = normalize_all_run_blocks(fixed)

    if not ok2 or need_norm2:
        print("❌ 修复后仍存在问题")
        if not ok2 and err2:
            print(f"   {err2.splitlines()[0]}")
        if err_line2 is not None:
            print_error_context(fixed, err_line2)
        return 1

    path.write_text(fixed, encoding="utf-8", newline="\n")
    print("✅ 修复成功，文件已写入")
    return 0


if __name__ == "__main__":
    sys.exit(main())
