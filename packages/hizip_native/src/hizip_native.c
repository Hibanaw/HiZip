#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "hizip_native.h"
#include "hizip_rar.h"
#include "vendor/archive.h"
#include "vendor/archive_entry.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>
#include <locale.h>
#include <errno.h>
#include <fcntl.h>
#ifdef __APPLE__
#include <sys/stdio.h>
#endif
#ifndef _WIN32
#include <unistd.h>
#endif
#ifdef _WIN32
#include <windows.h>
typedef struct _stat64 hz_stat_t;
#ifndef S_ISDIR
#define S_ISDIR(mode) (((mode) & _S_IFMT) == _S_IFDIR)
#endif
#ifndef S_ISREG
#define S_ISREG(mode) (((mode) & _S_IFMT) == _S_IFREG)
#endif
static wchar_t *wide(const char *s) {
  int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, NULL, 0);
  if (!n) return NULL;
  wchar_t *w = malloc(n * sizeof(wchar_t));
  if (w) MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, s, -1, w, n);
  return w;
}
static FILE *hz_fopen(const char *s, const char *mode) {
  wchar_t *w = wide(s), *m = wide(mode); FILE *f = w && m ? _wfopen(w, m) : NULL;
  free(w); free(m); return f;
}
static int hz_stat(const char *s, hz_stat_t *st) { wchar_t *w = wide(s); int r = w ? _wstat64(w, st) : -1; free(w); return r; }
static int hz_remove(const char *s) { wchar_t *w = wide(s); int r = w ? _wremove(w) : -1; free(w); return r; }
static int read_open(struct archive *a, const char *s) { wchar_t *w = wide(s); int r = w ? archive_read_open_filename_w(a, w, 65536) : ARCHIVE_FATAL; free(w); return r; }
static int write_open(struct archive *a, const char *s) { wchar_t *w = wide(s); int r = w ? archive_write_open_filename_w(a, w) : ARCHIVE_FATAL; free(w); return r; }
#else
typedef struct stat hz_stat_t;
#define hz_fopen fopen
#define hz_stat stat
#define hz_remove remove
static int read_open(struct archive *a, const char *s) { return archive_read_open_filename(a, s, 65536); }
static int write_open(struct archive *a, const char *s) { return archive_write_open_filename(a, s); }
#endif
#if defined(__APPLE__)
#include <pthread.h>
#include <pthread/qos.h>
#elif defined(__linux__) || defined(__ANDROID__)
#include <sys/resource.h>
#include <sys/syscall.h>
#include <unistd.h>
#endif

typedef struct { char *s; size_t n, cap; } buffer;
static void append(buffer *b, const char *fmt, ...) {
  va_list args; va_start(args, fmt); va_list copy; va_copy(copy, args);
  int n = vsnprintf(NULL, 0, fmt, copy); va_end(copy);
  if (n < 0) abort();
  if (b->n + (size_t)n + 1 > b->cap) {
    b->cap = (b->n + (size_t)n + 1) * 2;
    char *p = realloc(b->s, b->cap); if (!p) abort(); b->s = p;
  }
  vsnprintf(b->s + b->n, b->cap - b->n, fmt, args); va_end(args); b->n += n;
}
static void quote(buffer *b, const char *s) {
  append(b, "\"");
  for (const unsigned char *p = (const unsigned char *)(s ? s : ""); *p; p++) {
    if (*p == '"' || *p == '\\') append(b, "\\%c", *p);
    else if (*p < 32) append(b, "\\u%04x", *p);
    else append(b, "%c", *p);
  }
  append(b, "\"");
}
static char *error(const char *s) { buffer b = {0}; append(&b, "{\"error\":"); quote(&b, s); append(&b, "}"); return b.s; }
static char *ok(void) { buffer b = {0}; append(&b, "{\"ok\":true}"); return b.s; }
#ifdef _WIN32
#define HZ_THREAD_LOCAL __declspec(thread)
#else
#define HZ_THREAD_LOCAL _Thread_local
#endif
// Shared between the UI and workers. Lifetime belongs to the drained task scope.
#ifdef _WIN32
typedef struct { volatile LONG state; } hz_control;
static int control_state(hz_control *c) { return (int)InterlockedCompareExchange(&c->state, 0, 0); }
#else
#include <stdatomic.h>
#include <time.h>
typedef struct { _Atomic int state; } hz_control;
static int control_state(hz_control *c) { return atomic_load_explicit(&c->state, memory_order_acquire); }
#endif
static HZ_THREAD_LOCAL hz_control *active_control = NULL;
HZ_EXPORT void *hz_control_create(void) {
  hz_control *control = calloc(1, sizeof(hz_control));
#ifndef _WIN32
  if (control) atomic_init(&control->state, 0);
#endif
  return control;
}
HZ_EXPORT void hz_control_free(void *control) { free(control); }
HZ_EXPORT void hz_control_bind(void *control) { active_control = control; }
HZ_EXPORT int hz_control_get(void *control) { return control ? control_state(control) : 0; }
HZ_EXPORT void hz_control_set(void *control, int state) {
  hz_control *c = control;
  if (!c || state < 0 || state > 3) return;
#ifdef _WIN32
  LONG previous;
  do { previous = InterlockedCompareExchange(&c->state, 0, 0); if (previous >= 2) return; }
  while (InterlockedCompareExchange(&c->state, state, previous) != previous);
#else
  int previous = atomic_load(&c->state);
  do { if (previous >= 2) return; } while (!atomic_compare_exchange_weak(&c->state, &previous, state));
#endif
}
static int checkpoint(struct archive *a) {
  while (active_control && control_state(active_control) == 1) {
#ifdef _WIN32
    Sleep(20);
#else
    struct timespec delay = {0, 20000000}; nanosleep(&delay, NULL);
#endif
  }
  if (active_control && control_state(active_control) == 2) {
    if (a) archive_set_error(a, ECANCELED, "Operation cancelled");
    return 0;
  }
  return 1;
}
static int rar_checkpoint(void) { return checkpoint(NULL); }
HZ_EXPORT int hz_control_checkpoint(void *control) {
  hz_control *previous = active_control; active_control = control;
  int success = checkpoint(NULL); active_control = previous; return success;
}
static la_ssize_t controlled_read(struct archive *a, void *buffer, size_t size) {
  return checkpoint(a) ? archive_read_data(a, buffer, size) : -1;
}
static la_ssize_t controlled_write(struct archive *a, const void *buffer, size_t size) {
  return checkpoint(a) ? archive_write_data(a, buffer, size) : -1;
}

