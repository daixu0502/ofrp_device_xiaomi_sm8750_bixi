#!/bin/bash
# Local compatibility fixes for the official OrangeFox fox_14.1 source tree.
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

SOURCE_ROOT="${1:-$PWD}"
TWRP_CPP="$SOURCE_ROOT/bootable/recovery/twrp.cpp"
GUI_CPP="$SOURCE_ROOT/bootable/recovery/gui/gui.cpp"
BOOT_CONTROL_CLIENT_CPP="$SOURCE_ROOT/hardware/interfaces/boot/aidl/client/BootControlClient.cpp"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$TWRP_CPP" ]; then
    echo "OrangeFox twrp.cpp was not found at: $TWRP_CPP" >&2
    exit 1
fi

if [ ! -f "$GUI_CPP" ]; then
    echo "OrangeFox gui.cpp was not found at: $GUI_CPP" >&2
    exit 1
fi

if [ ! -f "$BOOT_CONTROL_CLIENT_CPP" ]; then
    echo "BootControlClient.cpp was not found at: $BOOT_CONTROL_CLIENT_CPP" >&2
    exit 1
fi

python3 - "$TWRP_CPP" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

include_anchor = '#include "FsCrypt.h"\n#include "Decrypt.h"\n'
include_replacement = (
    '#include <android/binder_auto_utils.h>\n'
    '#include <android/binder_manager.h>\n'
    '#include "FsCrypt.h"\n'
    '#include "Decrypt.h"\n'
)

if '#include <android/binder_manager.h>' not in text:
    if include_anchor not in text:
        raise SystemExit("Unable to find the crypto include block in twrp.cpp")
    text = text.replace(include_anchor, include_replacement, 1)

old_call = '''#ifdef TW_INCLUDE_CRYPTO
\tandroid::keystore::copySqliteDb();
#endif
'''

new_call = '''#ifdef TW_INCLUDE_CRYPTO
\t// copySqliteDb() calls waitForService() internally. If the stock KeyMint
\t// service cannot register, Keystore2 keeps crashing and that unbounded wait
\t// holds the only recovery/UI thread on the splash screen forever.
\tstatic constexpr const char* kKeystoreService =
\t\t\t"android.system.keystore2.IKeystoreService/default";
\tndk::SpAIBinder keystore_service(
\t\t\tAServiceManager_checkService(kKeystoreService));
\tif (keystore_service.get() != nullptr) {
\t\tandroid::keystore::copySqliteDb();
\t} else {
\t\tLOGINFO("Keystore2 is unavailable; skipping startup database sync\\n");
\t}
#endif
'''

if 'Keystore2 is unavailable; skipping startup database sync' in text:
    print("OrangeFox 14 Keystore startup guard is already applied.")
elif old_call in text:
    text = text.replace(old_call, new_call, 1)
    print("Added a non-blocking Keystore2 guard before copySqliteDb().")
else:
    raise SystemExit("Unable to find the expected copySqliteDb() call in twrp.cpp")

path.write_text(text)
PY

python3 - "$BOOT_CONTROL_CLIENT_CPP" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old_lookup = """ndk::SpAIBinder(AServiceManager_waitForService(instance_name.c_str()))"""
new_lookup = """ndk::SpAIBinder(AServiceManager_checkService(instance_name.c_str()))"""

old_error = """is declared but waitForService returned nullptr."""
new_error = """is declared but is not running; continuing without boot control."""

if new_lookup in text:
    print("OrangeFox 14 non-blocking Boot Control lookup is already applied.")
elif old_lookup in text:
    text = text.replace(old_lookup, new_lookup, 1)
    text = text.replace(old_error, new_error, 1)
    print("Changed the AIDL Boot Control lookup from an infinite wait to checkService().")
else:
    raise SystemExit("Unable to find the expected AIDL Boot Control wait in BootControlClient.cpp")

path.write_text(text)
PY

python3 - "$GUI_CPP" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old_state = '''static long long g_suppress_power_toggle_until_ms = 0;
static inline long long nowMs() { struct timeval t; gettimeofday(&t, NULL); return (long long)t.tv_sec * 1000LL + t.tv_usec / 1000; }
'''
new_state = '''// A screenshot chord may be held for longer than a fixed timeout. Keep the
// suppression armed until the POWER key is actually released.
static bool g_suppress_next_power_toggle = false;
'''

old_arm = '''\t\t\tg_suppress_power_toggle_until_ms = nowMs() + 1000; // prevent screen-off from power key after screenshot
'''
new_arm = '''\t\t\tg_suppress_next_power_toggle = true;
'''

old_release = '''\t\t\t\tlong long now = nowMs();
\t\t\t\tif (now < g_suppress_power_toggle_until_ms) {
\t\t\t\t\tLOGEVENT("Skipping POWER toggle due to recent screenshot\\n");
\t\t\t\t} else {
\t\t\t\t\tblankTimer.toggleBlank();
\t\t\t\t}
'''
previous_release = '''\t\t\t\tif (g_suppress_next_power_toggle) {
\t\t\t\t\tg_suppress_next_power_toggle = false;
\t\t\t\t\tLOGEVENT("Skipping POWER toggle after screenshot chord\\n");
\t\t\t\t} else {
\t\t\t\t\tblankTimer.toggleBlank();
\t\t\t\t}
'''
new_release = '''\t\t\t\tif (g_suppress_next_power_toggle) {
\t\t\t\t\tg_suppress_next_power_toggle = false;
\t\t\t\t\tLOGEVENT("Skipping POWER toggle after screenshot chord\\n");
\t\t\t\t} else if (key_status != KS_KEY_REPEAT) {
\t\t\t\t\tblankTimer.toggleBlank();
\t\t\t\t}
'''

