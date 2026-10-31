#!/usr/bin/env bash
# WaveDrom 描述 (*.json5) 检查: 先用 wavedrom 渲染一遍, 再查结构自洽与标签重叠
#
# 用法: script/ci/check_wavedrom.sh [路径...]
#
# 波形图查: 各行拍数 / "|" 对齐 / data 个数 / node 长度 / edge 引用 / 电平毛刺 / 标签重叠
# 位域图 (reg) 没有 lane 概念, 只查能不能渲染和标签有没有压在一起
# 导出 SVG 直接用实体: node script/ci/check-wavedrom.mjs -o <out.svg> <file.json5>
#
# 退出码: 0 = 通过; 1 = 渲染 / 结构 / 标签重叠有问题; 2 = 工具缺失或用法错误

set -uo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh" || exit 2

PATHS=()
while (($#)); do
    case $1 in
        -h|--help) ci_usage; exit 0 ;;
        -*)        ci_err "未知选项: $1"; ci_usage >&2; exit 2 ;;
        *)         PATHS+=("$1") ;;
    esac
    shift
done

ci_enter_repo PATHS || exit 2
ci_need node "装 Node.js 20+"
# WAVEDROM 可以指到另一份命令行, 与 check-wavedrom.mjs 里的同名环境变量一致
if [ -n "${WAVEDROM:-}" ]; then
    [ -x "$WAVEDROM" ] || { ci_err "WAVEDROM 指向的不是可执行文件: $WAVEDROM"; exit 2; }
else
    ci_need wavedrom "npm i -g wavedrom@3.7.0"
fi
ci_require_or_exit
ci_versions node

ci_collect .json5 "${PATHS[@]}"
if ((${#CI_FILES[@]} == 0)); then
    ci_log "没有 json5 文件, 跳过"
    exit 0
fi

ci_log "check-wavedrom -> ${#CI_FILES[@]} 个文件"
node "$CI_ROOT/script/ci/check-wavedrom.mjs" "${CI_FILES[@]}"
