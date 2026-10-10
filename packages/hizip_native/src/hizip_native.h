#ifndef HIZIP_NATIVE_H
#define HIZIP_NATIVE_H
#include <stdint.h>
#ifdef _WIN32
#define HZ_EXPORT __declspec(dllexport)
#else
#define HZ_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif
HZ_EXPORT void hz_configure_encoding(const char *read, const char *write, int level);
HZ_EXPORT void hz_configure_security(const char *password, const char *encryption, const char *zip_compression);
HZ_EXPORT char *hz_capabilities(void);
HZ_EXPORT void hz_prepare_worker(void);
HZ_EXPORT void *hz_control_create(void);
HZ_EXPORT void hz_control_free(void *control);
HZ_EXPORT void hz_control_bind(void *control);
HZ_EXPORT void hz_control_set(void *control, int state);
HZ_EXPORT int hz_control_get(void *control);
HZ_EXPORT int hz_control_checkpoint(void *control);
HZ_EXPORT char *hz_list(const char *path);
HZ_EXPORT char *hz_extract(const char *path, const char *entry, const char *output, int64_t limit);
typedef void (*hz_extract_progress)(int32_t completed, int64_t bytes);
HZ_EXPORT char *hz_extract_batch(const char *path, const char **names, const char **outputs, const int64_t *limits, int count, int64_t total_limit, hz_extract_progress progress);
typedef void (*hz_extract_detailed_progress)(int32_t completed, int64_t total_bytes, int32_t index, int64_t file_bytes, int64_t file_size);
HZ_EXPORT char *hz_extract_batch_detailed(const char *path, const char **names, const char **outputs, const int64_t *limits, int count, int64_t total_limit, hz_extract_detailed_progress progress);
HZ_EXPORT char *hz_replace(const char *path, const char *entry, const char *replacement, const char *output);
HZ_EXPORT char *hz_create(const char *output, const char **paths, const char **names, int count);
HZ_EXPORT char *hz_update(const char *path, const char *output, const char **paths, const char **names, int count, const char **removed, int remove_count);
HZ_EXPORT char *hz_rename(const char *path, const char *old_name, const char *new_name, const char *output);
HZ_EXPORT char *hz_verify(const char *path);
HZ_EXPORT char *hz_publish_new(const char *source, const char *destination);
HZ_EXPORT char *hz_set_read_only(const char *path, int read_only);
HZ_EXPORT void hz_free(char *result);
#endif
