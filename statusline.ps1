# ============================================================
# Claude Code 状态栏脚本 v2 (Windows PowerShell)
# Features: 燃烧速率 | 颜色警告 | 数据缓存自动刷新
# Requires: PowerShell 5.1+ (no jq needed)
# ============================================================

# ---- 文件路径 ----
$CacheFile = Join-Path $env:TEMP "claude-sb-cache.json"
$HistoryFile = Join-Path $env:TEMP "claude-sb-history.csv"
$MaxHistory = 120

# ---- ANSI 颜色 ----
$ESC = [char]27
$C_RED = "$ESC[31m"
$C_RED_BOLD = "$ESC[1;31m"
$C_YELLOW = "$ESC[33m"
$C_GREEN = "$ESC[32m"
$C_DIM = "$ESC[2m"
$C_RESET = "$ESC[0m"

# ---- 读取 stdin ----
$Input = @($input) -join "`n"

if ($Input -and $Input.Trim()) {
    $Input = $Input.Trim()
    Set-Content -Path $CacheFile -Value $Input -Encoding UTF8 -NoNewline
} elseif (Test-Path $CacheFile) {
    $Input = Get-Content -Path $CacheFile -Raw -Encoding UTF8
} else {
    Write-Host "${C_DIM}$([char]0x23F3) waiting...${C_RESET}"
    exit 0
}

if (-not $Input -or -not $Input.Trim()) {
    Write-Host "${C_DIM}$([char]0x23F3) waiting...${C_RESET}"
    exit 0
}

# ---- 解析 JSON ----
try {
    $Data = $Input | ConvertFrom-Json
} catch {
    Write-Host "${C_DIM}$([char]0x23F3) waiting...${C_RESET}"
    exit 0
}

$FivePct = $null; $FiveReset = $null
$WeekPct = $null; $WeekReset = $null
$CtxPct = $null; $CtxSize = $null
$TotalIn = 0; $TotalOut = 0

if ($Data.rate_limits.five_hour) {
    $FivePct = $Data.rate_limits.five_hour.used_percentage
    $FiveReset = $Data.rate_limits.five_hour.resets_at
}
if ($Data.rate_limits.seven_day) {
    $WeekPct = $Data.rate_limits.seven_day.used_percentage
    $WeekReset = $Data.rate_limits.seven_day.resets_at
}
if ($Data.context_window) {
    $CtxPct = $Data.context_window.used_percentage
    $CtxSize = $Data.context_window.context_window_size
    $TotalIn = [int]($Data.context_window.total_input_tokens)
    $TotalOut = [int]($Data.context_window.total_output_tokens)
}

# ---- 当前时间戳 (Unix epoch) ----
$Now = [int][double]::Parse((Get-Date -UFormat %s))

# ---- 记录历史数据 ----
if ($null -ne $FivePct -or $null -ne $WeekPct) {
    $fv = if ($FivePct) { $FivePct } else { 0 }
    $wk = if ($WeekPct) { $WeekPct } else { 0 }
    $NewLine = "${Now}|${fv}|${wk}"
    $ShouldWrite = $true

    if (Test-Path $HistoryFile) {
        $LastLine = Get-Content -Path $HistoryFile -Tail 1
        if ($LastLine) {
            $parts = $LastLine -split '\|'
            if ($parts.Count -ge 3 -and $parts[1] -eq "$fv" -and $parts[2] -eq "$wk") {
                $ShouldWrite = $false
            }
        }
    }

    if ($ShouldWrite) {
        Add-Content -Path $HistoryFile -Value $NewLine -Encoding UTF8
        # 保留最近 MaxHistory 条
        if (Test-Path $HistoryFile) {
            $lines = Get-Content -Path $HistoryFile
            if ($lines.Count -gt $MaxHistory) {
                $lines | Select-Object -Last $MaxHistory | Set-Content -Path $HistoryFile -Encoding UTF8
            }
        }
    }
}

# ---- 根据百分比获取颜色 ----
function Get-Color([double]$pct) {
    if ($pct -ge 80) { return $C_RED_BOLD }
    elseif ($pct -ge 60) { return $C_YELLOW }
    else { return $C_GREEN }
}

# ---- 带颜色的进度条 ----
function Make-Bar([double]$pct, [int]$width = 10) {
    $pctInt = [Math]::Round($pct)
    $color = Get-Color $pct
    $filled = [Math]::Min([Math]::Max([int]($pctInt * $width / 100), 0), $width)
    $empty = $width - $filled

    $bar = $color
    $bar += ([string][char]0x2588) * $filled   # █
    $bar += $C_DIM
    $bar += ([string][char]0x2591) * $empty     # ░
    $bar += $C_RESET
    return $bar
}

# ---- 格式化重置时间 ----
function Format-Reset([object]$resetTs) {
    if ($null -eq $resetTs) { return "" }
    $ts = [int]$resetTs
    $diff = $ts - $Now

    if ($diff -le 0) { return "now" }

    if ($diff -lt 86400) {
        $hours = [Math]::Floor($diff / 3600)
        $mins = [Math]::Floor(($diff % 3600) / 60)
        $secs = $diff % 60
        if ($hours -gt 0) { return "${hours}h${mins}m${secs}s" }
        elseif ($mins -gt 0) { return "${mins}m${secs}s" }
        else { return "${secs}s" }
    } else {
        $dt = (Get-Date "1970-01-01 00:00:00").AddSeconds($ts).ToLocalTime()
        return $dt.ToString("ddd HH:mm")
    }
}

