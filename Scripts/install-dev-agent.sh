#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$REPO_ROOT/Resources/LaunchAgents/com.vishruth.assistant.core.plist"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
INSTALLED_PLIST="$LAUNCH_AGENT_DIR/com.vishruth.assistant.core.plist"
LOG_DIR="$HOME/Library/Logs/Assistant"
LABEL="com.vishruth.assistant.core"

# Resolve the built daemon binary path
BUILT_PRODUCTS_DIR=$(xcodebuild -project "$REPO_ROOT/Assistant.xcodeproj" \
                                -scheme AssistantCoreHelper \
                                -configuration Debug \
                                -showBuildSettings 2>/dev/null \
                                | awk -F' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR[[:space:]]*=/{print $2; exit}')

if [ -z "${BUILT_PRODUCTS_DIR:-}" ]; then
    echo "ERROR: BUILT_PRODUCTS_DIR not found. Build AssistantCoreHelper first."
    exit 1
fi

BINARY_PATH="$BUILT_PRODUCTS_DIR/AssistantCoreHelper"
if [ ! -x "$BINARY_PATH" ]; then
    echo "ERROR: $BINARY_PATH not executable. Build AssistantCoreHelper first."
    exit 1
fi

mkdir -p "$LAUNCH_AGENT_DIR" "$LOG_DIR"

# Render plist with absolute paths
sed -e "s|__BINARY_PATH__|$BINARY_PATH|g" \
    -e "s|__LOG_DIR__|$LOG_DIR|g" \
    "$TEMPLATE" > "$INSTALLED_PLIST"

# If already loaded, bootout first (idempotent install)
if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$UID/$LABEL" || true
fi

launchctl bootstrap "gui/$UID" "$INSTALLED_PLIST"
launchctl enable "gui/$UID/$LABEL"

echo "Installed LaunchAgent:"
echo "  plist:  $INSTALLED_PLIST"
echo "  binary: $BINARY_PATH"
echo "  log:    $LOG_DIR/core.log"
echo ""
echo "Test it:"
echo "  launchctl print gui/\$UID/$LABEL | grep state"
