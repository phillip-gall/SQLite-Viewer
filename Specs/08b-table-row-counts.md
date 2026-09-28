# Plan 08b: Show table row counts

## Goal

Show each table's exact row count in the Schema tab and the selected table's total row count in the Rows tab.

## Planning

Read [the architecture](00-architecture.md), [Plan 03d](03d-schema-workspace.md), [Plan 04](04-row-grid.md), `SchemaService`, `RowsService`, and the workspace models and views. Check `git status` and recent commits. Inspect session cancellation and the SQL write refresh path before choosing where count requests live.

## Implementation

1. Add a shared count operation for `main` tables that runs `SELECT COUNT(*)` with the existing identifier quoting helper. Return `Int64`; do not infer a count from a page's size or page number. Keep views outside this table count and label them as views. Show a concrete error or unavailable state for a table that SQLite cannot count.
2. Request counts asynchronously after the schema catalog and selected Rows page can render. Count visible table entries progressively rather than blocking catalog display or launching unbounded simultaneous scans. Cache successful counts by database ID and table identity for the current workspace. Cancel obsolete requests on selection or database change. A count failure must not hide the schema or grid.
3. Show a count or `Counting…` state on Schema table entries and in a selected table's detail. Show the same total beside the selected table in Rows, including for an empty table. Use `rows` as the unit and accessibility text that includes the table name and exact count. Do not show an estimated count as exact.
4. Invalidate cached counts after every successful SQL submission and on explicit Schema or Rows refresh. Drop entries for removed or renamed tables. Reload visible counts without clearing the current row page; keep a count error local to its table. Design the service so Plan 08c can request an exact matching count using its filter predicates.

## Testing

Test empty and populated tables, a quoted table name, a large count beyond `Int32`, count failure, and refresh after INSERT, DELETE, and DROP TABLE. Verify Schema and Rows show the same total, counts do not stall first-page display, and a stale count cannot replace a newer one after rapid table switching. Run affected unit and UI tests on an available simulator.

## Review

Inspect generated SQL, cancellation, cache invalidation, actor contention on large tables, count conversion, and accessibility labels. Run `git diff --check` and inspect `git status`.

## Commit

Stage only this plan's changes and commit as `Show table row counts`. In the body state when counts load and how they refresh, plus tests run.

## Done when

Schema and Rows show the same exact count for a selected table, and the value refreshes after data changes without blocking row browsing.
