# Claude Ses giriş noktası
#   speak.ps1 -Text "..."     -> Claude'un ara bilgilendirmesi
#   speak.ps1 Notification    -> hook: onay / bekleme bildirimi
#   speak.ps1 Stop            -> hook: son mesajdaki "🔊" satırı
#   -DryRun                   -> okumadan sadece cümleyi yazdırır
# Uygulama açıksa mesajı kuyruğa bırakır (okuyup okumamaya o karar verir);
# kapalıysa kendisi, diğer seslerle çakışmadan sırayla okur.
param([string]$Event = "", [string]$Text = "", [switch]$DryRun)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\ortak.ps1"

function Get-HookInput {
    try {
        $stdin = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [Text.Encoding]::UTF8)
        $raw = $stdin.ReadToEnd()
        if ($raw) { return $raw | ConvertFrom-Json }
    } catch {}
    return $null
}

function Get-LastAssistantText($data) {
    if ($data.last_assistant_message) { return [string]$data.last_assistant_message }
    if (-not $data.transcript_path -or -not (Test-Path $data.transcript_path)) { return "" }
    $lines = @(Get-Content $data.transcript_path -Tail 300 -Encoding UTF8)
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        try { $entry = $lines[$i] | ConvertFrom-Json } catch { continue }
        if ($entry.type -ne "assistant") { continue }
        $parts = @($entry.message.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text })
        if ($parts.Count -gt 0) { return ($parts -join "`n") }
    }
    return ""
}

function Get-StopSentence($message) {
    if (-not $message) { return "İş bitti." }
    $marker = [char]::ConvertFromUtf32(0x1F50A)
    $line = ($message -split "`n" | Where-Object { $_.Trim().StartsWith($marker) } | Select-Object -Last 1)
    if ($line) { return $line.Trim().Substring($marker.Length).Trim() }

    # Yedek: temizlenmiş ilk cümle, en fazla 20 kelime
    $first = ((Clean-SpokenText $message) -split '(?<=[.!?])\s')[0]
    $words = $first -split ' '
    if ($words.Count -gt 20) { $first = ($words[0..19] -join ' ') + '.' }
    if ($first) { return $first }
    return "İş bitti."
}

$kind = "bilgi"
$link = ""
$data = $null
if (-not $Text) {
    $data = Get-HookInput
    if ($Event -eq "Notification") {
        $kind = "onay"
        if ($data.notification_type -eq "idle_prompt") { $Text = "Seni bekliyorum." }
        else {
            $tool = if ($data.message -match 'use (\w+)') { $Matches[1] } else { "" }
            switch -Regex ($tool) {
                '^(Bash|PowerShell)$' { $Text = "Onayın gerekiyor, bir komut çalıştırmak istiyorum." }
                '^(Edit|Write|NotebookEdit)$' { $Text = "Onayın gerekiyor, bir dosyayı değiştirmek istiyorum." }
                '^Web' { $Text = "Onayın gerekiyor, internete erişmek istiyorum." }
                default { $Text = "Onayın gerekiyor." }
            }
        }
    } else {
        $kind = "bitti"
        $lastMessage = Get-LastAssistantText $data
        $Text = Get-StopSentence $lastMessage
        $link = Find-ReportLink $lastMessage
    }
}

$Text = Clean-SpokenText $Text
if (-not $Text) { exit 0 }
$project = if ($data.cwd) { Split-Path -Leaf $data.cwd } else { Split-Path -Leaf (Get-Location).Path }
$msg = [pscustomobject]@{ time = (Get-Date).ToString('o'); kind = $kind; text = $Text; project = $project; link = "$link" }
if ($DryRun) { [Console]::OutputEncoding = [Text.Encoding]::UTF8; Write-Output $Text; if ($link) { Write-Output "link: $link" }; exit 0 }

try {
    Initialize-CSDirs
    $settings = Get-CSSettings
    $state = Get-CSState
    $appRunning = Test-CSAppRunning
    # Uygulama açıksa durumu o yazar; kapalıysa gece saatini burada uygularız
    if ((Update-NightState $state $settings (Get-Date)) -and -not $appRunning) { Save-CSState $state }

    # Telefon: ses sırasını beklemeden hemen. Uygulama kapalıysa "uzakta" kabul edilir.
    $phoneMode = if ($appRunning -or $state.mode -eq 'quiet') { $state.mode } else { 'away' }
    $pd = Get-PhoneDecision $msg $settings $phoneMode (Get-IdleMinutes)
    if ($pd.send) {
        try { Send-CSTelegram $settings $msg; Add-CSPhoneLog (Format-CSPhoneLogLine $msg $true '') }
        catch { Write-CSError "telegram: $_"; Add-CSPhoneLog (Format-CSPhoneLogLine $msg $false "hata: $_") }
    } else { Add-CSPhoneLog (Format-CSPhoneLogLine $msg $false $pd.note) }

    if ($appRunning) { New-CSMessage $Text $kind; exit 0 }

    # Uygulama kapalı: gece/sessiz ve "ne okunsun" ayarları yine geçerli; değilse "uzaktayım" kabul edilir, sırayla okunur
    $mode = if ($state.mode -eq 'quiet') { 'quiet' } else { 'away' }
    $mutex = New-Object System.Threading.Mutex($false, $CSSpeakMutex)
    try { $null = $mutex.WaitOne([TimeSpan]::FromMinutes($settings.maxAgeMin)) } catch [System.Threading.AbandonedMutexException] {}
    try {
        $d = Get-SpeakDecision $msg $settings $mode 0 (Get-Date)
        if (-not $d.speak) { Add-CSHistory $msg $false $d.note; exit 0 }
        $bytes = Get-SpeechBytes $Text $settings.rate
        $player = New-Object System.Media.SoundPlayer((New-Object System.IO.MemoryStream(, $bytes)))
        $player.PlaySync()
        Add-CSHistory $msg $true "uygulama kapalı"
    } finally { $mutex.ReleaseMutex() }
} catch {
    Write-CSError "speak: $_"
}
