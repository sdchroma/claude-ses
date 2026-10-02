# Claude Ses testleri:  powershell -ExecutionPolicy Bypass -File testler.ps1
. "$PSScriptRoot\lib\ortak.ps1"

$script:total = 0; $script:fail = 0
function Check([string]$name, $got, $expected) {
    $script:total++
    if ("$got" -ceq "$expected") { Write-Host "OK   $name" }
    else { $script:fail++; Write-Host "FAIL $name`n     beklenen: '$expected'`n     gelen:    '$got'" -ForegroundColor Red }
}

Write-Host "--- Cümle temizleme"
$cases = @(
    @("İndirilenler klasörüne kopyaladım: Zincir-v1.0.0.apk", "İndirilenler klasörüne kopyaladım."),
    @("APK'yı C:\Users\Kullanici\Downloads\app-release.apk konumuna kopyaladım.", "APK'yı konumuna kopyaladım."),
    @("Raporu docs/rapor.md dosyasına yazdım.", "Raporu dosyasına yazdım."),
    @("Detaylar [raporda](https://claude.ai/artifact/abc).", "Detaylar raporda."),
    @("Bak: https://example.com/a?b=1", "Bak."),
    @("**Build** tamamlandı ve ``gradlew`` hazır.", "Build tamamlandı ve hazır."),
    @("Sürüm v1.0.0 yayında 🎉", "Sürüm yayında"),
    @("Testler geçti (3/3).", "Testler geçti."),
    @("Saat 10.30'da bitti.", "Saat 10.30'da bitti."),
    @("Sprint 7 bitti, APK'yı telefonuna kurdum, detaylar raporda.", "Sprint 7 bitti, APK'yı telefonuna kurdum, detaylar raporda."),
    @("", "")
)
foreach ($c in $cases) { Check "temizle: $($c[0])" (Clean-SpokenText $c[0]) $c[1] }

Write-Host "--- Ayarlar"
$tmp = Join-Path ([IO.Path]::GetTempPath()) "cs-test-ayarlar.json"
Remove-Item $tmp -ErrorAction SilentlyContinue
$s = Get-CSSettings $tmp
Check "dosya yok -> varsayılan gece saati" $s.nightTime "23:00"
Check "dosya yok -> varsayılan hareketsizlik" $s.idleMin 10
[IO.File]::WriteAllText($tmp, "bozuk {json")
Check "bozuk dosya -> varsayılan" (Get-CSSettings $tmp).maxAgeMin 2
[IO.File]::WriteAllText($tmp, '{"idleMin":5}')
$s = Get-CSSettings $tmp
Check "kısmi dosya -> verilen değer" $s.idleMin 5
Check "kısmi dosya -> eksik değer varsayılan" $s.speakDone $true
$s.rate = "fast"; $s.nightEnabled = $false
Save-CSSettings $s $tmp
$s2 = Get-CSSettings $tmp
Check "kaydet/oku hız" $s2.rate "fast"
Check "kaydet/oku gece kapalı" $s2.nightEnabled $false
Remove-Item $tmp

Write-Host "--- Gece modu"
$set = Get-CSSettings "yok.json"
function St($mode, $prev, $last) { [ordered]@{ mode = $mode; prevMode = $prev; lastNight = $last } }
function At([string]$s) { [datetime]::ParseExact($s, "yyyy-MM-dd HH:mm", $null) }

$st = St "auto" "auto" ""
Check "22:59 değişmez" (Update-NightState $st $set (At "2026-10-02 22:59")) $false
Check "23:00 sessize geçer" ((Update-NightState $st $set (At "2026-10-02 23:00")) -and $st.mode -eq "quiet") $true
Check "önceki mod saklanır" $st.prevMode "auto"
Check "gece anahtarı" $st.lastNight "2026-10-02"
$st.mode = "away"   # kullanıcı 23:30'da elle sesi açtı
Check "elle açınca aynı gece tekrar susmaz" (Update-NightState $st $set (At "2026-10-02 23:31")) $false
Check "gece yarısından sonra da susmaz" (Update-NightState $st $set (At "2026-10-03 02:00")) $false
Check "ertesi gece yine susar" ((Update-NightState $st $set (At "2026-10-03 23:00")) -and $st.mode -eq "quiet") $true
Check "ertesi gece önceki mod away" $st.prevMode "away"

$st = St "auto" "auto" "2026-10-01"
Check "gece 01:30 açılış -> sessiz" ((Update-NightState $st $set (At "2026-10-03 01:30")) -and $st.mode -eq "quiet") $true
Check "gece 01:30 açılış anahtarı önceki gün" $st.lastNight "2026-10-02"
$st = St "auto" "auto" "2026-10-01"
Check "sabah 07:00 açılış -> değişmez" (Update-NightState $st $set (At "2026-10-03 07:00")) $false

$st = St "quiet" "here" ""
$null = Update-NightState $st $set (At "2026-10-02 23:00")
Check "zaten sessizse önceki mod korunur" $st.prevMode "here"

$off = Get-CSSettings "yok.json"; $off.nightEnabled = $false
$st = St "auto" "auto" ""
Check "gece kapalıysa değişmez" (Update-NightState $st $off (At "2026-10-02 23:30")) $false

$early = Get-CSSettings "yok.json"; $early.nightTime = "01:00"
$st = St "auto" "auto" ""
Check "01:00 ayarında 23:30 değişmez" (Update-NightState $st $early (At "2026-10-02 23:30")) $false
Check "01:00 ayarında 01:10 susar" ((Update-NightState $st $early (At "2026-10-03 01:10")) -and $st.mode -eq "quiet") $true

