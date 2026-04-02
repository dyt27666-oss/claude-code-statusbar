# ============================================================
# Claude Code StatusBar - Windows 安装脚本
# 利用 Claude Code 原生 statusLine 功能
# 将 statusline.ps1 注册到 ~/.claude/settings.json
# ============================================================

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$StatuslineScript = Join-Path $ScriptDir "statusline.ps1"

Write-Host ""
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host "  |   Claude Code StatusBar - Installer      |" -ForegroundColor Cyan
Write-Host "  |   Windows Edition                        |" -ForegroundColor Cyan
Write-Host "  +==========================================+" -ForegroundColor Cyan
Write-Host ""

# ---- 前置检查 ----

# 检查状态栏脚本
if (-not (Test-Path $StatuslineScript)) {
    Write-Host "  [X] statusline.ps1 not found in $ScriptDir" -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] statusline.ps1 found" -ForegroundColor Green

# 检查 PowerShell 版本
$psVer = $PSVersionTable.PSVersion
Write-Host "  [OK] PowerShell $psVer" -ForegroundColor Green

# 检查 claude
$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeCmd) {
    $claudeVer = & claude --version 2>&1
    Write-Host "  [OK] Claude Code $claudeVer" -ForegroundColor Green
} else {
    Write-Host "  [!] claude command not found (install it first)" -ForegroundColor Yellow
    Write-Host "      https://docs.anthropic.com/en/docs/claude-code"
}

# ---- 写入配置 ----

$SettingsFile = Join-Path $env:USERPROFILE ".claude\settings.json"

# 确保目录存在
$settingsDir = Split-Path -Parent $SettingsFile
if (-not (Test-Path $settingsDir)) {
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
}

# 确保文件存在
if (-not (Test-Path $SettingsFile)) {
    Set-Content -Path $SettingsFile -Value "{}" -Encoding UTF8
}

# 备份
$Backup = "${SettingsFile}.bak"
Copy-Item $SettingsFile $Backup -Force
Write-Host "  [OK] Backup -> $Backup" -ForegroundColor Green

# 读取现有配置
try {
    $settings = Get-Content -Path $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    $settings = [PSCustomObject]@{}
}

# 构建 statusLine 命令 — 使用 pwsh 调用脚本
$command = "pwsh -NoProfile -File `"$StatuslineScript`""

# 写入 statusLine 配置
$statusLine = [PSCustomObject]@{
    type = "command"
    command = $command
    refreshTime = 1
}

# 添加或覆盖 statusLine 属性
if ($settings.PSObject.Properties["statusLine"]) {
    $settings.statusLine = $statusLine
} else {
    $settings | Add-Member -NotePropertyName "statusLine" -NotePropertyValue $statusLine
}

# 保存
$settings | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsFile -Encoding UTF8

Write-Host "  [OK] statusLine config written" -ForegroundColor Green

Write-Host ""
Write-Host "  Done! Restart Claude Code to see the status bar." -ForegroundColor Green
Write-Host ""
Write-Host "  +---------------------------------------------------------------------+" -ForegroundColor DarkGray
Write-Host "  | Session XXXXX..... 55% ~2h | Week XXX....... 32% ~Sun 00:00        |" -ForegroundColor DarkGray
Write-Host "  +---------------------------------------------------------------------+" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Uninstall:" -ForegroundColor Gray
Write-Host "    pwsh $(Join-Path $ScriptDir 'uninstall.ps1')" -ForegroundColor Gray
Write-Host ""
