# Plan 03a: Schema object catalog

## Goal

Return a complete, typed catalog of tables, views, indexes, and triggers in the open imported database. This plan adds no UI.

## Planning

Read [the architecture](00-architecture.md), the current `DatabaseSession` and `DatabaseLibrary` APIs, recent commits, and `git status`. Confirm how `SQLiteResult.columns` and typed `SQLiteValue` rows are exposed. Use the existing `SQLIdentifier.quote` helper for identifiers.

## Implementation

1. Add `SchemaObject` with object type, name, `tbl_name` association, optional root page, optional SQL text, and an internal-object flag. Use a stable identity that includes object type and name. Preserve `NULL` SQL for SQLite-created indexes. Do not turn root page `0` into a valid B-tree page.
2. Add `SchemaService` backed by the existing `DatabaseSession` actor. Read `type`, `name`, `tbl_name`, `rootpage`, and `sql` from `main.sqlite_schema`. Filter to the four supported types, sort deterministically, and decode by result-column name rather than fixed position. Keep all SQLite calls inside `DatabaseSession`.
3. Fetch the catalog in pages or add a session API suited to complete metadata reads. The current `execute` default retains only 100 rows, so the service must detect truncation and never present a partial catalog as complete. Bind paging values if using `LIMIT` and `OFFSET`.
4. Mark names beginning with SQLite's reserved `sqlite_` prefix, without case sensitivity, as internal. Keep such objects in the catalog, including autoindexes. `sqlite_schema` itself has no catalog row and must not appear as a user table. Keep a table or view association for indexes and triggers through `tbl_name`.
5. Expose `loadCatalog()` as an async, throwing operation. Return an empty array when `main.sqlite_schema` has no rows; propagate SQLite and decoding failures with enough context for a later UI error.

## Testing

Run focused unit tests on an available iPhone simulator. Create tables, a view, a trigger, an explicit index, and a UNIQUE constraint that creates an autoindex. Check type, association, root page, SQL presence or absence, internal flag, and deterministic order. Include a name containing `"`, an empty database, and more than 100 objects so default result truncation cannot hide objects.

## Review

Check that no connection or statement pointer leaves `DatabaseSession`, catalog errors are not converted to empty results, and all rows are returned. Run `git diff --check` and inspect `git status`.

## Commit

Stage only this plan's changes. Commit as `Add schema object catalog` with a body naming the metadata source and tests run.

## Done when

Tests can request the full catalog and distinguish all four object types, their associations, and SQLite-created objects.
