# Claude Ses kurulumu:  powershell -ExecutionPolicy Bypass -File kur.ps1
# Klasörü istediğin yere koy, sonra bunu çalıştır. Klasörü taşırsan tekrar çalıştır.
param(
    [string]$ClaudeDir = (Join-Path $env:USERPROFILE '.claude'),
    [switch]$NoStartup,   # test için: açılışa ekleme
    [switch]$NoLaunch     # test için: uygulamayı başlatma
)
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
. "$root\lib\ortak.ps1"
. "$root\lib\ayarlar.ps1"

Get-ChildItem $root -Recurse -File | Unblock-File

Write-Host "Claude Ses kuruluyor: $root"

if (Test-TurkishVoice) { Write-Host "  [ok] Türkçe ses bulundu" }
else {
    Write-Host "  [!] Türkçe ses yok. Ayarlar > Saat ve dil > Konuşma > Ses ekle > Türkçe" -ForegroundColor Yellow
    Write-Host "      Kurulum devam ediyor; ses eklenene kadar varsayılan ses kullanılır." -ForegroundColor Yellow
}

New-Item -ItemType Directory -Force $ClaudeDir | Out-Null
$speak = ($root -replace '\\', '/') + '/speak.ps1'
$cmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$speak`""

# settings.json: eski Claude Ses girdilerini çıkar, yenilerini ekle; diğer ayarlara dokunma
$settingsPath = Join-Path $ClaudeDir 'settings.json'
if (Test-Path $settingsPath) { Copy-Item $settingsPath "$settingsPath.ClaudeSes.bak" -Force }
$settings = Read-ClaudeSettings $settingsPath
Remove-CSSettings $settings
Add-CSSettings $settings $cmd
Write-Utf8NoBom $settingsPath ($settings | ConvertTo-Json -Depth 20)
Write-Host "  [ok] Hook'lar ve izin eklendi: $settingsPath (yedek: settings.json.ClaudeSes.bak)"

# CLAUDE.md: işaretli bloğu yenile
$mdPath = Join-Path $ClaudeDir 'CLAUDE.md'
$md = if (Test-Path $mdPath) { [IO.File]::ReadAllText($mdPath, [Text.Encoding]::UTF8) } else { "" }
$rules = [IO.File]::ReadAllText("$root\claude-kurallari.md", [Text.Encoding]::UTF8).Replace('{{KOMUT}}', $cmd).TrimEnd()
$md = (Remove-CSRules $md).TrimStart("`n")
$md = $md + "`n$CSMarkerStart`n$rules`n$CSMarkerEnd`n"
Write-Utf8NoBom $mdPath $md
Write-Host "  [ok] Kurallar eklendi: $mdPath"

$vbs = Join-Path $root 'baslat.vbs'
if (-not $NoStartup) {
    $startup = (Get-CSSettings).startup
    Set-CSStartup $root $startup
    if ($startup) { Write-Host "  [ok] Bilgisayar açılınca başlayacak" }
    else { Write-Host "  [ok] Açılışta başlama ayarlarda kapalı, kısayol eklenmedi" }
}

if (-not $NoLaunch) {
    if (-not (Test-CSAppRunning)) { Start-Process "$env:WINDIR\System32\wscript.exe" -ArgumentList "`"$vbs`"" }
    Write-Host "  [ok] Uygulama çalışıyor (saatin yanındaki yuvarlak simge)"
}

Write-Host "`nBitti. Claude Code'u yeniden başlat ya da /hooks menüsünü bir kez aç."
