# Plan 07: Integration and release checks

## Goal

Make the library, schema browser, grid, SQL console, and storage analysis work as one reliable app on iPhone and iPad.

## Planning

Read the architecture and inspect the whole current app, test suite, project settings, and Git history. Check the working tree. Use code and tests as the source of truth. List actual integration defects before changing behavior; avoid duplicating tests already covered by earlier plans.

## Implementation

1. Run the complete flow: import, open, inspect schema and indexes, browse later row pages, execute SELECT and a write, inspect refreshed rows and storage, close, reopen, and delete. Fix broken navigation, state refresh, connection cleanup, and error handling found in that flow.
2. Check iPhone portrait and landscape and iPad split navigation. Make table and SQL result grids usable with long names, many columns, Dynamic Type, VoiceOver labels, and hardware keyboard input. Use concise copy that states when the user is editing an imported copy.
3. Verify backgrounding and device-lock behavior with complete file protection. Close or pause work cleanly when protected files become unavailable and restore the workspace after unlock without exposing stale data as current. Verify disk-full, invalid import, failed query, and missing-file recovery paths.
4. Remove starter placeholder tests and unused code. Keep vendor attribution and the architecture spec accurate if implementation choices changed. Put any required build or simulator setup in the repository README. Do not add a separate result file for information visible in code, tests, or Git history.

## Testing

Run `xcodebuild test -project 'SQLite Viewer.xcodeproj' -scheme 'SQLite Viewer' -destination 'platform=iOS Simulator,id=<selected-id>'` on an available iPhone simulator, then build Debug and Release for `generic/platform=iOS Simulator`. Run the end-to-end UI flow on an iPad simulator when available. Use a physical device for file-provider import and lock-state checks if available; if not, record only those unverified device checks in the final commit body. Confirm the app target does not bundle spec Markdown or temporary database fixtures unintentionally.

## Review

Review the full branch diff for data-loss risks, source-file writes, SQL pointer lifetimes, UI hangs on large data, privacy leaks, file protection, and storage totals. Run `git diff --check`, inspect `git status`, and resolve actionable findings. Ensure every plan's acceptance condition still holds.

## Commit

Stage only integration fixes and documentation changes. Commit as `Finish SQLite Viewer integration` with a body that lists the full test matrix, any device-only checks still unverified, and why the integration fixes were needed. Keep the work on the current branch unless the repository workflow calls for another branch; do not force-push or discard user commits.

## Done when

The complete workflow passes on a simulator, the app builds in Debug and Release, and any remaining device-only checks are plainly identified.
