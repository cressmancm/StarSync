#ifndef CSQLITESHIM_H
#define CSQLITESHIM_H

#include <sqlite3.h>

/// Calls sqlite3_db_config(db, op, value, result) for the SQLITE_DBCONFIG
/// options that take an int and an int* (DEFENSIVE, TRUSTED_SCHEMA and the
/// like). sqlite3_db_config is variadic, so Swift cannot call it; and on
/// arm64 Apple passes variadic arguments differently from fixed ones, so it
/// cannot be called through a re-typed function pointer either.
///
/// Pass -1 as `value` to read the setting without changing it.
int starsync_sqlite3_db_config_int(sqlite3 *db, int op, int value, int *result);

#endif
