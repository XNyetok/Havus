<img src="design/AppIcon.svg" width="128" alt="Havus app icon">

# Havus

**A lightweight, open-source Mac cleaner that minds its own business.**

Havus (a playful twist on *hapus*, Indonesian for "delete") cleans caches, logs and developer junk, uninstalls apps together with their leftovers, finds large files you rarely open, shows which folders take up the most space, and turns off programs that start on their own. Everything runs locally on your Mac: no account, no ads, no telemetry.

The app speaks casual Indonesian and English, following your Mac's language. [Ringkasan dalam Bahasa Indonesia ada di bawah.](#bahasa-indonesia)

> [!WARNING]
> Havus is in early development. Everything goes to the Trash first, but please review before you clean.

## Features

| Feature | What it covers |
|---|---|
| **System junk** (*Sampah Sistem*) | App caches and logs, Mail attachments you opened, iPhone/iPad update files, Trash contents |
| **Developer junk** (*Sampah Developer*) | Xcode (DerivedData, Archives, Device Support, Previews), Simulator caches, Homebrew, npm, Yarn, pnpm, CocoaPods, SwiftPM, pip, Go, Gradle, Bun, Cargo |
| **Uninstaller** (*Hapus Aplikasi*) | Removes an app together with its leftovers, or only the leftovers to "reset" it |
| **Large & old files** (*File Gede & Lama*) | Finds big, rarely opened files using the Spotlight index, so it's fast. Press Space to look inside one with Quick Look |
| **Disk map** (*Peta Disk*) | Shows which folders in your home folder take up the most space, biggest first. Click a folder to look inside. It only looks: nothing is removed here |
| **Startup items** (*Jalan Otomatis*) | Lists the launch agents in your Library with the app each belongs to. Turn one off, or move it to the Trash |

## Principles

- **Safety first.** Every item is previewed and selectable. Everything goes to the Trash, except when you explicitly empty the Trash.
- **Only touches what it knows.** Cleanup locations come from an auditable rule list ([`JunkRule+Catalog.swift`](Packages/HavusCore/Sources/HavusCore/Junk/JunkRule+Catalog.swift)), and every deletion is checked again by `PathGuard`.
- **Leaves alone what you protect.** Files and folders on your exclusion list (**Settings → Exclusions**, or right-click a result) never show up in cleanup results, and `PathGuard` refuses to remove them or any folder that holds them.
- **Private.** No telemetry, no analytics. Havus goes online for one thing only, and only if you turn it on: once a day it asks GitHub for the latest version number. Nothing about you or your Mac is sent.
- **Lightweight.** Native Swift + SwiftUI with zero third-party dependencies. Version 0.1.0: 1.5 MB app, about 34 MB of memory when idle.

## Requirements

macOS 14 Sonoma or later, on Apple silicon or Intel.

## Language

Havus speaks Indonesian and English. It uses whichever of the two comes first in your preferred languages (**System Settings → General → Language & Region**), and Indonesian when neither is on the list. To choose a language for Havus alone, click **+** under **Applications** in the same pane.

## Installation

### From GitHub Releases

Havus releases aren't notarized by Apple yet, so macOS blocks the app the first time you open it.

1. Download `Havus-x.y.z.zip` and `Havus-x.y.z.zip.sha256` from [Releases](../../releases) and verify the checksum:

   ```sh
   shasum -a 256 -c Havus-x.y.z.zip.sha256
   ```

2. Unzip it and move `Havus.app` to your **Applications** folder.
3. Open Havus. If macOS blocks it, go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.

Every release since 0.3.0 is signed with the same Havus certificate. To check a copy, run `codesign -d -r- /Applications/Havus.app`: the output ends with `certificate leaf = H"9e4a60cb751d37f504f5290a9ead326f31e739b5"`.

### Updating

