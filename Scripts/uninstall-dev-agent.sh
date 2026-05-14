#!/usr/bin/env bash
set -euo pipefail

LABEL="com.vishruth.assistant.core"
INSTALLED_PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$UID/$LABEL"
fi

rm -f "$INSTALLED_PLIST"
echo "Uninstalled $LABEL"
