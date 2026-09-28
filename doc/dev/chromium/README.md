# chromium 安装与使用

chromium 是开源的浏览器内核, 也是各种无头 (headless) 渲染工具的运行时.
本仓库里用到它的只有一处: 用 `mmdc` 把 Mermaid **真正渲染**成 SVG/PNG 时, 它由 puppeteer 拉起
(见 [doc/dev/mermaid/README.md](../mermaid/README.md)); 只做 Mermaid 语法校验用不到它

## 安装与卸载

Ubuntu 用 snap 安装:

```bash
sudo snap install chromium
```

*注: 没有 snapd 时先 `sudo apt install snapd`; snap 版会随通道自动更新, 不需要手工升级*

其它发行版按各自的包管理器安装 (Debian / Ubuntu 的传统包名是 `chromium` 或 `chromium-browser`,
Fedora 是 `chromium`), 以发行版仓库为准

确认:

```bash
which chromium
chromium --version
```

snap 安装时 `which chromium` 通常输出 `/snap/bin/chromium`, 以实际输出为准

卸载:

```bash
sudo snap remove chromium
```

## 让 puppeteer / mmdc 用它

puppeteer 默认会自己下载一份 Chromium 放在 `~/.cache/puppeteer` (几百 MB, 受限网络下会直接失败).
系统已经装了 Chromium 时, 用配置文件把路径指过去, 并顺手加上无沙箱参数:

```json
{
    "executablePath": "/snap/bin/chromium",
    "args": ["--no-sandbox"]
}
```

```bash
mmdc -i input.mmd -o output.svg -p puppeteer-config.json
```

几点说明:

- `executablePath` 填 `which chromium` 的实际输出; 上例是 snap 安装的常见路径
- puppeteer 只保证与它自带的 Chromium 兼容, 版本差太多可能报错; snap 的沙箱限制也可能让 puppeteer 起不来,
  这是用系统 Chromium 的已知代价
- 安装 puppeteer 依赖时设 `PUPPETEER_SKIP_DOWNLOAD=1`, 可以跳过它自带的下载

## 常见问题

- 报 `No usable sandbox!` 或 `Running as root without --no-sandbox is not supported`:
  在 puppeteer 配置里加 `"args": ["--no-sandbox"]`, 即上面的写法.
  这是容器/无 sandbox 内核下的临时办法, 能正常跑就不要关
- 无头运行: chromium 由调用方 (puppeteer / mmdc) 以 headless 方式自动拉起, 不需要手工开窗口
