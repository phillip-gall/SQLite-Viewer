# SQLite amalgamation

- Version: 3.53.4
- Source: https://www.sqlite.org/2026/sqlite-amalgamation-3530400.zip
- Archive SHA3-256: `628a44cfe82c66aed1ccbbe85a562d2e33ebe64b3288981ed76285612227934e`
- Files vendored from the archive: `sqlite3.c`, `sqlite3.h`
- C compile definitions: `SQLITE_ENABLE_DBSTAT_VTAB`, `SQLITE_OMIT_LOAD_EXTENSION`

The app compiles this source directly. It does not link the system SQLite library.
The `dbstat` option is needed for the storage analysis screen. Extension loading is
omitted because imported databases and user SQL do not need native code loading.