Write-Host "--- Okunsun mu kararı"
$now = At "2026-10-02 15:00"
function Msg($kind, $minAgo) { [pscustomobject]@{ kind = $kind; time = $now.AddMinutes(-$minAgo).ToString('o'); text = "x" } }
function D($msg, $mode, $idle, $settings = $set) { $d = Get-SpeakDecision $msg $settings $mode $idle $now; "$($d.speak)|$($d.note)" }

Check "gece -> sessiz" (D (Msg "onay" 0) "quiet" 60) "False|gece"
Check "buradayım -> sessiz" (D (Msg "bitti" 0) "here" 60) "False|buradaydın"
Check "uzakta -> okunur" (D (Msg "bitti" 0) "away" 0) "True|"
Check "otomatik, 5 dk -> sessiz" (D (Msg "bilgi" 0) "auto" 5) "False|buradaydın"
Check "otomatik, 12 dk -> okunur" (D (Msg "bilgi" 0) "auto" 12) "True|"
Check "3 dk eski -> okunmaz" (D (Msg "bitti" 3) "away" 0) "False|eski"
$noApproval = Get-CSSettings "yok.json"; $noApproval.speakApproval = $false
Check "onay kapalı -> okunmaz" (D (Msg "onay" 0) "away" 0 $noApproval) "False|kapalı tür"
Check "onay kapalıyken bitti okunur" (D (Msg "bitti" 0) "away" 0 $noApproval) "True|"

Write-Host "--- Telefon: ne zaman gitsin"
$ph = Get-CSSettings "yok.json"
$ph.phoneEnabled = $true; $ph.telegramTokenEnc = "x"; $ph.telegramChatId = "123"
function P($kind, $mode, $idle, $settings = $ph) { $d = Get-PhoneDecision (Msg $kind 0) $settings $mode $idle; "$($d.send)|$($d.note)" }
Check "telefon: uzakta -> gider" (P "bitti" "away" 0) "True|"
Check "telefon: gece -> gider" (P "onay" "quiet" 0) "True|"
Check "telefon: buradayım -> gitmez" (P "bitti" "here" 60) "False|buradaydın"
Check "telefon: otomatik 5 dk -> gitmez" (P "bilgi" "auto" 5) "False|buradaydın"
Check "telefon: otomatik 12 dk -> gider" (P "bilgi" "auto" 12) "True|"
Check "telefon: 30 dk eski mesaj da gider" ("$((Get-PhoneDecision (Msg 'bitti' 30) $ph 'away' 0).send)") "True"
$phOff = Get-CSSettings "yok.json"; $phOff.telegramTokenEnc = "x"; $phOff.telegramChatId = "123"
Check "telefon: kapalıysa gitmez" (P "bitti" "away" 0 $phOff) "False|kapalı"
$phNoChat = Get-CSSettings "yok.json"; $phNoChat.phoneEnabled = $true; $phNoChat.telegramTokenEnc = "x"
Check "telefon: bağlı değilse gitmez" (P "bitti" "away" 0 $phNoChat) "False|bağlı değil"
$phNoInfo = Get-CSSettings "yok.json"; $phNoInfo.phoneEnabled = $true; $phNoInfo.telegramTokenEnc = "x"; $phNoInfo.telegramChatId = "1"; $phNoInfo.phoneInfo = $false
Check "telefon: ara bilgi kapalı -> gitmez" (P "bilgi" "away" 0 $phNoInfo) "False|kapalı tür"

Write-Host "--- Rapor linki"
Check "link: claude.ai markdown" (Find-ReportLink "Detaylar [raporda](https://claude.ai/artifact/abc).") "https://claude.ai/artifact/abc"
Check "link: notion düz" (Find-ReportLink "Rapor: https://www.notion.so/Rapor-123 hazır") "https://www.notion.so/Rapor-123"
Check "link: metni rapor olan link" (Find-ReportLink "Bkz. [Sprint raporu](https://example.com/r/7)") "https://example.com/r/7"
Check "link: alakasız link alınmaz" (Find-ReportLink "Kaynak: https://github.com/x/y") ""
Check "link: yok" (Find-ReportLink "Sprint 7 bitti.") ""

Write-Host "--- Telegram mesajı"
$m = [pscustomobject]@{ kind = "bitti"; text = "Sprint 7 bitti, <b> detaylar raporda."; project = "Zincir"; link = "https://claude.ai/a" }
$f = Format-TelegramMessage $m
Check "mesaj: başlıkta proje ve tür" ($f.text -split "`n")[0] "<b>$([char]::ConvertFromUtf32(0x2705)) Zincir · İş bitti</b>"
Check "mesaj: metin HTML kaçışlı" ($f.text -split "`n")[1] "Sprint 7 bitti, &lt;b&gt; detaylar raporda."
Check "mesaj: rapor düğmesi" $f.reply_markup.inline_keyboard[0][0].url "https://claude.ai/a"
$f2 = Format-TelegramMessage ([pscustomobject]@{ kind = "onay"; text = "Onayın gerekiyor."; project = ""; link = "" })
Check "mesaj: projesiz başlık" ($f2.text -split "`n")[0] "<b>$([char]::ConvertFromUtf32(0x26A0))$([char]0xFE0F) Onay gerekiyor</b>"
Check "mesaj: linksizse düğme yok" ($null -eq $f2.reply_markup) $true

Write-Host "--- Anahtar şifreleme"
$enc = Protect-CSSecret "123:ABC"
Check "şifreli hali düz metin değil" ($enc.Contains("123:ABC")) $false
Check "çözülünce aynı" (Unprotect-CSSecret $enc) "123:ABC"
Check "boş anahtar" (Unprotect-CSSecret "") ""

Write-Host "`n$($total - $fail)/$total geçti"
exit $fail
