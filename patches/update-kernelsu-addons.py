#!/usr/bin/env python3
"""Overlay local KernelSU LKM files into OrangeFox addon ZIPs.

Standard KernelSU modules are read from prebuilt/kernelsu. KernelSU Next and
SukiSU Ultra modules are read from the next and suki subdirectories. Every
local module is matched by its Android/KMI name, so this works for all packaged
KMIs rather than only the one used by bixi.
"""

from __future__ import annotations

import copy
import hashlib
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import zipfile


MODULE_NAME_RE = re.compile(
    r"(?P<kmi>android\d+-\d+\.\d+)"
    r"(?:[-_]v\d+(?:\.\d+){1,2})?"
    r"(?:_kernelsu)?"
    r"(?:[-_]v\d+(?:\.\d+){1,2})?\.ko$",
    re.IGNORECASE,
)
VERSION_RE = re.compile(
    r"(?:^|[-_])v(?P<version>\d+(?:\.\d+){1,2})(?=(?:[-_]|\.ko$))",
    re.IGNORECASE,
)
MANAGED_BEGIN = "----- BEGIN device/xiaomi/bixi local module overrides -----"
MANAGED_END = "----- END device/xiaomi/bixi local module overrides -----"
EMBEDDED_VERSION_RE = re.compile(
    rb"(?<![A-Za-z0-9])v(?P<version>\d+\.\d+(?:\.\d+)?)"
    rb"(?=$|[^0-9.])",
    re.IGNORECASE,
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def version_tuple(value: str) -> tuple[int, int, int]:
    parts = [int(part) for part in value.split(".")]
    return tuple((parts + [0, 0, 0])[:3])


def validate_aarch64_module(path: Path, data: bytes) -> None:
    if len(data) < 64 or data[:4] != b"\x7fELF":
        raise SystemExit(f"KernelSU module is not an ELF file: {path}")
    if data[4] != 2 or data[5] != 1:
        raise SystemExit(f"KernelSU module is not little-endian ELF64: {path}")
    if int.from_bytes(data[18:20], "little") != 183:  # EM_AARCH64
        raise SystemExit(f"KernelSU module is not for ARM64: {path}")


def classify_module(path: Path) -> tuple[str, tuple[int, int, int] | None]:
    match = MODULE_NAME_RE.search(path.name)
    if match is None:
        raise SystemExit(
            "Unrecognised KernelSU module name: "
            f"{path.name}\nExpected a name ending in "
            "android<version>-<kernel>[_kernelsu][_v<version>].ko"
        )
    entry_name = match.group("kmi").lower() + "_kernelsu.ko"
    version_match = VERSION_RE.search(path.name)
    version = (
        version_tuple(version_match.group("version"))
        if version_match is not None
        else None
    )
    return entry_name, version


def find_overrides(directory: Path) -> dict[str, Path]:
    if not directory.is_dir():
        return {}

    grouped: dict[str, list[tuple[Path, tuple[int, int, int] | None]]] = {}
    for path in sorted(directory.iterdir(), key=lambda item: item.name.lower()):
        if not path.is_file() or path.suffix.lower() != ".ko":
            continue
        entry_name, version = classify_module(path)
        grouped.setdefault(entry_name, []).append((path, version))

    selected: dict[str, Path] = {}
    for entry_name, candidates in grouped.items():
        versioned = [candidate for candidate in candidates if candidate[1] is not None]
        if versioned:
            newest_version = max(candidate[1] for candidate in versioned)
            newest = [candidate for candidate in versioned if candidate[1] == newest_version]
            if len(newest) != 1:
                names = ", ".join(candidate[0].name for candidate in newest)
                raise SystemExit(f"Duplicate newest modules for {entry_name}: {names}")
            selected[entry_name] = newest[0][0]
        elif len(candidates) == 1:
            selected[entry_name] = candidates[0][0]
        else:
            names = ", ".join(candidate[0].name for candidate in candidates)
            raise SystemExit(f"Ambiguous modules for {entry_name}: {names}")
    return selected


def strip_managed_source(source: str) -> str:
    managed = re.compile(
        re.escape(MANAGED_BEGIN) + r".*?" + re.escape(MANAGED_END) + r"\s*",
        re.DOTALL,
    )
    source = managed.sub("", source).strip()

    # Remove metadata produced by the older bixi-only updater.
    old_separator = "Other KMI modules retained from the OrangeFox package:"
    if source.startswith("bixi android15-6.6 module:") and old_separator in source:
        source = source.split(old_separator, 1)[1].strip()

    original_header = "Original OrangeFox source metadata:"
    while source.startswith(original_header):
        source = source[len(original_header) :].lstrip()
    return source


def new_module_info(entry_name: str, source_path: Path) -> zipfile.ZipInfo:
    from datetime import datetime

    # ZIP timestamps cannot be older than 1980.
    timestamp = max(source_path.stat().st_mtime, 315532800)
    date_time = datetime.fromtimestamp(timestamp).timetuple()[:6]
    info = zipfile.ZipInfo(entry_name, date_time=date_time)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.create_system = 3
    info.external_attr = (stat.S_IFREG | 0o644) << 16
    return info


def update_addon(label: str, module_dir: Path, installer_path: Path) -> None:
    overrides = find_overrides(module_dir)
    if not overrides:
        print(f"No local {label} module overrides found in {module_dir}; skipping.")
        return
    if not installer_path.is_file():
        raise SystemExit(f"OrangeFox {label} installer was not found at: {installer_path}")

    module_data: dict[str, bytes] = {}
    module_hashes: dict[str, str] = {}
    for entry_name, path in overrides.items():
        data = path.read_bytes()
        validate_aarch64_module(path, data)
        module_data[entry_name] = data
        module_hashes[entry_name] = sha256(data)

    with zipfile.ZipFile(installer_path, "r") as archive:
        bad_entry = archive.testzip()
        if bad_entry is not None:
            raise SystemExit(f"OrangeFox {label} installer has a bad entry: {bad_entry}")
        original_infos = [copy.copy(info) for info in archive.infolist()]
        original_data = {
            info.filename: archive.read(info.filename)
            for info in archive.infolist()
            if not info.is_dir()
        }
        archive_comment = archive.comment

    source_text = original_data.get("source.txt", b"").decode(
        "utf-8", errors="replace"
    )
    base_source = strip_managed_source(source_text)
    manifest_lines = [MANAGED_BEGIN, f"{label} local modules:"]
    for entry_name in sorted(overrides):
        manifest_lines.extend(
            (
                f"{entry_name}",
                f"file={overrides[entry_name].name}",
                f"sha256={module_hashes[entry_name]}",
            )
        )
    manifest_lines.append(MANAGED_END)
    if base_source:
        manifest_lines.extend(("", "Original OrangeFox source metadata:", base_source))
    new_source = ("\n".join(manifest_lines).rstrip() + "\n").encode("utf-8")

    changed_entries = [
        entry_name
        for entry_name, data in module_data.items()
        if original_data.get(entry_name) != data
    ]
    source_changed = original_data.get("source.txt") != new_source
    if not changed_entries and not source_changed:
        print(f"OrangeFox {label} addon already contains every local module override.")
        return

    mode = stat.S_IMODE(installer_path.stat().st_mode)
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            prefix=installer_path.name + ".",
            suffix=".tmp",
            dir=installer_path.parent,
            delete=False,
        ) as temporary:
            temporary_name = temporary.name

        with zipfile.ZipFile(
            temporary_name, "w", compression=zipfile.ZIP_DEFLATED, allowZip64=True
        ) as archive:
            archive.comment = archive_comment
            written: set[str] = set()
            for info in original_infos:
                name = info.filename
                if name in module_data:
                    archive.writestr(info, module_data[name])
                elif name == "source.txt":
                    archive.writestr(info, new_source)
                elif info.is_dir():
                    archive.writestr(info, b"")
                else:
                    archive.writestr(info, original_data[name])
                written.add(name)

            for entry_name, data in module_data.items():
                if entry_name not in written:
                    archive.writestr(
                        new_module_info(entry_name, overrides[entry_name]), data
                    )
            if "source.txt" not in written:
                archive.writestr("source.txt", new_source)

        with zipfile.ZipFile(temporary_name, "r") as archive:
            bad_entry = archive.testzip()
            if bad_entry is not None:
                raise SystemExit(f"Updated {label} installer has a bad entry: {bad_entry}")
            for entry_name, expected_hash in module_hashes.items():
                actual_hash = sha256(archive.read(entry_name))
                if actual_hash != expected_hash:
                    raise SystemExit(
                        f"Updated {label} installer failed verification for {entry_name}"
                    )

        os.chmod(temporary_name, mode)
        os.replace(temporary_name, installer_path)
        temporary_name = None
    finally:
        if temporary_name is not None:
            Path(temporary_name).unlink(missing_ok=True)

    for entry_name in sorted(changed_entries):
        action = "Added" if entry_name not in original_data else "Updated"
        print(
            f"{action} {label} {entry_name} from {overrides[entry_name].name} "
            f"(sha256={module_hashes[entry_name]})."
        )
    if not changed_entries:
        print(f"Refreshed {label} addon module provenance metadata.")


