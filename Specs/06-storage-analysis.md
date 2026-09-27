# Plan 06: Storage analysis

## Goal

Show how logical database pages are distributed among table data, indexes, free pages, and other overhead.

## Planning

Read the architecture and current code, then check the working tree and recent commits. Confirm the bundled SQLite build exposes `dbstat` through the same connection as the rest of the app. Inspect current schema and refresh APIs before adding storage models.

## Implementation

1. Query `PRAGMA page_size`, `PRAGMA page_count`, and `PRAGMA freelist_count`. Query `dbstat` aggregated by B-tree `name` with `SUM(pgsize)`, page count, payload, and unused bytes. Use a normal page scan if aggregate mode would hide metrics needed by the UI. Keep the analysis on the session actor and show progress or loading for large files.
2. Map each table's own B-tree by table name and its indexes through `PRAGMA index_list`, including autoindexes. Show table bytes, index bytes, and inclusive bytes separately. `WITHOUT ROWID` storage must not double-count its primary-key B-tree. Treat views as having no storage. Keep unassigned SQLite internal B-trees visible in an Other category.
3. Compute logical database bytes as `page_count * page_size`, free bytes as `freelist_count * page_size`, and overhead as logical bytes minus counted B-tree bytes and free bytes. Do not force a percentage denominator from the physical file size when WAL is active. Display any `-wal` sidecar size separately, with a note that it is outside the logical page chart. If totals temporarily disagree because a concurrent write changes the snapshot, retry on one consistent session snapshot or show the numbers as temporarily unavailable.
4. Add Storage destination with a compact distribution chart and a sortable table of per-table values. Selecting a table shows its data/index split, percent of logical database bytes, page count, payload, and unused bytes. Make the chart accessible with text labels and values. Offer refresh and invalidate the analysis after SQL execution.
5. Handle empty databases, zero-byte percentages, virtual tables with storage in shadow tables, and B-trees that cannot be assigned to a user table without inventing ownership. Clearly label unassigned objects.

## Testing

Run unit and UI tests on an available simulator. Generate a fixture with a large table, multiple indexes, a `WITHOUT ROWID` table, a view, and deleted rows that create free pages. Assert that every B-tree is counted once and that table plus index plus free plus overhead totals equal logical database bytes. Check storage refresh after `CREATE INDEX`, `INSERT`, and `DROP TABLE`. Add a WAL-mode fixture and confirm the WAL file is reported outside the logical page total. Check chart and table labels in a UI test.

## Review

Inspect arithmetic for overflow and negative values, owner mapping for autoindexes and shadow tables, refresh behavior, large-file responsiveness, and visible explanations of logical versus WAL bytes. Run `git diff --check` and inspect `git status`.

## Commit

Stage only this plan's changes. Commit as `Add database storage analysis` with a body describing reconciliation rules and the tests run.

## Done when

Users can see per-table and per-index storage for the imported copy, and the displayed logical categories reconcile with SQLite's page total.
