# Architecture

## Overview

```
┌─────────────── Havus.app (SwiftUI, @MainActor) ───────────────┐
│  RootView (NavigationSplitView)                               │
│   ├─ Ringkasan          DiskSpace, every page model's state   │
│   ├─ Sampah Sistem      JunkCleanerModel(group: .system)      │
│   ├─ Sampah Developer   JunkCleanerModel(group: .developer)   │
│   ├─ Hapus Aplikasi     UninstallerModel                      │
│   ├─ File Gede & Lama   LargeFilesModel                       │
│   ├─ Peta Disk          DiskUsageModel (read-only)            │
│   ├─ Jalan Otomatis     StartupItemsModel                     │
│   └─ Tentang Havus      UpdateCenter, links to the website    │
│  Pengaturan             ExclusionStore ──► every page model   │
└───────────────┬───────────────────────────────────────────────┘
                │ runs in the background (TaskGroup / Task.detached)
┌───────────────▼──────── HavusCore (Swift package, no UI) ─────┐
│  JunkScanner + JunkRule.catalog                               │
│  AppCatalog + LeftoverFinder                                  │
│  LargeFileFinder (Spotlight, folder scan fallback)            │
│  DiskUsageScanner (sizes per folder, removes nothing)         │
│  LaunchAgentCatalog + Launchd (launchctl, Login Items)        │
│  ExclusionList (checked by every scanner and by PathGuard)    │
│                         │                                     │
│              FileRemover ──► PathGuard ──► FileManager        │
│              (the only way to delete anything)                │
└───────────────────────────────────────────────────────────────┘
```

