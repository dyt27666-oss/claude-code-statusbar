#!/bin/bash
# ============================================================
# Claude Code StatusBar - 安装脚本
# 利用 Claude Code 原生 statusLine 功能
# 将 statusline.sh 注册到 ~/.claude/settings.json
# ============================================================

set -e

# 自动检测脚本所在目录（支持从任意位置 clone）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUSLINE_SCRIPT="${SCRIPT_DIR}/statusline.sh"

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   Claude Code StatusBar - Installer      ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""

# ---- 前置检查 ----

# 检查状态栏脚本
if [ ! -f "$STATUSLINE_SCRIPT" ]; then
    echo "  [✗] statusline.sh not found in ${SCRIPT_DIR}"
    exit 1
fi
chmod +x "$STATUSLINE_SCRIPT"
echo "  [✓] statusline.sh found"

# 检查 jq
if ! command -v jq &> /dev/null; then
    echo "  [✗] jq is required but not installed"
    echo ""
    echo "  Install jq:"
    echo "    macOS:  brew install jq"
    echo "    Ubuntu: sudo apt install jq"
    echo "    Arch:   sudo pacman -S jq"
    exit 1
fi
echo "  [✓] jq $(jq --version 2>&1)"

# 检查 claude
if command -v claude &> /dev/null; then
    echo "  [✓] Claude Code $(claude --version 2>&1)"
else
    echo "  [!] claude command not found (install it first)"
    echo "      https://docs.anthropic.com/en/docs/claude-code"
fi

# ---- 写入配置 ----

SETTINGS_FILE="$HOME/.claude/settings.json"

# 跟踪符号链接
if [ -L "$SETTINGS_FILE" ]; then
    SETTINGS_FILE=$(readlink -f "$SETTINGS_FILE")
    echo "  [i] settings.json is symlink → ${SETTINGS_FILE}"
fi

# 确保文件存在
mkdir -p "$(dirname "$SETTINGS_FILE")"
[ ! -f "$SETTINGS_FILE" ] && echo "{}" > "$SETTINGS_FILE"

# 备份
BACKUP="${SETTINGS_FILE}.bak"
cp "$SETTINGS_FILE" "$BACKUP"
echo "  [✓] Backup → ${BACKUP}"

# 用 jq 写入 statusLine 配置（保留已有设置）
TEMP_FILE=$(mktemp)
if jq --arg cmd "$STATUSLINE_SCRIPT" \
    '. + {"statusLine": {"type": "command", "command": $cmd}}' \
    "$SETTINGS_FILE" > "$TEMP_FILE" 2>/dev/null; then
    mv "$TEMP_FILE" "$SETTINGS_FILE"
    echo "  [✓] statusLine config written"
else
    rm -f "$TEMP_FILE"
    echo "  [✗] Failed to update settings.json"
    echo "      Restoring backup..."
    cp "$BACKUP" "$SETTINGS_FILE"
    exit 1
fi

echo ""
echo "  ✅ Installed! Restart claude to see the status bar."
echo ""
echo "  ┌─────────────────────────────────────────────────────────────────────┐"
echo "  │ ⚡Session █████░░░░░ 55% ↻2h │ 📅Week ███░░░░░░░ 32% ↻Sun 00:00 │"
echo "  └─────────────────────────────────────────────────────────────────────┘"
echo ""
echo "  Uninstall:"
echo "    bash $(dirname "$0")/uninstall.sh"
echo ""
