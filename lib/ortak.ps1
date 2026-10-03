# Claude Ses ortak fonksiyonlar (speak.ps1 ve ClaudeSes.ps1 tarafından yüklenir)

$script:CSDir        = Join-Path $env:LOCALAPPDATA 'ClaudeSes'
$script:CSQueue      = Join-Path $CSDir 'kuyruk'
$script:CSHistory    = Join-Path $CSDir 'gecmis.jsonl'
$script:CSState      = Join-Path $CSDir 'durum.json'
$script:CSSettingsPath = Join-Path $CSDir 'ayarlar.json'
$script:CSErrorLog   = Join-Path $CSDir 'hata.log'
$script:CSPhoneLog   = Join-Path $CSDir 'telefon.log'
$script:CSPhoneLogMax = 500
$script:CSAppMutex   = 'Local\ClaudeSes.App'
$script:CSSpeakMutex = 'Local\ClaudeSes.Speak'
$script:CSHistoryMax = 20
$script:CSNightEnd   = [TimeSpan]::FromHours(6)   # bu saatten önce açılış hâlâ "gece" sayılır
$script:CSRates      = @{ slow = 0.8; normal = 1.0; fast = 1.3 }

function Initialize-CSDirs {
    New-Item -ItemType Directory -Force $CSQueue | Out-Null
}

function Write-CSError([string]$msg) {
    try { Add-Content -Path $CSErrorLog -Value "$(Get-Date -Format s) $msg" -Encoding UTF8 } catch {}
}

# Sesli okunacak metinden dosya adı, yol, link, kod ve emojiyi çıkarır
function Clean-SpokenText([string]$t) {
    if (-not $t) { return "" }
    $t = $t -replace '```[\s\S]*?```', ' '
    $t = $t -replace '`[^`]*`', ' '
    $t = $t -replace '\[([^\]]*)\]\([^)]*\)', '$1'
    # Sondaki noktalama korunur: "(3/3)." -> " ."
    $t = $t -replace 'https?://\S*?([.,;:!?]*)(?=\s|$)', ' $1'
    $t = $t -replace '[A-Za-z]:[\\/]\S*?([.,;:!?]*)(?=\s|$)', ' $1'
    $t = $t -replace '\S*[\\/]\S*?([.,;:!?]*)(?=\s|$)', ' $1'
    $t = $t -replace '[\w\-]+(\.[\w\-]+)*\.[A-Za-z][A-Za-z0-9]{0,4}(?![\w''])', ' '
    $t = $t -replace '\bv\d+(\.\d+)+\b|\b\d+\.\d+\.\d+\b', ' '
    $t = $t -replace '[\uD800-\uDFFF☀-➿️]', ' '
    $t = $t -replace '[*_#>|]', ' '
    $t = $t -replace '\(\s*\)', ' '
    $t = $t -replace '\s+', ' '
    $t = $t -replace '\s+([,.;:!?])', '$1'
    $t = $t -replace '[,;:]+([.!?])', '$1'
    $t = $t.Trim()
    $t = $t -replace '[,;:]+$', '.'
    return $t
}

function New-CSDefaultSettings {
    return [ordered]@{
        nightEnabled  = $true      # her gece kendiliğinden sessize geç
        nightTime     = "23:00"
        idleMin       = 10         # otomatik mod: bu kadar dakika hareketsizlik = uzakta
        speakApproval = $true      # onay istekleri
        speakDone     = $true      # iş bitti özetleri
        speakInfo     = $true      # ara bilgilendirmeler
        maxAgeMin     = 2          # bundan eski mesajlar okunmaz
        startup       = $true      # bilgisayar açılınca başla
        rate          = "normal"   # slow | normal | fast
        phoneEnabled  = $false     # uzaktayken Telegram'a gönder
        phoneApproval = $true
        phoneDone     = $true
        phoneInfo     = $true
        phoneNight    = $true      # gece modunda da gönder
        telegramTokenEnc = ""      # DPAPI ile şifreli bot anahtarı
        telegramChatId   = ""
    }
}

