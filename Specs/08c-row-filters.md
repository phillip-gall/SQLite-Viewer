# Plan 08c: Filter table rows

## Goal

Let users add several column conditions in Rows, such as `customer_id = 10` and `income > 1000`, and browse only matching rows.

## Planning

Read [the architecture](00-architecture.md), [Plan 04](04-row-grid.md), [Plan 08b](08b-table-row-counts.md), `RowsService`, `RowsWorkspaceModel`, `RowsWorkspaceView`, and `SQLiteValue`. Check `git status` and recent commits. Confirm how page, sort, count, and selected object state survive tab changes.

## Implementation

1. Define typed filter conditions with a column, operator, and SQLite value. Support equals, not equals, greater than, greater than or equal, less than, less than or equal, contains, is NULL, and is not NULL. Equality and comparison use SQLite's native type rules. `contains` accepts text and uses a bound, escaped LIKE pattern with an explicit `ESCAPE` clause; document its case behavior in the UI. NULL operators take no value. Reject invalid numbers instead of silently treating them as text.
2. Build one predicate compiler shared by the row-page query and Plan 08b's matching-count query. Verify the column exists in the selected object's schema, quote its identifier, allowlist the operator, and bind every value. Combine conditions with AND in the order shown. Keep the existing stable ordering and 100-row limit after the WHERE clause. Never interpolate a user-entered value into SQL.
3. Add a Rows filter editor with Add, edit, remove, and Clear all actions. Choose a column, operator, and value type supported by that column's current schema. Display active conditions as readable chips or rows above the grid, including their typed values. Show a validation message before applying an incomplete condition. Make controls usable on narrow iPhone layouts and by VoiceOver.
4. Keep filter state per table or view with its sort and page state. Applying, editing, removing, or clearing a condition resets that object's page to one and reloads rows and matching count. Switching objects restores valid conditions for that object. After schema changes, drop conditions whose columns disappeared and tell the user which were removed. SQL writes refresh the active filtered page and both counts.
5. Show `Matching N of M rows` when filters are active, where M is the unfiltered table total from Plan 08b and N uses the same predicates as the page query. When no filters are active, show the total once. For a view, show a matching count if supported, without claiming a table total. Keep an empty result distinct from a query error and preserve filters when the result is empty.

## Testing

Test one and several AND conditions, numeric comparison, text equality, LIKE wildcard escaping, NULL and non-NULL, quoted column names, BLOB exclusion or a documented supported encoding, invalid values, zero matches, and paging/sorting within filtered results. Verify page reset, per-object restoration, removed-column recovery, matching counts, and refresh after INSERT, UPDATE, and DELETE. Add a UI test for the `customer_id = 10` plus `income > 1000` flow. Run affected unit and UI tests on an available simulator.

## Review

Inspect SQL injection boundaries, SQLite type semantics, predicate parity between count and page queries, paging stability, state retention, cancellation, and error placement. Run `git diff --check` and inspect `git status`.

## Commit

Stage only this plan's changes and commit as `Filter table rows`. In the body state supported operators, predicate binding, and tests run.

## Done when

Several conditions narrow the grid together, page and matching count agree, and filters remain usable after tab changes and SQL writes.
