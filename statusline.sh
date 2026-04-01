#!/bin/bash
# ============================================================
# Claude Code 状态栏脚本
# 利用 Claude Code 原生 statusLine 功能，从 stdin 读取 JSON 数据
# 显示 session 限额、weekly 限额、context window 使用情况
# ============================================================

# 从 stdin 读取 Claude Code 传入的 JSON 数据
INPUT=$(cat)

# 如果没有输入，显示等待状态
if [ -z "$INPUT" ]; then
    echo "⏳ waiting..."
    exit 0
fi

# ---- 解析 rate_limits 数据 ----

# 5小时 session 限额
FIVE_PCT=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
FIVE_RESET=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)

# 7天 weekly 限额
WEEK_PCT=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
WEEK_RESET=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)

# ---- 解析 context_window 数据 ----
CTX_USED_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
CTX_SIZE=$(echo "$INPUT" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
TOTAL_IN=$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // 0' 2>/dev/null)
TOTAL_OUT=$(echo "$INPUT" | jq -r '.context_window.total_output_tokens // 0' 2>/dev/null)

# ---- 生成进度条 ----
# 参数: $1=百分比(0-100), $2=宽度
make_bar() {
    local pct=${1:-0}
    local width=${2:-10}
    # 取整
    local pct_int=$(printf '%.0f' "$pct" 2>/dev/null || echo "0")
    local filled=$(( pct_int * width / 100 ))
    [ "$filled" -gt "$width" ] && filled=$width
    [ "$filled" -lt 0 ] && filled=0
    local empty=$(( width - filled ))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo "$bar"
}

# ---- 格式化重置时间 ----
# 参数: $1=Unix epoch seconds
format_reset() {
    local reset_ts="$1"
    if [ -z "$reset_ts" ]; then
        echo ""
        return
    fi

    local now=$(date +%s)
    local diff=$(( reset_ts - now ))

    if [ "$diff" -le 0 ]; then
        echo "now"
        return
    fi

    # 如果不到24小时，显示时:分
    if [ "$diff" -lt 86400 ]; then
        local hours=$(( diff / 3600 ))
        local mins=$(( (diff % 3600) / 60 ))
        if [ "$hours" -gt 0 ]; then
            printf "%dh%dm" "$hours" "$mins"
        else
            printf "%dm" "$mins"
        fi
    else
        # 超过24小时，显示星期几 + 时间
        if [[ "$OSTYPE" == "darwin"* ]]; then
            date -r "$reset_ts" "+%a %H:%M" 2>/dev/null || echo "--"
        else
            date -d "@$reset_ts" "+%a %H:%M" 2>/dev/null || echo "--"
        fi
    fi
}

# ---- 格式化 token 数为简短形式 ----
format_tokens() {
    local n=${1:-0}
    if [ "$n" -ge 1000000 ]; then
        printf "%.1fM" "$(echo "scale=1; $n/1000000" | bc 2>/dev/null || echo "0")"
    elif [ "$n" -ge 1000 ]; then
        printf "%.0fk" "$(echo "scale=0; $n/1000" | bc 2>/dev/null || echo "0")"
    else
        echo "$n"
    fi
}

# ---- 组装输出 ----
OUTPUT=""

# Session 限额（5小时窗口）
if [ -n "$FIVE_PCT" ]; then
    FIVE_BAR=$(make_bar "$FIVE_PCT" 10)
    FIVE_RESET_STR=$(format_reset "$FIVE_RESET")
    FIVE_PCT_INT=$(printf '%.0f' "$FIVE_PCT")
    SESS_PART="⚡Session ${FIVE_BAR} ${FIVE_PCT_INT}%"
    [ -n "$FIVE_RESET_STR" ] && SESS_PART+=" ↻${FIVE_RESET_STR}"
    OUTPUT+="$SESS_PART"
fi

# Weekly 限额（7天窗口）
if [ -n "$WEEK_PCT" ]; then
    WEEK_BAR=$(make_bar "$WEEK_PCT" 10)
    WEEK_RESET_STR=$(format_reset "$WEEK_RESET")
    WEEK_PCT_INT=$(printf '%.0f' "$WEEK_PCT")
    WEEK_PART="🗓 Week ${WEEK_BAR} ${WEEK_PCT_INT}%"
    [ -n "$WEEK_RESET_STR" ] && WEEK_PART+=" ↻${WEEK_RESET_STR}"
    [ -n "$OUTPUT" ] && OUTPUT+=" │ "
    OUTPUT+="$WEEK_PART"
fi

# Context Window 使用
if [ -n "$CTX_USED_PCT" ]; then
    CTX_BAR=$(make_bar "$CTX_USED_PCT" 8)
    CTX_PCT_INT=$(printf '%.0f' "$CTX_USED_PCT")
    # 当前 context 使用的 token 数
    if [ -n "$CTX_SIZE" ] && [ "$CTX_SIZE" -gt 0 ] 2>/dev/null; then
        CTX_USED_TOKENS=$(( CTX_SIZE * CTX_PCT_INT / 100 ))
        CTX_SIZE_STR=$(format_tokens "$CTX_SIZE")
        CTX_USED_STR=$(format_tokens "$CTX_USED_TOKENS")
        CTX_PART="Ctx ${CTX_BAR} ${CTX_PCT_INT}%(${CTX_USED_STR}/${CTX_SIZE_STR})"
    else
        CTX_PART="Ctx ${CTX_BAR} ${CTX_PCT_INT}%"
    fi
    [ -n "$OUTPUT" ] && OUTPUT+=" │ "
    OUTPUT+="$CTX_PART"
fi

# In/Out token 累计
if [ "$TOTAL_IN" -gt 0 ] 2>/dev/null || [ "$TOTAL_OUT" -gt 0 ] 2>/dev/null; then
    IN_STR=$(format_tokens "$TOTAL_IN")
    OUT_STR=$(format_tokens "$TOTAL_OUT")
    TOK_PART="In:${IN_STR} Out:${OUT_STR}"
    [ -n "$OUTPUT" ] && OUTPUT+=" │ "
    OUTPUT+="$TOK_PART"
fi

# 如果什么数据都没有
if [ -z "$OUTPUT" ]; then
    OUTPUT="⏳ waiting for data..."
fi

echo "$OUTPUT"
