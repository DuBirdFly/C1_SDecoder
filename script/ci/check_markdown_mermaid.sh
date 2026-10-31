#!/usr/bin/env bash
# Markdown 里的 Mermaid 围栏块语法检查: 用 mermaid-check 逐块 parse, 不需要浏览器
#
# 用法: script/ci/check_markdown_mermaid.sh [路径...]
#
# 路径不给就查全仓库 git 跟踪的 md; 没有 mermaid 块的 md 会被跳过
#
# 退出码: 0 = 通过; 1 = 有块语法错误; 2 = 工具缺失, 文件读不到或用法错误

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
ci_need mermaid-check "见 .agents/skills/markdown-check/SKILL.md"
ci_require_or_exit
ci_versions node

ci_collect .md "${PATHS[@]}"
if ((${#CI_FILES[@]} == 0)); then
    ci_log "没有 md 文件, 跳过"
    exit 0
fi

ci_log "mermaid-check -> ${#CI_FILES[@]} 个 md"
mermaid-check "${CI_FILES[@]}"
