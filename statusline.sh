#!/bin/bash
# ============================================================
# Claude Code 状态栏脚本 v2
# Features: 燃烧速率 | 颜色警告 | 数据缓存自动刷新
# ============================================================

# ---- 文件路径 ----
CACHE_FILE="/tmp/claude-sb-cache.json"
HISTORY_FILE="/tmp/claude-sb-history.csv"
MAX_HISTORY=120

# ---- ANSI 颜色 ----
C_RED='\033[31m'
C_RED_BOLD='\033[1;31m'
C_YELLOW='\033[33m'
C_GREEN='\033[32m'
C_CYAN='\033[36m'
C_DIM='\033[2m'
C_BOLD='\033[1m'
C_RESET='\033[0m'

# ---- 读取输入，缓存机制 ----
INPUT=$(cat)

if [ -n "$INPUT" ]; then
    echo "$INPUT" > "$CACHE_FILE"
elif [ -f "$CACHE_FILE" ]; then
    INPUT=$(cat "$CACHE_FILE")
fi

if [ -z "$INPUT" ]; then
    echo -e "${C_DIM}⏳ waiting...${C_RESET}"
    exit 0
fi

# ---- 解析数据 ----
FIVE_PCT=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
FIVE_RESET=$(echo "$INPUT" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
WEEK_PCT=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
WEEK_RESET=$(echo "$INPUT" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)
CTX_USED_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
CTX_SIZE=$(echo "$INPUT" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
TOTAL_IN=$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // 0' 2>/dev/null)
TOTAL_OUT=$(echo "$INPUT" | jq -r '.context_window.total_output_tokens // 0' 2>/dev/null)

# ---- 记录历史数据（用于燃烧速率计算）----
NOW=$(date +%s)
if [ -n "$FIVE_PCT" ] || [ -n "$WEEK_PCT" ]; then
    # 只在有新数据（stdin 非空）时记录，避免缓存重复写入
    if [ -n "$(echo "$INPUT" | jq -r '.rate_limits // empty' 2>/dev/null)" ]; then
        # 检查是否与上次记录相同（去重）
        LAST_LINE=""
        [ -f "$HISTORY_FILE" ] && LAST_LINE=$(tail -1 "$HISTORY_FILE" 2>/dev/null)
        LAST_FIVE=$(echo "$LAST_LINE" | cut -d'|' -f2 2>/dev/null)
        LAST_WEEK=$(echo "$LAST_LINE" | cut -d'|' -f3 2>/dev/null)

        if [ "${FIVE_PCT:-0}" != "$LAST_FIVE" ] || [ "${WEEK_PCT:-0}" != "$LAST_WEEK" ]; then
            echo "${NOW}|${FIVE_PCT:-0}|${WEEK_PCT:-0}" >> "$HISTORY_FILE"
            # 保留最近 MAX_HISTORY 条
            if [ -f "$HISTORY_FILE" ]; then
                LINES=$(wc -l < "$HISTORY_FILE" | tr -d ' ')
                if [ "$LINES" -gt "$MAX_HISTORY" ]; then
                    tail -n "$MAX_HISTORY" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
                fi
            fi
        fi
    fi
fi

# ---- 根据百分比获取颜色 ----
get_color() {
    local pct_int=$(printf '%.0f' "${1:-0}" 2>/dev/null || echo "0")
    if [ "$pct_int" -ge 80 ]; then
        printf '%b' "$C_RED_BOLD"
    elif [ "$pct_int" -ge 60 ]; then
        printf '%b' "$C_YELLOW"
    else
        printf '%b' "$C_GREEN"
    fi
}

# ---- 带颜色的进度条 ----
make_bar() {
    local pct=${1:-0}
    local width=${2:-10}
    local pct_int=$(printf '%.0f' "$pct" 2>/dev/null || echo "0")
    local color
    color=$(get_color "$pct")
    local filled=$(( pct_int * width / 100 ))
    [ "$filled" -gt "$width" ] && filled=$width
    [ "$filled" -lt 0 ] && filled=0
    local empty=$(( width - filled ))

    local bar="${color}"
    for ((i=0; i<filled; i++)); do bar+="█"; done
    bar+="${C_DIM}"
    for ((i=0; i<empty; i++)); do bar+="░"; done
    bar+="${C_RESET}"
    printf '%b' "$bar"
}

# ---- 格式化重置时间（实时计算）----
format_reset() {
    local reset_ts="$1"
    if [ -z "$reset_ts" ]; then
        echo ""
        return
    fi

    local now
    now=$(date +%s)
    local diff=$(( reset_ts - now ))

    if [ "$diff" -le 0 ]; then
        echo "now"
        return
    fi

    if [ "$diff" -lt 86400 ]; then
        local hours=$(( diff / 3600 ))
        local mins=$(( (diff % 3600) / 60 ))
        local secs=$(( diff % 60 ))
        if [ "$hours" -gt 0 ]; then
            printf "%dh%dm%ds" "$hours" "$mins" "$secs"
        elif [ "$mins" -gt 0 ]; then
            printf "%dm%ds" "$mins" "$secs"
        else
            printf "%ds" "$secs"
        fi
    else
        if [[ "$OSTYPE" == "darwin"* ]]; then
            date -r "$reset_ts" "+%a %H:%M" 2>/dev/null || echo "--"
        else
            date -d "@$reset_ts" "+%a %H:%M" 2>/dev/null || echo "--"
        fi
    fi
}

# ---- 格式化 token ----
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

# ---- 燃烧速率计算 ----
# 参数: $1=当前百分比, $2=列号(2=session, 3=week)
calc_burn_rate() {
    local current_pct=${1:-0}
    local col=$2

    if [ ! -f "$HISTORY_FILE" ]; then
        echo ""
        return
    fi

    local lines
    lines=$(wc -l < "$HISTORY_FILE" | tr -d ' ')
    if [ "$lines" -lt 2 ]; then
        echo ""
        return
    fi

    # 找 10 分钟前的数据点（或最早的可用数据）
    local target_ts=$(( NOW - 600 ))
    local ref_line=""

    while IFS= read -r line; do
        local ts
        ts=$(echo "$line" | cut -d'|' -f1)
        if [ "$ts" -le "$target_ts" ] 2>/dev/null; then
            ref_line="$line"
        fi
    done < "$HISTORY_FILE"

    # 如果没有 10 分钟前的数据，用最早的记录
    if [ -z "$ref_line" ]; then
        ref_line=$(head -1 "$HISTORY_FILE")
    fi

    local ref_ts
    ref_ts=$(echo "$ref_line" | cut -d'|' -f1)
    local ref_val
    ref_val=$(echo "$ref_line" | cut -d'|' -f"$col")

    local time_diff=$(( NOW - ref_ts ))

    # 至少需要 120 秒的数据
    if [ "$time_diff" -lt 120 ]; then
        echo ""
        return
    fi

    # 计算每小时速率
    local val_diff
    val_diff=$(echo "$current_pct - $ref_val" | bc 2>/dev/null || echo "0")

    # 如果是负数（限额重置了），忽略
    local is_negative
    is_negative=$(echo "$val_diff < 0" | bc 2>/dev/null || echo "0")
    if [ "$is_negative" -eq 1 ]; then
        echo ""
        return
    fi

    local is_zero
    is_zero=$(echo "$val_diff == 0" | bc 2>/dev/null || echo "1")
    if [ "$is_zero" -eq 1 ]; then
        echo ""
        return
    fi

    local rate
    rate=$(echo "scale=1; $val_diff * 3600 / $time_diff" | bc 2>/dev/null || echo "0")

    # 预估耗尽时间
    local remaining
    remaining=$(echo "100 - $current_pct" | bc 2>/dev/null || echo "0")
    local eta_secs=""

    local rate_positive
    rate_positive=$(echo "$rate > 0" | bc 2>/dev/null || echo "0")
    if [ "$rate_positive" -eq 1 ]; then
        local eta_hours
        eta_hours=$(echo "scale=2; $remaining / $rate" | bc 2>/dev/null || echo "0")
        eta_secs=$(echo "scale=0; $eta_hours * 3600 / 1" | bc 2>/dev/null || echo "0")
    fi

    local color
    color=$(get_color "$current_pct")

    # 格式化输出
    local result="${color}🔥${rate}%/h${C_RESET}"

    # 添加预估耗尽时间
    if [ -n "$eta_secs" ] && [ "$eta_secs" -gt 0 ] 2>/dev/null; then
        local eta_h=$(( eta_secs / 3600 ))
        local eta_m=$(( (eta_secs % 3600) / 60 ))
        if [ "$eta_h" -gt 0 ]; then
            result+="${C_DIM} ~${eta_h}h${eta_m}m left${C_RESET}"
        else
            result+="${C_DIM} ~${eta_m}m left${C_RESET}"
        fi
    fi

    printf '%b' "$result"
}

# ---- 百分比文字带颜色 ----
colored_pct() {
    local pct=${1:-0}
    local pct_int
    pct_int=$(printf '%.0f' "$pct" 2>/dev/null || echo "0")
    local color
    color=$(get_color "$pct")
    printf '%b' "${color}${pct_int}%${C_RESET}"
}

# ---- 组装输出 ----
OUTPUT=""

# Session 限额
if [ -n "$FIVE_PCT" ]; then
    FIVE_BAR=$(make_bar "$FIVE_PCT" 10)
    FIVE_RESET_STR=$(format_reset "$FIVE_RESET")
    FIVE_PCT_STR=$(colored_pct "$FIVE_PCT")
    SESS_PART="⚡Session ${FIVE_BAR} ${FIVE_PCT_STR}"
    [ -n "$FIVE_RESET_STR" ] && SESS_PART+=" ↻${FIVE_RESET_STR}"

    # 燃烧速率
    BURN=$(calc_burn_rate "$FIVE_PCT" 2)
    [ -n "$BURN" ] && SESS_PART+=" ${BURN}"

    OUTPUT+="$SESS_PART"
fi

# Weekly 限额
if [ -n "$WEEK_PCT" ]; then
    WEEK_BAR=$(make_bar "$WEEK_PCT" 10)
    WEEK_RESET_STR=$(format_reset "$WEEK_RESET")
    WEEK_PCT_STR=$(colored_pct "$WEEK_PCT")
    WEEK_PART="🗓 Week ${WEEK_BAR} ${WEEK_PCT_STR}"
    [ -n "$WEEK_RESET_STR" ] && WEEK_PART+=" ↻${WEEK_RESET_STR}"

    # 燃烧速率
    BURN_W=$(calc_burn_rate "$WEEK_PCT" 3)
    [ -n "$BURN_W" ] && WEEK_PART+=" ${BURN_W}"

    [ -n "$OUTPUT" ] && OUTPUT+=" │ "
    OUTPUT+="$WEEK_PART"
fi

# Context Window
if [ -n "$CTX_USED_PCT" ]; then
    CTX_BAR=$(make_bar "$CTX_USED_PCT" 8)
    CTX_PCT_INT=$(printf '%.0f' "$CTX_USED_PCT")
    CTX_PCT_STR=$(colored_pct "$CTX_USED_PCT")
    if [ -n "$CTX_SIZE" ] && [ "$CTX_SIZE" -gt 0 ] 2>/dev/null; then
        CTX_USED_TOKENS=$(( CTX_SIZE * CTX_PCT_INT / 100 ))
        CTX_SIZE_STR=$(format_tokens "$CTX_SIZE")
        CTX_USED_STR=$(format_tokens "$CTX_USED_TOKENS")
        CTX_PART="Ctx ${CTX_BAR} ${CTX_PCT_STR}${C_DIM}(${CTX_USED_STR}/${CTX_SIZE_STR})${C_RESET}"
    else
        CTX_PART="Ctx ${CTX_BAR} ${CTX_PCT_STR}"
    fi
    [ -n "$OUTPUT" ] && OUTPUT+=" │ "
    OUTPUT+="$CTX_PART"
fi

# In/Out token
if [ "$TOTAL_IN" -gt 0 ] 2>/dev/null || [ "$TOTAL_OUT" -gt 0 ] 2>/dev/null; then
    IN_STR=$(format_tokens "$TOTAL_IN")
    OUT_STR=$(format_tokens "$TOTAL_OUT")
    TOK_PART="${C_DIM}In:${IN_STR} Out:${OUT_STR}${C_RESET}"
    [ -n "$OUTPUT" ] && OUTPUT+=" │ "
    OUTPUT+="$TOK_PART"
fi

if [ -z "$OUTPUT" ]; then
    OUTPUT="${C_DIM}⏳ waiting for data...${C_RESET}"
fi

echo -e "$OUTPUT"