Havus can't install updates by itself yet, but it can tell you when there's a new version. Choose **Turn On** when Havus asks on its first launch, or turn on **Havus → Check for Updates Automatically** in the menu bar. **Havus → Check for Updates…** checks right away. When a new version is out, Havus links to [what's new](https://havus.web.id/en/changelog/), and [havus.web.id/en/update](https://havus.web.id/en/update/) has the steps to install it. Since 0.3.0, Full Disk Access stays on when you update.

### Build from source

Requires Xcode 26 or later.

```sh
git clone https://github.com/XNyetok/Havus.git
cd Havus
make run
```

## Full Disk Access

macOS protects some locations (the Trash, Mail attachments, other apps' data). For a complete scan, open **System Settings → Privacy & Security → Full Disk Access** and turn on Havus. Without it, Havus still works but skips those locations.

> [!NOTE]
> Since 0.3.0, every release is signed with the same certificate, so macOS keeps this permission when you update. Coming from 0.2.0 or earlier, turn it on one more time.

## Roadmap

Everything Havus does today is free and will stay free. An optional paid tier may come later, but safety features, such as the exclusion list, will always be free.

Each open item has its own issue, where you can follow progress, share ideas or offer to help. The [roadmap label](https://github.com/XNyetok/Havus/issues?q=label%3Aroadmap) lists them all.

- [ ] Login items and launch agents manager: [#18](https://github.com/XNyetok/Havus/issues/18) (your own launch agents are done; system-wide ones need root)
- [ ] Maintenance tasks that need root (`SMAppService` + XPC helper): [#19](https://github.com/XNyetok/Havus/issues/19)
- [ ] Browser privacy cleanup: [#20](https://github.com/XNyetok/Havus/issues/20)
- [ ] Notarization and Homebrew Cask: [#23](https://github.com/XNyetok/Havus/issues/23)
- [x] App icon
- [x] New version notifications (opt-in, once a day)
- [x] Exclusion list (files and folders Havus never touches)
- [x] English UI, following your Mac's language
- [x] Disk map: which folders take up the most space

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Most wanted: new cleanup rules (with evidence that they're safe), bug reports, and design feedback. Technical background lives in [docs/](docs/).

Issues and pull requests in English are preferred; Bahasa Indonesia is welcome too.

## Security

Found a vulnerability? Please don't open a public issue. See [SECURITY.md](SECURITY.md).

## License

The source code is released under the [MIT License](LICENSE) © 2026 Debi Kurnia. The Havus name and app icon aren't covered by that license; see [TRADEMARKS.md](TRADEMARKS.md).

---

## Bahasa Indonesia

**Havus** (plesetan dari kata *hapus*) adalah pembersih Mac yang ringan, open source, dan nggak kepo. Havus bantu kamu bersihin cache, log, sisa build developer, aplikasi beserta file sisanya, nemuin file gede yang jarang dibuka, nunjukin folder mana yang paling makan tempat, sampai matiin program yang jalan otomatis. Semuanya jalan lokal di Mac kamu, tanpa akun, iklan, atau telemetri. Semua yang dihapus masuk Tong Sampah dulu, jadi masih bisa dibalikin. Ada file atau folder yang nggak boleh disentuh? Masukin ke **Pengaturan → Pengecualian**, atau klik kanan item di hasil pindai.

**Bahasa:** Havus bisa bahasa Indonesia dan Inggris, dan ngikutin bahasa yang duluan di daftar **System Settings → General → Language & Region**. Mac kamu pakai bahasa Inggris, tapi mau Havus tetap bahasa Indonesia? Di halaman yang sama, klik **+** di bagian **Applications**, pilih Havus, lalu pilih Bahasa Indonesia.

**Cara install:** unduh `Havus-x.y.z.zip` dari halaman [Releases](../../releases), ekstrak, lalu pindahin `Havus.app` ke folder **Applications**. Karena belum di-notarize Apple, waktu pertama kali dibuka kamu perlu ke **System Settings → Privacy & Security**, lalu klik **Open Anyway**. Biar hasil scan lengkap, nyalain Havus di **Privacy & Security → Full Disk Access**. Mulai versi 0.3.0, izin ini tetap nyala walaupun Havus di-update.

**Cara update:** Havus belum bisa pasang update sendiri, tapi bisa ngabarin kalau ada versi baru. Nyalain lewat menu **Havus → Cek Versi Baru Otomatis**: sehari sekali Havus nanya nomor versi terbaru ke GitHub, tanpa ngirim data apa pun soal kamu. Langkah update-nya ada di [havus.web.id/update](https://havus.web.id/update/).

Semua fitur yang ada sekarang gratis dan bakal tetap gratis. Nanti mungkin ada fitur tambahan berbayar, tapi fitur keamanan selalu gratis.

Mau lapor bug atau kasih ide? Boleh pakai Bahasa Indonesia di [Issues](../../issues).
