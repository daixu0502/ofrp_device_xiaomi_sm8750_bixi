#!/system/bin/sh

LOG_FILE=/tmp/bixi-recovery-charge.log
CHARGE_DIR=/sys/class/xm_power/charger/charge_interface
ENABLE_NODE=$CHARGE_DIR/charge_enable
SUSPEND_NODE=$CHARGE_DIR/input_suspend

echo "I:bixi-recovery-charge: waiting for Xiaomi charge interface" > "$LOG_FILE"

i=0
while [ "$i" -lt 20 ]; do
    if [ -e "$ENABLE_NODE" ] && [ -e "$SUSPEND_NODE" ]; then
        break
    fi
    sleep 1
    i=$((i + 1))
done

if [ ! -e "$ENABLE_NODE" ] || [ ! -e "$SUSPEND_NODE" ]; then
    echo "E:bixi-recovery-charge: charge interface did not appear" >> "$LOG_FILE"
    exit 1
fi

# Restore the normal kernel defaults. Do not touch iin_limit or Xiaomi's
# thermal FCC nodes; those remain under charger firmware/mi_thermald control.
# Xiaomi's MCA interface parses "<client> <path> <value>" rather than a bare
# integer. "buck" is the aggregate wired buck path used by the stock charge
# policy. Keep all current and voltage limits under the stock driver policy.
echo "recovery buck 0" > "$SUSPEND_NODE"
SUSPEND_RESULT=$?
echo "recovery buck 1" > "$ENABLE_NODE"
ENABLE_RESULT=$?

sleep 2
USB_PRESENT=$(cat /sys/class/power_supply/usb/present 2>/dev/null)
USB_ONLINE=$(cat /sys/class/power_supply/usb/online 2>/dev/null)
BATTERY_STATUS=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
BATTERY_CURRENT=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)

echo "I:bixi-recovery-charge: input_suspend=0 result=$SUSPEND_RESULT" >> "$LOG_FILE"
echo "I:bixi-recovery-charge: charge_enable=1 result=$ENABLE_RESULT" >> "$LOG_FILE"
echo "I:bixi-recovery-charge: usb_present=$USB_PRESENT usb_online=$USB_ONLINE battery_status=$BATTERY_STATUS current_now=$BATTERY_CURRENT" >> "$LOG_FILE"

if [ "$SUSPEND_RESULT" -ne 0 ] || [ "$ENABLE_RESULT" -ne 0 ]; then
    exit 1
fi
exit 0
