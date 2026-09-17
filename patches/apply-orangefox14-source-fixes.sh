#!/bin/bash
# Local compatibility fixes for the official OrangeFox fox_14.1 source tree.
# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

SOURCE_ROOT="${1:-$PWD}"
TWRP_CPP="$SOURCE_ROOT/bootable/recovery/twrp.cpp"
BOOT_CONTROL_CLIENT_CPP="$SOURCE_ROOT/hardware/interfaces/boot/aidl/client/BootControlClient.cpp"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "$TWRP_CPP" ]; then
    echo "OrangeFox twrp.cpp was not found at: $TWRP_CPP" >&2
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

python3 "$SCRIPT_DIR/apply-bixi-tied-profile-fix.py" "$SOURCE_ROOT"
python3 "$SCRIPT_DIR/update-kernelsu-addons.py" "$SOURCE_ROOT"

echo "OrangeFox 14 source fixes applied successfully."
