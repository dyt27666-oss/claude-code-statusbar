<p align="center">
  <h1 align="center">Claude Code StatusBar v2</h1>
  <p align="center">
    为 <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a> 实时显示速率限额与上下文窗口的状态栏
    <br/>
    全新 <b>燃烧速率</b>、<b>颜色警告</b>、<b>1 秒自动刷新</b>
  </p>
  <p align="center">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
    <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg" alt="Platform">
    <img src="https://img.shields.io/badge/shell-bash-green.svg" alt="Shell">
    <img src="https://img.shields.io/badge/claude--code-v2.1%2B-purple.svg" alt="Claude Code">
  </p>
  <p align="center">
    <a href="#安装">安装</a> &nbsp;·&nbsp;
    <a href="#显示内容">功能</a> &nbsp;·&nbsp;
    <a href="#v2-新特性">v2 新特性</a> &nbsp;·&nbsp;
    <a href="#工作原理">原理</a> &nbsp;·&nbsp;
    <a href="#自定义">自定义</a>
  </p>
  <p align="center">
    <a href="README.md">English</a> | <b>简体中文</b>
  </p>
</p>

---

```
⚡Session ████░░░░░░ 45% ↻2h30m15s 🔥3.2%/h ~17h left │ 🗓Week ███████░░░ 73% ↻Sun 00:00 🔥1.5%/h │ Ctx ██░░░░░░ 25%(250k/1.0M) │ In:284k Out:67k
```

基于 Claude Code **原生 `statusLine` API** 构建 — 无 hack、无 wrapper、无额外进程，仅一个 shell 脚本。

## v2 新特性

### 燃烧速率

追踪用量变化，计算限额消耗速度：

- **速率显示** — `🔥3.2%/h` 显示当前消耗速度
- **耗尽预估** — `~2h40m left` 预估何时触及限额
- 历史数据自动记录与去重，保留最近 120 个数据点
- 限额重置时自动忽略负值波动

### 颜色警告

进度条和百分比根据用量等级变色：

| 等级 | 阈值 | 颜色 |
|------|------|------|
| 安全 | < 60% | 绿色 |
| 警告 | 60% - 80% | 黄色 |
| 危险 | > 80% | 红色（加粗） |

### 1 秒自动刷新

- 倒计时 (`↻2h30m15s`) 每秒实时更新，精确到秒
- 数据缓存至 `/tmp/claude-sb-cache.json` — API 调用间隔期间读取缓存数据，实时重新计算倒计时
- 通过 `refreshTime: 1` 配置启用 1 秒轮询

## 显示内容

| 区域 | 说明 |
|------|------|
| ⚡ Session | 5 小时会话速率限额用量 + 重置倒计时 + 燃烧速率 |
| 🗓 Week | 7 天周限额用量 + 重置时间 + 燃烧速率 |
| Ctx | 上下文窗口使用率（百分比 + token 数） |
| In/Out | 当前会话累计输入/输出 token 数 |

## 前置依赖

| 依赖 | 说明 |
|------|------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Anthropic 官方 CLI 工具（v2.1+） |
| [jq](https://jqlang.github.io/jq/) | 轻量级 JSON 处理器 |
| [Bash](https://www.gnu.org/software/bash/) | macOS 和 Linux 自带 |

## 安装

```bash
git clone https://github.com/dyt27666-oss/claude-code-statusbar.git
cd claude-code-statusbar
bash install.sh
```

然后**重启 Claude Code**，状态栏会自动显示在输入框下方。

> [!NOTE]
> 速率限额数据（⚡Session 和 🗓Week）在会话首次 API 调用后才会出现。在此之前只显示上下文窗口信息。
> 燃烧速率需要至少 2 分钟的数据积累后才会开始显示。

## 卸载

```bash
cd claude-code-statusbar
bash uninstall.sh
```

## 工作原理

Claude Code 内置了 [`statusLine`](https://docs.anthropic.com/en/docs/claude-code/settings) 功能。在 `~/.claude/settings.json` 中配置后，它会执行指定的 shell 命令，并将 stdout 输出显示在输入框下方。

Claude Code 通过 stdin 传入 JSON 对象：

```json
{
  "rate_limits": {
    "five_hour":  { "used_percentage": 55.3, "resets_at": 1234567890 },
    "seven_day":  { "used_percentage": 32.1, "resets_at": 1234567890 }
  },
  "context_window": {
    "used_percentage": 42,
    "context_window_size": 1000000,
    "total_input_tokens": 284100,
    "total_output_tokens": 67432
  }
}
```

这与 `/usage` 命令使用的是**同一个数据源** — 均来自 API 响应头 (`anthropic-ratelimit-unified-*`)，状态栏数据与 `/usage` 始终一致。

### v2 架构

```
Claude Code stdin (JSON)
        │
        ▼
  ┌─────────────┐     ┌──────────────────────┐
  │ statusline.sh│────▶│ /tmp/claude-sb-cache  │  (数据缓存)
  │             │     └──────────────────────┘
  │  解析 JSON   │     ┌──────────────────────┐
  │  计算燃烧率  │◀───▶│ /tmp/claude-sb-history│  (燃烧速率历史)
  │  添加颜色    │     └──────────────────────┘
  │  格式化输出  │
  └──────┬──────┘
         │
         ▼
   彩色状态行 (ANSI)
```

- **缓存**：stdin 无数据时（API 调用间隔），读取上次缓存数据并用当前时间重新计算倒计时
- **历史**：记录用量数据点用于燃烧速率计算（自动去重，最多保留 120 条）
- **颜色**：基于阈值使用 ANSI 转义码显示绿/黄/红

## 自定义

编辑 `statusline.sh` 可修改：

- **进度条宽度** — 调整 `make_bar` 调用中的 `10` 或 `8`
- **进度条字符** — 将 `█` 和 `░` 替换为你喜欢的字符
- **显示区域** — 注释掉不需要的区域代码块
- **时间格式** — 修改 `format_reset()` 函数
- **颜色阈值** — 编辑 `get_color()` 函数（默认：60% 黄色，80% 红色）
- **燃烧速率窗口** — 修改 `target_ts=$(( NOW - 600 ))` 调整回溯时间（默认 10 分钟）
- **刷新间隔** — 编辑 `~/.claude/settings.json` 中的 `refreshTime`（默认 1 秒）

## 常见问题

**只看到上下文信息，没有 Session/Week 百分比？**

速率限额数据来自 API 响应头，首次发送消息后才会出现。

**燃烧速率没有显示？**

燃烧速率需要至少 2 分钟的历史数据且数值有变化后才会显示。继续使用 Claude Code 即可。

**API Key 用户（非订阅）能用吗？**

上下文窗口和 token 计数可以正常工作。速率限额部分取决于 Anthropic 是否为你的账户类型返回限额 header。

**会不会影响 Claude Code 正常使用？**

不会。`statusLine` 是官方支持的功能。即使脚本出错，Claude Code 也只是不显示状态栏，不会崩溃。

**如何关闭颜色？**

将 `statusline.sh` 顶部的所有 `C_*` 颜色变量设为空字符串即可。

## 许可证

[MIT](LICENSE)
