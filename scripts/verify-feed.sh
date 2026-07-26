#!/bin/sh

# Independent check of an assembled feed directory: every package and the index
# must verify against the tracked publisher key, the index must actually list
# each package, and the checksum manifest must cover every published file.

set -eu

fail() {
	printf 'verify-feed: %s\n' "$*" >&2
	exit 1
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/feed.env"

feed="${1:-$root/dist/feed}"
apk_tool="${FEED_APK_TOOL:-}"
keys_dir="${FEED_VERIFY_KEYS:-$root/keys}"

[ -d "$feed" ] || fail "feed directory not found: $feed"
[ -n "$apk_tool" ] || fail 'FEED_APK_TOOL is required'
[ -x "$apk_tool" ] || fail "APK tool is not executable: $apk_tool"

index="$feed/packages.adb"
key="$feed/nikitid-openwrt-release.pem"
checksums="$feed/SHA256SUMS"
for required in "$index" "$key" "$checksums" "$feed/install.sh"; do
	[ -r "$required" ] || fail "required feed file is missing: $required"
done

actual="$(sha256sum "$key" | awk '{ print $1 }')"
[ "$actual" = "$FEED_TRUST_SHA256" ] ||
	fail 'published public-key checksum mismatch'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

"$apk_tool" --keys-dir "$keys_dir" verify "$index"
"$apk_tool" --keys-dir "$keys_dir" adbdump --format json \
	"$index" >"$tmp/index.json"

: >"$tmp/published"
for candidate in "$feed"/*.apk; do
	[ -f "$candidate" ] || continue
	"$apk_tool" --keys-dir "$keys_dir" verify "$candidate"
	"$apk_tool" --keys-dir "$keys_dir" adbdump --format json \
		"$candidate" >"$tmp/package.json"
	python3 - "$tmp/index.json" "$tmp/package.json" "$FEED_OPENWRT_ARCH" <<'PY'
import json
import sys


def strings(value):
    if isinstance(value, dict):
        for key, item in value.items():
            yield str(key)
            yield from strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)
    elif isinstance(value, str):
        yield value


def load(path):
    with open(path, encoding="utf-8") as stream:
        return json.load(stream)


index = set(strings(load(sys.argv[1])))
package = load(sys.argv[2])
architecture = sys.argv[3]
values = set(strings(package))

info = package.get("info") or {}
name = info.get("name")
version = info.get("version")
if not name or not version:
    raise SystemExit("package metadata has no name or version")
if name not in index or version not in index:
    raise SystemExit(f"index does not contain {name} {version}")
if info.get("arch") != architecture:
    raise SystemExit(f"{name} is built for {info.get('arch')}, not {architecture}")
if architecture not in values:
    raise SystemExit(f"{name} does not reference {architecture}")
PY
	printf '%s\n' "$(basename "$candidate")" >>"$tmp/published"
done

[ -s "$tmp/published" ] || fail 'feed contains no package'

while IFS= read -r name; do
	grep -Fq "  $name" "$checksums" ||
		fail "checksum manifest does not contain $name"
done <"$tmp/published"
for name in packages.adb nikitid-openwrt-release.pem install.sh; do
	grep -Fq "  $name" "$checksums" ||
		fail "checksum manifest does not contain $name"
done

(
	cd "$feed"
	sha256sum -c SHA256SUMS
)

printf 'feed verification OK\n'
