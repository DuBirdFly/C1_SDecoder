# CONTRIBUTING

## 写 Markdown 文档

Markdown 文档遵循 [`doc/md 编写规范.md`](doc/md%20编写规范.md)

## 写 python 文件

### ruff 检查

写完或改完 `.py` 后, 在**仓库根目录**执行检查:

```bash
ruff check --config ./.config/ruff.toml .             # lint 全仓库
ruff format --check --config ./.config/ruff.toml .    # 只检查格式, 不落盘
```

注: 必须显式带 `--config`: ruff 不会去 `.config/` 找配置, 省略后 `.config/ruff.toml` 里的豁免全部失效

- 新写的代码要标类型注解: 函数签名与返回, 模块常量, 以及含义不直观的局部变量, 尽可能写全
- 检查完顺手删掉工作区里的 `.ruff_cache/` (已被 gitignore, 但不留在工作区)

规则集与命令说明见 [`doc/ubuntu_env/ruff.md`](doc/ubuntu_env/ruff.md);
按需加载的检查流程见 [`.agents/skills/python-check/SKILL.md`](.agents/skills/python-check/SKILL.md).

## 写 Verilog / SystemVerilog 文件

见 [`doc/sv 编写规范.md`](doc/sv%20编写规范.md)

## 写 UVM testbench

见 [`doc/uvm 编写规范.md`](doc/uvm%20编写规范.md)
