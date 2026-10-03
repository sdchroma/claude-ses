# Claude Ses

Claude Code çalışırken bilgisayar başında değilsen onay isteklerini, iş bitişlerini ve önemli ara gelişmeleri Türkçe sesli söyler, istersen Telegram'dan telefonuna da gönderir. Başındayken susar.

Sadece Windows'ta çalışır (10/11). Ek program gerekmez, Windows'un kendi PowerShell'iyle çalışır.

## Kurulum (her bilgisayarda bir kez)
1. Klasörü indir. Git ile:
   ```
   git clone https://github.com/sdchroma/claude-ses.git
   ```
   ya da GitHub'da **Code → Download ZIP** ile indirip istediğin yere aç.
2. Klasörde PowerShell aç ve şunu çalıştır:
   ```
   powershell -ExecutionPolicy Bypass -File kur.ps1
   ```
3. Claude Code'u yeniden başlat.

Klasörü sonradan taşırsan `kur.ps1` dosyasını tekrar çalıştır. Aynı kurulumu tekrar çalıştırmak sorun çıkarmaz, girdiler çift eklenmez.

**Güncelleme:** Klasörde `git pull` çalıştır, ardından `kur.ps1` dosyasını tekrar çalıştır.

**Ayarlar taşınmaz:** Ayarlar ve geçmiş her bilgisayarın kendi `%LOCALAPPDATA%\ClaudeSes` klasöründe durur. Telegram anahtarı da Windows hesabına özel şifrelendiği için her bilgisayarda Ayarlar'dan bir kez yeniden girilir.

**Türkçe ses gerekli.** Kurulum Türkçe sesin yüklü olup olmadığını kontrol eder. Yüklü değilse: Ayarlar > Saat ve dil > Konuşma > Ses ekle > Türkçe.

## Kullanım
Saatin yanında yuvarlak bir simge çıkar. Sağ tıklayınca şu menü açılır:

| Seçenek | Anlamı |
|---|---|
| Buradayım | Her zaman sessiz |
| Uzaktayım | Her zaman sesli |
| Otomatik (varsayılan) | Belirlenen süre (10 dk) klavye/fare hareketsizliğinde sesli, dokununca sessiz |
| Sessiz (gece) | Her şey susar (onay istekleri dahil), uygulama kapalı olsa bile |
| Sesi aç | Sadece gece modundayken görünür; gece öncesi moda döner |
| Son mesajlar | Son 20 mesaj; sessiz kalanlar ve nedeni de burada (sol tık da açar) |
| Ayarlar… | Aşağıdaki ayarlar penceresi |
| Sesi dene | Kısa bir test cümlesi okur |

Simgenin rengi anlamı:
- 🟢 Yeşil: buradasın, ses kapalı.
- 🔴 Kırmızı: uzaktasın, ses açık.
- Gri, içinde ay: gece modu.
- Simgenin içinde "A" harfi varsa otomatik moddasın.

### Gece modu
- Her gece ayarlanan saatte (varsayılan **23:00**) kendiliğinden sessize geçer.
- **Kendiliğinden kapanmaz.** Sabah menüden "Sesi aç" ya da başka bir mod seçene kadar sessiz kalır.
- Gece sesi elle açarsan o gece tekrar susmaz. Bilgisayar gece (06:00'dan önce) açılırsa sessiz başlar.

### Ayarlar penceresi
- **Gece modu:** açık/kapalı ve saati.
- **Otomatik mod:** kaç dakika hareketsizlikte "uzakta" sayılacağın.
- **Ne okunsun:** onay istekleri, iş bitti özetleri ve ara bilgilendirmeler ayrı ayrı açılıp kapatılabilir.
- **Diğer:** kaç dakikadan eski mesajların okunmayacağı, bilgisayar açılınca başlama, konuşma hızı (yavaş / normal / hızlı).

Kaydedince hemen geçerli olur, yeniden başlatmak gerekmez.

### Telefon bildirimi (Telegram)
Uzaktayken (gece modu dahil) mesajlar telefonuna Telegram'dan da gider:
- Başlıkta proje adı ve tür olur. Örnek: "✅ Zincir · İş bitti".
- Bitiş mesajında rapor linki varsa bildirimde **"Raporu aç"** düğmesi çıkar.

**Kurulum (bir kez):**
1. Telegram'da **@BotFather**'a `/newbot` yaz, bota bir ad ver. Sana bir anahtar (token) verir.
2. Ayarlar → **Telefon** bölümüne anahtarı yapıştır.
3. Telegram'da kendi botunu aç ve herhangi bir mesaj at.
4. **Bağla**'ya bas, sonra **Test bildirimi gönder**'e bas, en son da **Kaydet**'e bas.

**Bilmen gerekenler:**
- Anahtar Windows hesabına özel şifrelenerek saklanır. Klasörü başka bilgisayara taşırsan anahtarı orada bir kez tekrar girmen gerekir.
- Telefon bildirimi seslerin sırasını beklemez, mesaj gelince hemen gider. Eski mesaj sınırı sadece ses için geçerlidir.
- **Gece modunda da gönder** kutusu (varsayılan açık) kapatılırsa gece modunda telefon da susar.
- Her mesajın telefona gidip gitmediği (gitmediyse sebebi) `%LOCALAPPDATA%\ClaudeSes\telefon.log` dosyasına yazılır; son 500 satır tutulur.

## Nasıl çalışır
- **Hook'lar:** Claude Code onay istediğinde ve iş bitince `speak.ps1` dosyasını çağırır. Bitişte Claude'un son mesajındaki `🔊` satırı okunur.
- **Sıra:** Mesajlar sıraya girer ve uygulama bunları tek tek okur, sesler üst üste binmez. Ayarlanan süreden (varsayılan 2 dk) eski mesajlar okunmaz.
- **Temizleme:** Okunmadan önce dosya adları, klasör yolları, linkler, kod parçaları ve emojiler cümleden çıkarılır.
- **Uygulama kapalıysa:** Sesler yine sırayla okunur ve "uzaktayım" kabul edilir.

## Dosyalar
| Dosya | Görevi |
|---|---|
| `speak.ps1` | Hook'ların ve Claude'un çağırdığı giriş noktası |
| `ClaudeSes.ps1` | Simge uygulaması |
| `baslat.vbs` | Uygulamayı pencere açmadan başlatır |
| `kur.ps1` / `kaldir.ps1` | Kurulum / kaldırma |
| `claude-kurallari.md` | CLAUDE.md'ye eklenen kurallar |
| `lib/` | Ortak kod |
| `testler.ps1` | Otomatik testler (temizleme, ayarlar, gece modu, okunma kararı) |

Ayarlar ve geçmiş `%LOCALAPPDATA%\ClaudeSes` klasöründe durur. Hata olursa `hata.log` dosyasına yazılır.

## Kaldırma
```
powershell -ExecutionPolicy Bypass -File kaldir.ps1            # geçmişi korur
powershell -ExecutionPolicy Bypass -File kaldir.ps1 -GecmisiSil
```