def versions_in_module(data: bytes) -> list[tuple[int, int, int]]:
    return [
        version_tuple(match.group("version").decode("ascii"))
        for match in EMBEDDED_VERSION_RE.finditer(data)
    ]


def find_addon_version(label: str, module_dir: Path, installer_path: Path) -> str:
    overrides = find_overrides(module_dir)
    embedded_versions: list[tuple[int, int, int]] = []
    filename_versions: list[tuple[int, int, int]] = []

    # KernelSU Next and SukiSU LKMs currently embed strings such as "v3.3.0"
    # and "v4.2.0-904c60d1@main". Standard KernelSU does not always embed a
    # readable release number, so versioned filenames and source.txt remain
    # supported fallbacks.
    for path in overrides.values():
        data = path.read_bytes()
        embedded_versions.extend(versions_in_module(data))
        filename_version = VERSION_RE.search(path.name)
        if filename_version is not None:
            filename_versions.append(
                version_tuple(filename_version.group("version"))
            )

    if embedded_versions:
        return ".".join(str(part) for part in max(embedded_versions))
    if filename_versions:
        return ".".join(str(part) for part in max(filename_versions))

    detected: list[tuple[int, int, int]] = []
    source_text = ""
    with zipfile.ZipFile(installer_path, "r") as archive:
        for info in archive.infolist():
            if info.filename.endswith("_kernelsu.ko"):
                detected.extend(versions_in_module(archive.read(info.filename)))
        if "source.txt" in archive.namelist():
            source_text = archive.read("source.txt").decode(
                "utf-8", errors="replace"
            )

    if not detected:
        # Prefer release URLs over free-form labels such as OrangeFox's old
        # "v4.20" label for the v4.2.0 release.
        for match in re.findall(r"/tag/v(\d+(?:\.\d+){1,2})", source_text):
            detected.append(version_tuple(match))

    if not detected:
        raise SystemExit(
            f"Unable to determine the {label} version from local modules "
            f"or {installer_path}"
        )
    return ".".join(str(part) for part in max(detected))


