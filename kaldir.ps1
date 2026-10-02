# Claude Ses kaldırma:  powershell -ExecutionPolicy Bypass -File kaldir.ps1 [-GecmisiSil]
param(
    [string]$ClaudeDir = (Join-Path $env:USERPROFILE '.claude'),
    [switch]$GecmisiSil
)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
. "$root\lib\ortak.ps1"
. "$root\lib\ayarlar.ps1"

$settingsPath = Join-Path $ClaudeDir 'settings.json'
if (Test-Path $settingsPath) {
    $settings = Read-ClaudeSettings $settingsPath
    Remove-CSSettings $settings
    Write-Utf8NoBom $settingsPath ($settings | ConvertTo-Json -Depth 20)
    Write-Host "  [ok] Hook'lar ve izin çıkarıldı"
}

$mdPath = Join-Path $ClaudeDir 'CLAUDE.md'
if (Test-Path $mdPath) {
    Write-Utf8NoBom $mdPath (Remove-CSRules ([IO.File]::ReadAllText($mdPath, [Text.Encoding]::UTF8)))
    Write-Host "  [ok] Kurallar çıkarıldı"
}

Set-CSStartup $root $false
Write-Host "  [ok] Açılıştan çıkarıldı"

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object { $_.CommandLine -like '*ClaudeSes.ps1*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host "  [ok] Uygulama kapatıldı" }

if ($GecmisiSil -and (Test-Path $CSDir)) { Remove-Item $CSDir -Recurse -Force; Write-Host "  [ok] Geçmiş silindi" }

Write-Host "`nKaldırıldı. Klasörü silebilirsin."