# Eksik ya da bozuk dosyada varsayılanlara döner; geçersiz değerleri yok sayar
function Get-CSSettings([string]$path = $CSSettingsPath) {
    $s = New-CSDefaultSettings
    try {
        if (-not (Test-Path $path)) { return $s }
        $f = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
        foreach ($k in @($s.Keys)) {
            $v = $f.$k
            if ($null -eq $v) { continue }
            switch ($k) {
                { $_ -in 'nightEnabled', 'speakApproval', 'speakDone', 'speakInfo', 'startup', 'phoneEnabled', 'phoneApproval', 'phoneDone', 'phoneInfo', 'phoneNight' } { if ($v -is [bool]) { $s[$k] = $v } }
                'telegramTokenEnc' { $s[$k] = "$v" }
                'telegramChatId' { if ("$v" -match '^-?\d+$') { $s[$k] = "$v" } }
                'nightTime' { if ("$v" -match '^([01]\d|2[0-3]):[0-5]\d$') { $s[$k] = "$v" } }
                'idleMin' { if ([int]$v -ge 1 -and [int]$v -le 240) { $s[$k] = [int]$v } }
                'maxAgeMin' { if ([int]$v -ge 1 -and [int]$v -le 120) { $s[$k] = [int]$v } }
                'rate' { if ($CSRates.ContainsKey("$v")) { $s[$k] = "$v" } }
            }
        }
    } catch {}
    return $s
}