// Scoped by the synchronous FFI caller; concurrent workers never share options.
static HZ_THREAD_LOCAL char read_charset[64] = "";
static HZ_THREAD_LOCAL char write_charset[64] = "UTF-8";
static HZ_THREAD_LOCAL int compression_level = 6;
static HZ_THREAD_LOCAL char read_password[4097] = "";
static HZ_THREAD_LOCAL char write_encryption[16] = "none";
static HZ_THREAD_LOCAL char zip_compression[16] = "deflate";
HZ_EXPORT void hz_configure_security(const char *password, const char *encryption, const char *compression) {
  volatile unsigned char *secret = (volatile unsigned char *)read_password;
  for (size_t i = 0; i < sizeof(read_password); i++) secret[i] = 0;
  snprintf(read_password, sizeof(read_password), "%s", password ? password : "");
  snprintf(write_encryption, sizeof(write_encryption), "%s", encryption ? encryption : "none");
  snprintf(zip_compression, sizeof(zip_compression), "%s", compression ? compression : "deflate");
}
static int configure_writer(struct archive *, int, int, const char *);
static int format_for_filename(const char *, int *);
HZ_EXPORT char *hz_capabilities(void) {
  struct archive *w = archive_write_new();
  archive_write_set_format_zip(w);
  int aes = archive_write_set_format_option(w, "zip", "encryption", "aes256") == ARCHIVE_OK;
  archive_write_free(w);
  buffer b = {0}; append(&b, "{\"zipAES256\":%s,\"zipCompression\":[\"deflate\",\"store\"],\"encryptedUpdates\":false,\"headerEncryption\":false,\"writableFormats\":[", aes ? "true" : "false");
  const char *formats[] = {"zip", "7z", "tar", "tar.gz", "tar.bz2", "tar.xz", "tar.lzma", "tar.zst", "tar.lz4", "tar.lzip", "tar.Z", "cpio", "ar", "gz", "bz2", "xz", "lzma", "zst", "lz4", "lzip", "Z"};
  int first = 1;
  for (size_t i = 0; i < sizeof(formats)/sizeof(formats[0]); i++) {
    char filename[32]; snprintf(filename, sizeof(filename), "archive.%s", formats[i]);
    int filter, format = format_for_filename(filename, &filter); w = archive_write_new();
    if (configure_writer(w, format, filter, "UTF-8") == ARCHIVE_OK) {
      if (!first) append(&b, ","); first = 0; quote(&b, formats[i]);
    }
    archive_write_free(w);
  }
  append(&b, "],\"rarRead\":true,\"rarEncryption\":true,\"rarVolumes\":true}");
  return b.s;
}
HZ_EXPORT void hz_configure_encoding(const char *read, const char *write, int level) {
  snprintf(read_charset, sizeof(read_charset), "%s", read ? read : "");
  snprintf(write_charset, sizeof(write_charset), "%s", write ? write : "UTF-8");
  compression_level = level >= 0 && level <= 9 ? level : 6;
}
HZ_EXPORT void hz_prepare_worker(void) {
#ifdef _WIN32
  SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL);
#elif defined(__APPLE__)
  pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0);
#elif defined(__linux__) || defined(__ANDROID__)
  const pid_t thread_id = (pid_t)syscall(SYS_gettid);
  setpriority(PRIO_PROCESS, thread_id, 5);
