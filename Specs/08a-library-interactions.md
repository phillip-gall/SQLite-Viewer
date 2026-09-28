# Plan 08a: Rename and open library entries

## Goal

Let users rename an imported database's displayed name and open it by tapping anywhere on its library row, including the row background.

## Planning

Read [the architecture](00-architecture.md), [Plan 02](02-import-library.md), `DatabaseLibrary`, `LibraryViewModel`, and `ContentView`. Check `git status` and recent commits. Confirm how the active workspace receives its title and how damaged entries appear.

## Implementation

1. Add `DatabaseLibrary.rename(id:to:)`. Trim surrounding whitespace, reject an empty name, and cap the displayed name at 100 characters. Keep duplicate display names legal because UUIDs identify entries. Read the existing manifest, change only `displayName`, and write the replacement atomically with complete file protection. Preserve `originalFilename`, `importedAt`, the UUID directory, and `database.sqlite`. A missing or damaged manifest must produce a recoverable error and leave files unchanged.
2. Expose rename state and errors through `LibraryViewModel`. Update the list entry and `opened` value after success so an open workspace title changes without reconnecting. On failure, keep the previous name visible. Reload library data when returning from the workspace if needed to avoid a stale value.
3. Add a Rename action and an editor prefilled with the current display name. Show the validation error beside the editor, keep the editor open on save failure, and provide Cancel. Move secondary actions such as Rename and Delete to row swipe or context actions, with accessible equivalents. Keep deletion confirmation.
4. Make the library entry one full-width Open target with a rectangular hit shape covering its visible background, padding, and metadata. Ensure no nested control intercepts its main tap area. Keep the Open action disabled while an open is in progress, and expose a clear accessibility label that includes the displayed name.

## Testing

Add focused library tests for a rename surviving library reconstruction, preserved original filename and database bytes, duplicate names, blank and overlong input, missing manifest, and rename while the database is open. Add a UI test that taps the row's trailing blank/background area to open it, returns, renames it, reopens it, and sees the new title. Check Delete remains reachable through touch and accessibility. Run the affected unit and UI tests on an available simulator.

## Review

Check manifest replacement and protection, error recovery, active navigation state, row hit testing, VoiceOver actions, and whether a rename ever touches the source or SQLite copy. Run `git diff --check` and inspect `git status`.

## Commit

Stage only this plan's changes and commit as `Rename database library entries`. In the body state the manifest update rule and tests run.

## Done when

A renamed entry keeps its name after relaunch, an open workspace shows the new name, and a tap on the library row background opens the imported copy.
