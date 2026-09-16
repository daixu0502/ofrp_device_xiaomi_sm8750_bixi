#!/bin/bash
# OrangeFox Recovery Project environment for Xiaomi MIX Flip 2 (bixi).
# SPDX-License-Identifier: GPL-3.0-or-later

FDEVICE="bixi"

fox_get_target_device() {
    local chkdev
    chkdev=$(echo "$BASH_SOURCE" | grep -w "$FDEVICE")
    if [ -n "$chkdev" ]; then
        FOX_BUILD_DEVICE="$FDEVICE"
    else
        chkdev=$(set | grep BASH_ARGV | grep -w "$FDEVICE")
        [ -n "$chkdev" ] && FOX_BUILD_DEVICE="$FDEVICE"
    fi
}

if [ -z "$1" ] && [ -z "$FOX_BUILD_DEVICE" ]; then
    fox_get_target_device
fi

if [ "$1" = "$FDEVICE" ] || [ "$FOX_BUILD_DEVICE" = "$FDEVICE" ]; then
    export LC_ALL=C
    export FOX_BUILD_DEVICE="$FDEVICE"

    # Stock properties confirm A/B OTA, Virtual A/B snapshots and compression.
    export FOX_AB_DEVICE=1
    export FOX_VIRTUAL_AB_DEVICE=1
    export FOX_VANILLA_BUILD=1

    # The bixi fox_14.1 port remains experimental; label builds accordingly.
    export FOX_BUILD_TYPE=Alpha

    # Recent header-v4/GKI images need the current magiskboot implementation.
    # This is a boot-image utility and does not enable the Magisk addon UI.
    export FOX_USE_UPDATED_MAGISKBOOT=1

    # This port ships KernelSU-family installers instead of Magisk. Remove the
    # Magisk install/uninstall entries and omit their ZIPs from FoxFiles.
    export FOX_DELETE_MAGISK_ADDON=1

    # bixi is an ARM64 Virtual A/B device using a supported GKI 6.6 kernel.
    # Include the official OrangeFox root addons and their ksud userspace
    # helpers so KernelSU, KernelSU Next or SukiSU Ultra can be installed.
    export FOX_ENABLE_KERNELSU_SUPPORT=1
    export FOX_ENABLE_KERNELSU_NEXT_SUPPORT=1
    export FOX_ENABLE_SUKISU_SUPPORT=1
fi
