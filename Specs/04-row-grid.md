# Plan 04: Paged row grid

## Goal

Show table rows in a spreadsheet-style grid without loading the whole table.

## Planning

Read the architecture and current code, then check the working tree and recent commits. Inspect the schema model and SQLite value type before designing the grid API. Keep the grid reusable for SQL results in Plan 05.

## Implementation

1. Add a row-page service that returns column descriptors, typed values, page number, and whether another page exists. Fetch 100 rows at a time and at most 101 to detect the next page. Do not run `COUNT(*)` merely to open a table. All generated SQL must quote identifiers and bind `LIMIT` and `OFFSET` values.
2. Use a stable default order for ordinary tables through an unshadowed `rowid` alias or the integer primary-key column. A user column can shadow `rowid`, `_rowid_`, or `oid`, so inspect column names first. For `WITHOUT ROWID` tables, order by primary-key columns in key order. Some virtual tables and views have no stable key; show that paging order can change for those objects and allow browsing without claiming stable order. Make a column sort explicit and reset to page one when it changes. If duplicate sort values could make pages unstable, add the primary key or usable rowid alias as a tiebreaker when available.
3. Build a reusable grid with sticky column headers, horizontal column scrolling, vertical row scrolling, readable type-specific cells, and a visible loading state. Show NULL as `NULL`; render BLOBs as byte count plus a short hex preview with a detail view for full value. Keep values selectable where practical. A page control or incremental loading must let users reach rows beyond the first page.
4. Selecting a table from Schema opens its Rows view. Keep scroll and page state local to the selected object. On a SQL write or schema refresh, invalidate visible pages and reload them. Show SQL errors and empty tables inside the grid area.

## Testing

Run unit and UI tests on an available iPhone simulator. Cover more than two pages, zero rows, wide tables, NULL, BLOB, Unicode, quoted names, large `Int64`, `WITHOUT ROWID`, and sorting with duplicate values. Add a UI test that reaches a row past the first page and scrolls to an offscreen column. Check an iPad simulator layout or use an iPad preview if a simulator is unavailable. Keep memory bounded when opening a generated table with tens of thousands of rows.

## Review

Inspect pagination boundaries, stable ordering, identifier quoting, cancellation when switching tables, cell truncation, accessibility labels, and whether the view accidentally retains every visited page. Run `git diff --check` and inspect `git status`.

## Commit

Stage only this plan's changes. Commit as `Add paged table grid` with a body explaining the order and paging rules and listing the tests run.

## Done when

Users can browse wide and large tables through a grid, reach later rows, and distinguish every SQLite value type.