#endif
}
static int suffix(const char *path, const char *ending) {
  size_t a = strlen(path), b = strlen(ending);
  if (a < b) return 0;
  for (size_t i = 0; i < b; i++) {
    char c = path[a - b + i];
    if (c >= 'A' && c <= 'Z') c = (char)(c + ('a' - 'A'));
    if (c != ending[i]) return 0;
  }
  return 1;
}
static int writable_format(int format, int filter) {
  int base = format & ARCHIVE_FORMAT_BASE_MASK;
  return (base == ARCHIVE_FORMAT_ZIP || base == ARCHIVE_FORMAT_7ZIP ||
    base == ARCHIVE_FORMAT_TAR || base == ARCHIVE_FORMAT_CPIO ||
    base == ARCHIVE_FORMAT_AR ||
    base == ARCHIVE_FORMAT_RAW) &&
    (filter == ARCHIVE_FILTER_NONE || filter == ARCHIVE_FILTER_GZIP ||
      filter == ARCHIVE_FILTER_BZIP2 || filter == ARCHIVE_FILTER_XZ ||
      filter == ARCHIVE_FILTER_LZMA || filter == ARCHIVE_FILTER_COMPRESS ||
      filter == ARCHIVE_FILTER_LZIP || filter == ARCHIVE_FILTER_LZ4 ||
      filter == ARCHIVE_FILTER_ZSTD);
}
static int configure_writer(struct archive *w, int format, int filter, const char *charset) {
  int rc;
  switch (format & ARCHIVE_FORMAT_BASE_MASK) {
    case ARCHIVE_FORMAT_ZIP: rc = archive_write_set_format_zip(w); break;
    case ARCHIVE_FORMAT_7ZIP: rc = archive_write_set_format_7zip(w); break;
    case ARCHIVE_FORMAT_TAR: rc = archive_write_set_format_pax_restricted(w); break;
    case ARCHIVE_FORMAT_CPIO: rc = archive_write_set_format_cpio_newc(w); break;
    case ARCHIVE_FORMAT_AR: rc = archive_write_set_format_ar_svr4(w); break;
    case ARCHIVE_FORMAT_XAR: rc = archive_write_set_format_xar(w); break;
    case ARCHIVE_FORMAT_RAW: rc = archive_write_set_format_raw(w); break;
    default: return ARCHIVE_FATAL;
  }
  if (rc != ARCHIVE_OK) return rc;
  if ((format & ARCHIVE_FORMAT_BASE_MASK) == ARCHIVE_FORMAT_ZIP) {
    rc = archive_write_set_format_option(w, "zip", "hdrcharset", charset);
    if (rc != ARCHIVE_OK) return rc;
  }
  if ((format & ARCHIVE_FORMAT_BASE_MASK) == ARCHIVE_FORMAT_ZIP ||
      (format & ARCHIVE_FORMAT_BASE_MASK) == ARCHIVE_FORMAT_7ZIP) {
    char level[2] = {(char)('0' + compression_level), 0};
    rc = archive_write_set_format_option(w, NULL, "compression-level", level);
    if (rc != ARCHIVE_OK) return rc;
  }
  if (strcmp(write_encryption, "none")) {
    if ((format & ARCHIVE_FORMAT_BASE_MASK) != ARCHIVE_FORMAT_ZIP || strcmp(write_encryption, "aes256") || !*read_password) {
      archive_set_error(w, EINVAL, "Password encryption is supported only for ZIP AES-256"); return ARCHIVE_FATAL;
    }
    if (archive_write_set_passphrase(w, read_password) != ARCHIVE_OK ||
        archive_write_set_format_option(w, "zip", "encryption", write_encryption) != ARCHIVE_OK) return ARCHIVE_FATAL;
  }
  if ((format & ARCHIVE_FORMAT_BASE_MASK) == ARCHIVE_FORMAT_ZIP) {
    if (strcmp(zip_compression, "store") && strcmp(zip_compression, "deflate")) {
      archive_set_error(w, EINVAL, "Unsupported ZIP compression method"); return ARCHIVE_FATAL;
    }
    if (archive_write_set_format_option(w, "zip", "compression", zip_compression) != ARCHIVE_OK) return ARCHIVE_FATAL;
  }
  switch (filter) {
    case ARCHIVE_FILTER_NONE: return archive_write_add_filter_none(w);
    case ARCHIVE_FILTER_GZIP: return archive_write_add_filter_gzip(w);
    case ARCHIVE_FILTER_BZIP2: return archive_write_add_filter_bzip2(w);
    case ARCHIVE_FILTER_XZ: return archive_write_add_filter_xz(w);
    case ARCHIVE_FILTER_LZMA: return archive_write_add_filter_lzma(w);
    case ARCHIVE_FILTER_COMPRESS: return archive_write_add_filter_compress(w);
    case ARCHIVE_FILTER_LZIP: return archive_write_add_filter_lzip(w);
    case ARCHIVE_FILTER_LZ4: return archive_write_add_filter_lz4(w);
    case ARCHIVE_FILTER_ZSTD: return archive_write_add_filter_zstd(w);
    default: return ARCHIVE_FATAL;
  }
}
static int format_for_filename(const char *path, int *filter) {
  *filter = ARCHIVE_FILTER_NONE;
  if (suffix(path, ".zip")) return ARCHIVE_FORMAT_ZIP;
  if (suffix(path, ".7z")) return ARCHIVE_FORMAT_7ZIP;
  if (suffix(path, ".ar") || suffix(path, ".a")) return ARCHIVE_FORMAT_AR;
  if (suffix(path, ".xar")) return ARCHIVE_FORMAT_XAR;
  if (suffix(path, ".cpio")) return ARCHIVE_FORMAT_CPIO;
  if (suffix(path, ".tar")) return ARCHIVE_FORMAT_TAR;
  if (suffix(path, ".tar.gz") || suffix(path, ".tgz")) {
    *filter = ARCHIVE_FILTER_GZIP;
    return ARCHIVE_FORMAT_TAR;
  }
  if (suffix(path, ".tar.bz2") || suffix(path, ".tbz") || suffix(path, ".tbz2")) {
    *filter = ARCHIVE_FILTER_BZIP2;
    return ARCHIVE_FORMAT_TAR;
  }
  if (suffix(path, ".tar.xz") || suffix(path, ".txz")) {
    *filter = ARCHIVE_FILTER_XZ;
    return ARCHIVE_FORMAT_TAR;
  }
  if (suffix(path, ".tar.lzma") || suffix(path, ".tlz")) {
    *filter = ARCHIVE_FILTER_LZMA;
    return ARCHIVE_FORMAT_TAR;
  }
  if (suffix(path, ".tar.zst") || suffix(path, ".tzst")) {
    *filter = ARCHIVE_FILTER_ZSTD;
    return ARCHIVE_FORMAT_TAR;
  }
  if (suffix(path, ".tar.lz4") || suffix(path, ".tlz4")) {
    *filter = ARCHIVE_FILTER_LZ4;
    return ARCHIVE_FORMAT_TAR;
  }
  if (suffix(path, ".tar.lzip") || suffix(path, ".tlzip")) {
    *filter = ARCHIVE_FILTER_LZIP;
    return ARCHIVE_FORMAT_TAR;
  }
  if (suffix(path, ".tar.z")) {
    *filter = ARCHIVE_FILTER_COMPRESS;
    return ARCHIVE_FORMAT_TAR;
  }
  if (suffix(path, ".gz")) *filter = ARCHIVE_FILTER_GZIP;
  else if (suffix(path, ".bz2") || suffix(path, ".tbz") || suffix(path, ".tbz2")) *filter = ARCHIVE_FILTER_BZIP2;
  else if (suffix(path, ".xz") || suffix(path, ".txz")) *filter = ARCHIVE_FILTER_XZ;
  else if (suffix(path, ".lzma") || suffix(path, ".tlz")) *filter = ARCHIVE_FILTER_LZMA;
  else if (suffix(path, ".zst")) *filter = ARCHIVE_FILTER_ZSTD;
  else if (suffix(path, ".lz4")) *filter = ARCHIVE_FILTER_LZ4;
  else if (suffix(path, ".lzip") || suffix(path, ".lz")) *filter = ARCHIVE_FILTER_LZIP;
  else if (suffix(path, ".z")) *filter = ARCHIVE_FILTER_COMPRESS;
  else return 0;
  return ARCHIVE_FORMAT_RAW;
}
static struct archive *reader(const char *path) {
  struct archive *a = archive_read_new();
  archive_read_support_filter_all(a); archive_read_support_format_all(a);
  if (*read_password) archive_read_add_passphrase(a, read_password);
  int filter; if (format_for_filename(path, &filter) == ARCHIVE_FORMAT_RAW ||
      suffix(path, ".z") || suffix(path, ".zst") || suffix(path, ".lz4") ||
      suffix(path, ".lz") || suffix(path, ".lzip")) archive_read_support_format_raw(a);
  if (*read_charset && archive_read_set_format_option(a, NULL, "hdrcharset", read_charset) != ARCHIVE_OK) return a;
  if (read_open(a, path) != ARCHIVE_OK) { return a; }
  return a;
}
static int next_header(struct archive *a, struct archive_entry **entry, const char *path) {
  if (!checkpoint(a)) return ARCHIVE_FATAL;
  int rc = archive_read_next_header(a, entry);
  if (rc == ARCHIVE_OK && (archive_format(a) & ARCHIVE_FORMAT_BASE_MASK) == ARCHIVE_FORMAT_RAW) {
    const char *base = strrchr(path, '/'); base = base ? base + 1 : path;
    const char *win = strrchr(base, '\\'); if (win) base = win + 1;
    char *name = strdup(base);
    if (name) {
      char *dot = strrchr(name, '.'); if (dot && dot != name) *dot = 0;
      archive_entry_set_pathname_utf8(*entry, name); free(name);
    }
  }
  return rc;
}
static const char *entry_name(struct archive_entry *e) {
  const char *s = archive_entry_pathname_utf8(e); return s ? s : archive_entry_pathname(e);
}
static int safe_name(const char *s) {
  if (!s || !*s || *s == '/' || *s == '\\' || strchr(s, ':') || strchr(s, '\\')) return 0;
  const char *p = s;
  while (*p) { const char *end = strchr(p, '/'); size_t n = end ? (size_t)(end-p) : strlen(p);
    if (n == 2 && p[0] == '.' && p[1] == '.') return 0;
    if (!end) break; p = end + 1;
  }
  return 1;
}
static char *list_impl(const char *path) {
  struct archive *a = reader(path); struct archive_entry *e; buffer b = {0}; int rc, first = 1, safe_to_write = 1;
  append(&b, "{\"entries\":[");
  while ((rc = next_header(a, &e, path)) == ARCHIVE_OK) {
    if (!first) append(&b, ",");
    first = 0;
    const char *name = entry_name(e);
    if (!name || strlen(name) > 4096) { free(b.s); archive_read_free(a); return error("Invalid or excessively long entry path"); }
    if (!safe_name(name) || archive_entry_is_encrypted(e) != 0 || archive_entry_hardlink(e) ||
        (archive_entry_filetype(e) != AE_IFREG && archive_entry_filetype(e) != AE_IFDIR)) safe_to_write = 0;
    if ((archive_format(a) & ARCHIVE_FORMAT_BASE_MASK) == ARCHIVE_FORMAT_RAW) {
      if (archive_filter_code(a, 0) == ARCHIVE_FILTER_NONE) { free(b.s); archive_read_free(a); return error("Invalid compressed stream"); }
      int64_t size = 0; char data[65536]; la_ssize_t n;
      while ((n = controlled_read(a, data, sizeof(data))) > 0) {
        if (n > INT64_MAX - size) { free(b.s); archive_read_free(a); return error("File size overflow"); }
        size += n;
      }
      if (n < 0) { char *r = error(archive_error_string(a)); free(b.s); archive_read_free(a); return r; }
      archive_entry_set_size(e, size);
    }
    append(&b, "{\"path\":"); quote(&b, name);
    append(&b, ",\"size\":%lld,\"modified\":%lld,\"directory\":%s,\"regular\":%s,\"safe\":%s,\"encrypted\":%s",
      (long long)archive_entry_size(e), (long long)archive_entry_mtime(e),
      archive_entry_filetype(e) == AE_IFDIR ? "true" : "false",
      archive_entry_filetype(e) == AE_IFREG && !archive_entry_hardlink(e) ? "true" : "false",
      safe_name(name) ? "true" : "false", archive_entry_is_encrypted(e) > 0 ? "true" : "false");
    if (archive_entry_filetype(e) == AE_IFLNK) {
      const char *link = archive_entry_symlink_utf8(e);
      if (!link) link = archive_entry_symlink(e);
      if (link) { append(&b, ",\"link\":"); quote(&b, link); }
    }
    append(&b, "}");
    // Skipping data makes listing fast; decompression happens only on demand.
    if (archive_read_data_skip(a) < ARCHIVE_OK) { rc = ARCHIVE_FATAL; break; }
  }
  if (rc != ARCHIVE_EOF) { char *r = error(archive_error_string(a)); free(b.s); archive_read_free(a); return r; }
  append(&b, "],\"format\":"); quote(&b, archive_format_name(a));
  append(&b, ",\"writable\":%s}", (safe_to_write && writable_format(archive_format(a), archive_filter_code(a, 0)) && archive_read_has_encrypted_entries(a) <= 0) ? "true" : "false");
  archive_read_free(a); return b.s;
}
static char *extract_impl(const char *path, const char *name, const char *output, int64_t limit) {
  if (!safe_name(name)) return error("Unsafe archive path");
  hz_stat_t existing; if (!hz_stat(output, &existing)) return error("Output file already exists");
  struct archive *a = reader(path); struct archive_entry *e; int rc; char *result = NULL; FILE *f = NULL; int touched = 0;
  while ((rc = next_header(a, &e, path)) == ARCHIVE_OK) {
    if (!entry_name(e) || strcmp(entry_name(e), name)) { archive_read_data_skip(a); continue; }
    if (archive_entry_filetype(e) != AE_IFREG || archive_entry_hardlink(e) || archive_entry_symlink(e)) { result = error("Links and special files cannot be extracted"); break; }
    if (archive_entry_size(e) > limit) { result = error("File exceeds extraction size limit"); break; }
    f = hz_fopen(output, "wb"); if (!f) { result = error("Cannot open destination file"); break; }
    touched = 1;
    char data[65536]; la_ssize_t n; int64_t total = 0;
    while ((n = controlled_read(a, data, sizeof(data))) > 0) {
      if (n > limit - total) { result = error("Extraction size limit exceeded"); break; }
      if (fwrite(data, 1, n, f) != (size_t)n) { result = error("Disk write failed"); break; }
      total += n;
    }
    if (!result && n < 0) result = error(archive_error_string(a));
    if (fclose(f) && !result) result = error("Cannot flush extracted file"); f = NULL;
    if (!result) result = ok(); break;
  }
  if (!result) result = error(rc == ARCHIVE_EOF ? "Entry not found" : archive_error_string(a));
  archive_read_free(a);
  if (touched && strstr(result, "\"error\"")) hz_remove(output);
  return result;
}
// One reader per worker, with logarithmic lookup rather than reopening/scanning
// the archive for every file. Reader/codec state is never shared across threads.
typedef struct { const char *name, *output; int64_t limit; int touched, index; } extract_target;
static int target_compare(const void *left, const void *right) {
  return strcmp(((const extract_target *)left)->name, ((const extract_target *)right)->name);
}
static char *extract_batch_impl(const char *path, const char **names, const char **outputs,
    const int64_t *limits, int count, int64_t total_limit, hz_extract_progress progress, hz_extract_detailed_progress detailed) {
  if (count < 0 || total_limit < 0) return error("Invalid extraction batch");
  if (!count) return ok();
  extract_target *targets = calloc((size_t)count, sizeof(*targets));
  if (!targets) return error("Cannot allocate extraction batch");
  char *result = NULL;
  for (int i = 0; i < count; i++) {
    if (!safe_name(names[i]) || limits[i] < 0) { result = error("Unsafe archive path or invalid size limit"); break; }
    targets[i] = (extract_target){names[i], outputs[i], limits[i], 0, i};
  }
  if (result) { free(targets); return result; }
  qsort(targets, (size_t)count, sizeof(*targets), target_compare);
  for (int i = 1; i < count; i++) {
    if (!strcmp(targets[i - 1].name, targets[i].name)) { free(targets); return error("Duplicate extraction target"); }
  }
  struct archive *a = reader(path); struct archive_entry *e; int rc = ARCHIVE_OK, completed = 0;
  int64_t total = 0;
  char *data = malloc(262144);
  if (!data) result = error("Cannot allocate extraction buffer");
  while (!result && completed < count && (rc = next_header(a, &e, path)) == ARCHIVE_OK) {
    const char *name = entry_name(e);
    extract_target key = {name ? name : "", NULL, 0, 0, 0};
    extract_target *target = bsearch(&key, targets, (size_t)count, sizeof(*targets), target_compare);
    if (!target) {
      if (archive_read_data_skip(a) < ARCHIVE_OK) result = error(archive_error_string(a));
      continue;
    }
    if (target->touched) { result = error("Duplicate archive entry"); break; }
    if (archive_entry_filetype(e) != AE_IFREG || archive_entry_hardlink(e) || archive_entry_symlink(e) || (archive_entry_is_encrypted(e) > 0 && !*read_password)) {
      result = error("Links, encrypted and special files cannot be extracted"); break;
    }
    if (archive_entry_size(e) > target->limit) { result = error("File exceeds extraction size limit"); break; }
    hz_stat_t existing;
    if (!hz_stat(target->output, &existing)) { result = error("Output file already exists"); break; }
    FILE *f = hz_fopen(target->output, "wb");
    if (!f) { result = error("Cannot open destination file"); break; }
    target->touched = 1;
    int64_t bytes = 0; la_ssize_t n = 0;
    const int64_t file_size = archive_entry_size_is_set(e) ? archive_entry_size(e) : -1;
    if (detailed) detailed(completed, total, target->index, 0, file_size);
    while ((n = controlled_read(a, data, 262144)) > 0) {
      if (n > target->limit - bytes || n > total_limit - total) { result = error("Extraction size limit exceeded"); break; }
      if (fwrite(data, 1, (size_t)n, f) != (size_t)n) { result = error("Disk write failed"); break; }
      bytes += n; total += n;
      if (detailed) detailed(completed, total, target->index, bytes, file_size);
    }
    if (!result && n < 0) result = error(archive_error_string(a));
    if (fclose(f) && !result) result = error("Cannot flush extracted file");
    if (!result) {
      completed++;
      if (progress) progress(completed, total);
      if (detailed) detailed(completed, total, target->index, bytes, bytes);
    }
  }
  if (!result && completed != count) result = error(rc == ARCHIVE_EOF ? "Entry not found" : archive_error_string(a));
  free(data); archive_read_free(a);
  if (result) {
    for (int i = 0; i < count; i++) if (targets[i].touched) hz_remove(targets[i].output);
  } else {
    buffer b = {0}; append(&b, "{\"ok\":true,\"files\":%d,\"bytes\":%lld}", completed, (long long)total); result = b.s;
  }
  free(targets); return result;
}
static int write_file(struct archive *w, const char *path) {
  FILE *f = hz_fopen(path, "rb"); if (!f) return 0;
  char buf[65536]; size_t n; int success = 1;
  while ((n = fread(buf, 1, sizeof(buf), f)) > 0) {
    if (controlled_write(w, buf, n) != (la_ssize_t)n) { success = 0; break; }
  }
  if (ferror(f)) success = 0;
  fclose(f); return success;
}
static char *replace_impl(const char *path, const char *name, const char *replacement, const char *output) {
  if (!strcmp(path, output)) return error("Replacement must use a separate output file");
  hz_stat_t existing; if (!hz_stat(output, &existing)) return error("Output file already exists");
  hz_stat_t st; if (hz_stat(replacement, &st)) return error("Cannot read replacement");
  struct archive *r = reader(path), *w = archive_write_new(); struct archive_entry *e;
  int rc = next_header(r, &e, path), found = 0; char *result = NULL;
  if (!writable_format(archive_format(r), archive_filter_code(r, 0))) result = error("This archive format cannot be rewritten");
  if (!result && configure_writer(w, archive_format(r), archive_filter_code(r, 0), "UTF-8") != ARCHIVE_OK) result = error(archive_error_string(w));
  if (!result && write_open(w, output) != ARCHIVE_OK) result = error(archive_error_string(w));
  for (; !result && rc == ARCHIVE_OK; rc = next_header(r, &e, path)) {
    if (archive_entry_is_encrypted(e) != 0 || archive_entry_hardlink(e)) { result = error("Encrypted or linked entries cannot be rewritten"); break; }
    if (archive_entry_filetype(e) != AE_IFREG && archive_entry_filetype(e) != AE_IFDIR) { result = error("ZIP with special files cannot be rewritten safely"); break; }
    if (!entry_name(e) || !safe_name(entry_name(e))) { result = error("Unsafe archive path"); break; }
    int replace = !strcmp(entry_name(e), name);
    if (replace) { if (found++) { result = error("Duplicate entry path"); break; } archive_entry_set_size(e, st.st_size); archive_entry_set_mtime(e, st.st_mtime, 0); }
    char *utf8_name = strdup(entry_name(e));
    if (!utf8_name) { result = error("Out of memory"); break; }
    archive_entry_set_pathname_utf8(e, utf8_name); free(utf8_name);
    if (archive_write_header(w, e) != ARCHIVE_OK) { result = error(archive_error_string(w)); break; }
    if (replace) {
      if (!write_file(w, replacement)) result = error("Cannot write replacement data");
      archive_read_data_skip(r);
    } else {
      char buf[65536]; la_ssize_t n;
      while ((n = controlled_read(r, buf, sizeof(buf))) > 0) {
        if (controlled_write(w, buf, n) != n) { result = error(archive_error_string(w)); break; }
      }
      if (!result && n < 0) result = error(archive_error_string(r));
    }
    if (!result && archive_write_finish_entry(w) != ARCHIVE_OK) result = error(archive_error_string(w));
  }
  if (!result && rc != ARCHIVE_EOF) result = error(archive_error_string(r));
  if (!result && !found) result = error("Entry not found");
  if (archive_write_close(w) != ARCHIVE_OK && !result) result = error(archive_error_string(w));
  archive_write_free(w); archive_read_free(r);
  if (result) hz_remove(output);
  return result ? result : ok();
}
static char *create_impl(const char *output, const char **paths, const char **names, int count) {
  if (count < 0) return error("Invalid file count");
  hz_stat_t existing; if (!hz_stat(output, &existing)) return error("Output file already exists");
  struct archive *w = archive_write_new();
  int filter, format = format_for_filename(output, &filter);
  char *result = NULL;
  if (!format) result = error("Unsupported output archive extension");
  if (!result && format == ARCHIVE_FORMAT_RAW && count != 1) result = error("Single-file compression requires exactly one regular file");
  if (!result && configure_writer(w, format, filter, write_charset) != ARCHIVE_OK) result = error(archive_error_string(w));
  if (!result && write_open(w, output) != ARCHIVE_OK) result = error(archive_error_string(w));
  for (int i = 0; !result && i < count; i++) {
    if (!checkpoint(w)) { result = error("Operation cancelled"); break; }
    hz_stat_t st;
    if (!safe_name(names[i]) || hz_stat(paths[i], &st) || (!S_ISREG(st.st_mode) && !S_ISDIR(st.st_mode)) || (format == ARCHIVE_FORMAT_RAW && !S_ISREG(st.st_mode))) { result = error("Invalid input file"); break; }
    struct archive_entry *e = archive_entry_new(); archive_entry_set_pathname_utf8(e, names[i]);
    archive_entry_set_size(e, S_ISDIR(st.st_mode) ? 0 : st.st_size); archive_entry_set_filetype(e, S_ISDIR(st.st_mode) ? AE_IFDIR : AE_IFREG); archive_entry_set_perm(e, S_ISDIR(st.st_mode) ? 0755 : 0644); archive_entry_set_mtime(e, st.st_mtime, 0);
    if (archive_write_header(w, e) != ARCHIVE_OK || (!S_ISDIR(st.st_mode) && !write_file(w, paths[i])) || archive_write_finish_entry(w) != ARCHIVE_OK) result = error("Cannot write archive entry");
    archive_entry_free(e);
  }
  if (archive_write_close(w) != ARCHIVE_OK && !result) result = error(archive_error_string(w));
  archive_write_free(w); if (result) hz_remove(output); return result ? result : ok();
}

