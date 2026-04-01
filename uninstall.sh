#!/bin/bash
# ============================================================
# Claude Code StatusBar - 卸载脚本
# 从 ~/.claude/settings.json 移除 statusLine 配置
# ============================================================

set -e

SETTINGS_FILE="$HOME/.claude/settings.json"

# 跟踪符号链接
if [ -L "$SETTINGS_FILE" ]; then
    SETTINGS_FILE=$(readlink -f "$SETTINGS_FILE")
fi

if [ ! -f "$SETTINGS_FILE" ]; then
    echo "Nothing to uninstall (settings.json not found)"
    exit 0
fi

# 检查是否有 statusLine 配置
if ! jq -e '.statusLine' "$SETTINGS_FILE" > /dev/null 2>&1; then
    echo "Nothing to uninstall (statusLine not configured)"
    exit 0
fi

TEMP_FILE=$(mktemp)
jq 'del(.statusLine)' "$SETTINGS_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$SETTINGS_FILE"

echo "✅ statusLine removed from settings.json"
echo "   Restart claude to apply."
