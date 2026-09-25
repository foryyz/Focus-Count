#!/usr/bin/env python3
"""Package the built app, validate the ZIP, and archive older releases safely."""
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


def version_tuple(value):
    if not re.fullmatch(r"\d+\.\d+\.\d+", value):
        raise ValueError(f"Invalid release version: {value}")
    return tuple(map(int, value.split(".")))


def main():
    root = Path(__file__).resolve().parent.parent
    output = root / "dist/macos"
    app = output / "FocusCount.app"
    with (app / "Contents/Info.plist").open("rb") as file:
        version = plistlib.load(file)["CFBundleShortVersionString"]
    current = version_tuple(version)
    history = output / "history"
    older = []
    for archive in sorted(output.glob("FocusCount-*-macOS.zip")):
        match = re.fullmatch(r"FocusCount-(\d+\.\d+\.\d+)-macOS.zip", archive.name)
        if not match:
            continue
        release = version_tuple(match[1])
        if release > current:
            raise RuntimeError(f"A newer ZIP exists: {archive.name}; build the latest version first.")
        if release < current:
            if (history / archive.name).exists():
                raise FileExistsError(f"Archive already exists; nothing overwritten: {history / archive.name}")
            older.append(archive)
    filename = f"FocusCount-{version}-macOS.zip"
    # Replace the current package only after successful packaging and validation.
    with tempfile.TemporaryDirectory(prefix=".package-", dir=output) as temporary:
        package = Path(temporary) / filename
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(package)], check=True)
        subprocess.run(["unzip", "-tq", str(package)], check=True)
        package.replace(output / filename)
    history.mkdir(exist_ok=True)
    for archive in older:
        archive.rename(history / archive.name)
    print(f"Latest: {output / filename}")
    print(f"Archived {len(older)} older release(s) to {history}")


if __name__ == "__main__":
    main()
