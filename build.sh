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
cp "$root/Sources/TimeMachineBackup" "$resources/backup.sh"
chmod 755 "$resources/backup.sh"

swiftc -O -framework AppKit \
    -o "$macos/BackupMenu" \
    "$root/Sources/main.swift" \
    "$root/Sources/BackupMenu.swift" \
    "$root/Sources/EditExclusions.swift"
chmod 755 "$macos/BackupMenu"

clang -O2 -o "$macos/TimeMachineBackup" "$root/Sources/BackupJob.c"
chmod 755 "$macos/TimeMachineBackup"
# The Login Items row is named from this program. A resource fork blocks signing
# and stops macOS from recording that the job is running.
xattr -cr "$app"
codesign -s - --force --identifier local.fasttimemachine.backup "$macos/BackupMenu"
codesign -s - --force --identifier local.fasttimemachine.backup "$app"
# Login Items shows the icon of this program file. Apply it after signing.
# Signing rejects the icon's resource fork, and clearing attributes removes the icon.
APP="$app" swift - <<'SWIFT'
import AppKit
let app = ProcessInfo.processInfo.environment["APP"]!
let icon = NSImage(contentsOfFile: app + "/Contents/Resources/AppIcon.icns")!
let bin = app + "/Contents/MacOS/TimeMachineBackup"
if !NSWorkspace.shared.setIcon(icon, forFile: bin, options: []) {
    fputs("could not set the Time Machine icon\n", stderr)
    exit(1)
}
SWIFT

echo "Built $app"
echo "To install:  cp -R \"$app\" /Applications/"
