# Plan 03b: Table and view details

## Goal

Return complete column metadata for a selected table or view, plus table properties reported by SQLite. This plan adds no UI.

## Planning

Read [the architecture](00-architecture.md), [03a](03a-schema-catalog.md), current code, recent commits, and `git status`. Inspect the catalog model and session API before adding detail types. Use `main` only.

## Implementation

1. Add a detail model for a table or view and a column model with `cid`, name, declared type, `notnull`, default SQL expression, primary-key position, and `hidden` code. Represent normal, virtual-table hidden, VIRTUAL generated, and STORED generated columns separately. Preserve empty declared types and `NULL` defaults without guessing an affinity or expression.
2. Read `PRAGMA main.table_xinfo(<quoted object name>)` through `DatabaseSession`. Map PRAGMA fields by returned column name. Include hidden and generated rows in the returned order; `table_info` is insufficient. The current session API retains only 100 rows by default, so request all PRAGMA rows and reject truncation. Verify the selected object still exists and is a table or view before reading details, so a missing object does not look like a zero-column table.
3. Use `PRAGMA main.table_list(<quoted object name>)` to identify ordinary, virtual, and shadow tables and to read `wr` and `strict`. Match by exact name in the `main` schema. Do not parse `CREATE` SQL to infer `WITHOUT ROWID` or STRICT. Carry the `sqlite_schema.sql` text from 03a as stored, including its possible absence.
4. Keep views distinct from tables. A view can expose columns and SQL but has no `WITHOUT ROWID`, STRICT, or virtual-table status. Return a clear unsupported-object error if called for an index or trigger.

## Testing

Run focused unit tests on an available simulator. Cover ordinary and composite primary keys, `WITHOUT ROWID`, STRICT, a view, generated VIRTUAL and STORED columns, quoted names, and a virtual table with a hidden column if the bundled SQLite build supports the fixture. Compare the decoded `hidden`, `pk`, `wr`, and `strict` values to direct PRAGMA results. Check missing and wrong-type object errors.

## Review

Check identifier quoting, PRAGMA column-name mapping, `NULL` handling, and that shadow tables are not mislabeled as ordinary user tables. Run `git diff --check` and inspect `git status`.

## Commit

Stage only this plan's changes. Commit as `Add table and view schema details` with a body listing the PRAGMAs and tests run.

## Done when

Callers can inspect every column of a table or view, including hidden and generated columns, and can identify `WITHOUT ROWID`, STRICT, and virtual tables.
