#!/usr/bin/env python3
"""
回归测试主脚本: 每个 TB_TOP 只编一次 vcs, 然后依序跑各 TESTNAME 并收集 log.

用法: python3 script/regression_run.py

步骤 (对 TB_TOPS 里的每个 TB_TOP 各做一遍):
    1. make vcs 编译一次, 产物放在该 TB_TOP 自己的 RUN_DIR 下
    2. 依序对 REGRESS_CASES 里的每个 TESTNAME 执行 make simv_only, 复用上面编好的 simv
    3. 每跑完一个就把它的编译日志与仿真日志收进
       <LOG_DIR>/<TB_TOP>.<TESTNAME>/{vcs.log,simv.log}

注: 同一个 TB_TOP 的多个 case 共用一个 RUN_DIR, RUN_DIR/log 下的 vcs.log 与 simv.log
会被下一次运行覆盖, 故必须逐个另存.
注: 该脚本串行依次执行 TESTNAME, 不是并行跑多个 TESTNAME. 并行请使用 vcs 功能
注: 回归不存储波形 (DUMP_WAVE=0).如果有问题, 主动使用单测跑出问题的 TESTNAME, 并打开 Makefile 的 DUMP_WAVE=1
"""

import json
import os
import shutil
import subprocess
import sys

REPO_ROOT: str = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM_DIR: str = os.path.join(REPO_ROOT, "simulation")

# 要回归的 TB 顶层列表, 与单点跑的 TB_TOP 对应
TB_TOPS: list[str] = ["tb_sdtlb", "tb_sdptw"]
# 回归用例清单: 依序执行, 名字即 UVM 的 +UVM_TESTNAME
REGRESS_CASES: list[str] = ["TestBase", "TestRegress"]

# 回归运行目录的父目录名, 与单点跑的 run_single_testcase 分开
RUN_ROOT: str = "run_regress_testcase"
# 收集起来的各用例 log 放这里 (相对 simulation/), 每个用例一个 <TB_TOP>.<TESTNAME>/
LOG_DIR: str = f"{RUN_ROOT}/log"
# 每个用例要收走的日志文件 (均来自 RUN_DIR/log/)
CASE_LOGS: tuple[str, ...] = ("vcs.log", "simv.log")
# 回归不转储波形
DUMP_WAVE: int = 0
# 每个运行目录里放一份配置快照 (jsonc: 允许 // 注释)
CONFIG_NAME: str = "regression_run.jsonc"


def rel(path: str) -> str:
    """转成相对仓库根的路径, 便于打印."""
    return os.path.relpath(path, REPO_ROOT)


def run_dir_for(tb_top: str) -> str:
    """
    每个 TB_TOP 一个运行目录 (相对 simulation/), 显式传给 make: Makefile 里的 RUN_DIR
    是 ?= 赋的, 命令行传值即可覆盖默认值.

    同一个 TB_TOP 下的多个 TESTNAME 共用它, vcs 才只编一次.
    末级保留一层, 与单点跑的 run_single_testcase/<TB_TOP>.<TESTNAME> 同深度:
    Makefile 里的 REPO_ROOT=../../.. 是按 simulation/ 下两级推导的.
    """
    return f"{RUN_ROOT}/{tb_top}"


