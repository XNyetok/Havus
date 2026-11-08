<!-- What changed and why, in a few sentences. Link related issues, e.g. "Closes #12". -->

## How to test

<!-- Steps to check the change. Leave this section out if they're obvious. -->

## Checklist

<!-- Delete the items that don't apply. -->

- [ ] `make test` passes, and the app builds and runs on macOS <!-- version -->
- [ ] No secrets, certificates, Team IDs or personal data
- [ ] File removals go through `FileRemover` (no direct `FileManager.removeItem`/`trashItem` calls)
- [ ] New or changed cleanup rules come with evidence that they're safe, plus tests
- [ ] UI text is casual Indonesian ("kamu"), with English in `Localizable.xcstrings` (see the glossary in CONTRIBUTING.md)
