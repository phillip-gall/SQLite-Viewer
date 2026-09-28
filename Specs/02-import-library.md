# Plan 02: Import and database library

## Goal

Let users import a SQLite file into a protected app-owned library, reopen it, and remove it. Imported databases remain usable after the source file disappears.

## Planning

Read the architecture and current implementation. Check `git status`, recent commits, and the selected simulator. Reuse the SQLite access layer already present. The codebase determines its actual API; do not write a handoff note.

## Implementation

1. Create `DatabaseLibrary` with a stable UUID per import and a manifest containing display name, import date, and original filename only. Use `Application Support/Databases/<UUID>/database.sqlite`. Keep arbitrary imported paths out of the manifest. Use an internal staging directory and replace/move into the final directory only after validation succeeds.
2. Create directories with complete file protection and exclude the library from backup. Ensure `database.sqlite` and any journal/WAL sidecars inherit or receive protection. Handle file-protection errors as recoverable UI errors.
3. Present SwiftUI `fileImporter` for file URLs. The picker accepts recognized SQLite document types, as specified in [Plan 08e](08e-sqlite-file-picker.md), while the library service validates actual SQLite content regardless of the source extension. Start and stop security-scoped access exactly around import. Open source read-only, use `sqlite3_backup` into staging, run `PRAGMA quick_check`, close handles, then publish the new library entry. Detect and report source-open, backup, corruption, low-storage, and permission failures. Explain in the UI that import creates a snapshot and source WAL sidecars must be accessible for uncheckpointed transactions to appear.
4. Replace the hello-world screen with a database library showing name, import date, file size, Import, Open, and Delete. Confirm deletion of an imported copy, close its active session first, and remove its whole UUID directory. Never delete the original provider URL.
5. Reconcile manifests with disk on launch. Ignore and clean abandoned staging directories; show a repairable error for a missing or damaged database rather than crashing.

## Testing

Run the simulator unit tests and at least one UI test for import and reopen. Add focused library-service tests for a valid file with an unusual extension, a corrupt file, an import that fails midway, duplicate imports, reopen after source deletion, and deleting one copy without changing another. Verify file protection and backup exclusion attributes on the created directory and database. Build Release for `generic/platform=iOS Simulator` to catch configuration differences.

## Review

Inspect security-scope balance, source read-only flags, staging cleanup, file URL containment, protection on sidecars, error text, and whether app UI ever references the source URL after import. Run `git diff --check` and inspect `git status`.

## Commit

Stage only this plan's changes and commit as `Add protected database imports`. In the body state the import consistency rule, file-protection choice, and tests run. Keep generated databases and local Xcode data out of Git.

## Done when

A valid imported database survives source removal, invalid imports leave no library entry, and deleting an import cannot touch the original file.
