/* SPDX-License-Identifier: Apache-2.0 */

#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>

/* This shim is loaded only into bixi's stock vibrator HAL in recovery. */
/* Keep the HAL's haptics library on the recovery ramdisk. Its stock
 * absolute /odm path would pin the real ODM filesystem for the life of the
 * service and make OrangeFox's ODM unmount fail with EBUSY.
 */
__attribute__((visibility("default")))
void *dlopen(const char *filename, int flags) {
    typedef void *(*dlopen_fn)(const char *, int);
    dlopen_fn real_dlopen = (dlopen_fn)dlsym(RTLD_NEXT, "dlopen");

    if (real_dlopen == NULL) {
        errno = ENOSYS;
        return NULL;
    }
    if (filename != NULL && strcmp(filename, "/odm/lib64/libaachaptics.so") == 0) {
        filename = "/system/odm/lib64/libaachaptics.so";
    }
    return real_dlopen(filename, flags);
}

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
