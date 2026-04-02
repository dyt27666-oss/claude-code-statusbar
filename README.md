<p align="center">
  <h1 align="center">Claude Code StatusBar v2</h1>
  <p align="center">
    Real-time rate limits & context window status bar for <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a>
    <br/>
    Now with <b>burn rate</b>, <b>color warnings</b>, and <b>1-second auto-refresh</b>
  </p>
  <p align="center">
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
    <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey.svg" alt="Platform">
    <img src="https://img.shields.io/badge/shell-bash%20%7C%20PowerShell-green.svg" alt="Shell">
    <img src="https://img.shields.io/badge/claude--code-v2.1%2B-purple.svg" alt="Claude Code">
  </p>
  <p align="center">
    <a href="#install">Install</a> &nbsp;·&nbsp;
    <a href="#what-it-shows">Features</a> &nbsp;·&nbsp;
    <a href="#whats-new-in-v2">v2 Changes</a> &nbsp;·&nbsp;
    <a href="#how-it-works">How It Works</a> &nbsp;·&nbsp;
    <a href="#customization">Customize</a>
  </p>
  <p align="center">
    <b>English</b> | <a href="README.zh-CN.md">简体中文</a>
  </p>
</p>

---

```
⚡Session ████░░░░░░ 45% ↻2h30m15s 🔥3.2%/h ~17h left │ 🗓Week ███████░░░ 73% ↻Sun 00:00 🔥1.5%/h │ Ctx ██░░░░░░ 25%(250k/1.0M) │ In:284k Out:67k
```

Built on Claude Code's **native `statusLine` API** — no hacks, no wrappers, no extra processes. Just a single shell script.

## What's New in v2

### Burn Rate

Tracks your usage over time and calculates how fast you're consuming limits:

- **Rate display** — `🔥3.2%/h` shows your current burn speed
- **ETA to depletion** — `~2h40m left` estimates when you'll hit the limit
- History is auto-recorded and deduplicated, keeping the last 120 data points
- Handles limit resets gracefully (ignores negative rate spikes)

### Color Warnings

Progress bars and percentages change color based on usage level:

| Level | Threshold | Color |
|-------|-----------|-------|
| Safe | < 60% | Green |
| Warning | 60% - 80% | Yellow |
| Danger | > 80% | Red (bold) |

### 1-Second Auto-Refresh

- Countdown timers (`↻2h30m15s`) now update every second with live accuracy
- Data is cached to `/tmp/claude-sb-cache.json` — between API calls, the script reads cached data and recalculates countdowns in real-time
- `refreshTime: 1` in settings enables 1-second polling

## What It Shows

| Section | Description |
|---------|-------------|
| ⚡ Session | 5-hour session rate limit usage + reset countdown + burn rate |
| 🗓 Week | 7-day weekly rate limit usage + reset time + burn rate |
| Ctx | Context window usage (percentage + token counts) |
| In/Out | Cumulative input/output tokens for current session |

## Requirements

### macOS / Linux

| Dependency | Description |
|------------|-------------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Anthropic's CLI for Claude (v2.1+) |
| [jq](https://jqlang.github.io/jq/) | Lightweight JSON processor |
| [Bash](https://www.gnu.org/software/bash/) | Pre-installed on macOS and Linux |

### Windows

| Dependency | Description |
|------------|-------------|
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Anthropic's CLI for Claude (v2.1+) |
| [PowerShell 5.1+](https://learn.microsoft.com/en-us/powershell/) | Pre-installed on Windows 10+ (no jq needed!) |

## Install

### macOS / Linux

```bash
git clone https://github.com/dyt27666-oss/claude-code-statusbar.git
cd claude-code-statusbar
bash install.sh
```

### Windows (PowerShell)

```powershell
git clone https://github.com/dyt27666-oss/claude-code-statusbar.git
cd claude-code-statusbar
pwsh install.ps1
```

Then **restart Claude Code**. The status bar appears automatically at the bottom of the input area.

> [!NOTE]
> Rate limit data (⚡Session and 🗓Week) only appears after your first API call in the session. Before that, only context window info is shown.
> Burn rate requires at least 2 minutes of data before it starts displaying.

> [!TIP]
> **Windows users**: The PowerShell version uses built-in `ConvertFrom-Json` — no need to install jq!

## Uninstall

### macOS / Linux

```bash
cd claude-code-statusbar
bash uninstall.sh
```

### Windows (PowerShell)

```powershell
cd claude-code-statusbar
pwsh uninstall.ps1
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

### v2 Architecture

```
Claude Code stdin (JSON)
        │
        ▼
  ┌──────────────────┐     ┌──────────────────────┐
  │ statusline.sh    │────▶│ $TEMP/claude-sb-cache │  (data caching)
  │ statusline.ps1   │     └──────────────────────┘
  │                  │     ┌──────────────────────┐
  │  parse JSON      │◀───▶│ $TEMP/claude-sb-hist  │  (burn rate history)
  │  calc burn rate  │     └──────────────────────┘
  │  add ANSI colors │
  │  format output   │
  └────────┬─────────┘
         │
         ▼
   Colored status line (ANSI)
```

- **Cache**: When stdin is empty (between API calls), reads last known data from cache and recalculates countdowns with current time
- **History**: Records usage data points for burn rate calculation (deduplicated, max 120 entries)
- **Colors**: ANSI escape codes for green/yellow/red based on thresholds

## Customization

Edit `statusline.sh` (macOS/Linux) or `statusline.ps1` (Windows) to change:

- **Progress bar width** — adjust the `10` or `8` in `make_bar` calls
- **Progress bar characters** — replace `█` and `░` with any characters you like
- **Sections displayed** — comment out any section block to hide it
- **Time format** — modify `format_reset()` function
- **Color thresholds** — edit the `get_color()` function (default: 60% yellow, 80% red)
- **Burn rate window** — change `target_ts=$(( NOW - 600 ))` to adjust the lookback period (default: 10 minutes)
- **Refresh interval** — edit `refreshTime` in `~/.claude/settings.json` (default: 1 second)

## FAQ

**I only see context info, no Session/Week percentages?**

Rate limit headers are returned by the API after your first message. Send a message and the data will appear.

**Burn rate shows nothing?**

Burn rate needs at least 2 minutes of history data with changing values. Keep using Claude Code and it will appear.

**Does this work with API keys (non-subscription)?**

Context window and token counts will work. Rate limit sections depend on whether Anthropic returns rate limit headers for your account type.

**Will this break my Claude Code?**

No. `statusLine` is an official, supported feature. If the script fails, Claude Code simply shows nothing.

**Can I disable colors?**

Set all `C_*` color variables to empty strings at the top of `statusline.sh` / `statusline.ps1`.

## License

[MIT](LICENSE)
