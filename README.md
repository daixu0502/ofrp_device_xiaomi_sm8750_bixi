# Xiaomi MIX Flip 2 (`bixi`) OrangeFox `fox_14.1` device tree

This tree is derived from the unpacked HyperOS
`OS3.0.304.0.WOHCNXM` Android 16 images and is configured for the official
OrangeFox `fox_14.1` source branch.


## Confirmed stock layout

| Item | Stock value |
| --- | --- |
| Device | Xiaomi MIX Flip 2 / `bixi` / `2505APX7BC` |
| SoC | Qualcomm SM8750 family, DT compatible `qcom,sun` / `qcom,sunp` |
| Kernel | GKI 6.6.77, arm64 only |
| Boot format | Header v4, 4096-byte pages, LZ4 ramdisk |
| Recovery | Dedicated A/B partition, 104857600 bytes, no embedded kernel |
| Display | 1224x2912 inner panel, `panel0-backlight` |
| Storage | UFS, dynamic logical partitions, EROFS/ext4, F2FS userdata |
| Android | 16 / API 36 (TWRP 35) |


## Build with OrangeFox 14.1

Place this directory at `device/xiaomi/bixi` in the fully synchronized official
`fox_14.1` source tree, then run from the source root:

```sh
bash device/xiaomi/bixi/patches/apply-orangefox14-source-fixes.sh "$PWD"
source build/envsetup.sh
lunch twrp_bixi-ap2a-eng
mka adbd recoveryimage
```

The build produces an OrangeFox image under `out/target/product/bixi/` (normally
named `OrangeFox-*-bixi.img`) and may also produce an installer ZIP. 

Local KernelSU modules are overlaid by the source-fix helper. Standard,
KernelSU Next and SukiSU Ultra modules belong in `prebuilt/kernelsu`,
`prebuilt/kernelsu/next` and `prebuilt/kernelsu/suki`, respectively. For
SukiSU, the helper reads the version embedded in the selected module and
updates the stale hard-coded version labels in OrangeFox's Advanced menu.

The stock QTI flashlight driver needs both `led:torch_0` to select the current
and `led:switch_0` to enable the physical LED. OrangeFox appends `/brightness`
and `/max_brightness` to these two directory paths automatically.
