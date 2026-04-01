<p align="center">
  <h1 align="center">Claude Code StatusBar</h1>
  <p align="center">
    Real-time rate limits & context window status bar for <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a>
  </p>
  <p align="center">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
    <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg" alt="Platform">
    <img src="https://img.shields.io/badge/shell-bash-green.svg" alt="Shell">
    <img src="https://img.shields.io/badge/claude--code-v2.1%2B-purple.svg" alt="Claude Code">
  </p>
  <p align="center">
    <a href="#install">Install</a> &nbsp;·&nbsp;
    <a href="#what-it-shows">Features</a> &nbsp;·&nbsp;
    <a href="#how-it-works">How It Works</a> &nbsp;·&nbsp;
    <a href="#customization">Customize</a>
  </p>
  <p align="center">
    <b>English</b> | <a href="README.zh-CN.md">简体中文</a>
  </p>
</p>

---

```
⚡Session █████░░░░░ 55% ↻2h0m │ 🗓Week ███░░░░░░░ 32% ↻Sun 00:00 │ Ctx ███░░░░░ 42%(420k/1.0M) │ In:284k Out:67k
```

Built on Claude Code's **native `statusLine` API** — no hacks, no wrappers, no extra processes. Just a single shell script.

## What It Shows

| Section | Description |
|---------|-------------|
| ⚡ Session | 5-hour session rate limit usage + reset countdown |
| 🗓 Week | 7-day weekly rate limit usage + reset time |
| Ctx | Context window usage (percentage + token counts) |
| In/Out | Cumulative input/output tokens for current session |

## Requirements

| Dependency | Description |
|------------|-------------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Anthropic's CLI for Claude (v2.1+) |
| [jq](https://jqlang.github.io/jq/) | Lightweight JSON processor |
| [Bash](https://www.gnu.org/software/bash/) | Pre-installed on macOS and Linux |

## Install

```bash
git clone https://github.com/dyt27666-oss/claude-code-statusbar.git
cd claude-code-statusbar
bash install.sh
```

Then **restart Claude Code**. The status bar appears automatically at the bottom of the input area.

> [!NOTE]
> Rate limit data (⚡Session and 🗓Week) only appears after your first API call in the session. Before that, only context window info is shown.

## Uninstall

```bash
cd claude-code-statusbar
bash uninstall.sh
```

## How It Works

Claude Code has a built-in [`statusLine`](https://docs.anthropic.com/en/docs/claude-code/settings) feature. When configured in `~/.claude/settings.json`, it runs a shell command and displays its stdout beneath the input box.

Claude Code passes a JSON object via stdin containing:

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

This is the **same data source** as the `/usage` command — both read from API response headers (`anthropic-ratelimit-unified-*`), ensuring the status bar stays perfectly in sync.

`statusline.sh` reads this JSON with [jq](https://jqlang.github.io/jq/), formats it with progress bars and countdowns, and outputs one line.

## Customization

Edit `statusline.sh` to change:

- **Progress bar width** — adjust the `10` or `8` in `make_bar` calls
- **Progress bar characters** — replace `█` and `░` with any characters you like
- **Sections displayed** — comment out any section block to hide it
- **Time format** — modify `format_reset()` function

## FAQ

**I only see context info, no Session/Week percentages?**

Rate limit headers are returned by the API after your first message. Send a message and the data will appear.

**Does this work with API keys (non-subscription)?**

Context window and token counts will work. Rate limit sections depend on whether Anthropic returns rate limit headers for your account type.

**Will this break my Claude Code?**

No. `statusLine` is an official, supported feature. If the script fails, Claude Code simply shows nothing.

## License

[MIT](LICENSE)