# ---- 格式化 token ----
function Format-Tokens([long]$n) {
    if ($n -ge 1000000) { return "{0:F1}M" -f ($n / 1000000) }
    elseif ($n -ge 1000) { return "{0:F0}k" -f ($n / 1000) }
    else { return "$n" }
}

# ---- 燃烧速率计算 ----
function Calc-BurnRate([double]$currentPct, [int]$col) {
    if (-not (Test-Path $HistoryFile)) { return "" }

    $lines = Get-Content -Path $HistoryFile
    if ($lines.Count -lt 2) { return "" }

    # 找 10 分钟前的数据点
    $targetTs = $Now - 600
    $refLine = $null

    foreach ($line in $lines) {
        $parts = $line -split '\|'
        if ($parts.Count -ge 3) {
            $ts = [int]$parts[0]
            if ($ts -le $targetTs) { $refLine = $line }
        }
    }

    # 没有 10 分钟前的数据，用最早的
    if (-not $refLine) { $refLine = $lines[0] }

    $refParts = $refLine -split '\|'
    if ($refParts.Count -lt 3) { return "" }

    $refTs = [int]$refParts[0]
    $refVal = [double]$refParts[$col - 1]
    $timeDiff = $Now - $refTs

    # 至少 120 秒
    if ($timeDiff -lt 120) { return "" }

    $valDiff = $currentPct - $refVal

    # 负数或零忽略
    if ($valDiff -le 0) { return "" }

    $rate = [Math]::Round($valDiff * 3600 / $timeDiff, 1)
    $color = Get-Color $currentPct

    $result = "${color}$([char]0x1F525)${rate}%/h${C_RESET}"

    # 预估耗尽
    if ($rate -gt 0) {
        $remaining = 100 - $currentPct
        $etaSecs = [int]($remaining / $rate * 3600)
        if ($etaSecs -gt 0) {
            $etaH = [Math]::Floor($etaSecs / 3600)
            $etaM = [Math]::Floor(($etaSecs % 3600) / 60)
            if ($etaH -gt 0) {
                $result += "${C_DIM} ~${etaH}h${etaM}m left${C_RESET}"
            } else {
                $result += "${C_DIM} ~${etaM}m left${C_RESET}"
            }
        }
    }

    return $result
}

# ---- 百分比文字带颜色 ----
function Colored-Pct([double]$pct) {
    $pctInt = [Math]::Round($pct)
    $color = Get-Color $pct
    return "${color}${pctInt}%${C_RESET}"
}

# ---- 组装输出 ----
$Output = ""

# Session 限额
if ($null -ne $FivePct) {
    $bar = Make-Bar $FivePct 10
    $resetStr = Format-Reset $FiveReset
    $pctStr = Colored-Pct $FivePct
    $sess = "$([char]0x26A1)Session ${bar} ${pctStr}"
    if ($resetStr) { $sess += " $([char]0x21BB)${resetStr}" }

    $burn = Calc-BurnRate $FivePct 2
    if ($burn) { $sess += " ${burn}" }

    $Output += $sess
}

# Weekly 限额
if ($null -ne $WeekPct) {
    $bar = Make-Bar $WeekPct 10
    $resetStr = Format-Reset $WeekReset
    $pctStr = Colored-Pct $WeekPct
    $week = "$([char]0x1F5D3) Week ${bar} ${pctStr}"
    if ($resetStr) { $week += " $([char]0x21BB)${resetStr}" }

    $burn = Calc-BurnRate $WeekPct 3
    if ($burn) { $week += " ${burn}" }

    if ($Output) { $Output += " $([char]0x2502) " }
    $Output += $week
}

# Context Window
if ($null -ne $CtxPct) {
    $bar = Make-Bar $CtxPct 8
    $pctStr = Colored-Pct $CtxPct
    $pctInt = [Math]::Round($CtxPct)
    if ($CtxSize -and $CtxSize -gt 0) {
        $usedTokens = [int]($CtxSize * $pctInt / 100)
        $sizeStr = Format-Tokens $CtxSize
        $usedStr = Format-Tokens $usedTokens
        $ctx = "Ctx ${bar} ${pctStr}${C_DIM}(${usedStr}/${sizeStr})${C_RESET}"
    } else {
        $ctx = "Ctx ${bar} ${pctStr}"
    }
    if ($Output) { $Output += " $([char]0x2502) " }
    $Output += $ctx
}

# In/Out token
if ($TotalIn -gt 0 -or $TotalOut -gt 0) {
    $inStr = Format-Tokens $TotalIn
    $outStr = Format-Tokens $TotalOut
    $tok = "${C_DIM}In:${inStr} Out:${outStr}${C_RESET}"
    if ($Output) { $Output += " $([char]0x2502) " }
    $Output += $tok
}

if (-not $Output) {
    $Output = "${C_DIM}$([char]0x23F3) waiting for data...${C_RESET}"
}

Write-Host $Output
