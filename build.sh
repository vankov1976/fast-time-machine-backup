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
cp "$root/Resources/exclusions.txt" "$resources/exclusions.txt"
cp "$root/Sources/TimeMachineBackup" "$macos/TimeMachineBackup"
chmod 755 "$macos/TimeMachineBackup"

swiftc -O -framework AppKit \
    -o "$macos/BackupMenu" \
    "$root/Sources/main.swift" \
    "$root/Sources/BackupMenu.swift" \
    "$root/Sources/EditExclusions.swift"
chmod 755 "$macos/BackupMenu"

codesign -s - --force "$macos/BackupMenu"
codesign -s - --force "$app"

echo "Built $app"
echo "To install:  cp -R \"$app\" /Applications/"
