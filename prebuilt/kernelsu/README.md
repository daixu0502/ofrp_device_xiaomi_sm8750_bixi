# Local KernelSU module overrides

The OrangeFox source-fix helper scans this directory and overlays every local
ARM64 KernelSU module into `vendor/recovery/Files/KernelSU_Installer.zip`.
The target entry is derived from the Android/KMI part of the filename, so the
mechanism is not limited to bixi's current Android 15 / GKI 6.6 combination.

Accepted examples:

```text
android15-6.6_kernelsu.ko
android16-6.12_kernelsu.ko
lkm-aarch64-android16-6.12_kernelsu.ko
KernelSU-v3.4.0-android16-6.12_kernelsu.ko
```

The first two naming forms are preferred. A matching existing ZIP entry is
replaced; a KMI that is not yet present in the ZIP is added. When multiple
versioned files target the same KMI, the highest version in the filename is
selected. The script rejects malformed, non-ELF64, or non-ARM64 files and
records the selected filename and SHA-256 in the installer's `source.txt`.

Put KernelSU Next modules in the `next` subdirectory because its official
module filenames are otherwise identical to standard KernelSU modules:

```text
prebuilt/kernelsu/next/android15-6.6_kernelsu.ko
```

Put extracted SukiSU Ultra modules in the `suki` subdirectory:

```text
prebuilt/kernelsu/suki/android15-6.6_kernelsu.ko
```

The initially bundled `android15-6.6_kernelsu.ko` is the official ARM64
Android 15 / GKI 6.6 module from KernelSU v3.3.0:

<https://github.com/tiann/KernelSU/releases/tag/v3.3.0>

SHA-256:

```text
c31d994aaf285e7bf4cf1ec38c2bbf2d7f303d1a4a7d616405bcd9f850d684e5
```
