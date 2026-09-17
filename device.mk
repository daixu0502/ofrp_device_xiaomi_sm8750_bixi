DEVICE_PATH := device/xiaomi/bixi

# fox_14.1 provides System SDK/VNDK 34. The phone shipped with a newer Android
# release, but the recovery product itself must not request APIs newer than the
# source tree can provide.
PRODUCT_SHIPPING_API_LEVEL := 34
PRODUCT_TARGET_VNDK_VERSION := 34
PRODUCT_CHARACTERISTICS := nosdcard
PRODUCT_USE_DYNAMIC_PARTITIONS := true

PRODUCT_SOONG_NAMESPACES += \
    $(DEVICE_PATH)

# Release the bootloader's secondary-panel continuous splash before TWRP takes
# DRM master. This prevents the static Xiaomi logo from remaining on the OLED.
PRODUCT_PACKAGES += \
    bixi-cover-display-cleanup \
    libbixi_haptic_log_redirect

# OrangeFox-only settings that are valid in product makefiles. Variables with
# a FOX_ prefix live in vendorsetup.sh because OrangeFox reads them from the
# build environment.
$(call inherit-product, $(DEVICE_PATH)/fox_bixi.mk)
