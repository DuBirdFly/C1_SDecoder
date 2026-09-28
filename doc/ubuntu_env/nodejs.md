# node.js 安装

`node.js` 是一个基于 Chrome V8 引擎的 JavaScript 运行时环境. 它允许开发者在服务器端运行 JavaScript 代码.

`node.js` 有时候也简写为 `nodejs` 或 `node`

鉴于 `deepseek harness` 和 `markdownlint-cli2` 都需要 `node.js`, 其中:

- `deepseek harness` 要求 `node.js` 版本 >= 22.19.0
- `markdownlint-cli2` 要求 `node.js` 版本 >= 22

为稳妥起见, 建议采取 Node.js 24 系列 (LTS) 版本

[nodejs 官网](https://nodesource.com/products/distributions) 提供了不同 Linux 发行版的安装命令

以 Ubuntu 24 安装 Node.js 24 LTS 为例, 该官网的提供为:

```bash
sudo apt-get install -y curl
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs
node -v
```

nodejs 主要提供以下两个命令行工具:

```bash
which node
node --version

which npm
npm --version
```

注: *对于 WSL 用户, 确认 `which node` 输出为 `/usr/bin/node` (而非 `/mnt/...` 开头的 Windows 路径)*
