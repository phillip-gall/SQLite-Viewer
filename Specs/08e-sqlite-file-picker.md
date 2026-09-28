# Plan 08e: Select SQLite files in the picker

## Goal

When the user taps Import, the system file picker offers SQLite database files and makes unrelated files unavailable for selection.

## Planning

Read [the architecture](00-architecture.md), [Plan 02](02-import-library.md), `ContentView`, `DatabaseLibrary`, and the generated Info.plist settings in the Xcode project. Check `git status` and recent commits. Inspect the SDK's registered SQLite content types before declaring an imported type of this app's own.

## Implementation

1. Define one shared list of supported SQLite document types for the picker and Plan 08f's document registration. Recognize the common `.sqlite`, `.sqlite3`, and `.db` filename extensions. Use an existing system type when the SDK supplies one; otherwise declare an imported SQLite type conforming to `public.data`, with those filename tags. Do not claim ownership of SQLite's format through an exported type.
2. Replace `allowedContentTypes: [.item]` in the SwiftUI `fileImporter` with the SQLite type list. Keep folders navigable. Do not use a generic `public.data` or `public.item` fallback, since that would make unrelated documents selectable.
3. Keep the `DatabaseLibrary` header and `PRAGMA quick_check` validation. A `.db` file may use another format despite its suffix, and the picker cannot prove its contents are SQLite. Show the existing invalid-database error after selection in that case. Keep the service able to import a valid database with an unusual suffix when called directly; only the user-facing picker narrows the choices.
4. Add a short picker or import hint naming the supported extensions. Keep the existing snapshot and WAL-sidecar explanation.

## Testing

Inspect the built app's Info.plist and type tags. In Files on an available iPhone simulator, confirm `.sqlite`, `.sqlite3`, and `.db` samples can be selected while `.txt`, `.pdf`, and folders themselves cannot. Select a non-SQLite file renamed `.db` and confirm validation rejects it without adding a library entry. Recheck a valid unusual-extension file through the library service. Run affected unit and UI tests and build Debug and Release for `generic/platform=iOS Simulator`.

## Review

Check that declared identifiers and Swift `UTType` values match, provider-specific picker behavior, validation after selection, and unchanged source-file handling. Run `git diff --check` and inspect `git status`.

## Commit

Stage only this plan's changes and commit as `Limit picker to SQLite files`. In the body list supported extensions, the picker check, and tests run.

## Done when

The in-app picker permits recognized SQLite file types, unrelated file types cannot be selected, and a file with a SQLite-looking suffix still has to pass content validation.