static int compare_names(const void *a, const void *b) { return strcmp(*(const char *const *)a, *(const char *const *)b); }

// Stream retained entries into a fresh archive with the original format/filter.
// The caller commits only after verifying the source snapshot and output.
static char *update_impl(const char *path, const char *output, const char **paths,
    const char **names, int count, const char **removed, int remove_count) {
  hz_stat_t existing;
  if (!strcmp(path, output) || !hz_stat(output, &existing)) return error("Output must be a new separate file");
  if (count < 0 || remove_count < 0) return error("Invalid batch size");
  const char **sorted = malloc((size_t)(count ? count : 1) * sizeof(char *));
  const char **removed_sorted = malloc((size_t)(remove_count ? remove_count : 1) * sizeof(char *));
  if (!sorted || !removed_sorted) { free(sorted); free(removed_sorted); return error("Out of memory"); }
  for (int i = 0; i < count; i++) {
    if (!safe_name(names[i])) { free(sorted); free(removed_sorted); return error("Unsafe new entry path"); }
    sorted[i] = names[i];
  }
  for (int i = 0; i < remove_count; i++) removed_sorted[i] = removed[i];
  qsort(sorted, (size_t)count, sizeof(char *), compare_names);
  qsort(removed_sorted, (size_t)remove_count, sizeof(char *), compare_names);
  for (int i = 1; i < count; i++) {
    if (!strcmp(sorted[i - 1], sorted[i])) { free(sorted); free(removed_sorted); return error("Duplicate new entry path"); }
  }
  struct archive *r = reader(path), *w = archive_write_new(); struct archive_entry *e;
  char *result = NULL; int rc = next_header(r, &e, path);
  if (!writable_format(archive_format(r), archive_filter_code(r, 0))) result = error("This archive format cannot be updated");
  if (!result && configure_writer(w, archive_format(r), archive_filter_code(r, 0), "UTF-8") != ARCHIVE_OK) result = error(archive_error_string(w));
  if (!result && write_open(w, output) != ARCHIVE_OK) result = error(archive_error_string(w));
  for (; !result && rc == ARCHIVE_OK; rc = next_header(r, &e, path)) {
    const char *name = entry_name(e);
    if (archive_entry_is_encrypted(e) != 0 || archive_entry_hardlink(e) || !name || !safe_name(name) ||
        (archive_entry_filetype(e) != AE_IFREG && archive_entry_filetype(e) != AE_IFDIR)) {
      result = error("Only safe unencrypted regular entries can be updated"); break;
    }
    if (bsearch(&name, removed_sorted, (size_t)remove_count, sizeof(char *), compare_names)) { archive_read_data_skip(r); continue; }
    if (bsearch(&name, sorted, (size_t)count, sizeof(char *), compare_names)) result = error("New entry already exists");
    if (result) break;
    char *utf8_name = strdup(name);
    if (!utf8_name) { result = error("Out of memory"); break; }
    archive_entry_set_pathname_utf8(e, utf8_name); free(utf8_name);
    if (archive_write_header(w, e) != ARCHIVE_OK) { result = error(archive_error_string(w)); break; }
    char buf[65536]; la_ssize_t n;
    while ((n = controlled_read(r, buf, sizeof(buf))) > 0) {
      if (controlled_write(w, buf, n) != n) { result = error("Archive update failed"); break; }
    }
    if (!result && n < 0) result = error(archive_error_string(r));
    if (!result && archive_write_finish_entry(w) != ARCHIVE_OK) result = error(archive_error_string(w));
  }
  if (!result && rc != ARCHIVE_EOF) result = error(archive_error_string(r));
  for (int i = 0; !result && i < count; i++) {
    if (!checkpoint(w)) { result = error("Operation cancelled"); break; }
    hz_stat_t st;
    if (hz_stat(paths[i], &st) || (!S_ISREG(st.st_mode) && !S_ISDIR(st.st_mode))) { result = error("Invalid imported file"); break; }
    e = archive_entry_new(); archive_entry_set_pathname_utf8(e, names[i]);
    archive_entry_set_size(e, S_ISDIR(st.st_mode) ? 0 : st.st_size);
    archive_entry_set_filetype(e, S_ISDIR(st.st_mode) ? AE_IFDIR : AE_IFREG);
    archive_entry_set_perm(e, S_ISDIR(st.st_mode) ? 0755 : 0644); archive_entry_set_mtime(e, st.st_mtime, 0);
    if (archive_write_header(w, e) != ARCHIVE_OK ||
        (!S_ISDIR(st.st_mode) && !write_file(w, paths[i])) || archive_write_finish_entry(w) != ARCHIVE_OK) result = error("Cannot append imported file");
    archive_entry_free(e);
  }
  if (archive_write_close(w) != ARCHIVE_OK && !result) result = error(archive_error_string(w));
  archive_write_free(w); archive_read_free(r);
  free(sorted); free(removed_sorted);
  if (result) hz_remove(output);
  return result ? result : ok();
}

