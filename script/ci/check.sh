#!/usr/bin/env bash
# 仓库静态检查总入口: 本地与 CI 跑同一行命令, 两边口径不会漂移.
# 四个分项都是独立可跑的脚本, 这里只负责选择与汇总.
#
# 用法: script/ci/check.sh [--fix] [子项...] [路径...]
#
# 子项 (省略 = 四项全跑):
#   md       Markdown 排版   -> check_markdown_lint.sh
#   mermaid  Mermaid 语法    -> check_markdown_mermaid.sh
#   py       Python 规范     -> check_python_ruff.sh
#   wave     WaveDrom 波形   -> check_wavedrom.sh
#
# 路径: 给了就只查这些 (文件或目录), 不给就查全仓库 git 跟踪的文件. 路径只能配一个子项.
#
# 例:
#   script/ci/check.sh                      # CI 口径: 全量四项
#   script/ci/check.sh md py                # 只跑排版与 Python
#   script/ci/check.sh md doc/design_plan   # 只查改动目录
#   script/ci/check.sh --fix py             # 本地自动修 (CI 永远不带 --fix)
#
# 退出码: 0 = 全过; 1 = 有检查项失败; 2 = 用法错误或工具缺失

set -uo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh" || exit 2

# 子项名 -> 脚本; ORDER 决定执行与日志顺序
declare -A SCRIPTS=(
    [md]=check_markdown_lint.sh
    [mermaid]=check_markdown_mermaid.sh
    [py]=check_python_ruff.sh
    [wave]=check_wavedrom.sh
)
ORDER=(md mermaid py wave)

FIX=0
ITEMS=()
PATHS=()
while (($#)); do
    case $1 in
        -h|--help) ci_usage; exit 0 ;;
        --fix)     FIX=1 ;;
        -*)        ci_err "未知选项: $1"; ci_usage >&2; exit 2 ;;
        *)
            if [ -n "${SCRIPTS[$1]:-}" ]; then
                if ((${#PATHS[@]} == 0)); then
                    ITEMS+=("$1")
                else
                    ci_err "子项 $1 写在路径后面了: 子项要写在路径前面"
                    exit 2
                fi
            else
                PATHS+=("$1")
            fi
            ;;
    esac
    shift
done

# 去重并按 ORDER 排, 日志顺序固定
GIVEN=${#ITEMS[@]}
if ((${#ITEMS[@]})); then
    PICKED=()
    for name in "${ORDER[@]}"; do
        for got in "${ITEMS[@]}"; do
            if [ "$got" = "$name" ]; then
                PICKED+=("$name")
                break
            fi
        done
    done
    ITEMS=("${PICKED[@]}")
else
    ITEMS=("${ORDER[@]}")
fi

if ((${#PATHS[@]})); then
    if ((GIVEN == 0)); then
        ci_err "给了路径就要指明子项 (md / mermaid / py / wave), 例如: script/ci/check.sh md <路径>"
        exit 2
    fi
    if ((GIVEN > 1)); then
        ci_err "路径只能配一个子项, 多个子项请去掉路径跑全量"
        exit 2
    fi
fi
if ((FIX)); then
    for name in "${ITEMS[@]}"; do
        case $name in
            md|py) ;;
            *) ci_err "$name 没有自动修复, --fix 只对 md / py 有意义"; exit 2 ;;
        esac
    done
fi
ci_enter_repo PATHS || exit 2

CI_STATUS=0
ci_step() {
    local name=$1
    shift
    local status=0
    "$@" || status=$?
    case $status in
        0) ci_log "PASS  $name" ;;
        1) ci_log "FAIL  $name" ;;
        *) ci_log "ERROR $name (退出码 $status)" ;;
    esac
    if [ "$status" -gt "$CI_STATUS" ]; then
        CI_STATUS=$status
    fi
    return 0
}

ci_log "root: $CI_ROOT"
for name in "${ITEMS[@]}"; do
    ARGS=()
    ((FIX)) && ARGS+=(--fix)
    ARGS+=("${PATHS[@]}")
    ci_step "$name" bash "$CI_ROOT/script/ci/${SCRIPTS[$name]}" "${ARGS[@]}"
done

if ((CI_STATUS == 0)); then
    ci_log "全部通过"
else
    ci_log "未通过 (退出码 $CI_STATUS)"
fi
exit "$CI_STATUS"
