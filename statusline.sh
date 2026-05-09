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

# ---- 一次性解析所有字段 ----
NOW=$(date +%s)
IFS=$'\t' read -r FIVE_PCT FIVE_RESET WEEK_PCT WEEK_RESET CTX_USED_PCT CTX_SIZE TOTAL_IN TOTAL_OUT < <(
    jq -r '[
        (.rate_limits.five_hour.used_percentage // ""),
        (.rate_limits.five_hour.resets_at // ""),
        (.rate_limits.seven_day.used_percentage // ""),
        (.rate_limits.seven_day.resets_at // ""),
        (.context_window.used_percentage // ""),
        (.context_window.context_window_size // ""),
        (.context_window.total_input_tokens // 0),
        (.context_window.total_output_tokens // 0)
    ] | @tsv' <<< "$INPUT" 2>/dev/null
)

# ---- 记录历史数据（用于燃烧速率计算）----
if [ -n "$FIVE_PCT" ] || [ -n "$WEEK_PCT" ]; then
    if jq -e '.rate_limits' <<< "$INPUT" > /dev/null 2>&1; then
        LAST_LINE=""
        [ -f "$HISTORY_FILE" ] && LAST_LINE=$(tail -1 "$HISTORY_FILE" 2>/dev/null)
        IFS='|' read -r _ LAST_FIVE LAST_WEEK <<< "$LAST_LINE"

        if [ "${FIVE_PCT:-0}" != "$LAST_FIVE" ] || [ "${WEEK_PCT:-0}" != "$LAST_WEEK" ]; then
            echo "${NOW}|${FIVE_PCT:-0}|${WEEK_PCT:-0}" >> "$HISTORY_FILE"
            LINES=$(wc -l < "$HISTORY_FILE" | tr -d ' ')
            if [ "$LINES" -gt "$MAX_HISTORY" ]; then
                tail -n "$MAX_HISTORY" "$HISTORY_FILE" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
            fi
        fi
    fi
fi

# ---- 根据百分比获取颜色 ----
get_color() {
    local pct_int
    pct_int=$(printf '%.0f' "${1:-0}" 2>/dev/null || echo "0")
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
    local pct_int
    pct_int=$(printf '%.0f' "$pct" 2>/dev/null || echo "0")
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
    [ -z "$reset_ts" ] && echo "" && return

    local diff=$(( reset_ts - NOW ))

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
    awk -v n="$n" 'BEGIN {
        if (n >= 1000000) printf "%.1fM", n/1000000
        else if (n >= 1000) printf "%.0fk", n/1000
        else printf "%d", n
    }'
}

# ---- 燃烧速率计算 ----
# 参数: $1=当前百分比, $2=列号(2=session, 3=week)
calc_burn_rate() {
    local current_pct=${1:-0}
    local col=$2

    [ ! -f "$HISTORY_FILE" ] && echo "" && return

    local lines
    lines=$(wc -l < "$HISTORY_FILE" | tr -d ' ')
    [ "$lines" -lt 2 ] && echo "" && return

    # awk 单次扫描：找参考点 + 完成所有浮点运算
    local result
    result=$(awk -F'|' \
        -v target="$(( NOW - 600 ))" \
        -v col="$col" \
        -v now="$NOW" \
        -v current="$current_pct" '
        NR == 1 { first_ts = $1; first_val = $col }
        $1 + 0 <= target + 0 { ref_ts = $1; ref_val = $col }
        END {
            if (ref_ts == "") { ref_ts = first_ts; ref_val = first_val }
            time_diff = now - ref_ts
            if (time_diff < 120) exit
            val_diff = current + 0 - ref_val + 0
            if (val_diff <= 0) exit
            rate = val_diff * 3600 / time_diff
            if (rate <= 0) exit
            eta_secs = int((100 - current) / rate * 3600)
            printf "%.1f|%d", rate, eta_secs
        }
    ' "$HISTORY_FILE")

    [ -z "$result" ] && echo "" && return

    local rate eta_secs
    IFS='|' read -r rate eta_secs <<< "$result"

    local color
    color=$(get_color "$current_pct")
    local output="${color}🔥${rate}%/h${C_RESET}"

    if [ -n "$eta_secs" ] && [ "$eta_secs" -gt 0 ] 2>/dev/null; then
        local eta_h=$(( eta_secs / 3600 ))
        local eta_m=$(( (eta_secs % 3600) / 60 ))
        if [ "$eta_h" -gt 0 ]; then
            output+="${C_DIM} ~${eta_h}h${eta_m}m left${C_RESET}"
        else
            output+="${C_DIM} ~${eta_m}m left${C_RESET}"
        fi
    fi

    printf '%b' "$output"
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
    [ -n "$FIVE_RESET_STR" ] && SESS_PART+=" ↻ ${FIVE_RESET_STR}"

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
    [ -n "$WEEK_RESET_STR" ] && WEEK_PART+=" ↻ ${WEEK_RESET_STR}"

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
