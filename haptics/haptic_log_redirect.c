/* SPDX-License-Identifier: Apache-2.0 */

#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>

/* This shim is loaded only into bixi's stock vibrator HAL in recovery. */
__attribute__((visibility("default")))
FILE *fopen(const char *path, const char *mode) {
    typedef FILE *(*fopen_fn)(const char *, const char *);
    fopen_fn real_fopen = (fopen_fn)dlsym(RTLD_NEXT, "fopen");

    if (real_fopen == NULL) {
        errno = ENOSYS;
        return NULL;
    }

    if (strcmp(path, "/data/local/log/hapticDump.bin") == 0) {
        path = "/tmp/bixi-hapticDump.bin";
    }
    return real_fopen(path, mode);
}
