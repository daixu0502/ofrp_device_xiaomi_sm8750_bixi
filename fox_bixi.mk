# OrangeFox Recovery Project settings for Xiaomi MIX Flip 2 (bixi).
# SPDX-License-Identifier: GPL-3.0-or-later

# Inner display: 1224x2912 (approximately 21.4:9). OrangeFox lays out its
# portrait theme on a virtual 1080-pixel-wide canvas.
OF_MAINTAINER := Jaco
OF_SCREEN_H := 2570
OF_STATUS_H := 120
OF_STATUS_INDENT_LEFT := 48
OF_STATUS_INDENT_RIGHT := 48
OF_HIDE_NOTCH := 1
OF_CLOCK_POS := 1
OF_ALLOW_DISABLE_NAVBAR := 0

# bixi is a Virtual A/B device with a dedicated A/B recovery partition. Its
# stock recovery is a kernel-less, header-v4 image with an LZ4 ramdisk.
OF_AB_DEVICE_WITH_RECOVERY_PARTITION := 1
OF_USE_LZ4_COMPRESSION := 1
OF_FORCE_PREBUILT_KERNEL := 1
OF_ENABLE_ALL_PARTITION_TOOLS := 1
OF_USE_AIDL_BOOT_CONTROL := 1

# OrangeFox appends /brightness and /max_brightness to these LED directories.
# The QTI driver needs a torch-current node followed by its hardware switch.
OF_FL_PATH1 := /sys/class/leds/led:torch_0
OF_FL_PATH2 := /sys/class/leds/led:switch_0
OF_USE_GREEN_LED := 0

# The custom KeyMint/Weaver chain is initialized once after TWRP has staged
# the matching vendor modules. Do not repeat recovery startup after decrypt.
OF_NO_RELOAD_AFTER_DECRYPTION := 1
