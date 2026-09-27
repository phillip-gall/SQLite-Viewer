# Plan 05: Raw SQL console

## Goal

Let users run raw SQLite commands against the open imported copy and inspect results or errors.

## Planning

Read the architecture and current code, then check the working tree and recent commits. Reuse the session actor, value model, and row grid. Inspect their real APIs before changing them. Decide how the editor submits text without altering what the user typed.

## Implementation

1. Add an SQL destination with a multiline monospaced editor, Run action, execution status, and results below the editor. Keep the draft text when switching destinations within the same database. Label the target database so writes are visibly directed at its imported copy.
2. Support one or more SQL statements in a submission. Iterate with `sqlite3_prepare_v3` and the tail pointer, not string splitting, so semicolons in strings and comments work. Execute statements in order with SQLite's normal transaction semantics. Stop on the first error and report the statement number, SQLite code, message, and text location if available. Do not insert an implicit transaction around the script.
3. Return a result block per statement. For row-producing statements show column names and typed values in the shared grid. Retain at most 200 rows per block, then continue stepping to completion without retaining later rows. Label the displayed rows as truncated and tell the user to rerun with `LIMIT` for a narrower result. Finishing each statement matters for `RETURNING` and for scripts with later statements. For commands without rows show affected row count and elapsed time.
4. Handle an empty editor, parameter placeholders without supplied values, busy databases, and long-running queries with clear errors. Provide a Cancel control that sets a thread-safe flag read by `sqlite3_progress_handler`; its callback returns nonzero to stop the active statement. Do not queue cancellation solely through the busy actor. Release all statements and return the session to a usable state afterward. Keep the callback context alive until the session closes.
5. After any successful statement, refresh schema and visible row/storage state. This covers DDL, data changes, and PRAGMAs without trying to guess which statements mutate. Keep user SQL unrestricted within SQLite's compiled capabilities; extension loading is disabled at build time.

## Testing

Run unit and UI tests on an available simulator. Cover SELECT, INSERT/UPDATE/DELETE with reopen persistence, CREATE/DROP table and index with browser refresh, multiple statements, quoted semicolons, a deliberate syntax error after a successful statement, explicit BEGIN/COMMIT and ROLLBACK, a result over 200 rows, and query cancellation followed by a successful query. Confirm the original source file remains unchanged after writes to the import. Test a BLOB and NULL in result output.

## Review

Inspect statement-tail advancement, pointer lifetimes, finalization on every failure path, output limits, cancel races, error visibility, and consistency after DDL. Run `git diff --check` and inspect `git status`.

## Commit

Stage only this plan's changes. Commit as `Add raw SQL console` with a body explaining script semantics, result limits, cancellation, and tests run.

## Done when

Users can run read and write SQL on the imported copy, see every statement's outcome, and continue using the workspace after errors or cancellation.
