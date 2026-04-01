# Claude Code StatusBar

A lightweight status bar for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that displays real-time usage limits and context window info directly in your terminal.

Built on Claude Code's **native `statusLine` API** — no hacks, no wrappers, no extra processes.

```
⚡Session █████░░░░░ 55% ↻2h0m │ 📅Week ███░░░░░░░ 32% ↻Sun 00:00 │ Ctx ███░░░░░ 42%(420k/1.0M) │ In:284k Out:67k
```

## What it shows

| Section | Description |
|---------|-------------|
| ⚡ Session | 5-hour session rate limit usage + reset countdown |
| 📅 Week | 7-day weekly rate limit usage + reset time |
| Ctx | Context window usage (percentage + token counts) |
| In/Out | Cumulative input/output tokens for current session |

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI (v2.1+)
- [jq](https://jqlang.github.io/jq/) (JSON processor)
- macOS or Linux with Bash

## Install

```bash
git clone https://github.com/dyt27666-oss/claude-code-statusbar.git
cd claude-code-statusbar
bash install.sh
```

Then restart Claude Code. The status bar appears automatically at the bottom of the input area.

> **Note:** Rate limit data (`⚡Session` and `📅Week`) only appears after your first API call in the session. Before that, only context window info is shown.

## Uninstall

```bash
bash uninstall.sh
```

Or manually:

```bash
# Remove statusLine from settings
jq 'del(.statusLine)' ~/.claude/settings.json > /tmp/s.json && mv /tmp/s.json ~/.claude/settings.json
```

## How it works

Claude Code has a built-in `statusLine` feature. When configured in `~/.claude/settings.json`, it runs a shell command and displays its stdout as a status line beneath the input box.

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
  },
  "model": { "id": "claude-opus-4-6", "display_name": "Claude Opus 4" },
  ...
}
```

This is the **same data source** as the `/usage` command — both read from API response headers (`anthropic-ratelimit-unified-*`), so the status bar is always consistent with `/usage`.

`statusline.sh` simply reads this JSON with `jq`, formats it with progress bars and countdowns, and prints one line.

## Customization

Edit `statusline.sh` to change:

- **Progress bar width** — adjust the `10` or `8` in `make_bar` calls
- **Progress bar characters** — change `█` and `░` to any characters
- **Sections shown** — comment out any section block you don't want
- **Time format** — modify `format_reset()` function

## FAQ

**Q: I only see context info, no Session/Week percentages?**
A: Rate limit headers are returned by the API after your first message. Send a message and the data will appear.

**Q: Does this work with API keys (non-subscription)?**
A: Context window and token counts will work. Rate limit sections depend on whether Anthropic returns rate limit headers for your account type.

**Q: Will this break my Claude Code experience?**
A: No. The `statusLine` is an official, supported feature. It runs your script and displays the output — if the script fails, Claude Code simply shows nothing.

## License

MIT