// Rebuild without extracting entries: preserve metadata and stream the data once.
static char *rename_impl(const char *path, const char *old_name, const char *new_name, const char *output) {
  hz_stat_t st;
  if (!safe_name(old_name) || !safe_name(new_name) || !strcmp(path, output) || !hz_stat(output, &st)) return error("Invalid rename paths");
  struct archive *r = reader(path), *w = archive_write_new(); struct archive_entry *e;
  int rc = next_header(r, &e, path), found = 0; char *result = NULL;
  if (!writable_format(archive_format(r), archive_filter_code(r, 0))) result = error("This archive format cannot be updated");
  if (!result && configure_writer(w, archive_format(r), archive_filter_code(r, 0), "UTF-8") != ARCHIVE_OK) result = error(archive_error_string(w));
  if (!result && write_open(w, output) != ARCHIVE_OK) result = error(archive_error_string(w));
  size_t prefix = strlen(old_name);
  for (; !result && rc == ARCHIVE_OK; rc = next_header(r, &e, path)) {
    const char *name = entry_name(e);
    if (!name || !safe_name(name) || archive_entry_is_encrypted(e) != 0 || archive_entry_hardlink(e) ||
        (archive_entry_filetype(e) != AE_IFREG && archive_entry_filetype(e) != AE_IFDIR)) { result = error("Only safe unencrypted entries can be renamed"); break; }
    int match = !strcmp(name, old_name) || (!strncmp(name, old_name, prefix) && name[prefix] == '/');
    char *renamed = NULL;
    if (match) {
      found++;
      size_t size = strlen(new_name) + strlen(name + prefix) + 1;
      renamed = malloc(size);
      if (!renamed) { result = error("Out of memory"); break; }
      snprintf(renamed, size, "%s%s", new_name, name + prefix);
    } else if (!strcmp(name, new_name) || (!strncmp(name, new_name, strlen(new_name)) && name[strlen(new_name)] == '/')) {
      result = error("Rename destination already exists"); break;
    }
    if (!renamed) renamed = strdup(name);
    if (!renamed) { result = error("Out of memory"); break; }
    archive_entry_set_pathname_utf8(e, renamed);
    free(renamed);
    if (archive_write_header(w, e) != ARCHIVE_OK) { result = error(archive_error_string(w)); break; }
    char bytes[65536]; la_ssize_t n;
    while ((n = controlled_read(r, bytes, sizeof(bytes))) > 0) {
      if (controlled_write(w, bytes, n) != n) { result = error(archive_error_string(w)); break; }
    }
    if (!result && n < 0) result = error(archive_error_string(r));
    if (!result && archive_write_finish_entry(w) != ARCHIVE_OK) result = error(archive_error_string(w));
  }
  if (!result && rc != ARCHIVE_EOF) result = error(archive_error_string(r));
  if (!result && !found) result = error("Entry not found");
  if (archive_write_close(w) != ARCHIVE_OK && !result) result = error(archive_error_string(w));
  archive_write_free(w); archive_read_free(r);
  if (result) hz_remove(output);
  return result ? result : ok();
}
static char *verify_impl(const char *path) {
  struct archive *r = reader(path); struct archive_entry *e; int rc; char *result = NULL;
  int64_t files = 0, bytes = 0; char block[65536]; la_ssize_t n;
  while ((rc = next_header(r, &e, path)) == ARCHIVE_OK) {
    if ((archive_format(r) & ARCHIVE_FORMAT_BASE_MASK) == ARCHIVE_FORMAT_RAW && archive_filter_code(r, 0) == ARCHIVE_FILTER_NONE) { result = error("Invalid compressed stream"); break; }
    files++;
    while ((n = controlled_read(r, block, sizeof(block))) > 0) {
      if (n > INT64_MAX - bytes) { result = error("Uncompressed size overflow"); break; }
      bytes += n;
    }
    if (!result && n < 0) result = error(archive_error_string(r));
    if (result) break;
  }
  if (!result && rc != ARCHIVE_EOF) result = error(archive_error_string(r));
  archive_read_free(r);
  if (!result) { buffer b = {0}; append(&b, "{\"ok\":true,\"files\":%lld,\"bytes\":%lld}", (long long)files, (long long)bytes); result = b.s; }
  return result;
}

