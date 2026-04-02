# ============================================================
# Claude Code StatusBar - Windows 卸载脚本
# 从 ~/.claude/settings.json 移除 statusLine 配置
# ============================================================

$ErrorActionPreference = "Stop"

$SettingsFile = Join-Path $env:USERPROFILE ".claude\settings.json"

if (-not (Test-Path $SettingsFile)) {
    Write-Host "Nothing to uninstall (settings.json not found)"
    exit 0
}

try {
    $settings = Get-Content -Path $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-Host "Nothing to uninstall (invalid settings.json)"
    exit 0
}

if (-not $settings.PSObject.Properties["statusLine"]) {
    Write-Host "Nothing to uninstall (statusLine not configured)"
    exit 0
}

$settings.PSObject.Properties.Remove("statusLine")
$settings | ConvertTo-Json -Depth 10 | Set-Content -Path $SettingsFile -Encoding UTF8

Write-Host "Done! statusLine removed from settings.json" -ForegroundColor Green
Write-Host "   Restart Claude Code to apply."

# 清理缓存文件
$cacheFile = Join-Path $env:TEMP "claude-sb-cache.json"
$historyFile = Join-Path $env:TEMP "claude-sb-history.csv"
if (Test-Path $cacheFile) { Remove-Item $cacheFile -Force }
if (Test-Path $historyFile) { Remove-Item $historyFile -Force }
Write-Host "   Cache files cleaned up."
