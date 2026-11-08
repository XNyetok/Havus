# Stack Decision

> Technical decision record for Havus, written on 2 November 2026 when the project started.
> If a decision changes, update this document together with the reasoning.

## Requirements

1. **Lightweight.** Small app, low idle memory, instant launch.
2. **Powerful.** Full access to macOS APIs: Full Disk Access, the Trash, Spotlight, app metadata, and later a helper with root privileges.
3. **Safe.** Controlled deletion, no network access beyond an opt-in update check, and the smallest possible supply chain.
4. **Contributor-friendly.** Few tools to install, builds without a paid account, fast tests.

## Candidates

| | Swift + SwiftUI | Tauri 2 | Electron | Flutter |
|---|---|---|---|---|
| App size | **1.5 MB** (Havus 0.1.0, universal) | ~5–15 MB | ~150–250 MB | ~30–50 MB |
| Idle memory | **~34 MB** (Havus 0.1.0, measured) | ~50–150 MB (app + WebKit processes) | ~150–400 MB | ~60–120 MB |
| macOS API access | Direct | Through plugins or bridging | Through native addons | Through platform channels |
| Contributor toolchain | Xcode | Rust + Node + Xcode | Node + Xcode | Flutter + Xcode |
| Dependencies | 0 | crates + npm | npm (many) | pub + plugins |
| Look and feel | Native, follows the latest macOS design | Web | Web | Custom |

The Swift numbers were measured on the Havus 0.1.0 release build: `du -sh` for the app size and `footprint` for idle memory after 5 seconds. The other columns are rough estimates from public benchmarks. For example, Hopp's benchmark measured an 8.6 MB Tauri demo app against 244 MB for Electron, and about 172 MB against 409 MB of memory with six windows open. Those numbers were not measured in this project.

## Decision: Swift 6 + SwiftUI, zero third-party dependencies

Why:

- **A cleaner is almost entirely macOS API work:** `FileManager` to scan and measure files, `trashItem` for the Trash, Spotlight `MDQuery` to find large files, `NSWorkspace` and `NSRunningApplication` for app info, and later `SMAppService` + XPC for a root helper. Swift calls all of these directly; Tauri and Electron need a native bridge for each one.
- **The lightest option.** No web runtime and no WebView processes. The measurements are in the table above.
- **The safest supply chain.** Zero dependencies means no third-party package that could be compromised, which matters for an app that asks for Full Disk Access.
- **Contributors only need Xcode.** The core tests run with `swift test`.
- **A native look for free.** Standard SwiftUI controls follow the latest macOS design automatically, including Liquid Glass on macOS 26 and later.

Trade-offs: Havus runs only on macOS (which is the goal), and contributors need to know Swift.

## Technical details

| Need | Choice | Notes |
|---|---|---|
| Language | Swift 6, strict concurrency | Prevents data races during parallel scans |
| UI | SwiftUI, plus AppKit where needed | `NavigationSplitView` and native controls |
| State | Observation (`@Observable`) | Requires macOS 14 |
| Minimum OS | macOS 14 Sonoma | Older Intel Macs stuck on Sonoma are still supported |
| CPU architecture | Universal (arm64 + x86_64) | Verified with `lipo -archs` |
| Core module | Local Swift package `HavusCore` | Testable without the UI |
| Tests | Swift Testing | `swift test`, or ⌘U in Xcode |
| Formatting | `swift-format` from the toolchain | Nothing extra to install |
| Xcode project | Synchronized folders (Xcode 16+ format) | Adding files doesn't touch `project.pbxproj`, so fewer merge conflicts |
| Sandbox | Off | A cleaner must read other apps' caches. As a result, Havus can't ship on the Mac App Store |
| Hardened Runtime | On | Required for notarization later |
| UI language | Indonesian and English (String Catalog, source language `id`) | Follows the Mac's preferred languages |

## macOS APIs per feature

