# Contributing to Havus

Thanks for helping out! This guide covers setup, ground rules and the checks that matter most, because Havus is an app that **deletes files**.

Issues and pull requests in English are preferred. Bahasa Indonesia is welcome too.

## Setup

Requirements: macOS 14+, Xcode 26+ (Swift 6.2+). Optional but recommended: `gitleaks` (`brew install gitleaks`).

```sh
git clone https://github.com/XNyetok/Havus.git
cd Havus
make setup   # installs git hooks: blocks sensitive files and scans for secrets before each commit
make test    # runs the HavusCore unit tests
make run     # builds and launches the app (or open Havus.xcodeproj and press ⌘R)
```

Run `make` to list all commands. You **don't need an Apple Developer account**: builds are ad-hoc signed ("Sign to Run Locally") by default.

### Local signing (optional, but makes life easier)

macOS ties the **Full Disk Access** permission to the app's signature. Ad-hoc builds get a new signature on every build, so the permission keeps resetting. To keep it:

1. `cp Config/Local.xcconfig.example Config/Local.xcconfig`
2. Set `DEVELOPMENT_TEAM` to your Team ID. A free Apple ID works; you'll find it in Xcode → Settings → Accounts.

`Config/Local.xcconfig` is gitignored, so your Team ID never gets committed.

Debug builds use their own bundle ID, `id.nyetok.havus.debug`, and show up as **Havus Debug** in System Settings. They have their own Full Disk Access entry and settings, so they never switch off the permission of a Havus release installed on the same Mac.

## Project layout

```
Havus/                  SwiftUI app: views, state and the UI copy (Indonesian, with English)
Packages/HavusCore/     Core logic: scanning, cleanup rules, PathGuard, removal (+ tests)
Config/                 Build settings (xcconfig)
design/                 App icon source (SVG), rendered to PNGs by make icon
docs/                   Stack decision, architecture, maintainer guide
scripts/                Bootstrap, release build and icon rendering
.githooks/              Pre-commit hook
.github/                CI, release, issue and PR templates
```

See [docs/architecture.md](docs/architecture.md) for details.

## Golden rules: protect user data

