#ifndef HIZIP_RAR_H
#define HIZIP_RAR_H
#include "hizip_native.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef int (*hz_rar_checkpoint)(void);
int hz_rar_probe(const char *path);
char *hz_rar_list(const char *path, const char *password, hz_rar_checkpoint checkpoint);
char *hz_rar_extract(const char *path, const char *password, const char **names,
    const char **outputs, const int64_t *limits, int count, int64_t total_limit,
    hz_rar_checkpoint checkpoint, hz_extract_progress progress,
    hz_extract_detailed_progress detailed);
char *hz_rar_verify(const char *path, const char *password, hz_rar_checkpoint checkpoint);
#ifdef __cplusplus
}
#endif
#endif
