# Xiaomi MIX Flip 2 (bixi) minimal TWRP bring-up tree.
DEVICE_PATH := device/xiaomi/bixi

# A minimal TWRP manifest does not contain every Android platform dependency.
ALLOW_MISSING_DEPENDENCIES := true

# OrangeFox fox_14.1 uses Soong plugins from bootable/recovery and vendor/recovery
# that are intentionally outside the minimal manifest's plugin allow-list.
BUILD_BROKEN_PLUGIN_VALIDATION += \
    soong-libaosprecovery_defaults \
    soong-libguitwrp_defaults \
    soong-libminuitwrp_defaults \
    soong-vold_defaults

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := oryon
TARGET_2ND_ARCH :=

# Qualcomm SM8750 / Sun
TARGET_BOARD_PLATFORM := xiaomi_sm8750
TARGET_BOARD_PLATFORM_GPU := qcom-adreno830
QCOM_BOARD_PLATFORMS += xiaomi_sm8750

# Bootloader
PRODUCT_PLATFORM := sun
TARGET_BOOTLOADER_BOARD_NAME := $(PRODUCT_PLATFORM)
TARGET_NO_BOOTLOADER := true

# Stock images use boot header v4 and 4096-byte pages. Recovery is a dedicated
# A/B, kernel-less ramdisk; the bootloader supplies boot's kernel and
# vendor_boot's DTB/vendor ramdisk.
BOARD_BOOT_HEADER_VERSION := 4
BOARD_BOOTIMG_HEADER_VERSION := 4
BOARD_KERNEL_PAGESIZE := 4096
BOARD_KERNEL_IMAGE_NAME := Image
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/kernel
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)
BOARD_RAMDISK_USE_LZ4 := true
BOARD_USES_GENERIC_KERNEL_IMAGE := true
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true

# Exact stock partition sizes
BOARD_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := 8388608
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 100663296
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 104857600
BOARD_FLASH_BLOCK_SIZE := 262144

# A/B and AVB image formatting
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS += \
    boot \
    init_boot \
    recovery \
    vendor_boot \
    dtbo \
    vbmeta \
    vbmeta_system \
    mi_ext \
    odm \
    product \
    system \
    system_dlkm \
    system_ext \
    vendor \
    vendor_dlkm
BOARD_AVB_ENABLE := true

# Dynamic partitions and filesystems
BOARD_USES_METADATA_PARTITION := true
BOARD_SUPER_PARTITION_SIZE := 11811160064
BOARD_SUPER_PARTITION_GROUPS := qti_dynamic_partitions
BOARD_QTI_DYNAMIC_PARTITIONS_SIZE := $(shell echo $$(($(BOARD_SUPER_PARTITION_SIZE) - 4194304)))
BOARD_QTI_DYNAMIC_PARTITIONS_PARTITION_LIST := \
    system \
    system_ext \
    product \
    vendor \
    vendor_dlkm \
    odm \
    system_dlkm
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs
TARGET_COPY_OUT_SYSTEM := system
TARGET_COPY_OUT_VENDOR := vendor
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/recovery.fstab
BOARD_ROOT_EXTRA_FOLDERS := firmware persist
BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED := true
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop

# File-based encryption (FBE v2 + metadata encryption).
BOARD_USES_QCOM_FBE_DECRYPTION := true
TW_INCLUDE_CRYPTO := true
TW_INCLUDE_CRYPTO_FBE := true
TW_INCLUDE_FBE_METADATA_DECRYPT := true
TW_INCLUDE_OMAPI := true
TW_USE_FSCRYPT_POLICY := 2
PLATFORM_VERSION := 99.87.36
PLATFORM_VERSION_LAST_STABLE := $(PLATFORM_VERSION)
PLATFORM_SECURITY_PATCH := 2099-12-31
VENDOR_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)
BOOT_SECURITY_PATCH := $(PLATFORM_SECURITY_PATCH)

# The NXP eSE transport is required by the stock Weaver HAL. Keep the module
# list intentionally minimal; its Qualcomm dependencies are supplied by the
# matching stock vendor_boot ramdisk.
TW_LOAD_VENDOR_MODULES := "nxp-nci.ko"
TW_LOAD_VENDOR_MODULES_EXCLUDE_GKI := true
TW_LOAD_PREBUILT_MODULES_AT_FIRST := true

# Recovery UI: stock inner display is 1224x2912.
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
TW_THEME := portrait_hdpi
TW_BRIGHTNESS_PATH := /sys/class/backlight/panel0-backlight/brightness
TW_MAX_BRIGHTNESS := 16383
TW_DEFAULT_BRIGHTNESS := 500
TW_FRAMERATE := 60
TW_EXTRA_LANGUAGES := true
TW_DEFAULT_LANGUAGE := zh_CN
TW_DEVICE_VERSION := 0_xiaomi-sm8750-bixi_Jaco
TW_NO_SCREEN_BLANK := true

# 关闭背屏
TW_INPUT_BLACKLIST := "goodix_ts"

# Tool
TW_INCLUDE_7ZA := true
TW_INCLUDE_ZSTD := true
TW_INCLUDE_REPACKTOOLS := true
TW_ENABLE_ALL_PARTITION_TOOLS := true

# The stock recovery vibrator service is now started successfully and exposes
# a non-default AIDL instance. Point minuitwrp at that exact instance and make
# sure a timed vibration is explicitly switched off afterwards.
TW_SUPPORT_INPUT_AIDL_HAPTICS := true
TW_SUPPORT_INPUT_AIDL_HAPTICS_FQNAME := IVibrator/vibratorfeature
TW_SUPPORT_INPUT_AIDL_HAPTICS_FIX_OFF := true

# Minimal but useful recovery features.
TW_INCLUDE_FASTBOOTD := true
TW_INCLUDE_RESETPROP := true
TW_INCLUDE_LIBRESETPROP := true
TW_EXCLUDE_DEFAULT_USB_INIT := true
TW_USE_TOOLBOX := true
TW_EXCLUDE_APEX := true
TW_EXCLUDE_TWRPAPP := true
TW_HAS_NO_REAL_SDCARD := true
RECOVERY_SDCARD_ON_DATA := true
TW_INTERNAL_STORAGE_PATH := /data/media/0
TW_INTERNAL_STORAGE_MOUNT_POINT := data
TARGET_RECOVERY_QCOM_RTC_FIX := true
TW_USE_SERIALNO_PROPERTY_FOR_DEVICE_ID := true

# Keep adb/logcat available for first-boot diagnosis.
TARGET_USES_LOGD := true
TWRP_INCLUDE_LOGCAT := true

# The matching stock Qualcomm Boot Control HAL is shipped as a recovery
# prebuilt. Allow it and its vendor library to be copied into the ramdisk.
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true
