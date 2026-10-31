#!/usr/bin/env bash
# Python 规范检查: ruff check + ruff format --check, 规则集 .config/ruff.toml
#
# 用法: script/ci/check_python_ruff.sh [--fix] [路径...]
#
# 路径不给就查整个仓库; --fix 是本地动作 (check --fix + format), CI 不带
# 一律带 --no-cache, 不往工作区留 .ruff_cache/
#
# 退出码: 0 = 通过; 1 = 有违规; 2 = 工具缺失或用法错误

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
ci_need ruff "pipx install ruff==0.16.8"
ci_require_or_exit
ci_versions ruff

((${#PATHS[@]})) || PATHS=(".")
ARGS=(--config "$CI_CONFIG/ruff.toml" --no-cache)
STATUS=0
if ((FIX)); then
    ci_log "ruff check --fix + ruff format -> ${PATHS[*]}"
    ruff check --fix "${ARGS[@]}" "${PATHS[@]}" || STATUS=$?
    ruff format "${ARGS[@]}" "${PATHS[@]}" || STATUS=$?
else
    ci_log "ruff check + ruff format --check -> ${PATHS[*]}"
    ruff check "${ARGS[@]}" "${PATHS[@]}" || STATUS=$?
    ruff format --check "${ARGS[@]}" "${PATHS[@]}" || STATUS=$?
fi
exit "$STATUS"
