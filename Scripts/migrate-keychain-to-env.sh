#!/usr/bin/env bash
# One-time move of Assistant's secrets from the macOS Keychain into <repo>/.env.
#
#   Scripts/migrate-keychain-to-env.sh           copy Keychain values into .env
#   Scripts/migrate-keychain-to-env.sh --delete  ...then delete the Keychain items
#
# Only fills keys that are missing or empty in .env; never overwrites a value
# already there. "Empty" is decided on the parsed value, with the same rules
# the app uses (Sources/AssistantLLM/Secrets/EnvFile.swift): quotes, escapes,
# inline comments — so KEY="" and KEY= # note both count as empty.
#
# --delete removes a Keychain item only after reading .env back and finding
# exactly the Keychain value there. If .env holds a different value, the
# Keychain copy is kept and reported.
#
# Writes hold the same advisory lock as the app (flock on
# "<resolved .env path>.lock"), so a running daemon can't lose an update.
# macOS may prompt for your login password per item.
#
# For testing only: MIGRATE_ENV_FILE overrides the .env path and
# MIGRATE_SECURITY_BIN replaces the `security` binary (e.g. with a stub).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="${MIGRATE_ENV_FILE:-$REPO_ROOT/.env}"
SECURITY="${MIGRATE_SECURITY_BIN:-security}"
SERVICE="com.vishruth.assistant"
DELETE=0
[ "${1:-}" = "--delete" ] && DELETE=1

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

[ -e "$ENV_FILE" ] || [ ! -e "$REPO_ROOT/.env.example" ] || cp "$REPO_ROOT/.env.example" "$ENV_FILE"
[ -e "$ENV_FILE" ] && chmod 600 "$ENV_FILE"

HELPER_DIR="$(mktemp -d)"
trap 'rm -rf "$HELPER_DIR"' EXIT
ENVTOOL="$HELPER_DIR/envtool.py"

# envtool.py get <file> <KEY>           print the parsed value ("" if absent)
# envtool.py set-if-empty <file> <KEY>  value on stdin; exit 3 if already set
cat > "$ENVTOOL" <<'PY'
import fcntl, os, sys, unicodedata, uuid

def ws(c):
    return c in " \t" or unicodedata.category(c) == "Zs"

def trim(s):
    a, b = 0, len(s)
    while a < b and ws(s[a]): a += 1
    while b > a and ws(s[b - 1]): b -= 1
    return s[a:b]

def valid_key(k):
    if not k or not (k[0] == "_" or k[0].isalpha()): return False
    return all(c == "_" or (c.isascii() and c.isalnum()) for c in k)

def decode(raw):
    if raw.startswith('"'):
        out, esc = [], False
        for ch in raw[1:]:
            if esc:
                if ch == "n": out.append("\n")
                elif ch in '"\\': out.append(ch)
                else: out.append("\\" + ch)
                esc = False
            elif ch == "\\": esc = True
            elif ch == '"': return "".join(out)
            else: out.append(ch)
        return "".join(out)
    if raw.startswith("'"):
        body = raw[1:]
        i = body.find("'")
        return body if i < 0 else body[:i]
    value, prev = raw, " "
    for i, ch in enumerate(raw):
        if ch == "#" and prev in " \t":
            value = raw[:i]
            break
        prev = ch
    return trim(value)

def parse(line):
    rest = line.lstrip(" \t")
    if not rest or rest.startswith("#"): return None
    if rest.startswith("export "): rest = rest[len("export "):]
    eq = rest.find("=")
    if eq < 0: return None
    key = trim(rest[:eq])
    if not valid_key(key): return None
    return key, decode(rest[eq + 1:].lstrip(" \t"))

SAFE = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:+=@,%~")

def encode(v):
    if all(c in SAFE for c in v): return v
    return '"' + v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'

def resolve(path):
    path = os.path.normpath(os.path.abspath(path))
    for _ in range(32):
        try: dest = os.readlink(path)
        except OSError: break
        path = os.path.normpath(dest if os.path.isabs(dest) else os.path.join(os.path.dirname(path), dest))
    return path

def read_lines(path):
    try:
        with open(path, "rb") as f: text = f.read().decode("utf-8")
    except FileNotFoundError:
        text = ""
    raw = text.split("\n")
    if raw and raw[-1] == "": raw.pop()
    return [l[:-1] if l.endswith("\r") else l for l in raw]

def value_of(lines, key):
    for l in reversed(lines):
        p = parse(l)
        if p and p[0] == key: return p[1]
    return None

def atomic_write(target, text):
    d = os.path.dirname(target)
    tmp = os.path.join(d, ".%s.tmp-%s" % (os.path.basename(target), uuid.uuid4()))
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(fd, text.encode("utf-8"))
        os.fchmod(fd, 0o600)
        os.fsync(fd)
        os.close(fd)
        os.rename(tmp, target)
    except BaseException:
        try: os.unlink(tmp)
        except OSError: pass
        raise

def main():
    cmd, path, key = sys.argv[1:4]
    target = resolve(path)
    if cmd == "get":
        sys.stdout.write(value_of(read_lines(target), key) or "")
        return 0
    if cmd != "set-if-empty": return 2
    value = sys.stdin.read()
    os.makedirs(os.path.dirname(target), exist_ok=True)
    lock = os.open(target + ".lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        os.fchmod(lock, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)   # same lock as SecretStore
        lines = read_lines(target)
        if value_of(lines, key): return 3
        new, replaced = [], False
        for l in lines:
            p = parse(l)
            if p and p[0] == key:
                if replaced: continue
                replaced = True
                new.append(key + "=" + encode(value))
            else:
                new.append(l)
        if not replaced: new.append(key + "=" + encode(value))
        atomic_write(target, "\n".join(new) + "\n" if new else "")
        return 0
    finally:
        fcntl.flock(lock, fcntl.LOCK_UN)
        os.close(lock)

sys.exit(main())
PY

env_get() { python3 -I "$ENVTOOL" get "$ENV_FILE" "$1"; }

# keychain account -> .env variable
PAIRS="claude_api_key:ANTHROPIC_API_KEY
openai_api_key:OPENAI_API_KEY
gemma_hosted_api_key:GEMMA_HOSTED_API_KEY
google_oauth_client_secret:GOOGLE_OAUTH_CLIENT_SECRET
google_oauth_refresh_token:GOOGLE_OAUTH_REFRESH_TOKEN"

while IFS=: read -r account var; do
    if ! value="$("$SECURITY" find-generic-password -s "$SERVICE" -a "$account" -w 2>/dev/null)" \
        || [ -z "$value" ]; then
        echo "none  $var (not in Keychain)"
        continue
    fi

    status=0
    printf '%s' "$value" | python3 -I "$ENVTOOL" set-if-empty "$ENV_FILE" "$var" || status=$?
    case "$status" in
        0) echo "moved $var" ;;
        3) echo "skip  $var (already set in .env)" ;;
        *) echo "error $var (could not write .env; Keychain item kept)" >&2; continue ;;
    esac

    if [ "$DELETE" = 1 ]; then
        if [ "$(env_get "$var")" = "$value" ]; then
            "$SECURITY" delete-generic-password -s "$SERVICE" -a "$account" >/dev/null 2>&1 \
                && echo "      deleted Keychain item $account" || true
        else
            echo "      kept Keychain item $account (.env value differs from the Keychain copy)"
        fi
    fi
done <<< "$PAIRS"

echo ""
echo "Done. Secrets file: $ENV_FILE"
[ "$DELETE" = 1 ] || echo "Re-run with --delete once the app works, to remove the Keychain copies."
