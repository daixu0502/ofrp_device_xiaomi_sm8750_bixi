#!/system/bin/sh

# Run the unmodified stock bixi post-boot policy and retain enough state for
# recovery-side diagnosis. This wrapper never sets a fixed frequency ceiling.
LOG_FILE=/tmp/bixi-recovery-power.log
STOCK_POLICY=/system/odm/bin/init.kernel.post_boot-sun_default_6_2.sh

echo "I:bixi-recovery-power: starting stock dynamic policy" > "$LOG_FILE"

if [ ! -r "$STOCK_POLICY" ]; then
    echo "E:bixi-recovery-power: missing $STOCK_POLICY" >> "$LOG_FILE"
    exit 1
fi

/system/bin/sh "$STOCK_POLICY" >> "$LOG_FILE" 2>&1
RESULT=$?

echo "I:bixi-recovery-power: stock policy exit=$RESULT parsed=$(getprop vendor.post_boot.parsed)" >> "$LOG_FILE"
for POLICY in /sys/devices/system/cpu/cpufreq/policy*; do
    [ -d "$POLICY" ] || continue
    GOVERNOR=$(cat "$POLICY/scaling_governor" 2>/dev/null)
    MIN_FREQ=$(cat "$POLICY/scaling_min_freq" 2>/dev/null)
    MAX_FREQ=$(cat "$POLICY/scaling_max_freq" 2>/dev/null)
    echo "I:bixi-recovery-power: $(basename "$POLICY") governor=$GOVERNOR min=$MIN_FREQ max=$MAX_FREQ" >> "$LOG_FILE"
done

exit "$RESULT"
