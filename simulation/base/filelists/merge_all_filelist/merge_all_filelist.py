#!/usr/bin/env python3
"""
合并 .f 文件脚本, 递归解析 -f 引用, 输出单个合并后的文件.

用法: python merge_all_filelist.py -top ../all.f [-output merged.f] [-log merge.log]

示例:
    python merge_all_filelist.py -top ../all.f
    python merge_all_filelist.py -top ../all.f -output sim_merged.f -log merge.log
"""

import argparse
import os
import sys


def resolve_f_file(f_path: str, base_dir: str, visited: set, lines_out: list, log_lines: list) -> None:
    """
    递归解析一个 .f 文件, 将其内容展开写入 lines_out.

    Args:
        f_path:   .f 文件路径 (相对于 base_dir 或绝对路径)
        base_dir: 当前 .f 文件所在目录, 用于解析相对路径
        visited:  已访问的 .f 文件绝对路径集合, 用于检测循环引用
        lines_out: 输出行列表
        log_lines: 日志行列表
    """
    # 解析为绝对路径
    if os.path.isabs(f_path):
        abs_path = os.path.normpath(f_path)
    else:
        abs_path = os.path.normpath(os.path.join(base_dir, f_path))

    # 循环引用检测
    if abs_path in visited:
        msg = f"Warning: 检测到循环引用, 跳过 {abs_path}"
        print(msg, file=sys.stderr)
        log_lines.append(msg)
        return

    if not os.path.isfile(abs_path):
        msg = f"Warning: 文件不存在, 跳过 {abs_path}"
        print(msg, file=sys.stderr)
        log_lines.append(msg)
        return

    visited.add(abs_path)
    current_dir = os.path.dirname(abs_path)

    msg = f"解析: {abs_path}"
    print(msg)
    log_lines.append(msg)

    with open(abs_path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()

            # 跳过空行和注释行 (// 和 #)
            if not line or line.startswith(("//", "#")):
                continue

            # 去除行内注释 (// 之后的部分)
            # 注意: 路径中可能含有 //, 这里只处理空格后的 //
            comment_pos = line.find("//")
            if comment_pos > 0 and line[comment_pos - 1] == " ":
                line = line[:comment_pos].strip()

            if not line:
                continue

            # 递归解析 -f 引用
            if line.startswith("-f "):
                ref_path = line[3:].strip()
                lines_out.append(f"// >>> 来自: -f {ref_path}")
                resolve_f_file(ref_path, current_dir, visited, lines_out, log_lines)
                lines_out.append(f"// <<< 结束: -f {ref_path}")
            else:
                # 直接输出该行 (选项, +define, 文件路径等)
                lines_out.append(line)


def main():
    parser = argparse.ArgumentParser(
        description="合并 .f 文件, 递归解析 -f 引用, 输出单个合并文件",
        epilog="示例: python merge_all_filelist.py -top ../all.f -output sim_merged.f -log merge.log",
    )
    parser.add_argument(
        "-top",
        required=True,
        help="顶层 .f 文件 (例如 ../all.f)",
    )
    parser.add_argument(
        "-output",
        default="merged.f",
        help="输出文件名 (默认: merged.f)",
    )
    parser.add_argument(
        "-log",
        default="merge.log",
        help="日志文件名 (可选, 例如 merge.log)",
    )
    args = parser.parse_args()

    # 脚本所在目录即为 merge_all_filelist/
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # 输出文件路径 (放在脚本所在目录 merge_all_filelist/ 下)
    output_path = os.path.join(script_dir, args.output)

    visited: set = set()
    lines_out: list = []
    log_lines: list = []

    resolve_f_file(args.top, script_dir, visited, lines_out, log_lines)

    # 写入输出文件
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("// ================================================\n")
        f.write(f"// 合并自顶层文件: {args.top}\n")
        f.write(f"// 包含以下 .f 文件:\n")
        f.writelines(f"//   {v}\n" for v in sorted(visited))
        f.write("// ================================================\n\n")
        f.writelines(line + "\n" for line in lines_out)

    # 写入日志文件
    if args.log:
        log_path = os.path.join(script_dir, args.log)
        with open(log_path, "w", encoding="utf-8") as f:
            f.write(f"合并日志\n")
            f.write(f"顶层文件: {args.top}\n")
            f.write(f"输出文件: {output_path}\n")
            f.write(f"总行数: {len(lines_out)}\n")
            f.write(f"来源文件数: {len(visited)}\n")
            f.write(f"{'=' * 50}\n\n")
            f.writelines(line + "\n" for line in log_lines)

    summary = f"合并完成! 输出文件: {output_path}, 共 {len(lines_out)} 行, 来自 {len(visited)} 个 *.f 文件"
    print(f"\n{summary}")
    if args.log:
        log_lines.append(summary)


if __name__ == "__main__":
    main()
