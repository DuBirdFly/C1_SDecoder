# C1_SDecoder

## 工程结构

只列到文件夹一级 (省略各目录下的具体文件):

```text
C1_SDecoder/
├── .agents/                      # agent 常驻配置
│   ├── notes/                    # 决策与理由记录 (为什么这么定)
│   └── skills/                   # 按需加载的能力 (带 YAML frontmatter 的 SKILL.md)
├── .config/                      # 仓库级工具配置
├── .vscode/                      # 项目共享的编辑器配置
├── bsp/                          # 板级支持包: 面向 DUT 的测试程序 (C / 汇编) 的编译, 汇编与链接
├── doc/                          # 项目文档
│   ├── script/                   # 文档处理脚本
│   ├── ubuntu_env/               # 本机 (Ubuntu) 环境与工具链说明
│   ├── verif_plan/               # 验证计划类文档
│   └── design_plan/              # 设计方案归档, 一个方案一个目录
│       └── 内存池化SDecoder和SMMU部件设计方案2.6/
├── formal/                       # 形式验证
├── rtl/                          # 设计代码 (RTL)
├── script/                       # 项目流程脚本
├── simulation/                   # VCS 仿真环境
│   ├── base/                     # 仿真公共底座
│   │   ├── filelists/            # 文件列表及其合并脚本
│   │   ├── novas/                # Verdi / Novas 配置
│   │   └── option/               # 编译与仿真选项
│   └── script/                   # 仿真专属脚本
└── testbench/                    # UVM 验证平台
    ├── env/                      # 验证环境
    ├── inc/                      # 公共头文件
    ├── ral/                      # 寄存器抽象层 (RAL) 模型
    ├── test/                     # 测试用例
    │   ├── regress/              # 回归用例
    │   ├── seqlib/               # 激励序列库
    │   └── smoke/                # 冒烟用例
    ├── top/                      # 顶层与接口
    ├── utils/                    # 通用工具
    └── vip/                      # 验证 IP
```

说明:

- `simulation/` 下的 `run_case.<TB_TOP>.<TESTNAME>/` 不是源码目录, 由 `make base` 按需生成,
  存放单次仿真的日志与产物 (`log/`, `output/`), 已由 `.gitignore` 排除.
- `doc/` 下每个设计方案的图片放在同级 `image/<文档名>/` 目录, 具体约定见
  [`doc/md文件编写规范.md`](doc/md文件编写规范.md).