function Save-CSSettings($s, [string]$path = $CSSettingsPath) {
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    [IO.File]::WriteAllText($path, ($s | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
}

# mode: auto | here | away | quiet (gece);  prevMode: gece öncesi mod;  lastNight: son otomatik sessize geçilen gece
function Get-CSState {
    $st = [ordered]@{ mode = "auto"; prevMode = "auto"; lastNight = "" }
    try {
        $f = [IO.File]::ReadAllText($CSState, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($f.mode -in 'auto', 'here', 'away', 'quiet') { $st.mode = $f.mode }
        if ($f.prevMode -in 'auto', 'here', 'away') { $st.prevMode = $f.prevMode }
        if ($f.lastNight) { $st.lastNight = [string]$f.lastNight }
    } catch {}
    return $st
}

function Save-CSState($st) {
    Initialize-CSDirs
    [IO.File]::WriteAllText($CSState, ($st | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
}

# Gece saatine girildiyse ve bu gece henüz sessize geçilmediyse sessize alır.
# Elle sesi açarsan aynı gece tekrar susmaz; kendiliğinden kapanmaz. Değiştiyse $true döner.
function Update-NightState($state, $settings, [datetime]$now) {
    if (-not $settings.nightEnabled) { return $false }
    $start = [TimeSpan]::Parse($settings.nightTime)
    $tod = $now.TimeOfDay
    $key = $null
    if ($start -lt $CSNightEnd) {
        if ($tod -ge $start -and $tod -lt $CSNightEnd) { $key = $now.Date }
    } elseif ($tod -ge $start) { $key = $now.Date }
    elseif ($tod -lt $CSNightEnd) { $key = $now.Date.AddDays(-1) }
    if ($null -eq $key) { return $false }

    $keyStr = $key.ToString('yyyy-MM-dd')
    if ($state.lastNight -eq $keyStr) { return $false }
    if ($state.mode -ne 'quiet') { $state.prevMode = $state.mode }
    $state.mode = 'quiet'
    $state.lastNight = $keyStr
    return $true
}

function Get-SpeakDecision($msg, $settings, [string]$mode, [double]$idleMin, [datetime]$now) {
    $no = { param($note) [pscustomobject]@{ speak = $false; note = $note } }
    if ($mode -eq 'quiet') { return & $no 'gece' }
    $kindOn = switch ($msg.kind) { 'onay' { $settings.speakApproval } 'bitti' { $settings.speakDone } default { $settings.speakInfo } }
    if (-not $kindOn) { return & $no 'kapalı tür' }
    $away = switch ($mode) { 'here' { $false } 'away' { $true } default { $idleMin -ge $settings.idleMin } }
    if (-not $away) { return & $no 'buradaydın' }
    if (($now - [datetime]$msg.time).TotalMinutes -gt $settings.maxAgeMin) { return & $no 'eski' }
    return [pscustomobject]@{ speak = $true; note = '' }
}

# Telefon: sadece uzaktayken (gece dahil); ses kuyruğunu beklemez, eski mesaj sınırı yok
function Get-PhoneDecision($msg, $settings, [string]$mode, [double]$idleMin) {
    $no = { param($note) [pscustomobject]@{ send = $false; note = $note } }
    if (-not $settings.phoneEnabled) { return & $no 'kapalı' }
    if (-not $settings.telegramTokenEnc -or -not $settings.telegramChatId) { return & $no 'bağlı değil' }
    $kindOn = switch ($msg.kind) { 'onay' { $settings.phoneApproval } 'bitti' { $settings.phoneDone } default { $settings.phoneInfo } }
    if (-not $kindOn) { return & $no 'kapalı tür' }
    if ($mode -eq 'quiet' -and -not $settings.phoneNight) { return & $no 'gece' }
    $away = switch ($mode) { 'quiet' { $true } 'here' { $false } 'away' { $true } default { $idleMin -ge $settings.idleMin } }
    if (-not $away) { return & $no 'buradaydın' }
    return [pscustomobject]@{ send = $true; note = '' }
}

# Telefon logu: her mesaj için tek satır (gitti / gitmedi: sebep / hata: ...)
function Format-CSPhoneLogLine($msg, [bool]$sent, [string]$note) {
    $t = ([datetime]$msg.time).ToString('yyyy-MM-dd HH:mm:ss')
    $result = if ($sent) { 'gitti' } else { "gitmedi: $note" }
    return (@($t, $msg.project, $msg.kind, $result) | Where-Object { $_ }) -join ' '
}

function Add-CSPhoneLog([string]$line, [string]$path = $CSPhoneLog, [int]$max = $CSPhoneLogMax) {
    try {
        $lines = @()
        if (Test-Path $path) { $lines = @([IO.File]::ReadAllLines($path, [Text.Encoding]::UTF8)) }
        $lines = @($lines + $line)
        if ($lines.Count -gt $max) { $lines = $lines[($lines.Count - $max)..($lines.Count - 1)] }
        [IO.File]::WriteAllLines($path, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
    } catch {}
}

# Rapor/doküman linki: bilinen doküman siteleri ya da metni "rapor/report" olan link
function Find-ReportLink([string]$message) {
    if (-not $message) { return "" }
    $docHosts = 'https://([\w-]+\.)*(claude\.ai|notion\.so|notion\.site|docs\.google\.com)/'
    foreach ($m in [regex]::Matches($message, '\[([^\]]*)\]\((https?://[^)\s]+)\)')) {
        if ($m.Groups[2].Value -match $docHosts -or $m.Groups[1].Value -match '(?i)rapor|report') { return $m.Groups[2].Value }
    }
    foreach ($m in [regex]::Matches($message, 'https?://[^\s)\]>]+')) {
        $url = $m.Value.TrimEnd('.', ',', ';', ':')
        if ($url -match $docHosts) { return $url }
    }
    return ""
}

function Format-TelegramMessage($msg) {
    $kinds = @{
        onay  = @(([char]::ConvertFromUtf32(0x26A0) + [char]0xFE0F), "Onay gerekiyor")
        bitti = @([char]::ConvertFromUtf32(0x2705), "İş bitti")
        bilgi = @(([char]::ConvertFromUtf32(0x2139) + [char]0xFE0F), "Bilgi")
    }
    $k = if ($kinds.ContainsKey("$($msg.kind)")) { $kinds["$($msg.kind)"] } else { $kinds.bilgi }
    $esc = { param($s) "$s".Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }
    $title = if ($msg.project) { "$($k[0]) $(& $esc $msg.project) · $($k[1])" } else { "$($k[0]) $($k[1])" }
    $out = [ordered]@{ text = "<b>$title</b>`n$(& $esc $msg.text)"; reply_markup = $null }
    if ($msg.link) { $out.reply_markup = @{ inline_keyboard = @(, @(@{ text = "Raporu aç"; url = "$($msg.link)" })) } }
    return [pscustomobject]$out
}

# Windows kullanıcı hesabına bağlı şifreleme (DPAPI): başka bilgisayarda/kullanıcıda çözülemez
function Protect-CSSecret([string]$plain) {
    if (-not $plain) { return "" }
    return ConvertTo-SecureString $plain -AsPlainText -Force | ConvertFrom-SecureString
}

function Unprotect-CSSecret([string]$enc) {
    if (-not $enc) { return "" }
    try {
        $ss = ConvertTo-SecureString $enc
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
        try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
        finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
    } catch { return "" }
}

function Invoke-Telegram([string]$token, [string]$method, $body = $null) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $uri = "https://api.telegram.org/bot$token/$method"
    if ($null -eq $body) { return Invoke-RestMethod -Uri $uri -TimeoutSec 15 }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 10 -Compress))
    return Invoke-RestMethod -Uri $uri -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 15
}

function Send-CSTelegram($settings, $msg) {
    $token = Unprotect-CSSecret $settings.telegramTokenEnc
    if (-not $token) { throw "Bot anahtarı çözülemedi (başka bilgisayardan kopyalandıysa Ayarlar'dan tekrar gir)" }
    $f = Format-TelegramMessage $msg
    $body = [ordered]@{ chat_id = $settings.telegramChatId; text = $f.text; parse_mode = 'HTML'; disable_web_page_preview = $true }
    if ($f.reply_markup) { $body.reply_markup = $f.reply_markup }
    $null = Invoke-Telegram $token 'sendMessage' $body
}

# Bota en son mesaj atan sohbeti bulur. Dönüş: @{ chatId; name }
function Connect-CSTelegram([string]$token) {
    try { $me = Invoke-Telegram $token 'getMe' } catch { throw "Bot anahtarı geçersiz ya da internete ulaşılamıyor." }
    $updates = Invoke-Telegram $token 'getUpdates'
    $chat = @($updates.result | Where-Object { $_.message } | ForEach-Object { $_.message.chat }) | Select-Object -Last 1
    if (-not $chat) { throw "Önce Telegram'da @$($me.result.username) botuna herhangi bir mesaj at, sonra tekrar Bağla'ya bas." }
    return @{ chatId = "$($chat.id)"; name = "$($chat.first_name)"; bot = "$($me.result.username)" }
}

function Get-IdleMinutes {
    if (-not ('CSIdle' -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class CSIdle {
    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
    [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static double Minutes() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(lii);
        if (!GetLastInputInfo(ref lii)) return 0;
        return unchecked((uint)Environment.TickCount - lii.dwTime) / 60000.0;
    }
}
"@
    }
    return [CSIdle]::Minutes()
}

function Set-CSStartup([string]$root, [bool]$on) {
    $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Claude Ses.lnk'
    if (-not $on) { if (Test-Path $lnk) { Remove-Item $lnk }; return }
    $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
    $sc.TargetPath = "$env:WINDIR\System32\wscript.exe"
    $sc.Arguments = "`"$(Join-Path $root 'baslat.vbs')`""
    $sc.WorkingDirectory = $root
    $sc.Save()
}

function Get-SpeechBytes([string]$text, [string]$rate = "normal") {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media, ContentType = WindowsRuntime]
    $null = [Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType = WindowsRuntime]

    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1
    $await = {
        param($op, [Type]$resultType)
        $task = $asTask.MakeGenericMethod($resultType).Invoke($null, @($op))
        $task.Wait() | Out-Null
        $task.Result
    }

    $synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
    $voice = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { $_.Language -eq 'tr-TR' } | Select-Object -First 1
    if ($voice) { $synth.Voice = $voice }
    if ($synth.Options -and $CSRates.ContainsKey($rate)) { $synth.Options.SpeakingRate = $CSRates[$rate] }

    $stream = & $await ($synth.SynthesizeTextToStreamAsync($text)) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
    $size = [uint32]$stream.Size
    $reader = New-Object Windows.Storage.Streams.DataReader($stream.GetInputStreamAt(0))
    $null = & $await ($reader.LoadAsync($size)) ([uint32])
    $bytes = New-Object byte[] $size
    $reader.ReadBytes($bytes)
    return , $bytes
}

function Test-TurkishVoice {
    try {
        $null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media, ContentType = WindowsRuntime]
        return [bool]([Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { $_.Language -eq 'tr-TR' })
    } catch { return $false }
}

# WAV başlığından süreyi hesaplar (sıradaki mesajı ne zaman okuyacağımızı bilmek için)
function Get-WavDuration([byte[]]$bytes) {
    $byteRate = [BitConverter]::ToUInt32($bytes, 28)
    if ($byteRate -eq 0) { return [TimeSpan]::FromSeconds(3) }
    return [TimeSpan]::FromSeconds(($bytes.Length - 44) / $byteRate)
}

function New-CSMessage([string]$text, [string]$kind) {
    Initialize-CSDirs
    $msg = [ordered]@{ time = (Get-Date).ToString('o'); kind = $kind; text = $text }
    $name = '{0}-{1}' -f (Get-Date -Format 'yyyyMMddHHmmssfff'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $tmp = Join-Path $CSQueue "$name.tmp"
    [IO.File]::WriteAllText($tmp, ($msg | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
    Move-Item $tmp (Join-Path $CSQueue "$name.json")
}

function Add-CSHistory($msg, [bool]$spoken, [string]$note) {
    $entry = [ordered]@{ time = $msg.time; kind = $msg.kind; text = $msg.text; spoken = $spoken; note = $note }
    $line = $entry | ConvertTo-Json -Compress
    try {
        $lines = @()
        if (Test-Path $CSHistory) { $lines = @(Get-Content $CSHistory -Encoding UTF8 | Select-Object -Last ($CSHistoryMax - 1)) }
        $lines += $line
        [IO.File]::WriteAllLines($CSHistory, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
    } catch { Write-CSError "gecmis: $_" }
}

function Get-CSHistory {
    if (-not (Test-Path $CSHistory)) { return @() }
    return @(Get-Content $CSHistory -Encoding UTF8 | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} })
}

function Test-CSAppRunning {
    $m = $null
    if ([System.Threading.Mutex]::TryOpenExisting($CSAppMutex, [ref]$m)) { $m.Dispose(); return $true }
    return $false
}
