#!/system/bin/sh

# Complete bixi's credential decryption chain after TWRP has processed fstab
# and loaded the NXP transport module. Keep failures visible in recovery.log.
LOGFILE=/tmp/recovery.log

log_crypto() {
	echo "I:bixi-crypto::$1" >>"$LOGFILE"
}

wait_for_property() {
	i=0
	while [ "$i" -lt "$3" ]; do
		if [ "$(getprop "$1")" = "$2" ]; then
			return 0
		fi
		sleep 1
		i=$((i + 1))
	done
	log_crypto "Timed out waiting for $1=$2"
	return 1
}

wait_for_service() {
	i=0
	while [ "$i" -lt "$2" ]; do
		if [ "$(getprop init.svc."$1")" = "running" ]; then
			return 0
		fi
		sleep 1
		i=$((i + 1))
	done
	log_crypto "Timed out waiting for service $1"
	return 1
}

ensure_modem_firmware() {
	ese_ta=/vendor/firmware_mnt/image/05B04A44-BF30-42DF-9E2F-B366B980ED19.b00
	weaver_ta=/vendor/firmware_mnt/image/32552B22-89FE-42B4-8A45-A0C4E2DB0326.mdt
	if [ -r "$ese_ta" ] && [ -r "$weaver_ta" ]; then
		return 0
	fi

	suffix=$(getprop ro.boot.slot_suffix)
	modem_block=/dev/block/bootdevice/by-name/modem$suffix
	mkdir -p /vendor/firmware_mnt
	i=0
	while [ "$i" -lt 10 ]; do
		if ! grep -q " /vendor/firmware_mnt " /proc/mounts && [ -e "$modem_block" ]; then
			mount -t vfat \
				-o ro,shortname=lower,uid=1000,gid=1000,dmask=227,fmask=337 \
				"$modem_block" /vendor/firmware_mnt 2>/dev/null || true
		fi
		if [ -r "$ese_ta" ] && [ -r "$weaver_ta" ]; then
			log_crypto "Mounted modem firmware fallback from $modem_block"
			return 0
		fi
		sleep 1
		i=$((i + 1))
	done

	log_crypto "Modem firmware or required eSE/Weaver TA files are unavailable"
	return 1
}

# gpqese identifies the product by these read-only properties. The build
# product must remain twrp_bixi, so publish the stock device identity here.
if [ -x /system/bin/resetprop ]; then
	resetprop_bin=/system/bin/resetprop
elif [ -x /sbin/resetprop ]; then
	resetprop_bin=/sbin/resetprop
else
	resetprop_bin=setprop
fi

for product_prop in \
	ro.build.product \
	ro.product.device \
	ro.product.odm.device \
	ro.product.vendor.device \
	ro.product.product.device \
	ro.product.system_ext.device \
	ro.product.system.device \
	ro.product.bootimage.device \
	ro.product.name \
	ro.product.odm.name \
	ro.product.vendor.name \
	ro.product.product.name \
	ro.product.system_ext.name \
	ro.product.system.name; do
	"$resetprop_bin" "$product_prop" bixi
done

wait_for_property vendor.sys.listeners.registered true 30 || exit 1
setprop crypto.weaver.ready 0

setprop ctl.start vendor.gatekeeper_default
ensure_modem_firmware || exit 1
setprop ctl.start vendor.ssgtzd

# KeyMint reads OS/security-patch properties in its constructor. Set them from
# the installed ROM before the service starts, then let metadata decrypt run.
if ! /system/bin/sh /system/bin/prepdecrypt.sh; then
	log_crypto "prepdecrypt failed; not starting the credential Weaver chain"
	exit 1
fi
wait_for_property crypto.ready 1 5 || exit 1

wait_for_service vendor.ssgtzd 10 || exit 1
if [ ! -e /dev/nq-nci ]; then
	log_crypto "Missing /dev/nq-nci after TWRP module loading"
	exit 1
fi

# ssgtzd has no ready property. Its TA autoloader initializes in milliseconds;
# one second prevents a cold-boot race without holding Android init itself.
sleep 1
setprop ctl.start vendor.secure_element
wait_for_service vendor.secure_element 10 || exit 1

sleep 1
setprop ctl.start se_omapi
wait_for_service se_omapi 10 || exit 1

sleep 1
setprop ctl.start vendor.weaver_nxp
wait_for_service vendor.weaver_nxp 10 || exit 1

setprop crypto.weaver.ready 1
log_crypto "KeyMint, GPQeSE, OMAPI and Weaver startup complete"
exit 0
