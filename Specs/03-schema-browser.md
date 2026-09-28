# Plan 03: Schema browser

Run these plans in order after [02 import and library](02-import-library.md) and before [04 row grid](04-row-grid.md). Each plan has its own test, review, and commit. The last plan replaces the current workspace placeholder.

1. [03a Schema object catalog](03a-schema-catalog.md) reads every object in `main.sqlite_schema` and defines the shared schema models.
2. [03b Table and view details](03b-table-view-details.md) reads columns and table properties.
3. [03c Index details](03c-index-details.md) reads index properties and key entries.
4. [03d Schema workspace](03d-schema-workspace.md) adds navigation, detail screens, errors, and refresh.

The plans use the bundled SQLite connection owned by `DatabaseSession`. They cover the imported database's `main` schema. Temp and attached databases are outside this feature.
