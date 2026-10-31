#!/usr/bin/env bash
# script/ci 的公共部分: 仓库根定位, 工具探测, 文件清单, 结果汇总.
# 由各 check_*.sh source, 不单独执行.
#
# 几条硬规则 (改脚本时别破坏):
#   - 进入脚本后统一 cd 到仓库根: 显式路径先转绝对再转回仓库相对, 所以从哪个目录调用都一样;
#     不这么做的话, 从仓库外调用时 markdownlint 会 "Linting: 0 files" 却退 0, 等于静默空跑
#   - 配置路径写死在 .config/ 下, 调用方不用再记 --config
#   - 文件清单走 git ls-files -z + mapfile: 本仓库有带空格与 CJK 的路径
#     (doc/design_plan/SDecoder 设计方案 v1.0.md), 用 $(...) 展开会被拆成多个参数
#   - 外部命令缺失时报 2, 不静默跳过

if [ -n "${CI_LIB_LOADED:-}" ]; then
    return 0
fi
CI_LIB_LOADED=1

CI_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd) || exit 2
CI_CONFIG="$CI_ROOT/.config"

# ci_collect 的产物
CI_FILES=()
# ci_need 攒下的缺失命令
CI_MISSING=()

ci_log() { printf '[ci] %s\n' "$*"; }
ci_err() { printf '[ci] ERROR %s\n' "$*" >&2; }

# 把调用方脚本的头注释 (第 2 行到第一个空行) 打印成 usage
ci_usage() {
    local file=${BASH_SOURCE[1]:-$0}
    sed -n '2,/^[[:space:]]*$/p' "$file" | sed 's/^# \{0,1\}//; $d'
}

# 探测外部命令, 缺失记进 CI_MISSING
ci_need() {
    local cmd=$1
    local hint=${2:-}
    command -v -- "$cmd" >/dev/null 2>&1 && return 0
    CI_MISSING+=("$cmd${hint:+, 装法: $hint}")
    return 1
}

# 缺失的工具一次报全, 然后退 2: 少一个工具时宁可红, 也别让某项检查静默漏跑
ci_require_or_exit() {
    ((${#CI_MISSING[@]})) || return 0
    local item
    for item in "${CI_MISSING[@]}"; do
        ci_err "缺少命令: $item"
    done
    ci_err "工具不全, 检查会漏跑, 这里直接失败"
    exit 2
}

# 把实际用到的工具版本打进日志: CI 上先看这几行, 判断是不是版本漂移
ci_versions() {
    local cmd version
    for cmd in "$@"; do
        version=$("$cmd" --version 2>/dev/null | head -1) || continue
        ci_log "$cmd -> $version"
    done
}

# 处理显式路径并进入仓库根
#   $1: 调用方保存路径的数组名 (会被就地改写成仓库相对路径)
#   路径不存在退 2; 仓库内的路径转成相对仓库根, 仓库外的保留绝对路径
ci_enter_repo() {
    local -n paths=$1
    local i raw abs bad=0
    for i in "${!paths[@]}"; do
        raw=${paths[i]}
        abs=$(realpath -m -- "$raw") || { ci_err "路径解析失败: $raw"; bad=1; continue; }
        if [ ! -e "$abs" ]; then
            ci_err "路径不存在: $raw"
            bad=1
            continue
        fi
        case $abs in
            "$CI_ROOT"/*) paths[i]=${abs#"$CI_ROOT"/} ;;
            *)            paths[i]=$abs ;;
        esac
    done
    ((bad)) && return 2
    cd "$CI_ROOT" || return 2
    return 0
}

# 展开显式路径 (NUL 分隔): 目录按后缀递归取, 文件原样留下
ci_expand_paths() {
    local ext=$1
    shift
    local p
    for p in "$@"; do
        if [ -d "$p" ]; then
            find "$p" -type f -name "*$ext" \
                -not -path '*/.git/*' -not -path '*/node_modules/*' -print0
        else
            printf '%s\0' "$p"
        fi
    done
}

# 收集待查文件到 CI_FILES
#   $1: 后缀 (.md / .json5), 其余: 显式路径 (可空)
#   给了路径 = 只查这些 (本地); 没给 = 查 git 跟踪的全仓库文件 (CI 口径)
#   只留工作区里真实存在的文件: git ls-files 会列出"已删但还没 add"的路径,
#   那些喂给检查工具只会读不到 (mermaid-check 直接退 2)
ci_collect() {
    local ext=$1
    shift
    CI_FILES=()
    local -a found=()
    if (($#)); then
        mapfile -d '' -t found < <(ci_expand_paths "$ext" "$@" | sort -zu)
    else
        mapfile -d '' -t found < <(git -C "$CI_ROOT" ls-files -z -- "*$ext" | sort -zu)
    fi
    local f
    for f in "${found[@]}"; do
        [ -e "$f" ] && CI_FILES+=("$f")
    done
}