def sync_addon_theme_version(
    source_root: Path,
    label: str,
    menu_variable: str,
    module_dir: Path,
    installer_path: Path,
) -> None:
    version = find_addon_version(label, module_dir, installer_path)
    theme_path = (
        source_root
        / "bootable"
        / "recovery"
        / "gui"
        / "theme"
        / "portrait_hdpi"
        / "pages"
        / "advanced.xml"
    )
    if not theme_path.is_file():
        raise SystemExit(f"OrangeFox advanced.xml was not found at: {theme_path}")

    text = theme_path.read_text()
    escaped_label = re.escape(label)
    confirmation_re = re.compile(
        r'(<action function="set">fox_m_name=\{@module_install\} '
        + escaped_label
        + r')(?: v?\d+(?:\.\d+){1,2})?(</action>)'
    )
    menu_re = re.compile(
        r'(<listitem name="\{@module_install\} '
        + escaped_label
        + r')(?:(?: %'
        + re.escape(menu_variable)
        + r'%)|(?: v?\d+(?:\.\d+){1,2}))?(">)'
    )
    updated, confirmation_count = confirmation_re.subn(
        rf"\g<1> {version}\g<2>", text, count=1
    )
    updated, menu_count = menu_re.subn(
        rf"\g<1> {version}\g<2>", updated, count=1
    )
    if confirmation_count != 1 or menu_count != 1:
        raise SystemExit(
            f"Unable to find both {label} version labels in "
            f"{theme_path}"
        )
    if updated == text:
        print(f"OrangeFox {label} UI version is already {version}.")
        return
    theme_path.write_text(updated)
    print(f"Updated OrangeFox {label} UI version to {version}.")


if len(sys.argv) != 2:
    raise SystemExit("usage: update-kernelsu-addons.py <orangefox-source-root>")

source_root = Path(sys.argv[1]).resolve()
device_root = Path(__file__).resolve().parent.parent
module_root = device_root / "prebuilt" / "kernelsu"
installer_root = source_root / "vendor" / "recovery" / "Files"

update_addon(
    "KernelSU",
    module_root,
    installer_root / "KernelSU_Installer.zip",
)
update_addon(
    "KernelSU Next",
    module_root / "next",
    installer_root / "KernelSU_Next_Installer.zip",
)
update_addon(
    "SukiSU Ultra",
    module_root / "suki",
    installer_root / "KernelSU_Suki_Installer.zip",
)
sync_addon_theme_version(
    source_root,
    "KernelSU",
    "ksu_ver",
    module_root,
    installer_root / "KernelSU_Installer.zip",
)
sync_addon_theme_version(
    source_root,
    "KernelSU Next",
    "ksun_ver",
    module_root / "next",
    installer_root / "KernelSU_Next_Installer.zip",
)
sync_addon_theme_version(
    source_root,
    "SukiSU Ultra",
    "ssu_ver",
    module_root / "suki",
    installer_root / "KernelSU_Suki_Installer.zip",
)