def write_config(run_dir: str, tb_top: str) -> None:
    """把本次回归用到的变量值写成 jsonc, 放进该 TB_TOP 的运行目录, 便于事后复现."""
    path: str = os.path.join(SIM_DIR, run_dir, CONFIG_NAME)
    os.makedirs(os.path.dirname(path), exist_ok=True)

    lines: list[str] = [
        "// 本次回归用到的变量值, 由 script/regression_run.py 生成",
        "{",
        "  // 路径推导 (REPO_ROOT 由脚本自身位置推出, 绝对路径)",
        f'  "REPO_ROOT": {json.dumps(REPO_ROOT)},',
        f'  "SIM_DIR": {json.dumps(SIM_DIR)},',
        "  // 回归范围",
        f'  "TB_TOPS": {json.dumps(TB_TOPS)},',
        f'  "REGRESS_CASES": {json.dumps(REGRESS_CASES)},',
        "  // 本运行目录 (相对 simulation/) 与它服务的 TB_TOP",
        f'  "RUN_ROOT": {json.dumps(RUN_ROOT)},',
        f'  "RUN_DIR": {json.dumps(run_dir)},',
        f'  "TB_TOP": {json.dumps(tb_top)},',
        f'  "LOG_DIR": {json.dumps(LOG_DIR)},',
        # 末项不写尾随逗号: jsonc 允许, 但去掉后 "剥掉注释即为合法 JSON", 更好消费
        f'  "DUMP_WAVE": {json.dumps(DUMP_WAVE)}',
        "}",
    ]

    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"  配置 -> {rel(path)}", flush=True)


def run_make(
    tb_top: str, run_dir: str, target: str, testname: str | None = None
) -> int:
    """在 simulation/ 下跑一个 make 目标, 返回其退出码."""
    cmd: list[str] = [
        "make",
        target,
        f"TB_TOP={tb_top}",
        f"RUN_DIR={run_dir}",
        f"DUMP_WAVE={DUMP_WAVE}",
    ]
    if testname is not None:
        cmd.append(f"TESTNAME={testname}")

    # flush: 子进程的输出直接写 fd, 自己的进度行若被块缓冲会跑到 make 输出后面,
    # 重定向到文件时顺序就乱了
    print(f"$ {' '.join(cmd)}", flush=True)
    result: subprocess.CompletedProcess[str] = subprocess.run(
        cmd, cwd=SIM_DIR, check=False
    )
    return result.returncode


def main() -> int:
    log_dir: str = os.path.join(SIM_DIR, LOG_DIR)
    os.makedirs(log_dir, exist_ok=True)

    failed: list[str] = []
    for tb_top in TB_TOPS:
        run_dir: str = run_dir_for(tb_top)
        print(f"\n===== {tb_top} =====", flush=True)

        # 0. 先落下本次的配置快照 (编译失败也能留下记录)
        write_config(run_dir, tb_top)

        # 1. 这个 TB_TOP 只编一次
        if run_make(tb_top, run_dir, "vcs") != 0:
            print(f"{tb_top}: vcs 编译失败, 跳过它的用例", file=sys.stderr, flush=True)
            failed.append(f"{tb_top} (vcs)")
            continue

        # 2. 依序跑各 TESTNAME, 每跑完一个就把它的日志收进自己的文件夹
        for testname in REGRESS_CASES:
            if run_make(tb_top, run_dir, "simv_only", testname) != 0:
                failed.append(f"{tb_top}.{testname}")

            case_log_dir: str = os.path.join(log_dir, f"{tb_top}.{testname}")
            os.makedirs(case_log_dir, exist_ok=True)

            missing: list[str] = []
            for name in CASE_LOGS:
                src: str = os.path.join(SIM_DIR, run_dir, "log", name)
                if os.path.isfile(src):
                    shutil.copyfile(src, os.path.join(case_log_dir, name))
                else:
                    missing.append(name)

            saved: list[str] = [name for name in CASE_LOGS if name not in missing]
            print(f"  log -> {rel(case_log_dir)}/ ({', '.join(saved)})", flush=True)
            if missing:
                print(f"  没有找到: {', '.join(missing)}", file=sys.stderr, flush=True)

    print(
        f"\n跑完 {len(TB_TOPS)} 个 TB_TOP x {len(REGRESS_CASES)} 个用例, "
        f"log 收在 {rel(log_dir)}",
        flush=True,
    )
    if failed:
        print(
            f"以下条目 make 返回非 0: {', '.join(failed)}", file=sys.stderr, flush=True
        )
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
