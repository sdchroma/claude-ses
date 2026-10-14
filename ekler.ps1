# Claude Ses ek gönderici: speak.ps1'in bıraktığı iş dosyasındaki ekleri Telegram'a yükler.
# Hook'tan ayrı süreçte çalışır; her dosyanın sonucu telefon.log'a yazılır.
param([Parameter(Mandatory)][string]$Job)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\ortak.ps1"

try {
    $data = [IO.File]::ReadAllText($Job, [Text.Encoding]::UTF8) | ConvertFrom-Json
    Remove-Item -LiteralPath $Job -ErrorAction SilentlyContinue
    $settings = Get-CSSettings
    $msg = [pscustomobject]@{ time = (Get-Date).ToString('o'); kind = "$($data.kind)"; project = "$($data.project)" }
    foreach ($p in @($data.files) | Select-Object -First $CSFilesMax) {
        $name = ("$p" -split '[\\/]')[-1]
        $att = Test-CSAttachment "$p"   # dosya iş sırasında değişmiş olabilir: tekrar kontrol
        if (-not $att.ok) { Add-CSPhoneLog (Format-CSPhoneLogLine $msg $false "ek $name : $($att.note)"); continue }
        try {
            try { Send-CSTelegramFile $settings $att }
            catch {
                # Telegram çok uzun/geniş resimleri fotoğraf olarak kabul etmez: dosya olarak tekrar dene
                if ($att.method -ne 'sendPhoto' -or "$_" -notmatch '^HTTP 4') { throw }
                $att.method = 'sendDocument'
                Send-CSTelegramFile $settings $att
            }
            Add-CSPhoneLog (Format-CSPhoneLogLine $msg $true '' "ek $name gitti")
        } catch { Write-CSError "ek: $_"; Add-CSPhoneLog (Format-CSPhoneLogLine $msg $false "ek $name hata: $_") }
    }
} catch {
    Write-CSError "ekler: $_"
}