- **System and developer junk:** a `FileManager` enumerator with `totalFileAllocatedSizeKey` (symlinks are never followed), then `FileManager.trashItem`.
- **Uninstaller:** reads `Info.plist`, then looks for leftovers by bundle ID in `~/Library/...`. `NSRunningApplication` checks whether the app is running. System apps are recognized by their location in `/System`, a symlink into the system *cryptex* (for example Safari), or the SIP `restricted` flag.
- **Large and old files:** Spotlight `MDQuery` (`kMDItemFSSize`, `kMDItemLastUsedDate`). If Spotlight returns nothing, Havus scans the standard folders directly. Files inside *packages* (such as the Photos library) and in `~/Library` are always skipped.
- **Permissions:** Full Disk Access is detected by trying to open a TCC-protected file, which never triggers a prompt. An `x-apple.systempreferences:` deep link takes the user straight to the right settings page.
- **Startup items:** reads the property lists in `~/Library/LaunchAgents` with `PropertyListSerialization`, asks launchd through `/bin/launchctl` (`list` and `print-disabled`, then `disable` + `bootout` or `enable` + `bootstrap` in the user's `gui/<uid>` domain, which needs no root), and reads the switches in Login Items with `SMAppService.statusForLegacyPlist(at:)`. Removing an agent goes through `FileRemover` like every other removal.
- **Later (root access):** `SMAppService.daemon` + XPC, validating the caller's *code signing requirement* on the connection.

## Distribution

For now there's **no Apple Developer Program membership**, so releases are zips on GitHub Releases with a SHA-256 checksum, signed with a self-signed certificate instead of a Developer ID, and not notarized.

What that means:

- Since macOS 15, the right-click → Open trick is gone. Users have to go to System Settings → Privacy & Security → **Open Anyway**, once for each version.
- Full Disk Access is tied to the app's signature. Up to 0.2.0, releases were ad-hoc signed, and an ad-hoc signature changes with every build, so users had to grant the permission again after each update. Since 0.3.0, every release is signed with the same certificate, so the permission survives updates. See [Release signing certificate](maintainer.md#release-signing-certificate).
- Homebrew 5.0 (November 2025) removed the `--no-quarantine` option, and since 1 September 2026 Homebrew disables casks that fail Gatekeeper checks. The official Homebrew Cask only becomes realistic after notarization.

The upgrade path: Apple Developer Program → Developer ID certificate → notarization (`notarytool`) → Homebrew Cask, and optionally Sparkle for auto-updates. The steps are in [maintainer.md](maintainer.md).

**Update check (added 5 November 2026).** Havus couldn't tell users about new versions, so they had to find out from GitHub or havus.web.id. The app now has an opt-in check: once a day it asks GitHub's API for the latest release tag, then links to the changelog on havus.web.id. It uses plain `URLSession`, so there's still no third-party dependency. Real auto-updates with Sparkle wait for notarization. Until then, an app with the Hardened Runtime and without a Developer ID may refuse to load `Sparkle.framework` unless library validation is turned off, and that isn't worth it in an app with Full Disk Access. Details in [architecture.md](architecture.md#update-check).

## Open-source repository security

- `.gitignore` rejects certificates, private keys, provisioning profiles, `.env` files and `Config/Local.xcconfig`.
- Team IDs and personal signing settings live in `Config/Local.xcconfig` (gitignored), not in `project.pbxproj`.
- The `pre-commit` hook blocks sensitive files and runs `gitleaks git --pre-commit --staged`.
- CI runs gitleaks over the full history on every push and pull request. The binary is verified with a SHA-256 checksum, actions are pinned to commit SHAs, and the default permission is `contents: read`.
- Dependabot keeps the GitHub Actions versions up to date.
- On GitHub: secret scanning with push protection, private vulnerability reporting, Dependabot alerts and security updates, and a ruleset protecting `main`. See [maintainer.md](maintainer.md).

## CI

- `macos-latest` currently points to macOS 26 (arm64). The macOS 14 image is deprecated.
- The project uses the Xcode 16+ project format and `swift-tools-version: 6.0`, so it builds with the runner's default Xcode. Local development uses Xcode 27.

## Similar projects

For ideas only. **Don't copy their code**: the licenses differ.

| Project | Stack | License | Notes |
|---|---|---|---|
| Pearcleaner | Swift/SwiftUI | Apache 2.0 + Commons Clause (source-available, not OSI) | Uninstaller reference. The license forbids selling it |
| Mole | Shell/Go (CLI) | GPL-3.0 | Developer cleanup rules reference. GPL code can't be copied into an MIT project |
| PureMac | Swift/SwiftUI | MIT (according to its listing) | Small project |
| MacSai | Swift 6/SwiftUI | BSD-3-Clause (according to its listing) | Already notarized |

The Pearcleaner and Mole licenses were checked directly against the LICENSE files in their repositories.

## Sources

- Tauri vs. Electron benchmark (Hopp): <https://dev.to/gethopp/tauri-vs-electron-performance-bundle-size-and-the-real-trade-offs-1el4>
- Homebrew 5.0 and the Gatekeeper policy: <https://workbrew.com/blog/homebrew-5-0-0>
- GitHub Actions runner labels: <https://github.com/actions/runner-images>
- gitleaks: <https://github.com/gitleaks/gitleaks>
- Pearcleaner: <https://github.com/alienator88/Pearcleaner>
- Mole: <https://github.com/tw93/Mole>
- PureMac: <https://awesome.ecosyste.ms/projects/github.com%2Fmomenbasel%2Fpuremac>
- MacSai: <https://awesome.ecosyste.ms/projects/github.com%2Filiyami%2FMacSai>
- Contributor Covenant 2.1: <https://www.contributor-covenant.org/version/2/1/code_of_conduct/>
