#include "LCArchive.h"
#ifdef __APPLE__
#include "../../Utilities/archive.h"
#include "../../Utilities/archive_entry.h"
#else
#include <archive.h>
#include <archive_entry.h>
#endif
#include <stdlib.h>
struct LCArchive { struct archive *archive; const char *error; };
LCArchive *lc_archive_open(const void *bytes, size_t count) {
    LCArchive *r = calloc(1, sizeof(*r));
    if (!r) return NULL;
    r->archive = archive_read_new();
    if (!r->archive) { free(r); return NULL; }
    /* No external decompressor programs and no automatic nested extraction. */
    archive_read_support_format_tar(r->archive);
    archive_read_support_filter_none(r->archive);
    const unsigned char *magic = bytes;
    int support = ARCHIVE_OK;
    if (count >= 2 && magic[0] == 0x1f && magic[1] == 0x8b)
        support = archive_read_support_filter_gzip(r->archive);
    else if (count >= 6 && magic[0] == 0xfd && magic[1] == '7' && magic[2] == 'z')
        support = archive_read_support_filter_xz(r->archive);
    else if (count >= 4 && magic[0] == 0x28 && magic[1] == 0xb5 && magic[2] == 0x2f && magic[3] == 0xfd)
        support = archive_read_support_filter_zstd(r->archive);
    if (support != ARCHIVE_OK) {
        r->error = "Unsupported compression in this system libarchive; external decompressors are disabled";
        return r;
    }
    if (archive_read_open_memory(r->archive, bytes, count) != ARCHIVE_OK)
        r->error = "Unable to decode tar archive with available compression filters";
    return r;
}
int lc_archive_next(LCArchive *r, const char **path, int64_t *size, int *directory) {
    if (r->error) return -1;
    struct archive_entry *e = NULL;
    int status = archive_read_next_header(r->archive, &e);
    if (status == ARCHIVE_EOF) return 0;
    if (status != ARCHIVE_OK) return -1;
    int type = archive_entry_filetype(e);
    if (archive_entry_symlink(e) || archive_entry_hardlink(e) ||
        (type != AE_IFREG && type != AE_IFDIR) || archive_entry_sparse_count(e) > 0) {
        r->error = "Links, special files and sparse entries are unsupported";
        return -1;
    }
    *path = archive_entry_pathname(e);
    *size = archive_entry_size(e);
    *directory = type == AE_IFDIR;
    return 1;
}
int64_t lc_archive_read(LCArchive *r, void *buffer, size_t count) {
    return archive_read_data(r->archive, buffer, count);
}
const char *lc_archive_error(LCArchive *r) {
    const char *message = r->error ? r->error : archive_error_string(r->archive);
    return message ? message : "Malformed archive";
}
void lc_archive_close(LCArchive *r) {
    if (r) { archive_read_free(r->archive); free(r); }
}
