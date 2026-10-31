---
name: python-check
description: "检查 Python 代码: 用仓库自己的 ruff 配置跑 lint 与格式化检查, 可按需自动修复, 并给出退出码与问题定位."
whenToUse: "写完或改完 Python 文件 (.py) 之后; 或用户要求检查, 修复 Python 代码风格时."
---

# python-check

Python 规范检查: lint + 格式检查, 规则集 `.config/ruff.toml`.

```bash
script/ci/check.sh py          # 全仓库
script/ci/check.sh py script/  # 只查目录或文件
script/ci/check.sh --fix py    # 本地自动修
```

退出码 `0` 才算过; `--fix` 只用于本地, CI 不带. 脚本自带 `--no-cache`, 不会留下 `.ruff_cache/`.
参数见 [`script/ci/check_python_ruff.sh`](../../../script/ci/check_python_ruff.sh) 的 `-h`.
