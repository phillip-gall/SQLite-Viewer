# Plan 03c: Index details

## Goal

Return the indexes belonging to a table and explain each index's keys and SQLite-reported properties. This plan adds no UI.

## Planning

Read [the architecture](00-architecture.md), [03a](03a-schema-catalog.md), [03b](03b-table-view-details.md), current code, recent commits, and `git status`. Inspect the models and `DatabaseSession.execute` result shape before adding index queries.

## Implementation

1. Add an index model with name, owning table, unique flag, origin (`CREATE INDEX`, UNIQUE constraint, or PRIMARY KEY), partial flag, optional creation SQL, and ordered entries. An entry keeps `seqno`, `cid`, optional column name, descending flag, collation, and key-versus-auxiliary status. Represent expression entries (`cid = -2`) and rowid entries (`cid = -1`) explicitly.
2. For a selected ordinary or `WITHOUT ROWID` table, read `PRAGMA main.index_list(<quoted table name>)`. For each result, read `PRAGMA main.index_xinfo(<quoted index name>)`. Map fields by column name. Request all PRAGMA rows and reject truncation; the current session API retains only 100 by default. Keep only `key = 1` entries in the displayed key list, but preserve auxiliary entries in the model so no PRAGMA information is lost.
3. Match each index to its catalog row for creation SQL and root page. Autoindexes can have `NULL` SQL; a `WITHOUT ROWID` PRIMARY KEY may have no catalog index row. Show the origin and available PRAGMA metadata without inventing SQL or a root page. For expression entries, show an expression marker and the index creation SQL. Do not attempt to parse an expression out of SQL text.
4. Keep index names attached to the owning table, including SQLite-created indexes. Return an empty list for a table without indexes. Reject a view or missing table with a clear error.

## Testing

Run focused unit tests on an available simulator. Cover a normal index, UNIQUE and PRIMARY KEY autoindexes, a partial index, an expression index, DESC and COLLATE clauses, and a `WITHOUT ROWID` table. Compare uniqueness, origin, partial status, key flags, `cid`, collation, and sort direction with direct PRAGMA output. Check quoted table and index names, `NULL` SQL, and a table with no indexes.

## Review

Check that expression and rowid entries are not presented as named columns, auxiliary entries are not counted as keys, and absent catalog rows remain absent. Run `git diff --check` and inspect `git status`.

## Commit

Stage only this plan's changes. Commit as `Add index schema details` with a body naming the PRAGMAs and tests run.

## Done when

Callers can list every SQLite-reported index on a table and inspect its ordered keys, origin, uniqueness, partial status, and available SQL.
