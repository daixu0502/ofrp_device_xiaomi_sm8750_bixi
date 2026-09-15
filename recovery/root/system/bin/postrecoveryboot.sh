#!/system/bin/sh

# Compatibility fallback for recovery branches that still invoke this hook.
# fox_14.1 starts these services from twrp.modules.loaded in the device RC.
umount /odm 2>/dev/null || true
setprop vendor.haptic.calibrate.done 1
setprop ctl.start odm.vibratorfeature-service

exit 0
