/* Build-time check of the queries a program makes with Env.db_row.
   Usage: querycheck schema.sql < queries   (each line: "<kinds> <sql>", kinds being the struct fields' kinds, comma
   separated: 1 long, 2 int, 3 bool, 4 Bytes). Each query is prepared against a database made from the schema, so an
   unknown table or column is an error; the number of columns and each column's declared type must agree with the
   struct (integers for long/int/bool, text for Bytes); a plan that scans a whole table is reported as a warning. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "sqlite3.h"

static char *read_file(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) return NULL;
    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    fseek(file, 0, SEEK_SET);
    char *text = (char *)malloc((size_t)size + 1);
    if (!text || fread(text, 1, (size_t)size, file) != (size_t)size) { fclose(file); return NULL; }
    text[size] = 0;
    fclose(file);
    return text;
}

int main(int argc, char **argv) {
    if (argc != 2) { fprintf(stderr, "usage: querycheck schema.sql < queries\n"); return 2; }
    char *schema = read_file(argv[1]);
    if (!schema) { fprintf(stderr, "nlc: cannot read %s\n", argv[1]); return 2; }
    sqlite3 *db = NULL;
    sqlite3_open(":memory:", &db);
    char *message = NULL;
    if (sqlite3_exec(db, schema, NULL, NULL, &message) != SQLITE_OK) {
        fprintf(stderr, "nlc: %s: %s\n", argv[1], message ? message : "schema error");
        return 1;
    }
    char line[16384];
    int failures = 0;
    while (fgets(line, sizeof(line), stdin)) {
        size_t length = strlen(line);
        while (length && (line[length - 1] == '\n' || line[length - 1] == '\r')) line[--length] = 0;
        char *space = strchr(line, ' ');
        if (!space) continue;
        *space = 0;
        const char *kinds = line, *sql = space + 1;
        sqlite3_stmt *statement = NULL;
        if (sqlite3_prepare_v2(db, sql, -1, &statement, NULL) != SQLITE_OK) {
            fprintf(stderr, "nlc: query error: %s\n  %s\n", sqlite3_errmsg(db), sql);
            failures++;
            continue;
        }
        if (kinds[0] == 'x') {   /* an Env.db_exec statement: prepared, nothing more to check */
            sqlite3_finalize(statement);
            continue;
        }
        int columns = sqlite3_column_count(statement), index = 0;
        for (const char *at = kinds; *at; ) {
            int kind = atoi(at);
            if (index >= columns) { index++; }
            else {
                const char *declared = sqlite3_column_decltype(statement, index);
                if (declared) {
                    int integer = strcasestr(declared, "INT") != NULL || strcasestr(declared, "BOOL") != NULL;
                    /* SQLite stores dates and times as text (Rails' datetime columns are); a Bytes field takes them */
                    int text = strcasestr(declared, "CHAR") || strcasestr(declared, "TEXT") || strcasestr(declared, "CLOB") || strcasestr(declared, "BLOB") ||
                               strcasestr(declared, "DATE") || strcasestr(declared, "TIME");
                    if ((kind <= 3 && !integer) || (kind == 4 && !text)) {
                        fprintf(stderr, "nlc: query error: column %s is declared %s but the struct field wants %s\n  %s\n",
                                sqlite3_column_name(statement, index), declared, kind == 4 ? "text" : "an integer", sql);
                        failures++;
                    }
                }
                index++;
            }
            const char *comma = strchr(at, ',');
            if (!comma) break;
            at = comma + 1;
        }
        if (index != columns) {
            fprintf(stderr, "nlc: query error: the struct has %d fields but the query returns %d columns\n  %s\n", index, columns, sql);
            failures++;
        }
        sqlite3_finalize(statement);
        char plan_sql[16500];
        snprintf(plan_sql, sizeof(plan_sql), "EXPLAIN QUERY PLAN %s", sql);
        if (sqlite3_prepare_v2(db, plan_sql, -1, &statement, NULL) == SQLITE_OK) {
            sqlite3_bind_int64(statement, 1, 1);
            while (sqlite3_step(statement) == SQLITE_ROW) {
                const char *detail = (const char *)sqlite3_column_text(statement, 3);
                /* a scan of a subquery's result (SCAN (subquery-1)) is not a table scan */
                if (detail && strncmp(detail, "SCAN ", 5) == 0 && !strstr(detail, "INDEX") && strncmp(detail, "SCAN (subquery", 14) != 0) {
                    fprintf(stderr, "nlc: warning: this query reads a whole table (%s); add an index?\n  %s\n", detail, sql);
                }
            }
            sqlite3_finalize(statement);
        }
    }
    sqlite3_close(db);
    return failures ? 1 : 0;
}
