$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota/compression.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)
$(call inherit-product, vendor/twrp/config/common.mk)
$(call inherit-product, device/xiaomi/bixi/device.mk)

PRODUCT_DEVICE := bixi
PRODUCT_NAME := twrp_bixi
PRODUCT_BRAND := Xiaomi
PRODUCT_MODEL := 2505APX7BC
PRODUCT_MANUFACTURER := Xiaomi
