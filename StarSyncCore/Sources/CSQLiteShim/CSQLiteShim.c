#include "CSQLiteShim.h"

int starsync_sqlite3_db_config_int(sqlite3 *db, int op, int value, int *result) {
    return sqlite3_db_config(db, op, value, result);
}
