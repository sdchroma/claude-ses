# Claude Ses: backlog

Zamanlanmamış fikirler. Bir sprint'e alınmadıkça üzerinde çalışılmaz.

- **Telegram'dan onay verme (rafa kaldırıldı, 2026-10-14):** Onay bildirimine "Onayla / Reddet" düğmeleri; basınca Claude Code'daki izin isteği cevaplansın.
  - Teknik yol: Claude Code'un `PermissionRequest` hook'u `allow`/`deny` döndürebilir; cevap gelmezse normal onay penceresi açılır.
  - Taslak tasarım: uzaktaysan düğmeli mesaj gönder, cevabı en fazla N dk bekle (hook süre sınırı bunun üstünde olmalı), bilgisayara dönünce ya da süre dolunca bırak; düğme basışlarını tek bir süreç kilitle dinlesin (`getUpdates` aynı anda tek okuyucu ister); sadece kayıtlı sohbet + aynı kullanıcı, tek kullanımlık rastgele kimlik; aynı onay için düğmesiz ikinci bildirimi sustur.
  - Neden durdu: Claude Code'un otomatik izin modu, Claude'un kendi izin sistemine dışarıdan onay yolu eklemesini "güvenliği zayıflatma" sayıp engelliyor. Devam edilecekse kurulum adımını kullanıcı elle onaylamalı ya da hook'u kendisi eklemeli.
