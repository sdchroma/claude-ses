# Claude Ses simge uygulaması: durum seçimi, gece modu, ayarlar, kuyruğu sırayla okuma, son mesajlar
# Başlatma: baslat.vbs (konsol penceresi açmadan)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\lib\ortak.ps1"

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Tek kopya: zaten açıksa çık. Bu mutex aynı zamanda speak.ps1'e "uygulama açık" sinyali.
$createdNew = $false
$appMutex = New-Object System.Threading.Mutex($true, $CSAppMutex, [ref]$createdNew)
if (-not $createdNew) { exit 0 }

Initialize-CSDirs
$script:settings = Get-CSSettings
$script:state = Get-CSState
$script:busyUntil = [datetime]::MinValue
$script:player = $null
$modeNames = @{ auto = "Otomatik"; here = "Buradayım"; away = "Uzaktayım"; quiet = "Sessiz (gece)" }
$rateNames = [ordered]@{ slow = "Yavaş"; normal = "Normal"; fast = "Hızlı" }

function Test-Away {
    switch ($script:state.mode) {
        "quiet" { return $false }
        "here" { return $false }
        "away" { return $true }
        default { return ((Get-IdleMinutes) -ge $script:settings.idleMin) }
    }
}

function New-DotIcon([System.Drawing.Color]$color, [string]$mark) {
    $bmp = New-Object System.Drawing.Bitmap 16, 16
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.FillEllipse((New-Object System.Drawing.SolidBrush $color), 1, 1, 14, 14)
    if ($mark -eq "A") {
        $font = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
        $g.DrawString("A", $font, [System.Drawing.Brushes]::White, (New-Object System.Drawing.RectangleF(0, 0, 16, 16)), $sf)
    } elseif ($mark -eq "moon") {
        $g.FillEllipse([System.Drawing.Brushes]::White, 4, 3, 9, 9)
        $g.FillEllipse((New-Object System.Drawing.SolidBrush $color), 6, 2, 8, 8)
    }
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$green = [System.Drawing.Color]::FromArgb(46, 160, 67)
$red = [System.Drawing.Color]::FromArgb(207, 34, 46)
$gray = [System.Drawing.Color]::FromArgb(110, 118, 129)
$icons = @{
    "here"      = New-DotIcon $green ""
    "away"      = New-DotIcon $red ""
    "auto-here" = New-DotIcon $green "A"
    "auto-away" = New-DotIcon $red "A"
    "quiet"     = New-DotIcon $gray "moon"
}

$tray = New-Object System.Windows.Forms.NotifyIcon
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$itemResume = $menu.Items.Add("Sesi aç")
$itemHere = $menu.Items.Add("Buradayım (sessiz)")
$itemAway = $menu.Items.Add("Uzaktayım (sesli)")
$itemAuto = $menu.Items.Add("Otomatik")
$itemQuiet = $menu.Items.Add("Sessiz (gece)")
$null = $menu.Items.Add("-")
$itemHistory = $menu.Items.Add("Son mesajlar")
$itemSettings = $menu.Items.Add("Ayarlar…")
$itemTest = $menu.Items.Add("Sesi dene")
$null = $menu.Items.Add("-")
$itemExit = $menu.Items.Add("Çıkış")
$tray.ContextMenuStrip = $menu

function Update-Tray {
    $mode = $script:state.mode
    $itemHere.Checked = ($mode -eq "here")
    $itemAway.Checked = ($mode -eq "away")
    $itemAuto.Checked = ($mode -eq "auto")
    $itemQuiet.Checked = ($mode -eq "quiet")
    $itemAuto.Text = "Otomatik ($($script:settings.idleMin) dk hareketsizlik)"
    $itemResume.Visible = ($mode -eq "quiet")
    $itemResume.Text = "Sesi aç (önceki mod: $($modeNames[$script:state.prevMode]))"
    if ($mode -eq "quiet") {
        $tray.Icon = $icons["quiet"]
        $tray.Text = "Claude Ses: Sessiz (gece)"
        return
    }
    $away = Test-Away
    if ($mode -eq "auto") {
        $tray.Icon = $icons[$(if ($away) { "auto-away" } else { "auto-here" })]
        $tray.Text = "Claude Ses: Otomatik (" + $(if ($away) { "uzaktasın, sesli" } else { "buradasın, sessiz" }) + ")"
    } else {
        $tray.Icon = $icons[$mode]
        $tray.Text = "Claude Ses: " + $modeNames[$mode]
    }
}

function Set-Mode([string]$m) {
    if ($m -eq "quiet" -and $script:state.mode -ne "quiet") { $script:state.prevMode = $script:state.mode }
    $script:state.mode = $m
    Save-CSState $script:state
    Update-Tray
}

function Start-Speech([string]$text, [string]$rate = $script:settings.rate) {
    $bytes = Get-SpeechBytes $text $rate
    $script:player = New-Object System.Media.SoundPlayer((New-Object System.IO.MemoryStream(, $bytes)))
    $script:player.Play()
    $script:busyUntil = (Get-Date) + (Get-WavDuration $bytes) + [TimeSpan]::FromMilliseconds(400)
}

function Show-History {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Claude Ses: son mesajlar"
    $form.Size = New-Object System.Drawing.Size(600, 420)
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true
    $list = New-Object System.Windows.Forms.ListBox
    $list.Dock = "Fill"
    $list.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $list.HorizontalScrollbar = $true
    $items = @(Get-CSHistory)
    [array]::Reverse($items)
    foreach ($h in $items) {
        $t = ([datetime]$h.time).ToString("dd.MM HH:mm")
        $s = if ($h.spoken) { "okundu" } else { "sessiz: $($h.note)" }
        $null = $list.Items.Add("$t   [$s]   $($h.text)")
    }
    if ($items.Count -eq 0) { $null = $list.Items.Add("Henüz mesaj yok.") }
    $form.Controls.Add($list)
    $null = $form.ShowDialog()
    $form.Dispose()
}

function Show-Settings {
    $s = $script:settings
    $font = New-Object System.Drawing.Font("Segoe UI", 9)
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Claude Ses: ayarlar"
    $form.Font = $font
    $form.ClientSize = New-Object System.Drawing.Size(770, 445)
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false; $form.MinimizeBox = $false
    $form.StartPosition = "CenterScreen"
    $form.TopMost = $true

    function Add-Group($text, $y, $h, $x = 10) {
        $g = New-Object System.Windows.Forms.GroupBox
        $g.Text = $text; $g.Location = "$x,$y"; $g.Size = "370,$h"
        $form.Controls.Add($g); return $g
    }
    function Add-Ctl($parent, $ctl, $x, $y, $text) {
        $ctl.Location = "$x,$y"
        if ($null -ne $text) { $ctl.Text = $text }
        if ($ctl -is [System.Windows.Forms.Label] -or $ctl -is [System.Windows.Forms.CheckBox]) { $ctl.AutoSize = $true }
        $parent.Controls.Add($ctl); return $ctl
    }

    $gNight = Add-Group "Gece modu" 10 85
    $chkNight = Add-Ctl $gNight (New-Object System.Windows.Forms.CheckBox) 15 24 "Her gece kendiliğinden sessize geç"
    $chkNight.Checked = $s.nightEnabled
    $null = Add-Ctl $gNight (New-Object System.Windows.Forms.Label) 15 54 "Saat:"
    $dtp = Add-Ctl $gNight (New-Object System.Windows.Forms.DateTimePicker) 60 50 $null
    $dtp.Format = "Custom"; $dtp.CustomFormat = "HH:mm"; $dtp.ShowUpDown = $true; $dtp.Width = 70
    $dtp.Value = [datetime]::Today + [TimeSpan]::Parse($s.nightTime)
    $chkNight.add_CheckedChanged({ $dtp.Enabled = $chkNight.Checked })
    $dtp.Enabled = $chkNight.Checked

    $gAuto = Add-Group "Otomatik mod" 105 60
    $null = Add-Ctl $gAuto (New-Object System.Windows.Forms.Label) 15 27 "Kaç dakika hareketsizlikte uzakta sayılayım:"
    $numIdle = Add-Ctl $gAuto (New-Object System.Windows.Forms.NumericUpDown) 295 24 $null
    $numIdle.Minimum = 1; $numIdle.Maximum = 240; $numIdle.Width = 60; $numIdle.Value = $s.idleMin

    $gKinds = Add-Group "Ne okunsun" 175 105
    $chkApproval = Add-Ctl $gKinds (New-Object System.Windows.Forms.CheckBox) 15 24 "Onay istekleri"
    $chkDone = Add-Ctl $gKinds (New-Object System.Windows.Forms.CheckBox) 15 50 "İş bitti özetleri"
    $chkInfo = Add-Ctl $gKinds (New-Object System.Windows.Forms.CheckBox) 15 76 "Ara bilgilendirmeler"
    $chkApproval.Checked = $s.speakApproval; $chkDone.Checked = $s.speakDone; $chkInfo.Checked = $s.speakInfo

    $gOther = Add-Group "Diğer" 290 110
    $null = Add-Ctl $gOther (New-Object System.Windows.Forms.Label) 15 27 "Kaç dakikadan eski mesajlar okunmasın:"
    $numAge = Add-Ctl $gOther (New-Object System.Windows.Forms.NumericUpDown) 295 24 $null
    $numAge.Minimum = 1; $numAge.Maximum = 120; $numAge.Width = 60; $numAge.Value = $s.maxAgeMin
    $chkStartup = Add-Ctl $gOther (New-Object System.Windows.Forms.CheckBox) 15 52 "Bilgisayar açılınca başlasın"
    $chkStartup.Checked = $s.startup
    $null = Add-Ctl $gOther (New-Object System.Windows.Forms.Label) 15 81 "Konuşma hızı:"
    $cmbRate = Add-Ctl $gOther (New-Object System.Windows.Forms.ComboBox) 110 77 $null
    $cmbRate.DropDownStyle = "DropDownList"; $cmbRate.Width = 100
    foreach ($v in $rateNames.Values) { $null = $cmbRate.Items.Add($v) }
    $cmbRate.SelectedIndex = [array]::IndexOf(@($rateNames.Keys), $s.rate)

    # Sağ sütun: Telefon (Telegram)
    $script:pendingTokenEnc = $s.telegramTokenEnc
    $script:pendingChatId = $s.telegramChatId
    $gPhone = Add-Group "Telefon (Telegram)" 10 390 390
    $chkPhone = Add-Ctl $gPhone (New-Object System.Windows.Forms.CheckBox) 15 24 "Uzaktayken telefona bildirim gönder"
    $chkPhone.Checked = $s.phoneEnabled
    $null = Add-Ctl $gPhone (New-Object System.Windows.Forms.Label) 15 56 "Bot anahtarı (BotFather'dan):"
    $txtToken = Add-Ctl $gPhone (New-Object System.Windows.Forms.TextBox) 15 76 $null
    $txtToken.Width = 340; $txtToken.UseSystemPasswordChar = $true
    $btnConnect = Add-Ctl $gPhone (New-Object System.Windows.Forms.Button) 15 106 "Bağla"
    $btnConnect.Width = 85
    $lblConn = Add-Ctl $gPhone (New-Object System.Windows.Forms.Label) 108 111 $(if ($s.telegramChatId) { "Bağlı (kayıtlı)" } else { "Bağlı değil" })
    $lblConn.MaximumSize = "250,0"
    $lblHelp = Add-Ctl $gPhone (New-Object System.Windows.Forms.Label) 15 140 "1) Telegram'da @BotFather'a /newbot yaz, botu oluştur.`n2) Verdiği anahtarı yukarı yapıştır.`n3) Kendi botuna herhangi bir mesaj at.`n4) Bağla'ya bas, sonra Kaydet."
    $lblHelp.ForeColor = [System.Drawing.Color]::DimGray
    $null = Add-Ctl $gPhone (New-Object System.Windows.Forms.Label) 15 222 "Ne gönderilsin:"
    $chkPApproval = Add-Ctl $gPhone (New-Object System.Windows.Forms.CheckBox) 15 244 "Onay istekleri"
    $chkPDone = Add-Ctl $gPhone (New-Object System.Windows.Forms.CheckBox) 15 268 "İş bitti özetleri (rapor linkiyle)"
    $chkPInfo = Add-Ctl $gPhone (New-Object System.Windows.Forms.CheckBox) 15 292 "Ara bilgilendirmeler"
    $chkPApproval.Checked = $s.phoneApproval; $chkPDone.Checked = $s.phoneDone; $chkPInfo.Checked = $s.phoneInfo
    $chkPNight = Add-Ctl $gPhone (New-Object System.Windows.Forms.CheckBox) 15 322 "Gece modunda da gönder"
    $chkPNight.Checked = $s.phoneNight
    $btnPhoneTest = Add-Ctl $gPhone (New-Object System.Windows.Forms.Button) 15 352 "Test bildirimi gönder"
    $btnPhoneTest.Width = 160
    $lblPhoneTest = Add-Ctl $gPhone (New-Object System.Windows.Forms.Label) 185 357 ""
    $lblPhoneTest.MaximumSize = "175,0"

    $btnConnect.add_Click({
        try {
            $form.Cursor = 'WaitCursor'
            $token = if ($txtToken.Text.Trim()) { $txtToken.Text.Trim() } else { Unprotect-CSSecret $script:pendingTokenEnc }
            if (-not $token) { throw "Önce bot anahtarını yapıştır." }
            $c = Connect-CSTelegram $token
            $script:pendingTokenEnc = Protect-CSSecret $token
            $script:pendingChatId = $c.chatId
            $lblConn.Text = "Bağlandı: $($c.name) (@$($c.bot))"
            $lblConn.ForeColor = [System.Drawing.Color]::ForestGreen
            $txtToken.Text = ""
        } catch {
            $lblConn.Text = "$($_.Exception.Message)"
            $lblConn.ForeColor = [System.Drawing.Color]::Firebrick
        } finally { $form.Cursor = 'Default' }
    })
    $btnPhoneTest.add_Click({
        try {
            $form.Cursor = 'WaitCursor'
            $tmp = New-CSDefaultSettings
            $tmp.telegramTokenEnc = $script:pendingTokenEnc; $tmp.telegramChatId = $script:pendingChatId
            if (-not $tmp.telegramChatId) { throw "Önce Bağla'ya bas." }
            Send-CSTelegram $tmp ([pscustomobject]@{ kind = "bilgi"; text = "Test bildirimi, Claude Ses telefonuna ulaşıyor."; project = "Claude Ses"; link = "" })
            $lblPhoneTest.Text = "Gönderildi"
            $lblPhoneTest.ForeColor = [System.Drawing.Color]::ForestGreen
        } catch {
            $lblPhoneTest.Text = "$($_.Exception.Message)"
            $lblPhoneTest.ForeColor = [System.Drawing.Color]::Firebrick
        } finally { $form.Cursor = 'Default' }
    })

    $selectedRate = { @($rateNames.Keys)[$cmbRate.SelectedIndex] }
    $btnTest = Add-Ctl $form (New-Object System.Windows.Forms.Button) 10 410 "Sesi dene"
    $btnTest.Width = 90
    $btnTest.add_Click({ try { Start-Speech "Ses testi, Claude Ses çalışıyor." (& $selectedRate) } catch { Write-CSError "test: $_" } })
    $btnSave = Add-Ctl $form (New-Object System.Windows.Forms.Button) 580 410 "Kaydet"
    $btnSave.Width = 85; $btnSave.DialogResult = "OK"
    $btnCancel = Add-Ctl $form (New-Object System.Windows.Forms.Button) 675 410 "İptal"
    $btnCancel.Width = 85; $btnCancel.DialogResult = "Cancel"
    $form.AcceptButton = $btnSave; $form.CancelButton = $btnCancel

    if ($form.ShowDialog() -eq "OK") {
        $new = New-CSDefaultSettings
        $new.nightEnabled = $chkNight.Checked
        $new.nightTime = $dtp.Value.ToString("HH:mm")
        $new.idleMin = [int]$numIdle.Value
        $new.speakApproval = $chkApproval.Checked
        $new.speakDone = $chkDone.Checked
        $new.speakInfo = $chkInfo.Checked
        $new.maxAgeMin = [int]$numAge.Value
        $new.startup = $chkStartup.Checked
        $new.rate = & $selectedRate
        $new.phoneEnabled = $chkPhone.Checked
        $new.phoneApproval = $chkPApproval.Checked
        $new.phoneDone = $chkPDone.Checked
        $new.phoneInfo = $chkPInfo.Checked
        $new.phoneNight = $chkPNight.Checked
        $new.telegramTokenEnc = $script:pendingTokenEnc
        $new.telegramChatId = $script:pendingChatId
        Save-CSSettings $new
        $script:settings = $new
        try { Set-CSStartup $PSScriptRoot $new.startup } catch { Write-CSError "startup: $_" }
        Update-Tray
    }
    $form.Dispose()
}

$itemResume.add_Click({ Set-Mode $script:state.prevMode })
$itemHere.add_Click({ Set-Mode "here" })
$itemAway.add_Click({ Set-Mode "away" })
$itemAuto.add_Click({ Set-Mode "auto" })
$itemQuiet.add_Click({ Set-Mode "quiet" })
$itemHistory.add_Click({ Show-History })
$itemSettings.add_Click({ Show-Settings })
$tray.add_MouseClick({ param($s, $e) if ($e.Button -eq 'Left') { Show-History } })
$itemTest.add_Click({ try { Start-Speech "Ses testi, Claude Ses çalışıyor." } catch { Write-CSError "test: $_" } })
$itemExit.add_Click({ $timer.Stop(); $tray.Visible = $false; [System.Windows.Forms.Application]::Exit() })

function Invoke-NightCheck {
    if (Update-NightState $script:state $script:settings (Get-Date)) { Save-CSState $script:state }
    Update-Tray
}

# Kuyruk: her yarım saniyede bir; okuma sürerken sıradakini bekletir
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500
$script:tick = 0
$timer.add_Tick({
    try {
        $script:tick++
        if ($script:tick % 20 -eq 0) { Invoke-NightCheck }   # ~10 sn'de bir gece saati ve simge
        if ((Get-Date) -lt $script:busyUntil) { return }
        $file = Get-ChildItem $CSQueue -Filter *.json -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
        if (-not $file) { return }
        $msg = Get-Content $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        Remove-Item $file.FullName -Force
        $d = Get-SpeakDecision $msg $script:settings $script:state.mode (Get-IdleMinutes) (Get-Date)
        if (-not $d.speak) { Add-CSHistory $msg $false $d.note; return }
        Start-Speech $msg.text
        Add-CSHistory $msg $true ""
    } catch { Write-CSError "tick: $_" }
})

# Uygulama açıkken speak.ps1 her zaman kuyruğa yazar; tek okuyucu burası olduğu için sesler çakışmaz.
Invoke-NightCheck
$tray.Visible = $true
$timer.Start()
[System.Windows.Forms.Application]::Run()

$tray.Dispose()
$appMutex.ReleaseMutex()