HZ_EXPORT void hz_free(char *result) { free(result); }

HZ_EXPORT char *hz_set_read_only(const char *path, int read_only) {
#ifdef _WIN32
  wchar_t *name = wide(path);
  DWORD attributes = name ? GetFileAttributesW(name) : INVALID_FILE_ATTRIBUTES;
  int success = attributes != INVALID_FILE_ATTRIBUTES && SetFileAttributesW(name,
    read_only ? attributes | FILE_ATTRIBUTE_READONLY : attributes & ~FILE_ATTRIBUTE_READONLY);
  free(name);
#else
  struct stat st;
  int success = !lstat(path, &st) && !S_ISLNK(st.st_mode) &&
    !chmod(path, read_only ? st.st_mode & ~0222 : st.st_mode | 0200);
#endif
  return success ? ok() : error("Cannot set temporary file read-only permissions");
}

// libarchive uses locale conversions internally even with UTF-8 ZIP headers.
// Scope UTF-8 to the worker thread; never mutate the app's global locale.
#ifdef _WIN32
typedef struct { int mode; char previous[128]; } locale_guard;
static locale_guard enter_utf8(void) {
  locale_guard g; g.mode = _configthreadlocale(_ENABLE_PER_THREAD_LOCALE);
  const char *old = setlocale(LC_CTYPE, NULL);
  snprintf(g.previous, sizeof(g.previous), "%s", old ? old : "C");
  setlocale(LC_CTYPE, ".UTF8"); return g;
}
static void leave_utf8(locale_guard g) { setlocale(LC_CTYPE, g.previous); _configthreadlocale(g.mode); }
#else
typedef struct { locale_t previous, current; } locale_guard;
static locale_guard enter_utf8(void) {
  locale_guard g = {0};
  g.current = newlocale(LC_CTYPE_MASK, "C.UTF-8", NULL);
  if (!g.current) g.current = newlocale(LC_CTYPE_MASK, "en_US.UTF-8", NULL);
  if (g.current) g.previous = uselocale(g.current);
  return g;
}
static void leave_utf8(locale_guard g) { if (g.current) { uselocale(g.previous); freelocale(g.current); } }
#endif
HZ_EXPORT char *hz_list(const char *path) {
  locale_guard g = enter_utf8(); char *r = hz_rar_probe(path) ? hz_rar_list(path, read_password, rar_checkpoint) : list_impl(path); leave_utf8(g); return r;
}
HZ_EXPORT char *hz_extract(const char *path, const char *entry, const char *output, int64_t limit) {
  locale_guard g = enter_utf8(); char *r = hz_rar_probe(path) ? hz_rar_extract(path, read_password, &entry, &output, &limit, 1, limit, rar_checkpoint, NULL, NULL) : extract_impl(path, entry, output, limit); leave_utf8(g); return r;
}
HZ_EXPORT char *hz_replace(const char *path, const char *entry, const char *replacement, const char *output) {
  locale_guard g = enter_utf8(); char *r = replace_impl(path, entry, replacement, output); leave_utf8(g); return r;
}
HZ_EXPORT char *hz_create(const char *output, const char **paths, const char **names, int count) {
  locale_guard g = enter_utf8(); char *r = create_impl(output, paths, names, count); leave_utf8(g); return r;
}

