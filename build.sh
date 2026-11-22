#!/bin/bash
# Assemble TimeMachineBackup.app from the sources in this folder.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
app="$root/build/TimeMachineBackup.app"
macos="$app/Contents/MacOS"
resources="$app/Contents/Resources"

rm -rf "$app"
mkdir -p "$macos" "$resources"

cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$resources/AppIcon.icns"
cp "$root/Sources/TimeMachineBackup" "$macos/TimeMachineBackup"
chmod 755 "$macos/TimeMachineBackup"

swiftc -O -framework AppKit \
    -o "$macos/BackupMenu" \
    "$root/Sources/main.swift" \
    "$root/Sources/BackupMenu.swift" \
    "$root/Sources/EditExclusions.swift"
chmod 755 "$macos/BackupMenu"

codesign -s - --force "$macos/BackupMenu"

# Login Items uses the icon of the executable. A shell script otherwise shows
# the Terminal icon, so the Time Machine icon is attached to that file.
# A resource-fork icon cannot be sealed by codesign, so the bundle is left unsigned.
swift - "$macos/TimeMachineBackup" "$resources/AppIcon.icns" <<'SWIFT'
import AppKit
let ok = NSWorkspace.shared.setIcon(NSImage(contentsOfFile: CommandLine.arguments[2])!, forFile: CommandLine.arguments[1], options: [])
if !ok { fputs("Could not set the executable icon\n", stderr); exit(1) }
SWIFT
codesign --remove-signature "$app" 2>/dev/null || true

echo "Built $app"
echo "To install:  cp -R \"$app\" /Applications/"
