# Maintainer Guide

## Repository settings

These are enabled on [XNyetok/Havus](https://github.com/XNyetok/Havus). Keep them on, and use this list to recreate them if needed:

- **Secret scanning** with **push protection**
- **Private vulnerability reporting** (used by [SECURITY.md](../SECURITY.md))
- **Dependabot alerts** and **Dependabot security updates**
- **Squash merging** only (merge commits and rebase merging are off), with **auto-merge** allowed
- **Automatically delete head branches** after a merge
- **Ruleset "Protect main"** on the default branch:
  - pull request required, with 0 approvals so the maintainer can merge their own PRs, and squash as the only merge method
  - required status checks `Scan secret` and `Build & test`, accepted only from GitHub Actions
  - no force pushes, no branch deletion, no bypass

## Git identity

This repository uses a local identity, separate from the global Git config:

```sh
git config user.name   # Debi Kurnia
git config user.email  # debi@elysiumx.org
```

On a new machine, set both before the first commit, run `make setup` and `git config fetch.prune true`, and add the `git sync` alias that the workflow below uses:

```sh
git config alias.sync '!git switch main && git pull --ff-only --prune && git branch --format="%(refname:short) %(upstream:track)" | sed -n "s/ \[gone\]$//p" | xargs -r git branch -D'
```

GitHub signs the squash commits on `main`, so they show as **Verified**. To sign the commits on your branches too, use an SSH or GPG key registered on your account (`git config commit.gpgsign true`).

## Day-to-day workflow

`main` only changes through pull requests, and every pull request is squash-merged. Keep yours to one commit: its message becomes the commit on `main`, so you write it once. See [Commit messages](../CONTRIBUTING.md#commit-messages).

```sh
git sync
git switch -c fix/short-description
# ...work, then one commit...
make lint test build
git push -u origin HEAD
gh pr create --fill
gh pr merge --auto --squash --author-email debi@elysiumx.org
```

- `git sync` switches to an up-to-date `main` and deletes the local branches of merged pull requests.
- `gh pr create --fill` takes the title and description from the commit.
- `gh pr merge --auto` lets GitHub merge once `Scan secret` and `Build & test` pass, then delete the branch, so there's no need to wait. The `--author-email` flag keeps the squash commit on the project identity.

If a check fails, the pull request stays open. Fix the commit and push it again:

```sh
git commit --amend
git push --force-with-lease
```

Force-push only to a pull request branch; the ruleset blocks it on `main`. When a pull request has more than one commit, such as a contributor's, write the squash commit yourself with `--subject "... (#N)"` and `--body`.

## Releases (signed, not notarized yet)

1. Make sure `main` is green in CI.
2. Create and push a version tag:

   ```sh
   git tag -a vX.Y.Z -m "Havus X.Y.Z"
   git push origin vX.Y.Z
   ```

3. The **Release** workflow runs in the `release` environment. It imports the [release certificate](#release-signing-certificate), builds a universal app signed with it, and creates a **draft release** with `Havus-X.Y.Z.zip`, `Havus-X.Y.Z.zip.sha256` and `Havus.app.dSYM.zip`, the debug symbols for [reading crash reports](#reading-a-crash-report). It stops if the certificate is missing or the app doesn't match it.
4. Review the draft, edit the release notes, and publish.

Publishing is what reaches users: Havus's update check reads GitHub's *latest* release, so users who turned the check on hear about it within a day. Drafts and prereleases never show up. Keep tags in the `vX.Y.Z` form, because the app ignores any other tag and links to the release by it (`havus.web.id/changelog/#vX.Y.Z`, or `/en/changelog/#vX.Y.Z` when Havus runs in English).

## Reading a crash report

When Havus crashes, macOS writes a report to `~/Library/Logs/DiagnosticReports/` on the user's Mac, named like `Havus-2026-11-08-201402.ips`, and later moves it into the `Retired` folder there. Apple passes crash reports on only to developers of App Store and TestFlight apps, so a report reaches you only when the user sends it.

Release builds are stripped, so the report shows Havus's own code only as offsets into the binary. Every release after 0.3.0 comes with `Havus.app.dSYM.zip`, the debug symbols that turn those offsets into function names and line numbers. A dSYM fits only the build it came from, because the report names the binary by its UUID, and `scripts/build-release.sh` checks that the two match. 0.3.0 and earlier have no dSYM.

The report's first line has the version (`"app_version"`). Download that release's dSYM, symbolicate the report with the script that comes with Xcode, and open the result in Console:

```sh
gh release download vX.Y.Z --repo XNyetok/Havus --pattern Havus.app.dSYM.zip --dir /tmp/havus-X.Y.Z
ditto -x -k /tmp/havus-X.Y.Z/Havus.app.dSYM.zip /tmp/havus-X.Y.Z
python3 "$(xcode-select -p)/../SharedFrameworks/CoreSymbolicationDT.framework/Versions/A/Resources/CrashSymbolicator.py" \
  -d /tmp/havus-X.Y.Z/Havus.app.dSYM -o Havus-symbolicated.ips Havus-2026-11-08-201402.ips
open -a Console Havus-symbolicated.ips
```

The app version comes from the tag name, so there's no need to edit `MARKETING_VERSION` by hand. To try it locally first, run `make release VERSION=X.Y.Z`; the output lands in `build/release/`. A local build is ad-hoc signed unless you import the certificate, as described below.

## Release signing certificate

macOS ties Full Disk Access to an app's *designated requirement*. An ad-hoc signature changes with every build, so users had to turn the permission on again after every update. Since 0.3.0, every release is signed with the same self-signed certificate, so the requirement stays the same and the permission survives updates:

```
identifier "id.nyetok.havus" and certificate leaf = H"9e4a60cb751d37f504f5290a9ead326f31e739b5"
```

It doesn't replace notarization: macOS still blocks the first launch of each downloaded version until the user clicks **Open Anyway**.

| Certificate | |
|---|---|
| Common name | Havus Release Signing |
| SHA-1 | `9e4a60cb751d37f504f5290a9ead326f31e739b5` |
| SHA-256 | `4fd1005daf81b64ff4e8f10727a238f34cd6ba26f2c374d7cb6f3b1d823ebf4d` |
| Valid | November 5, 2026 to November 5, 2046 |
| Key | RSA 3072 |

**Where it lives:**

- On GitHub, in the `release` environment, which only tags matching `v*.*.*` can use: `HAVUS_SIGNING_P12_BASE64` (the `.p12` file in base64) and `HAVUS_SIGNING_P12_PASSWORD`.
- In the maintainer's password manager: the `.p12` file and its password. This is the only backup.
- Nowhere else. Never commit it (the pre-commit hook blocks `.p12` files anyway), and never paste it into an issue, a chat or a CI log.

To restore the secrets from the backup:

```sh
base64 -i havus-release-signing.p12 | tr -d '\n' | gh secret set HAVUS_SIGNING_P12_BASE64 --env release
gh secret set HAVUS_SIGNING_P12_PASSWORD --env release < havus-release-signing-password.txt
```

To sign a release on your Mac, for example while GitHub Actions is down:

```sh
HAVUS_SIGNING_P12_BASE64="$(base64 -i havus-release-signing.p12 | tr -d '\n')" \
HAVUS_SIGNING_P12_PASSWORD="$(cat havus-release-signing-password.txt)" \
  scripts/import-signing-certificate.sh /tmp/havus-signing.keychain-db
HAVUS_SIGNING_KEYCHAIN=/tmp/havus-signing.keychain-db make release VERSION=X.Y.Z
security delete-keychain /tmp/havus-signing.keychain-db
```

**Never change it.** `scripts/build-release.sh` pins the SHA-1 above and refuses any other certificate, because a new one makes every user turn Full Disk Access on once more. Replace it only when you have to:

- **The key is lost:** create a new certificate, update `RELEASE_CERT_SHA1` in `scripts/build-release.sh` and this section, and say so in the release notes.
- **The key leaks:** do the same right away and warn users. Anyone with the key can sign an app that macOS treats as Havus, Full Disk Access included, and a self-signed certificate can't be revoked.

To create a replacement, use macOS's own `/usr/bin/openssl` (LibreSSL), because `security import` can't read a `.p12` from OpenSSL 3 unless it's exported with `-legacy`:

```sh
/usr/bin/openssl req -x509 -newkey rsa:3072 -sha256 -days 7305 -nodes \
  -keyout key.pem -out cert.pem -subj "/CN=Havus Release Signing" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -name "Havus Release Signing" \
  -out havus-release-signing.p12
```

Then delete `key.pem`.

**Debug builds** use the bundle ID `id.nyetok.havus.debug` and show up as *Havus Debug*. When an app with the release bundle ID but a different signature runs, macOS switches off the Full Disk Access of the installed Havus, so `id.nyetok.havus` is for releases only.

## Upgrading to notarization

Do this once there's an Apple Developer Program membership ($99/year).

1. Create a **Developer ID Application** certificate and an **App Store Connect API key** (for `notarytool`).
2. Store them as **GitHub Secrets**, never in the repository:
   - `MACOS_CERTIFICATE_P12` (base64) and `MACOS_CERTIFICATE_PASSWORD`
   - `NOTARY_API_KEY_P8` (base64), `NOTARY_API_KEY_ID` and `NOTARY_API_ISSUER_ID`
3. In the workflow, import the certificate into a temporary keychain like the release certificate today, then change `scripts/build-release.sh` to sign with the Developer ID (`--options runtime`) instead, run `xcrun notarytool submit --wait`, and `xcrun stapler staple`.
4. Submit the app to Homebrew Cask. Optionally add Sparkle for auto-updates with an EdDSA-signed appcast.

After this, macOS no longer blocks the first launch. Moving from the self-signed certificate to a Developer ID changes the designated requirement once, so users turn Full Disk Access on one more time; say so in those release notes.

## Routine

- Review Dependabot PRs (GitHub Actions versions).
- Run `make scan` before every release.
- Update the minimum Xcode and macOS versions in README and CONTRIBUTING when the CI runners change.
- Run `scripts/download-stats.sh` once a week. It appends each asset's download count to `../Havus-stats/download-stats.csv`, outside the repo. GitHub keeps only the running total, so the history exists only if it's recorded.