HZ_EXPORT char *hz_update(const char *path, const char *output, const char **paths, const char **names, int count, const char **removed, int remove_count) {
  locale_guard g = enter_utf8(); char *r = update_impl(path, output, paths, names, count, removed, remove_count); leave_utf8(g); return r;
}

HZ_EXPORT char *hz_extract_batch(const char *path, const char **names, const char **outputs, const int64_t *limits, int count, int64_t total_limit, hz_extract_progress progress) {
  locale_guard g = enter_utf8();
  char *r = hz_rar_probe(path) ? hz_rar_extract(path, read_password, names, outputs, limits, count, total_limit, rar_checkpoint, progress, NULL) : extract_batch_impl(path, names, outputs, limits, count, total_limit, progress, NULL);
  leave_utf8(g); return r;
}

HZ_EXPORT char *hz_extract_batch_detailed(const char *path, const char **names, const char **outputs, const int64_t *limits, int count, int64_t total_limit, hz_extract_detailed_progress progress) {
  locale_guard g = enter_utf8();
  char *r = hz_rar_probe(path) ? hz_rar_extract(path, read_password, names, outputs, limits, count, total_limit, rar_checkpoint, NULL, progress) : extract_batch_impl(path, names, outputs, limits, count, total_limit, NULL, progress);
  leave_utf8(g); return r;
}

