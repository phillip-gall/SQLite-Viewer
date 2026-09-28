# Plan 08f: Import files sent from other apps

## Goal

Show SQLite Viewer as an app choice when a user shares a SQLite file from Files. Tapping its icon starts importing that file without asking the user to choose it again.

## Planning

Read [the architecture](00-architecture.md), [Plan 08e](08e-sqlite-file-picker.md), `SQLite_ViewerApp`, `ContentView`, `LibraryViewModel`, `DatabaseLibrary`, and the app target's Info.plist generation. Check `git status` and recent commits. Inspect the actual file-opening callback on the target iOS version before wiring it to the model.

## Implementation

1. Register the SQLite document types from 08e in the app target's `CFBundleDocumentTypes` with `LSItemContentTypes`, `CFBundleTypeRole` as Viewer, and `LSHandlerRank` as Alternate. Keep the registration limited to SQLite types. The app imports a copy, so do not advertise editing the provider's document in place. Verify the generated Debug and Release Info.plist files contain the declarations.
2. Receive incoming file URLs at the SwiftUI app or root scene boundary with `onOpenURL`. If the system delivers file opens through a scene delegate in this project configuration, forward those contexts to the same import coordinator. Handle a cold launch after the library initializes and a warm launch while the user is viewing a database. Reject a non-file URL with a visible error.
3. Pass the received URL into the existing `LibraryViewModel.importFile` and `DatabaseLibrary.importDatabase` path. Start the import as soon as the app receives the URL. Keep security-scoped access balanced around the snapshot, preserve read-only access to the source, and never treat the source as the active database. Do not persist an external file URL in the library manifest.
4. Show import progress and the new entry in the library when complete. If the app is in a workspace, return to the library when the import completes so the result is visible. Report invalid SQLite content, unavailable provider files, and low storage through the same recoverable error UI as picker imports. Prevent duplicate imports caused by repeated delivery of one open event while allowing a later deliberate share of the same file.
5. Verify the Files share sheet presents the SQLite Viewer app icon for each supported SQLite extension. If a provider does not offer the document handoff, inspect its offered content type and correct the document association or handling before closing the plan. The acceptance check is the actual Files share sheet, not the presence of Info.plist keys alone.

## Testing

From Files on an available iPhone simulator or physical device, share each supported extension and tap the app icon with SQLite Viewer closed, then repeat while it is open. Confirm import begins automatically, the new copy appears once, it opens after the source disappears, and the original file is unchanged. Test a corrupt `.sqlite` file and a provider URL that becomes unavailable. Check an iPad share sheet if available. Run affected unit and UI tests plus Debug and Release builds for `generic/platform=iOS Simulator`; record any file-provider checks that require a device.

## Review

Check the built document registration, cold and warm URL delivery, event deduplication, security-scope lifetime, navigation after import, source immutability, and failure cleanup. Run `git diff --check` and inspect `git status`.

## Commit

Complete the final checks in [Plan 08](08-product-improvements.md). Stage only this plan's changes and commit as `Import SQLite files shared from Files`. In the body state which share-sheet flows were observed and list the tests run.

## Done when

Selecting SQLite Viewer from a SQLite file's Files share sheet starts the existing protected-copy import, and success or failure is visible in the app without a second file selection.
