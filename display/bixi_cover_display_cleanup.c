/* SPDX-License-Identifier: Apache-2.0 */

#include <xf86drm.h>
#include <xf86drmMode.h>

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <unistd.h>

#ifndef DRM_MODE_CONNECTOR_DSI
#define DRM_MODE_CONNECTOR_DSI 16
#endif

#define BIXI_COVER_WIDTH 1208
#define BIXI_COVER_HEIGHT 1392
#define BIXI_DSI_CONNECTOR_INDEX 2
#define DEBUGFS_MOUNT_POINT "/sys/kernel/debug"
#define REGULATOR_DEBUGFS_ROOT DEBUGFS_MOUNT_POINT "/regulator"
#define COVER_VCI_REGULATOR_NAME "pm_humu_l8"

static void log_result(const char *message) {
    FILE *log = fopen("/tmp/bixi-cover-display.log", "a");

    if (log != NULL) {
        fprintf(log, "I:bixi-cover-display: %s\n", message);
        fclose(log);
    }
    fprintf(stderr, "bixi-cover-display: %s\n", message);
}

/*
 * The bootloader leaves the secondary OLED displaying its continuous-splash
 * framebuffer.  Detaching the DRM pipeline stops scanout, but the panel keeps
 * that last frame as long as its analogue VCI rail remains powered.  The stock
 * display driver also keeps its stale continuous-splash regulator vote, so a
 * normal regulator disable is not available from userspace.  Recovery's
 * regulator debug interface provides force_disable specifically for clearing
 * such a stuck vote.  pm_humu_l8 is dedicated to the cover panel on bixi.
 */
static int force_disable_cover_vci(void) {
    char path[PATH_MAX];
    DIR *directory;
    struct dirent *entry;
    int fd = -1;
    int result = -ENOENT;

    if (mkdir(DEBUGFS_MOUNT_POINT, 0755) != 0 && errno != EEXIST) {
        return -errno;
    }

    if (mount("debugfs", DEBUGFS_MOUNT_POINT, "debugfs",
              MS_NOSUID | MS_NODEV | MS_NOEXEC, NULL) != 0 && errno != EBUSY) {
        return -errno;
    }

    directory = opendir(REGULATOR_DEBUGFS_ROOT);
    if (directory == NULL) {
        return -errno;
    }

    while ((entry = readdir(directory)) != NULL) {
        ssize_t written;

        if (strstr(entry->d_name, COVER_VCI_REGULATOR_NAME) == NULL) {
            continue;
        }

        if (snprintf(path, sizeof(path), "%s/%s/force_disable",
                     REGULATOR_DEBUGFS_ROOT, entry->d_name) >= (int)sizeof(path)) {
            result = -ENAMETOOLONG;
            break;
        }

        fd = open(path, O_WRONLY | O_CLOEXEC);
        if (fd < 0) {
            result = -errno;
            break;
        }

        written = write(fd, "1\n", 2);
        if (written != 2) {
            result = written < 0 ? -errno : -EIO;
        } else {
            result = 0;
        }
        close(fd);
        fd = -1;
        break;
    }

    if (fd >= 0) {
        close(fd);
    }
    closedir(directory);
    return result;
}

static int cover_mode_is_active(int fd, uint32_t crtc_id) {
    drmModeCrtc *crtc;
    int active;

    if (crtc_id == 0) {
        return 0;
    }

    crtc = drmModeGetCrtc(fd, crtc_id);
    if (crtc == NULL) {
        return 0;
    }

    active = crtc->mode_valid && crtc->mode.hdisplay == BIXI_COVER_WIDTH &&
             crtc->mode.vdisplay == BIXI_COVER_HEIGHT;
    drmModeFreeCrtc(crtc);
    return active;
}

static uint32_t active_crtc_from_encoder(int fd, uint32_t encoder_id) {
    drmModeEncoder *encoder;
    uint32_t crtc_id;

    if (encoder_id == 0) {
        return 0;
    }

    encoder = drmModeGetEncoder(fd, encoder_id);
    if (encoder == NULL) {
        return 0;
    }

    crtc_id = encoder->crtc_id;
    drmModeFreeEncoder(encoder);
    return cover_mode_is_active(fd, crtc_id) ? crtc_id : 0;
}

static uint32_t find_secondary_crtc(int fd, uint32_t *target_connector_id) {
    drmModeRes *resources;
    uint32_t target_crtc = 0;

    resources = drmModeGetResources(fd);
    if (resources == NULL) {
        return 0;
    }

    for (int i = 0; i < resources->count_connectors; ++i) {
        drmModeConnector *connector =
                drmModeGetConnector(fd, resources->connectors[i]);

        if (connector == NULL) {
            continue;
        }
        if (connector->connector_type != DRM_MODE_CONNECTOR_DSI ||
            connector->connector_type_id != BIXI_DSI_CONNECTOR_INDEX) {
            drmModeFreeConnector(connector);
            continue;
        }

        *target_connector_id = connector->connector_id;
        target_crtc = active_crtc_from_encoder(fd, connector->encoder_id);

        if (target_crtc == 0) {
            for (int j = 0; j < connector->count_encoders; ++j) {
                target_crtc = active_crtc_from_encoder(fd, connector->encoders[j]);
                if (target_crtc != 0) {
                    break;
                }
            }
        }
        drmModeFreeConnector(connector);
        break;
    }

    drmModeFreeResources(resources);
    return target_crtc;
}

