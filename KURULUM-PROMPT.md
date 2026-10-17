# Claude ile kurulum

Yeni bir Windows bilgisayarda Claude Code'u aç, aşağıdaki kutunun tamamını kopyala ve Claude'a yapıştır. Claude, Claude Ses'i indirir, kurar, kontrol eder ve sonunda senin yapman gerekenleri söyler. Daha önce kurulmuş bir bilgisayarda aynı metin güncelleme yapar.

````text
Bu bilgisayara "Claude Ses" uygulamasını kurmanı istiyorum. Bu benim açık isteğim ve onayım: uygulamanın kurulum betiği Claude Code ayarlarına iki bildirim hook'u (Notification ve Stop), sesli ara bilgi komutu için izin satırları ve kullanıcı CLAUDE.md dosyasına işaretli bir kural bloğu ekler. Bunların eklenmesini onaylıyorum. Uygulamanın kendi dosyalarını değiştirme, sadece aşağıdaki adımları uygula.

Claude Ses nedir: Windows'ta saatin yanında duran küçük bir simge uygulaması. Ben bilgisayar başında değilken onay isteklerini, iş bitişlerini ve önemli ara gelişmeleri Türkçe sesli söyler; istersem Telegram'dan telefonuma da gönderir. Başındayken konuşmaz, onay isteği ya da iş bitince sadece kısa bir ses çalar. Kaynak: https://github.com/sdchroma/claude-ses

ADIMLAR (komutların hepsi PowerShell komutudur; PowerShell aracınla çalıştır, Git Bash ile değil)

1. Ön kontrol
   - Bilgisayar Windows 10 ya da 11 değilse dur ve bana söyle; uygulama sadece Windows'ta çalışır.
   - git yüklü mü bak (git --version).
   - Türkçe ses yüklü mü bak:
     Add-Type -AssemblyName System.Runtime.WindowsRuntime; $null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media, ContentType = WindowsRuntime]; [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object Language -eq 'tr-TR' | ForEach-Object DisplayName
     Boş çıkarsa kuruluma devam et ama sonda bana şunu söyle: Ayarlar > Saat ve dil > Konuşma > Ses ekle > Türkçe.

2. İndirme ya da güncelleme (klasör: "$env:USERPROFILE\ClaudeSes")
   - Önce daha önce başka bir klasöre kurulmuş mu bak: "$env:USERPROFILE\.claude\settings.json" içinde speak.ps1 geçen bir hook varsa, o yolun klasörü mevcut kurulumdur. Bu adımda ve sonraki adımlarda "$env:USERPROFILE\ClaudeSes" yerine o klasörü kullan; ikinci bir kopya indirme.
   - Klasör varsa ve içinde .git varsa: git -C "$env:USERPROFILE\ClaudeSes" pull
   - Klasör yoksa ve git varsa: git clone https://github.com/sdchroma/claude-ses.git "$env:USERPROFILE\ClaudeSes"
   - git yoksa: https://github.com/sdchroma/claude-ses/archive/refs/heads/main.zip dosyasını indir, boş bir geçici klasöre aç, içindeki claude-ses-main klasörünün içeriğini "$env:USERPROFILE\ClaudeSes" içine taşı. Bu yolda güncelleme için aynı adımı tekrar etmek gerekir; bunu sonda bana not et.
   - Klasör varsa ama .git yoksa ve git varsa: önce bana sor, eski klasörü silme.

3. Kurulum
   Şunu çalıştır:
     powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\ClaudeSes\kur.ps1"
   Betik şunları yapar: hook'ları ve izinleri ekler (settings.json'un yedeğini settings.json.ClaudeSes.bak olarak alır), CLAUDE.md'ye kural bloğunu ekler ya da yeniler, bilgisayar açılınca başlamayı ayarlar ve uygulamayı başlatır. Tekrar çalıştırmak sorun çıkarmaz, girdiler çift eklenmez.
   Claude Code'un izin sistemi bu adımı engellerse zorlamaya ya da başka yoldan ayar yazmaya çalışma. Bana yukarıdaki tek satırlık komutu ver, kendi terminalimde çalıştırayım; sonra 4. adımdan devam et.

