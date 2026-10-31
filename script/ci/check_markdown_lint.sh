#!/usr/bin/env bash
# Markdown 排版检查: markdownlint-cli2, 规则集 .config/.markdownlint.jsonc
#
# 用法: script/ci/check_markdown_lint.sh [--fix] [路径...]
#
# 路径不给就查全仓库 git 跟踪的 md; --fix 是本地动作, CI 不带
#
# 退出码: 0 = 通过; 1 = 有排版问题; 2 = 工具缺失或用法错误

set -uo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh" || exit 2

FIX=0
PATHS=()
while (($#)); do
    case $1 in
        -h|--help) ci_usage; exit 0 ;;
        --fix)     FIX=1 ;;
        -*)        ci_err "未知选项: $1"; ci_usage >&2; exit 2 ;;
        *)         PATHS+=("$1") ;;
    esac
    shift
done

ci_enter_repo PATHS || exit 2
ci_need markdownlint-cli2 "npm i -g markdownlint-cli2@0.24.0"
ci_require_or_exit
ci_versions markdownlint-cli2

ci_collect .md "${PATHS[@]}"
if ((${#CI_FILES[@]} == 0)); then
    ci_log "没有 md 文件, 跳过"
    exit 0
fi

ARGS=(--config "$CI_CONFIG/.markdownlint.jsonc")
((FIX)) && ARGS+=(--fix)
ci_log "markdownlint-cli2 -> ${#CI_FILES[@]} 个文件"
markdownlint-cli2 "${ARGS[@]}" "${CI_FILES[@]}"