static int add_named_property(int fd, drmModeAtomicReq *request,
                              uint32_t object_id, uint32_t object_type,
                              const char *name, uint64_t value) {
    drmModeObjectProperties *properties;
    int result = -ENOENT;

    properties = drmModeObjectGetProperties(fd, object_id, object_type);
    if (properties == NULL) {
        return -errno;
    }

    for (uint32_t i = 0; i < properties->count_props; ++i) {
        drmModePropertyRes *property = drmModeGetProperty(fd, properties->props[i]);

        if (property == NULL) {
            continue;
        }
        if (strcmp(property->name, name) == 0) {
            result = drmModeAtomicAddProperty(request, object_id,
                                              property->prop_id, value) < 0
                         ? -errno
                         : 0;
            drmModeFreeProperty(property);
            break;
        }
        drmModeFreeProperty(property);
    }

    drmModeFreeObjectProperties(properties);
    return result;
}

static int disable_crtc(int fd, uint32_t connector_id, uint32_t crtc_id) {
    drmModeAtomicReq *request = NULL;
    drmModePlaneRes *plane_resources = NULL;
    int result = -EINVAL;

    if (drmSetClientCap(fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1) != 0 ||
        drmSetClientCap(fd, DRM_CLIENT_CAP_ATOMIC, 1) != 0) {
        return -errno;
    }

    request = drmModeAtomicAlloc();
    if (request == NULL) {
        return -ENOMEM;
    }

    if (add_named_property(fd, request, connector_id, DRM_MODE_OBJECT_CONNECTOR,
                           "CRTC_ID", 0) != 0 ||
        add_named_property(fd, request, crtc_id, DRM_MODE_OBJECT_CRTC,
                           "MODE_ID", 0) != 0 ||
        add_named_property(fd, request, crtc_id, DRM_MODE_OBJECT_CRTC,
                           "ACTIVE", 0) != 0) {
        goto out;
    }

    plane_resources = drmModeGetPlaneResources(fd);
    if (plane_resources != NULL) {
        for (uint32_t i = 0; i < plane_resources->count_planes; ++i) {
            drmModePlane *plane = drmModeGetPlane(fd, plane_resources->planes[i]);

            if (plane == NULL) {
                continue;
            }
            if (plane->crtc_id == crtc_id &&
                (add_named_property(fd, request, plane->plane_id,
                                    DRM_MODE_OBJECT_PLANE, "CRTC_ID", 0) != 0 ||
                 add_named_property(fd, request, plane->plane_id,
                                    DRM_MODE_OBJECT_PLANE, "FB_ID", 0) != 0)) {
                drmModeFreePlane(plane);
                goto out;
            }
            drmModeFreePlane(plane);
        }
    }

    result = drmModeAtomicCommit(fd, request, DRM_MODE_ATOMIC_ALLOW_MODESET, NULL);
    if (result != 0) {
        result = drmModeSetCrtc(fd, crtc_id, 0, 0, 0, NULL, 0, NULL);
    }

out:
    if (plane_resources != NULL) {
        drmModeFreePlaneResources(plane_resources);
    }
    drmModeAtomicFree(request);
    return result;
}

int main(void) {
    char message[160];
    uint32_t connector_id = 0;
    uint32_t crtc_id;
    int power_result;
    int fd;

    fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        snprintf(message, sizeof(message), "cannot open card0: %s", strerror(errno));
        log_result(message);
        return EXIT_FAILURE;
    }

    if (drmSetMaster(fd) != 0 && errno != EINVAL) {
        snprintf(message, sizeof(message), "cannot become DRM master: %s", strerror(errno));
        log_result(message);
        close(fd);
        return EXIT_FAILURE;
    }

    crtc_id = find_secondary_crtc(fd, &connector_id);
    if (crtc_id == 0) {
        log_result("active 1208x1392 DSI-2 pipeline not found; nothing changed");
        close(fd);
        return EXIT_SUCCESS;
    }

    if (disable_crtc(fd, connector_id, crtc_id) != 0) {
        snprintf(message, sizeof(message), "failed to disable CRTC %u: %s",
                 crtc_id, strerror(errno));
        log_result(message);
        close(fd);
        return EXIT_FAILURE;
    }

    snprintf(message, sizeof(message), "disabled DSI-2 CRTC %u", crtc_id);
    log_result(message);
    close(fd);

    power_result = force_disable_cover_vci();
    if (power_result != 0) {
        snprintf(message, sizeof(message), "failed to force off cover VCI: %s",
                 strerror(-power_result));
        log_result(message);
        return EXIT_FAILURE;
    }

    log_result("forced cover VCI pm_humu_l8 off");
    return EXIT_SUCCESS;
}