**The app** (`Havus/`) contains only views, state and the UI copy (the page names above are the Indonesian ones users see; see [Languages](#languages)). **HavusCore** (`Packages/HavusCore/`) contains all logic that touches the disk, and all of it is testable without the UI.

## Removal flow

Every deletion goes through this path, no exceptions:

1. A scanner produces items. Each item has `removalTargets`: the URLs that will actually be removed.
2. The user reviews and selects items in the UI, then confirms in a dialog.
3. `FileRemover.remove(_:method:allowedRoots:)` processes each URL:
   - `PathGuard.check` **rejects** the URL if it isn't a file URL; if it's a protected location (the home folder, `~/Documents`, `~/Library`, `/System`, `/Applications` and similar); if it's inside a system folder such as `/System` or `/usr`, iCloud Drive or `~/Library/CloudStorage`; if it's on the user's [exclusion list](#exclusion-list), inside an excluded folder, or holds an excluded item; or if it isn't **strictly inside** one of the `allowedRoots`. `..` and symlinks in parent folders are resolved first, so traversal tricks can't slip through.
   - If it passes, the item is moved with `trashItem` (the default) or deleted with `removeItem` (only for the contents of the Trash).
4. The result lists what succeeded and what failed, with reasons, and is shown to the user.

Symlinks are always judged as the link itself, never as its destination. Removing a symlink only removes the link.

## Cleanup rules

Rules (`JunkRule`) are data, not code:

| Property | Meaning |
|---|---|
| `relativePath` | Location relative to the home folder. Must stay inside home (checked by tests) |
| `strategy` | `.eachChild`: every entry in the folder is its own item. `.wholeContents`: all contents form one item, and the folder itself is kept |
| `safety` | `.safe` items are selected automatically; `.review` items must be selected by the user |
| `removal` | `.moveToTrash` (default) or `.deletePermanently` (only for the Trash contents, locked by tests) |
| `excludedNames` | Entries that are never offered, such as iCloud sync state |

When a more specific rule lives inside another rule's folder (for example `Library/Caches/Homebrew` inside `Library/Caches`), that folder appears only under the more specific rule, so nothing is counted twice.

## Exclusion list

Files and folders the user protects in **Pengaturan → Pengecualian**, or with **Masukin ke Pengecualian** in a result's right-click menu.

- **What it blocks.** `ExclusionList.blocks(_:)` is true for an excluded path, anything inside it, and any folder that holds it, since removing that folder would remove the excluded item too. Paths are compared in their literal and symlink-resolved forms, without regard to case or Unicode normalization, so a mismatch can only block more.
- **Where it's checked.** `JunkScanner`, `LeftoverFinder`, `LargeFileFinder` and `LaunchAgentCatalog` leave blocked items out and don't measure them. `PathGuard` checks the list again before every removal (`.excluded`), so an item that gets past a scanner still can't be removed. **Peta Disk** is the exception: it removes nothing, so it measures excluded items too, or the map would hide where space goes, and marks them *Dikecualiin*.
- **How pages get it.** `ExclusionStore` keeps the list in UserDefaults (`Exclusions.paths`). `RootView` hands every page model the current `ExclusionList` whenever it changes, and each model drops the results it now blocks. A `.wholeContents` item goes away as a whole when any of its targets is blocked, because its size covers all of them; the next scan brings back the rest. Removing an exclusion takes effect on the next scan.
- **Apps.** `AppCatalog` still lists excluded apps, so their bundle identifiers keep protecting their data when another app's leftovers are searched. **Hapus Aplikasi** marks them *Dikecualiin* and only offers their leftovers.

## Startup items

**Jalan Otomatis** lists the launch agents in `~/Library/LaunchAgents`: the jobs launchd starts for this user alone, which Havus can change without root.

- **What's listed.** `LaunchAgentCatalog` reads every property list directly in that folder. launchd ignores subfolders, and so does Havus. A file without a `Label`, or without a program to run, shows up as unused, because launchd never loads it; Google Software Update leaves agents like that behind. A program counts as missing only when its full path surely doesn't exist (`ENOENT`), never when macOS hides it or it's on a disk that isn't connected.
- **Which app it belongs to.** The first match of: the app named in `AssociatedBundleIdentifiers`, which Login Items in System Settings uses too; the outermost app bundle that holds the program; an installed app whose bundle identifier starts the label. When **Hapus Aplikasi** lists that app, the agent's menu can open it there. **Hapus Aplikasi** trusts only the first two: an agent whose name merely starts with an app's bundle identifier starts ticked only when one of them points to that app, since another app's label can start the same way.
- **Its state.** `Launchd` reads `launchctl list` for the jobs that are loaded and running, and `launchctl print-disabled gui/<uid>` for launchd's overrides, which outrank the file's `Disabled` key. It also asks Background Task Management, through `SMAppService.statusForLegacyPlist(at:)`, whether the user switched the agent off in **System Settings → General → Login Items & Extensions**.
- **Turning off and on.** Off runs `launchctl disable gui/<uid>/<label>`, then `bootout` to stop the job now. On runs `enable`, then `bootstrap` to load it like at login. Both change only launchd's record, never the file, so they can always be undone. launchd keeps the record by label, so it also covers a file the app writes again. A switch the user flipped in System Settings stays theirs: Havus shows it but leaves it alone. Login Items and launchd keep separate records, so an agent Havus turned off can still look allowed in System Settings.
- **Removing.** The file goes to the Trash through `FileRemover`, with `~/Library/LaunchAgents` as the only allowed root. Only once it's there is the job booted out. Restoring the file brings the job back at the next login. Turning an agent off is the default the page suggests, because many apps write their agent again when it's missing; removing the app in **Hapus Aplikasi** is the lasting fix.
- **Not yet.** The agents and daemons in `/Library/LaunchAgents` and `/Library/LaunchDaemons` need root to change, so they wait for the [root helper](#root-helper-plan-next-phase). macOS has no public API that lists every app that opens at login, or the agents apps register with `SMAppService`, so the page links to Login Items in System Settings for those.

## Disk map

**Peta Disk** shows where the space in the home folder goes, biggest first, and opens a folder when it's clicked. It's read-only: nothing on the page removes anything.

- **One pass.** `DiskUsageScanner` walks the home folder once, hidden items included, and adds up the space allocated to each folder, like `DirectorySize`. Symbolic links are never followed. Packages, such as apps and Photos libraries, are measured as a whole and never opened.
- **Light on memory.** A folder is read one entry at a time, never listed all at once, because one folder can hold a hundred thousand files (a framework's view cache, say); listing those at once took over 1 GB. Each folder keeps its 50 biggest items and adds up the rest (*N item lain*), and a folder under 10 MB keeps no list at all. Opening such a folder scans it on its own, which is quick since it's small. A 46 GB home folder took about 30 seconds.
- **Remembers the last map.** Each finished scan is saved as a `DiskUsageSnapshot` in `~/Library/Application Support/<bundle ID>/DiskMap.plist`: the names and sizes on the map, when the scan started, and whether Full Disk Access was on. The page opens with that map and says how old it is (*Dipindai 2 hari yang lalu*), so the user waits only for a scan they ask for. Havus never scans by itself, since a scan without Full Disk Access can make macOS ask for permission. A map of 8,000 items takes about 300 kB and loads in 40 ms, so it's read when the page first opens, not at launch.
- **Says when the map is behind.** A folder that's gone by the time it's opened says so. A note asks for a new scan when Full Disk Access came on after the map was made, or when another page moved or deleted files since (`DiskMap.lastRemoval` in UserDefaults). While a new scan runs, its progress bar goes by the size of the home folder in the last map.
- **Cloud files stay in the cloud.** The scan turns off `IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES` for its thread, so files and folders that only exist in iCloud Drive or a File Provider app (Dropbox, Google Drive, OneDrive) are never downloaded. They count as the space they take on the Mac, which is next to nothing.
- **What it can't read.** Without Full Disk Access, macOS keeps some folders closed. They show *Nggak kebaca*, or their size with a `+`, like in **Hapus Aplikasi**, and a folder with such parts gets a note at the top of its list with a button to the setting. The Photos library and the Music and TV media folders count as closed too: the map doesn't open them, since that would make macOS ask (see [macOS permissions](#macos-permissions)).
- **VoiceOver.** Each row has its own name, size and *Dikecualiin* as its label and its share as its value, e.g. *Library, Lebih dari 15,92 GB, 34%*. Combining the row's children left it without a name.
- **Bars, not a treemap.** Each row has a bar for its share of the folder on screen, in the accent color on a lighter track, next to its size. Bars on one baseline compare sizes more exactly than the areas of a treemap, every name stays readable, and the page is a plain list for VoiceOver.

## Concurrency

- **Core:** `Sendable` types and synchronous (blocking) functions that regularly check `Task.isCancelled`. Kept simple on purpose, so it's easy to test.
- **App:** `@MainActor @Observable` models. Disk work runs in `TaskGroup` child tasks (a parallel scan per rule, app sizes three at a time) or in a detached task, and the results are sent back to the main actor. Scans can be cancelled at any time. Awaiting a bare `Task.detached` ignores the caller's cancellation, so work the user can cancel goes through `Background.run`, which passes it on.

## macOS permissions

- **Full Disk Access and the signature:** macOS ties the permission to the app's designated requirement. Releases are all signed with one certificate, so the permission survives updates; Debug builds use the bundle ID `id.nyetok.havus.debug`, so they don't disturb it. See [Release signing certificate](maintainer.md#release-signing-certificate).
- **Full Disk Access:** checked without a prompt by trying to open a TCC-protected file. Checked again whenever the app becomes active, for example after the user comes back from System Settings.
- **App Management:** macOS sometimes requires it to move other apps to the Trash. If it's denied, Havus shows a button that opens the right settings page.
- **Launch agents:** reading and changing the user's own launch agents needs no permission, because `launchctl` acts only in the user's own GUI domain.
- **Folders that make macOS ask:** without Full Disk Access, macOS asks before Havus reads Desktop, Documents or Downloads, once per folder, and remembers the answer for that signature: releases share one certificate, so the answer survives updates, while every ad-hoc Debug build asks again. The Photos library and the Music and TV media folders have permissions of their own, so **Peta Disk** and **File Gede & Lama** leave them out (`MediaLibraries`) until Full Disk Access is on, and both pages say so before the first scan. Full Disk Access covers all of these, so with it nothing asks.

## Update check

The only network access in Havus. It tells the user about a new version; it never downloads or installs anything.

- **Off until the user turns it on.** The welcome sheet asks once, on the first launch (*Mau dikabarin kalau ada versi baru?*), and needs an answer. The app menu has **Cek Versi Baru…** and the **Cek Versi Baru Otomatis** toggle, and **Pengaturan → Umum** has the toggle too. Once it's on, `UpdateCenter` checks when Havus starts or comes to the front, at most once a day.
- **One request that carries nothing about the user.** `UpdateCheck` sends a GET to GitHub's `releases/latest` endpoint for XNyetok/Havus, which never returns drafts or prereleases. It uses an ephemeral session with no cookies and no cache. It also replaces the default `User-Agent` and `Accept-Language`, which would name the macOS version and the user's languages, with `Havus` and `en`.
- **Only the tag is read.** The tag must look like `vX.Y.Z`; the release notes and assets are ignored. The answer can't change anything in the app except the version number shown, and the link always goes to the release on the changelog at havus.web.id, in the language Havus runs in: `https://havus.web.id/en/changelog/#vX.Y.Z` in English, `https://havus.web.id/changelog/#vX.Y.Z` otherwise. The website builds that page from the same GitHub releases.
- **Failures stay quiet.** When an automatic check fails, Havus tries again the next day. A check started from the menu shows an alert that it couldn't connect.

## Logging

Havus writes to the unified log under the subsystem `id.nyetok.havus` (`Log` in HavusCore), so a problem on a user's Mac can be traced afterwards. The log stays on the Mac, like every other app's.

- **What Havus did, and why.** Each session starts with the Havus and macOS versions and whether Full Disk Access is on. Scans and cleanups log a line each with what they found or removed and how long they took. `FileRemover` logs every refusal with `PathGuard`'s reason and every failed removal with its error code, and `Launchd` logs what launchctl answered. Categories: `app`, `scan`, `removal`, `launchd`, `updates` and `reports`.
- **Private by default.** Paths and the names of the user's apps and launch agents are logged as `.private(mask: .hash)`. The log shows a hash, the same for the same value, so the lines about one file can be matched up without revealing it. Counts, sizes, durations, rule IDs, reasons and error codes are public.
- **`notice` or above.** macOS keeps those on disk for a few days. It keeps `info` lines only in memory unless an error follows, and `debug` lines not at all.
- **Reading it.** Filter Console on the subsystem, or run the command below. In zsh, a bare `log` is a shell builtin, hence the full path.

  ```sh
  /usr/bin/log show --last 1h --info --predicate 'subsystem == "id.nyetok.havus"'
  ```

- **In a problem report.** `LogExport` reads Havus's lines back with `OSLogStore` and writes them to a file the user can attach (see [Crash reports](#crash-reports)). Lines from an earlier session, such as the one that crashed, need the store's system scope, which macOS opens only for admin accounts outside the sandbox. For other accounts, the file holds only the running session's lines.

## Crash reports

Apple passes crash reports on only to developers of App Store apps, so Havus helps the user send one. It never sends anything itself, and goes online for nothing new.

- **Where macOS keeps them.** When Havus crashes, macOS writes a report to `~/Library/Logs/DiagnosticReports`, named after the process (`Havus-2026-11-08-201402.ips`), and moves it into `Retired` there a few hours later. `CrashReport` reads both folders, which needs no permission. A file counts only when its first line, a JSON header, says it's a crash (`bug_type` 309) of the running app's bundle identifier, so a Debug build sees only its own reports.
- **Offered once, at launch.** `ProblemReportCenter` offers the newest report since the last one it offered, in an alert, unless the welcome sheet is up. The first launch only notes the time, so reports from versions without [debug symbols](maintainer.md#reading-a-crash-report) aren't offered. The check runs at launch also because **Sampah Sistem** offers `~/Library/Logs`, crash reports included, for cleanup.
- **The user sends it.** **Lapor lewat GitHub** opens the bug report form with the Havus and macOS versions filled in, and **Kirim lewat Email** opens an email with the same details. Either way, Havus then writes two files to its temporary folder and shows them in Finder to look at and attach: a copy of the report as `.ips.txt`, since GitHub doesn't take `.ips` files, with the home folder written as `~`, and its [log](#logging) lines from the three hours before the crash as `Havus-log-<date>.txt`. **Laporkan Masalah…** in the Help menu offers the same two ways at any time, with the log lines of the past day and the newest crash report of the past week, if there is one.

## Languages

The UI is in Indonesian and English.

- **Indonesian is the source.** UI text is written as Indonesian literals in SwiftUI, and those literals are the keys of `Havus/Localizable.xcstrings`, which holds the English for each one, with plural forms where a string has a count. Indonesian is also the project's development language, so it needs no `id.lproj`: a string without English shows its Indonesian key.
- **macOS picks the language.** Havus runs in whichever of the two comes first in the user's preferred languages, or in the language set for Havus under **Applications** in **System Settings → General → Language & Region**. When neither is listed, it uses Indonesian, the development language. The app never chooses or stores a language itself.
- **Sizes and dates follow it.** `Format` uses the current locale, which macOS builds from the app's language and the user's region, so they match the text around them (`3 bulan yang lalu`, `3 months ago`).
- **CI checks the catalog.** While building, the compiler lists the strings it finds in `.stringsdata` files. `scripts/check-strings.sh` syncs a copy of the catalog with them and fails when a string has no English, or the catalog keeps one the code no longer uses. `make strings` writes new strings into the catalog itself, like a build in Xcode does.

## Adding a feature

1. Logic → `Packages/HavusCore/Sources/HavusCore/<Feature>/`, with tests in `Tests/HavusCoreTests/`.
2. UI → `Havus/Features/<Feature>/` (model + view). Use the components in `Havus/Shared/Components.swift` and the tokens in `Design.swift`. The page's name and subtitle come from `SidebarItem` and show in the toolbar, together with page-wide actions such as **Pindai Ulang** (⌘R). A results page puts its summary in the header of a `RowList` and lays its rows out on the `Design.Column` widths, so the summary, the rows and the `ActionBar` all start on `Design.pageMargin`, under the name in the toolbar. Outside a `List` or `ScrollView`, never use `.fixedSize(horizontal: false, vertical: true)` on text, such as in an `ActionBar`: the window measures the page's minimum height with the text squeezed narrow, where it grows hundreds of points tall, and the whole page, sidebar included, then overflows the window and gets cut off.
3. Need a new page? Add a case to `SidebarItem`. In `RootView`, the compiler then asks for the page's view in `detail`, but not for its row in the sidebar or the `setExclusions(_:)` call that hands its model the exclusion list.
4. Write UI text as Indonesian literals in SwiftUI, then add the English in `Localizable.xcstrings`. See [Languages](#languages) and the glossary in [CONTRIBUTING.md](../CONTRIBUTING.md).
5. Offering files for removal? Take the page's `ExclusionList` (see `setExclusions(_:)` in the existing models) and pass it to the scanner and to `PathGuard`.

## Root helper plan (next phase)

Some features, such as system maintenance and caches in `/Library`, need root. The plan:

- A separate helper daemon registered with `SMAppService.daemon(plistName:)`. The user approves it in System Settings → Login Items.
- App ↔ helper communication over XPC. The helper validates the caller's *code signing requirement* (`NSXPCConnection.setCodeSigningRequirement`), so only Havus can command it.
- The helper accepts only commands from a fixed allowlist, never arbitrary paths, and runs its own root-side `PathGuard`.
- Prerequisite: a Developer ID and notarization (#23). The self-signed release certificate, used since 0.3.0, keeps Full Disk Access across updates, but a helper that runs as root should come from a notarized app.