4. Kontrol (her birinin sonucunu not et)
   - Testler: powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\ClaudeSes\testler.ps1"  → son satır "N/N geçti" olmalı.
   - Uygulama açık mı (bir süreç numarası çıkmalı):
     Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'ClaudeSes\.ps1' } | Select-Object -ExpandProperty ProcessId
   - "$env:USERPROFILE\.claude\settings.json" içinde Notification ve Stop altında speak.ps1 geçen hook'lar olmalı.
   - "$env:USERPROFILE\.claude\CLAUDE.md" içinde "<!-- ClaudeSes:start -->" ile "<!-- ClaudeSes:end -->" arasında kural bloğu olmalı.
   - Bana bir deneme sesi çal (önce kısa zil, sonra Türkçe cümle):
     . "$env:USERPROFILE\ClaudeSes\lib\ortak.ps1"; foreach ($b in (Get-ChimeBytes bitti), (Get-SpeechBytes 'Claude Ses kuruldu.')) { (New-Object System.Media.SoundPlayer((New-Object System.IO.MemoryStream(, $b)))).PlaySync() }

5. Bundan sonra bu oturumda da kuralları uygula (kurulum bunları CLAUDE.md'ye kalıcı yazdı; yeni oturumlarda kendiliğinden geçerli olur):
   - Her son mesajını 🔊 ile başlayan tek satırla bitir: en fazla ~15 kelimelik kısa Türkçe cümle (ne bitti, sonuç, benden ne bekleniyor). Dosya adı, yol, link, sürüm numarası ya da teknik ayrıntı yazma. Bu satırı Stop hook'u okur, ayrıca kendin seslendirme.
   - Büyük bir işin sonunda 🔊 satırının hemen üstüne 📋 satırı ve en fazla 4 kısa "- " maddesi yaz (ne yapıldı, sonuç, benden beklenen). Telefonda görmeye değer bir dosya varsa (ekran görüntüsü, PDF, APK) her biri için bir "📎 <tam yol>" satırı ekle, en fazla 5; gizli bilgi ya da ayar dosyası asla. Bunlar okunmaz, sadece uzaktaysam Telegram'a gider.
   - Önemli anlarda (yön değiştirme, uzun bir bekleme başlarken, dikkat çekici bir sonuç ya da hata) kısa bir Türkçe cümleyle ara bilgi ver; komutun tam hali CLAUDE.md'deki bloktadır (speak.ps1 -Text "..."). Rutin adımlar ve kısa işler için kullanma. Sesin gerçekten okunup okunmayacağına uygulama karar verir.

6. Son rapor
   Bana kısa ve sade Türkçe ile şunları söyle: neyin kurulduğu ya da güncellendiği, kontrollerin sonucu (geçmeyen varsa nedeni), ve benim yapmam gerekenler:
   - Claude Code'u yeniden başlatmam (hook'lar ancak o zaman devreye girer).
   - Türkçe ses yoksa nasıl ekleyeceğim.
   - İstersem Telegram'ı bağlamam: saatin yanındaki simgeye sağ tık > Ayarlar > Telefon. Bot anahtarını ben girerim, sen girme ya da isteme.
   - Simge menüsü: Buradayım / Uzaktayım / Otomatik (varsayılan, 10 dk hareketsizlikte uzakta sayar) / Sessiz (gece, her gece 23:00'te kendiliğinden).
````

## Kaldırma
Claude'a "Claude Ses'i kaldır" demen yeterli; klasördeki `kaldir.ps1` hook'ları, kuralları ve açılış kısayolunu temizler. Elle:
```
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\ClaudeSes\kaldir.ps1"
```
