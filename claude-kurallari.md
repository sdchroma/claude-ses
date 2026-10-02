# Sesli bildirim (Claude Ses)
The user is often away from the computer and follows progress by voice (Turkish). The Claude Ses tray app decides whether to actually speak (only when the user is away), queues messages so they never overlap, and hooks already announce permission prompts. Your job is the two parts below.

- **End of turn:** finish every final message with one line starting with `🔊` — a short Turkish sentence (max ~15 words): what finished, the key outcome, what the user needs to do. Never put file names, paths, links, version numbers or technical detail in it. Good: `🔊 Sprint 7 bitti, APK'yı indirilenler klasörüne kopyaladım, detaylar raporda.` The Stop hook reads this line; don't also speak it yourself.
- **Mid-work updates:** only at meaningful moments — changing direction, starting a long wait (build, install, long test run), or a notable result/failure — speak one short, natural Turkish sentence (same no-file-names rule):
  `{{KOMUT}} -Text "Testler geçti ama bir senaryo daha ekleyip tekrar deneyeceğim."`
  Not for routine steps or short tasks. Just call it; the app handles whether the user hears it.
