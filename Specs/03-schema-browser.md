# Plan 03: Schema browser

## Goal

Show database objects, table definitions, columns, and indexes for the open imported copy.

## Planning

Read the architecture, current code, and previous commits. Check the working tree. Choose navigation that works on iPhone and iPad using the app's existing SwiftUI structure. Inspect the actual `DatabaseSession` API before adding services.

## Implementation

1. Add a schema model that distinguishes table, view, index, and trigger. Read object names, type, root page, and original `CREATE` SQL from `sqlite_schema`, including objects with no SQL text. Exclude `sqlite_schema` itself from ordinary user tables but make internal objects distinguishable when shown.
2. For a selected table or view, load `PRAGMA table_xinfo` so generated and hidden columns appear. For each table, load `PRAGMA index_list` and `PRAGMA index_xinfo`; show uniqueness, origin, partial-index status, key columns, expressions, and sort direction where SQLite reports them. Show the index creation SQL when available. Display `WITHOUT ROWID`, STRICT, and virtual table status where the source schema supports it.
3. Add a database workspace and Schema destination. Group objects by type, provide a usable empty state, and show a detail screen with the original SQL in monospaced selectable text. Never use a database object's name in generated SQL without the shared quoting helper.
4. Refresh schema after opening a database and expose a refresh method for the SQL console to call after changes. Keep SQLite work off the main actor.

## Testing

Run unit tests on the selected simulator. Add fixture coverage for quoted names, generated columns, partial and expression indexes, a view, a trigger, and a `WITHOUT ROWID` table. Confirm index metadata matches SQLite's PRAGMA output and an empty database displays an empty state. Add one UI test that opens an import and navigates to a table's schema. Build for an iPad simulator or generic iOS Simulator as an additional layout check.

## Review

Check that internal and user objects are labeled correctly, metadata queries do not assume fixed PRAGMA column ordering, errors are visible, and schema refresh invalidates stale detail screens. Run `git diff --check` and inspect `git status`.

## Commit

Stage only this plan's changes. Commit as `Add schema browser` with a body describing the metadata sources and the tests run.

## Done when

Users can open an imported database and inspect tables, views, columns, indexes, triggers, and their SQL definitions without missing generated or hidden columns.
