---
name: python-check
description: "检查 Python 代码: 用仓库自己的 ruff 配置跑 lint 与格式化检查, 可按需自动修复, 并给出退出码与问题定位."
whenToUse: "写完或改完 Python 文件 (.py) 之后; 或用户要求检查, 修复 Python 代码风格时."
---

# python-check

在**仓库根目录**执行. `--config` 必须带: ruff 不会去 `.config/` 找配置,
省略后会误报 F541 (无占位符 f-string), 而且 `--fix` 会真的删掉代码里多余的 `f` 前缀

```bash
ruff check --config ./.config/ruff.toml .                        # lint 全仓库
ruff check --config ./.config/ruff.toml doc/script/.docx2md.py   # 单个文件
```

- 通过时输出 `All checks passed!`, 退出码 `0`; 有问题时退出码 `1`,
  输出形如 `规则码 [*] 说明` + `--> 文件:行:列`, 行首 `[*]` 表示该问题可自动修复
- 自动修复前先预览要改什么, 确认后再落盘:

  ```bash
  ruff check --diff --config ./.config/ruff.toml .      # 只看差异
  ruff check --fix  --config ./.config/ruff.toml .      # 实际改写
  ```

- 格式化是单独一条命令, 需要时再跑:

  ```bash
  ruff format --check --config ./.config/ruff.toml .    # 只检查, 不改文件
  ```

  **不要顺手格式化整个仓库**: 目前
  `simulation/base/filelists/merge_all_filelist/merge_all_filelist.py` 仍有待重排的内容,
  混进功能改动会污染 diff, 要格式化就单独提一个提交
- 它只回答"代码规范对不对", 不跑测试, 不做类型检查

## 收尾: 清掉 .ruff_cache

ruff 会在**执行命令的目录**留下 `.ruff_cache/`. 它已被 `.gitignore` 排除 (不会出现在 `git status`),
但按本仓库约定, 检查完顺手删掉, 不要留在工作区:

```bash
rm -rf .ruff_cache     # 常规: 只在仓库根跑过时一条就够

# 在别的目录也跑过 (例如 cd .config 或 cd doc/script), 用这条兜底
find . -name .ruff_cache -type d -not -path "./.git/*" -prune -exec rm -rf {} +
```

规则集内容与更多用法 (缓存位置, 扫描范围等) 见 [`doc/ubuntu_env/ruff.md`](../../../doc/ubuntu_env/ruff.md).
