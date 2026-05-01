#!/bin/sh
set -eu

LABEL="local.quickask"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
UID_VALUE="$(id -u)"

launchctl bootout "gui/$UID_VALUE" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

echo "Uninstalled $PLIST"
