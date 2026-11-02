#!/usr/bin/env bash
set -euo pipefail

# Render the launchd plist by key. Shell substitution treats '&', '|', and
# '\' specially and a failed redirect truncates the destination. plutil writes
# a temp file in the destination directory, lints it, then renames it into place.
render_plist() {
    local binary_path="$1"
    local log_dir="$2"
    local env_file="$3"
    local template="$4"
    local out="$5"

    if [ ! -f "$template" ]; then
        echo "ERROR: template not found: $template" >&2
        return 1
    fi

    local dest_dir tmp
    dest_dir="$(dirname "$out")"
    mkdir -p "$dest_dir"
    tmp="$(mktemp "${dest_dir}/assistant-plist.XXXXXX")"

    if ! cp "$template" "$tmp" \
        || ! plutil -replace ProgramArguments -array "$tmp" \
        || ! plutil -insert ProgramArguments.0 -string "$binary_path" "$tmp" \
        || ! plutil -replace StandardOutPath -string "${log_dir}/core.log" "$tmp" \
        || ! plutil -replace StandardErrorPath -string "${log_dir}/core.log" "$tmp" \
        || ! plutil -replace EnvironmentVariables.ASSISTANT_ENV_FILE -string "$env_file" "$tmp" \
        || ! plutil -lint "$tmp" >/dev/null \
        || [ "$(plutil -extract ProgramArguments json -o - "$tmp" | python3 -c 'import json,sys; a=json.load(sys.stdin); print(len(a))')" != 1 ]; then
        rm -f "$tmp"
        echo "ERROR: failed to render $out" >&2
        return 1
    fi
    mv -f "$tmp" "$out"
}

if [ "${RENDER_ONLY:-}" = "1" ]; then
    : "${BINARY_PATH:?BINARY_PATH is required when RENDER_ONLY=1}"
    : "${LOG_DIR:?LOG_DIR is required when RENDER_ONLY=1}"
    : "${ENV_FILE:?ENV_FILE is required when RENDER_ONLY=1}"
    : "${TEMPLATE:?TEMPLATE is required when RENDER_ONLY=1}"
    : "${OUT:?OUT is required when RENDER_ONLY=1}"
    render_plist "$BINARY_PATH" "$LOG_DIR" "$ENV_FILE" "$TEMPLATE" "$OUT"
    exit 0
fi

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

# Secrets live in <repo root>/.env (gitignored). Seed it from the example on
# first install and keep it owner-only.
ENV_FILE="$REPO_ROOT/.env"
if [ ! -e "$ENV_FILE" ]; then
    cp "$REPO_ROOT/.env.example" "$ENV_FILE"
    echo "Created $ENV_FILE from .env.example. Fill in your keys (or paste them in Settings)."
fi
chmod 600 "$ENV_FILE"

# Render plist with absolute paths. A failed render leaves the installed plist.
render_plist "$BINARY_PATH" "$LOG_DIR" "$ENV_FILE" "$TEMPLATE" "$INSTALLED_PLIST"

# If already loaded, bootout first (idempotent install)
if launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$UID/$LABEL" || true
    # bootout returns before the service is fully removed; bootstrapping too
    # early fails with "Bootstrap failed: 5: Input/output error".
    for _ in $(seq 1 50); do
        launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1 || break
        sleep 0.2
    done
fi

launchctl bootstrap "gui/$UID" "$INSTALLED_PLIST"
launchctl enable "gui/$UID/$LABEL"

echo "Installed LaunchAgent:"
echo "  plist:  $INSTALLED_PLIST"
echo "  binary: $BINARY_PATH"
echo "  log:    $LOG_DIR/core.log"
echo "  env:    $ENV_FILE"
echo ""
echo "Test it:"
echo "  launchctl print gui/\$UID/$LABEL | grep state"