1. **Every removal goes through `FileRemover`**, which always checks `PathGuard` first. Never call `FileManager.removeItem` or `trashItem` directly.
2. **Trash by default.** Permanent deletion is only for the contents of the Trash.
3. **No network, no telemetry.** Havus goes online for one thing only: the update check, which stays off until the user turns it on and asks GitHub only for the latest version number (see [docs/architecture.md](docs/architecture.md#update-check)). PRs that add other network access, analytics or third-party SDKs will be declined unless discussed in an issue first.
4. **Zero dependencies.** Want to add a package? Open an issue first: every dependency adds supply-chain risk.

### Adding a cleanup rule

Rules live in [`JunkRule+Catalog.swift`](Packages/HavusCore/Sources/HavusCore/Junk/JunkRule+Catalog.swift). Checklist:

- [ ] The data is **regenerable** by the app or tool that owns it (caches, logs, build products). Never documents, databases or user settings.
- [ ] The PR description includes **evidence**, such as official docs or an official command like `brew cleanup` or `go clean -cache`.
- [ ] Pick a `safety`: `.safe` if it can be deleted at any time, `.review` if the user should look first.
- [ ] Add the UI title and description in [`JunkRule+Copy.swift`](Havus/Features/Junk/JunkRule+Copy.swift), and their English in [`Localizable.xcstrings`](Havus/Localizable.xcstrings). The compiler reminds you of the first, CI of the second.
- [ ] Run `make test`. `catalogIsCompleteAndConservative` checks that rules stay inside the home folder and never delete permanently.

## Code style

- Identifiers, code comments, commit messages and docs are in **English**. UI text is written in **Indonesian** in the code, with an English translation in the string catalog (see below).
- Format with the `swift-format` that ships with Xcode: `make format` before committing, `make lint` to check.
- Swift 6 strict concurrency: UI and models are `@MainActor`; heavy work (disk scans) runs in background tasks.
- New logic goes into `HavusCore`, with tests. Tests use a temporary home folder and never touch the real one.

## UI copy (Indonesian and English)

Havus shows Indonesian or English, whichever comes first in the Mac's preferred languages. Indonesian is the source language: the strings in the code are Indonesian, and the English lives in [`Havus/Localizable.xcstrings`](Havus/Localizable.xcstrings).

### Indonesian

The app speaks casual, friendly Indonesian. Keep it consistent:

- Address the user as **"kamu"**, never "Anda".
- Casual but clear: "nggak", "udah", "lagi" and "biar" are fine; avoid heavy slang and abbreviations.
- Buttons are verbs: *Pindai*, *Bersihin*, *Pindahin ke Tong Sampah*, *Batal*.
- Dialogs that delete permanently are **never** playful: state the risk plainly.
- Write UI strings as Indonesian literals in SwiftUI; Xcode adds them to `Localizable.xcstrings`.

### English

Every UI string also needs its English, with the same friendly tone in plain words.

- Add it in Xcode's String Catalog editor (`Localizable.xcstrings`). Xcode adds new strings to the catalog when you build in Xcode; from the command line, `make strings` does it.
- Talk to the user as "you"; contractions are fine. Buttons and menu items use title case (*Scan Now*, *Move to Trash*), everything else sentence case.
- A string with a count needs plural forms, such as *1 file* and *3 files*: choose **Vary by Plural** in the catalog editor. When that string has other arguments too, number them in the English, such as `Moved %1$@%#@leftovers@ to the Trash (%3$@).` Unnumbered ones next to a plural show the wrong values or crash the app.
- CI fails when a string has no English, or when the catalog keeps a string the code no longer uses.

### Glossary

Not fluent in Indonesian? Put the English text in your PR description and a maintainer will help with the Indonesian. Use these terms in both languages:

| English | Indonesian |
|---|---|
| Overview | Ringkasan |
| System Junk | Sampah Sistem |
| Developer Junk | Sampah Developer |
| Uninstaller | Hapus Aplikasi |
| Large & Old Files | File Gede & Lama |
| Disk Map | Peta Disk |
| Startup Items | Jalan Otomatis |
| Settings | Pengaturan |
| Check for Updates | Cek Versi Baru |
| Scan | Pindai |
| Clean Up | Bersihin |
| Trash | Tong Sampah |
| Move to Trash | Pindahin ke Tong Sampah |
| Empty Trash | Kosongin Tong Sampah |
| Cancel | Batal |
| Open Settings | Buka Pengaturan |
| Full Disk Access | Akses Disk Penuh |
| Leftover files | File sisa |
| In use | Lagi dipakai |
| Review first | Cek dulu |
| Permanent | Permanen |
| Exclusions | Pengecualian |
| Add to Exclusions | Masukin ke Pengecualian |
| Excluded | Dikecualiin |
| Can't be read | Nggak kebaca |
| Turn On / Turn Off | Nyalain / Matiin |
| Running | Lagi jalan |
| Unused | Nggak kepakai |

## Commits and pull requests

- One focused change per PR. PRs are squash-merged.
- `main` is protected: changes land through pull requests, and CI (`Scan secret` and `Build & test`) must pass.
- Fill in the PR template, and delete the checklist items that don't apply.

### Commit messages

Commit messages are in English and use [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `chore:`, ...).

- The subject says what changes, in the imperative, in 60 characters or fewer. The reason goes in the body.
- Small changes need no body. Otherwise, write a few lines of prose about why the change is needed and anything the diff doesn't show, wrapped at 72 characters. Leave out the list of changed files: the diff already has it.

```text
fix: add the signing keychain to the search list

The v0.3.0 release run stopped at "no identity found". On the macOS 26
runner, codesign only finds an identity in a keychain on the search
list, even with --keychain.
```

## Never commit sensitive data

The `pre-commit` hook (enabled by `make setup`) blocks certificates (`.p12`, `.cer`), private keys (`.p8`, `.pem`, `.key`), provisioning profiles, `.env` files and `Config/Local.xcconfig`, and scans staged changes with gitleaks. CI scans the full Git history again, and GitHub push protection is on.

If you accidentally push a secret, **treat it as leaked**: revoke or rotate it first, then clean up the history.

Also watch for personal data in issues and PRs, such as screenshots or logs that show `/Users/your-name` or private file names.

## Licensing

By contributing, you agree that your contributions are released under the [MIT License](LICENSE).

**Don't copy code from projects with incompatible licenses**, such as GPL projects (like Mole) or "Commons Clause"/source-available licenses (like Pearcleaner). Taking inspiration is fine; write your own implementation.

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). In short: be respectful, and discuss ideas, not people.