HZ_EXPORT char *hz_rename(const char *path, const char *old_name, const char *new_name, const char *output) {
  locale_guard g = enter_utf8(); char *r = rename_impl(path, old_name, new_name, output); leave_utf8(g); return r;
}
HZ_EXPORT char *hz_verify(const char *path) {
  locale_guard g = enter_utf8(); char *r = hz_rar_probe(path) ? hz_rar_verify(path, read_password, rar_checkpoint) : verify_impl(path); leave_utf8(g); return r;
}

HZ_EXPORT char *hz_publish_new(const char *source, const char *destination) {
#ifdef _WIN32
  wchar_t *s = wide(source), *d = wide(destination);
  int success = s && d && MoveFileExW(s, d, MOVEFILE_WRITE_THROUGH);
  free(s); free(d);
  return success ? ok() : error("Cannot publish new output without replacing an existing file");
#else
#if defined(__APPLE__)
  return renamex_np(source, destination, RENAME_EXCL) == 0 ? ok() : error("Cannot publish output without replacing an existing item");
#elif defined(__linux__) || defined(__ANDROID__)
  return syscall(SYS_renameat2, AT_FDCWD, source, AT_FDCWD, destination, 1) == 0 ? ok() : error("Cannot publish output without replacing an existing item");
#else
  hz_stat_t st;
  if (lstat(source, &st) || S_ISDIR(st.st_mode)) return error("Exclusive directory publication is unavailable on this platform");
  if (link(source, destination)) return error("Cannot publish new output without replacing an existing file");
  if (unlink(source)) { unlink(destination); return error("Cannot release staged output"); }
  return ok();
#endif
#endif
}
