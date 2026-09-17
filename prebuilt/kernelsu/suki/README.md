# SukiSU Ultra overrides

Place extracted ARM64 SukiSU Ultra `.ko` files in this directory. The
source-fix helper matches them by Android/KMI name and updates
`vendor/recovery/Files/KernelSU_Suki_Installer.zip`.

Examples:

```text
android15-6.6_kernelsu.ko
android16-6.12_kernelsu.ko
SukiSU-v4.3.0-android16-6.12_kernelsu.ko
```

Official SukiSU Ultra releases currently distribute each LKM inside a ZIP such
as `aarch64-android16-6.12-lkm.zip`. Extract its `kernelsu.ko`, rename it using
one of the examples above, and place it here. The helper reads the version
embedded in the official module (for example `v4.2.0-904c60d1@main`) and
updates both SukiSU version labels in OrangeFox's Advanced menu automatically.
