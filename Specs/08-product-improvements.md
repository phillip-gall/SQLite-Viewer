# Plan 08: Library, rows, storage, and import

## Goal

Make imported databases easier to open and rename, show table row counts in Schema and Rows, filter rows by several conditions, let users inspect each storage category by owner, restrict the file picker to SQLite types, and start imports from shared files.

## Execution order

Run these plans in order against the current repository:

1. [08a Rename and open library entries](08a-library-interactions.md)
2. [08b Show table row counts](08b-table-row-counts.md)
3. [08c Filter table rows](08c-row-filters.md)
4. [08d Inspect storage categories](08d-storage-drilldown.md)
5. [08e Select SQLite files in the picker](08e-sqlite-file-picker.md)
6. [08f Import files sent from other apps](08f-shared-file-import.md)

Plan 08c uses the count service from 08b so its matching count and row page apply the same filters. Plan 08d can use the existing storage report. Plan 08f uses the SQLite document types from 08e and the existing protected-copy import service. Keep each subplan's code, tests, review, and commit together. Inspect current code and Git state before starting each one; these plans describe behavior, not a frozen API.

## Final integration check

After 08f, run the full unit and UI suites on an available iPhone simulator and build Debug and Release for `generic/platform=iOS Simulator`. Check the library and workspace on an iPad simulator or preview. Walk through picker import, rename, whole-row Open, Schema count, Rows count, two filters and paging, SQL INSERT and DELETE, refreshed counts and filtered rows, storage category selection and refresh, then importing a SQLite file from Files while the app is closed and while it is open. Check the picker excludes unrelated files, long database and table names, VoiceOver labels, small chart segments, empty tables, and zero-byte storage categories. Inspect `git diff --check` and `git status`. Record any simulator or device checks that could not run in the final subplan's commit body.

## Done when

The seven requested behaviors work together after a database changes, and each subplan's acceptance condition holds.
