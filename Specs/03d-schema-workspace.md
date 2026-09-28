# Plan 03d: Schema workspace

## Goal

Replace the workspace placeholder with a Schema destination where users can browse objects, columns, indexes, triggers, and stored SQL on iPhone and iPad.

## Planning

Read [the architecture](00-architecture.md), [03a](03a-schema-catalog.md), [03b](03b-table-view-details.md), [03c](03c-index-details.md), current UI, recent commits, and `git status`. Confirm how `DatabaseLibrary` opens and closes its active session. Pick navigation using the app's actual SwiftUI structure.

## Implementation

1. Give the workspace a safe way to use the `DatabaseSession` already opened by `DatabaseLibrary` for its database ID. Do not open a second connection or expose a raw SQLite pointer. Close or discard workspace state when the library closes or switches databases.
2. Replace `WorkspaceStub` with a database workspace and Schema destination. Keep a clear place for the Rows, Storage, and SQL destinations added by later plans. Group catalog entries by table, view, index, and trigger. Label internal and shadow objects; show an empty state when the catalog is empty. Make long names readable and provide stable accessibility labels.
3. Selecting a table or view shows columns, object properties, its stored SQL, and related indexes and triggers. Selecting an index shows its owning table, flags, ordered key entries, and SQL when present. Selecting a trigger shows its associated table or view and SQL. Show a specific "No stored CREATE SQL" message when the catalog value is `NULL`. Render SQL in selectable monospaced text. Keep data and schema views separate so a view or trigger never offers table-row browsing by mistake.
4. Load schema metadata asynchronously through the service. Show loading and concrete errors with Retry. Cancel or ignore a prior selection's result when the user changes selection or database. Do not block the main actor on SQLite work.
5. Add a workspace `refreshSchema()` operation and a visible Refresh action. Reload the catalog and selected detail after refresh; clear the selection when its object was dropped. Make this operation callable from Plan 05 after SQL execution. A refresh failure must keep the error visible rather than showing stale details as current.

## Testing

Run unit and UI tests on an available iPhone simulator. Add a UI test that imports a fixture, opens the workspace, selects a table, and inspects columns, an index, and SQL text. Check empty, missing-object, and SQLite-error states. Test refresh after creating and dropping an object through the existing session API, including a selected object that disappears. Build for an iPad simulator or `generic/platform=iOS Simulator` and inspect the workspace layout at iPad width.

## Review

Check session ownership, database-ID changes, stale async results, complete object grouping, internal labels, visible errors, and whether spec Markdown entered the app bundle through Xcode's synchronized group. Run `git diff --check` and inspect `git status`.

## Commit

Stage only this plan's changes. Commit as `Add schema workspace` with a body explaining navigation, refresh behavior, and tests run.

## Done when

Users can open an imported database and inspect all supported schema objects and their details. Refresh updates the list and selected detail after schema changes without showing stale content as current.