old_power_release_condition = '''\t\t} else {
\t\t\tif (ev.code == KEY_POWER && key_status != KS_KEY_REPEAT) {
'''
new_power_release_condition = '''\t\t} else {
\t\t\tif (ev.code == KEY_POWER) {
'''

bad_hardware_power_condition = '''\t\t\t\tif (ev.code == KEY_POWER) {
\t\t\t\t\tLOGEVENT("POWER Key Released\\n");
\t\t\t\t\tPageManager::SelectFocusedElement(false);
\t\t\t\t}
'''
hardware_power_condition = '''\t\t\t\tif (ev.code == KEY_POWER && key_status != KS_KEY_REPEAT) {
\t\t\t\t\tLOGEVENT("POWER Key Released\\n");
\t\t\t\t\tPageManager::SelectFocusedElement(false);
\t\t\t\t}
'''

old_keydown = '''\t\tif (kb->KeyDown(ev.code) >= 0) {
\t\t\t// Key repeat is enabled for this key
'''
previous_keydown = '''\t\tif (kb->KeyDown(ev.code) >= 0) {
\t\t\t// Some devices continuously emit EV_KEY repeat events, resetting the
\t\t\t// hold timer before the original 200 ms chord handler can run. Trigger
\t\t\t// the screenshot as soon as the second physical key goes down.
\t\t\tif (ev.value == 1 && !g_suppress_next_power_toggle &&
\t\t\t\tkb->AreKeysPressed(KEY_VOLUMEDOWN, KEY_POWER)) {
\t\t\t\tg_suppress_next_power_toggle = true;
\t\t\t\tGUIAction::screenshotImpl("");
\t\t\t\tDataManager::Vibrate("tw_button_vibrate");
\t\t\t\tkb->ConsumeKeyRelease(KEY_VOLUMEDOWN);
\t\t\t\tkb->ConsumeKeyRelease(KEY_POWER);
\t\t\t\tkey_status = KS_KEY_REPEAT;
\t\t\t\ttouch_status = TS_NONE;
\t\t\t\treturn;
\t\t\t}

\t\t\t// Key repeat is enabled for this key
'''
new_keydown = '''\t\tif (kb->KeyDown(ev.code) >= 0) {
\t\t\t// Some devices continuously emit EV_KEY repeat events, resetting the
\t\t\t// hold timer before the original 200 ms chord handler can run. Trigger
\t\t\t// the screenshot as soon as the second physical key goes down.
\t\t\tif (ev.value == 1 && !g_suppress_next_power_toggle &&
\t\t\t\tkb->AreKeysPressed(KEY_VOLUMEDOWN, KEY_POWER)) {
\t\t\t\tg_suppress_next_power_toggle = true;
\t\t\t\tLOGINFO("Screenshot chord detected; suppressing POWER release\\n");
\t\t\t\tGUIAction::screenshotImpl("");
\t\t\t\tDataManager::Vibrate("tw_button_vibrate");
\t\t\t\tkb->ConsumeKeyRelease(KEY_VOLUMEDOWN);
\t\t\t\tkb->ConsumeKeyRelease(KEY_POWER);
\t\t\t\tkey_status = KS_KEY_REPEAT;
\t\t\t\ttouch_status = TS_NONE;
\t\t\t\treturn;
\t\t\t}

\t\t\t// Key repeat is enabled for this key
'''

changed = False
for name, alternatives, new in (
    ("timer state", (old_state,), new_state),
    ("screenshot arm", (old_arm,), new_arm),
    ("power release", (old_release, previous_release), new_release),
    (
        "power release condition",
        (old_power_release_condition,),
        new_power_release_condition,
    ),
    (
        "hardware-control power release condition",
        (bad_hardware_power_condition,),
        hardware_power_condition,
    ),
    (
        "immediate chord handler",
        (old_keydown, previous_keydown),
        new_keydown,
    ),
):
    if new in text:
        continue
    old = next((candidate for candidate in alternatives if candidate in text), None)
    if old is None:
        raise SystemExit(
            f"Unable to apply the screenshot power-key fix; missing: {name}"
        )
    text = text.replace(old, new, 1)
    changed = True

if changed:
    path.write_text(text)
    print("Enabled immediate screenshot chord handling and safe POWER release.")
else:
    print("OrangeFox screenshot power-key fix is already applied.")
PY

python3 "$SCRIPT_DIR/apply-bixi-tied-profile-fix.py" "$SOURCE_ROOT"
python3 "$SCRIPT_DIR/update-kernelsu-addons.py" "$SOURCE_ROOT"

echo "OrangeFox 14 source fixes applied successfully."
