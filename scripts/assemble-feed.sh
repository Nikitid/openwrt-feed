#!/bin/sh

# Build and sign the package index over a directory of member APKs prepared by
# scripts/fetch-members.sh.
#
# Only packages that already verify against the tracked publisher key enter the
# index, so a mis-signed or tampered release cannot be republished as trusted.

set -eu

fail() {
	printf 'assemble-feed: %s\n' "$*" >&2
	exit 1
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/feed.env"

sdk="${FEED_SDK_DIR:-}"
signing_key="${FEED_SIGNING_KEY:-}"
apk_dir="${FEED_APK_DIR:-$root/dist/members}"
output="${FEED_OUTPUT:-$root/dist/feed}"
public_key="$root/$FEED_KEY_FILE"

[ -n "$sdk" ] && [ -d "$sdk" ] || fail 'FEED_SDK_DIR is required'
[ -n "$signing_key" ] && [ -r "$signing_key" ] ||
	fail 'FEED_SIGNING_KEY is required'
[ -d "$apk_dir" ] || fail "member APK directory not found: $apk_dir"
[ -r "$public_key" ] || fail "public key not found: $public_key"

case "$(basename "$sdk")" in
	"${FEED_SDK_ARCHIVE%.tar.zst}") ;;
	*) fail "unexpected SDK directory: $(basename "$sdk")" ;;
esac

output_parent="$(dirname "$output")"
output_name="$(basename "$output")"
case "$output_name" in
	'' | . | /) fail 'unsafe feed output path' ;;
esac
[ "$output" != "$root" ] || fail 'feed output must not replace the repository'

for command in openssl python3 sha256sum; do
	command -v "$command" >/dev/null 2>&1 ||
		fail "required command is missing: $command"
done

actual_key_hash="$(sha256sum "$public_key" | awk '{ print $1 }')"
[ "$actual_key_hash" = "$FEED_TRUST_SHA256" ] ||
	fail "public key checksum mismatch: $actual_key_hash"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

# A signing key that does not derive to the tracked public key would produce an
# index no installed router can verify.
openssl ec -in "$signing_key" -pubout -out "$tmp/derived-public.pem" \
	>/dev/null 2>&1 || fail 'invalid EC signing key'
cmp -s "$tmp/derived-public.pem" "$public_key" ||
	fail 'signing key does not match the tracked publisher key'

apk_tool="$sdk/staging_dir/host/bin/apk"
[ -x "$apk_tool" ] || fail "SDK APK tool not found: $apk_tool"

feed="$tmp/feed"
mkdir -p "$feed"
members=''
for candidate in "$apk_dir"/*.apk; do
	[ -f "$candidate" ] || continue
	"$apk_tool" --keys-dir "$root/keys" verify "$candidate" ||
		fail "member APK is not signed by the publisher key: $(basename "$candidate")"
	cp "$candidate" "$feed/$(basename "$candidate")"
	members="$members $(basename "$candidate")"
done
[ -n "$members" ] || fail "no member APK found in $apk_dir"

(
	cd "$feed"
	# shellcheck disable=SC2086
	"$apk_tool" mkndx \
		--keys-dir "$root/keys" \
		--sign-key "$signing_key" \
		--description "$FEED_NAME" \
		--output packages.adb \
		$members
)

cp "$public_key" "$feed/nikitid-openwrt-release.pem"
cp "$root/install.sh" "$feed/install.sh"
chmod 0755 "$feed/install.sh"

(
	cd "$feed"
	# shellcheck disable=SC2086
	sha256sum $members packages.adb nikitid-openwrt-release.pem install.sh \
		>SHA256SUMS
)

FEED_APK_TOOL="$apk_tool" "$root/scripts/verify-feed.sh" "$feed"

mkdir -p "$output_parent"
rm -rf "${output_parent:?}/${output_name:?}"
mv "$feed" "$output"

printf 'feed assembled in %s\n' "$output"
