#ifndef LC_ARCHIVE_H
#define LC_ARCHIVE_H
#include <stddef.h>
#include <stdint.h>
typedef struct LCArchive LCArchive;
LCArchive *lc_archive_open(const void *bytes, size_t count);
/* 1 = entry, 0 = EOF, -1 = error. Input memory must outlive the reader. */
int lc_archive_next(LCArchive *reader, const char **path, int64_t *size, int *directory);
int64_t lc_archive_read(LCArchive *reader, void *buffer, size_t count);
const char *lc_archive_error(LCArchive *reader);
void lc_archive_close(LCArchive *reader);
#endif
