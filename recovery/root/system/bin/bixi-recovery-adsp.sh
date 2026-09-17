#!/system/bin/sh

LOG_FILE=/tmp/bixi-recovery-adsp.log
STATE_NODE=/sys/class/remoteproc/remoteproc1/state
NAME_NODE=/sys/class/remoteproc/remoteproc1/name

echo "I:bixi-recovery-adsp: waiting for ADSP remoteproc" > "$LOG_FILE"

i=0
while [ "$i" -lt 20 ]; do
    if [ -e "$STATE_NODE" ] && [ "$(cat "$NAME_NODE" 2>/dev/null)" = "3000000.remoteproc-adsp" ]; then
        break
    fi
    sleep 1
    i=$((i + 1))
done

if [ ! -e "$STATE_NODE" ] || [ "$(cat "$NAME_NODE" 2>/dev/null)" != "3000000.remoteproc-adsp" ]; then
    echo "E:bixi-recovery-adsp: ADSP remoteproc did not appear" >> "$LOG_FILE"
    setprop twrp.adsp.ready false
    exit 1
fi

if [ "$(cat "$STATE_NODE" 2>/dev/null)" != "running" ]; then
    echo start > "$STATE_NODE"
    START_RESULT=$?
    echo "I:bixi-recovery-adsp: start result=$START_RESULT" >> "$LOG_FILE"
    if [ "$START_RESULT" -ne 0 ]; then
        setprop twrp.adsp.ready false
        exit 1
    fi
fi

i=0
while [ "$i" -lt 15 ]; do
    STATE=$(cat "$STATE_NODE" 2>/dev/null)
    if [ "$STATE" = "running" ]; then
        echo "I:bixi-recovery-adsp: state=running" >> "$LOG_FILE"
        setprop twrp.adsp.ready true
        exit 0
    fi
    sleep 1
    i=$((i + 1))
done

echo "E:bixi-recovery-adsp: final state=$STATE" >> "$LOG_FILE"
setprop twrp.adsp.ready false
exit 1
