#!/bin/sh
#
# Build swanmon 0.1 for the release this feed targets, signed with the
# publisher key, until the release feed carries a swanmon that waits for the
# answer to its event unregistration. Without it every streamed query ("list-sas")
# leaves before charon has answered, and charon logs "vici header write error:
# Broken pipe" each time.
#
# The release's own recipe is used unchanged except for one patch, kept in
# patches/swanmon, and the release number. The release recipe is 0.1-r2; this
# build is r3, so it replaces r2, and the line is dropped together with
# FEED_EXTRAS once the release feed carries the fix.
#
#   FEED_SDK_DIR=/path/to/sdk FEED_SIGNING_KEY=/path/to/key.pem \
#     ./scripts/build-swanmon.sh [output directory]
#
# Without FEED_SIGNING_KEY the package is left unsigned, for a local test.

set -eu

fail() {
	printf 'build-swanmon: %s\n' "$*" >&2
	exit 1
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/feed.env"

sdk="${FEED_SDK_DIR:-}"
signing_key="${FEED_SIGNING_KEY:-}"
output="${1:-$root/dist/swanmon}"
case "$output" in /*) ;; *) output="$PWD/$output" ;; esac
public_key="$root/$FEED_KEY_FILE"

version=0.1
release=3
patch="$root/patches/swanmon/100-wait-for-queued-requests.patch"
patch_hash=905db32e5d5be2658eb219109fd2b4217b2d357bf7ad3cdaf0a477b9b0979a75

[ -n "$sdk" ] && [ -d "$sdk" ] || fail 'FEED_SDK_DIR is required'
case "$(basename "$sdk")" in
	"${FEED_SDK_ARCHIVE%.tar.zst}") ;;
	*) fail "unexpected SDK directory: $(basename "$sdk")" ;;
esac
[ -z "$signing_key" ] || [ -r "$signing_key" ] || fail 'FEED_SIGNING_KEY is not readable'
[ -r "$public_key" ] || fail "public key not found: $public_key"
printf '%s  %s\n' "$patch_hash" "$patch" | sha256sum -c - >/dev/null || fail 'the patch changed'

cd "$sdk"
recipe="$sdk/feeds/packages/utils/swanmon"
for feed in base packages; do
	[ -d "feeds/$feed" ] || ./scripts/feeds update "$feed" >/dev/null
	[ -s "feeds/$feed.index" ] || ./scripts/feeds update -i "$feed" >/dev/null
done
[ -d "$recipe" ] || fail 'the SDK packages feed has no swanmon recipe'
grep -Fxq "PKG_VERSION:=$version" "$recipe/Makefile" || fail "the SDK recipe is not swanmon $version"
grep -Fxq 'PKG_RELEASE:=2' "$recipe/Makefile" || grep -Fxq "PKG_RELEASE:=$release" "$recipe/Makefile" ||
	fail 'the SDK recipe is not the release one'
mkdir -p "$recipe/patches"
cp "$patch" "$recipe/patches/"
sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=$release/" "$recipe/Makefile"

./scripts/feeds uninstall swanmon >/dev/null 2>&1 || :
./scripts/feeds install swanmon >/dev/null
[ -e package/feeds/packages/swanmon ] || fail 'unable to register the swanmon package'
make -C "$sdk" defconfig >/dev/null
sed -i -e '/^CONFIG_PACKAGE_/d' -e '/^# CONFIG_PACKAGE_/d' "$sdk/.config"
printf 'CONFIG_PACKAGE_swanmon=m\n' >>"$sdk/.config"
make -C "$sdk" defconfig >/dev/null
make -C "$sdk" package/feeds/packages/swanmon/clean V=s >/dev/null
make -C "$sdk" -j"$(nproc)" package/feeds/packages/swanmon/compile V=s \
	${signing_key:+BUILD_KEY_APK_SEC="$signing_key" BUILD_KEY_APK_PUB="$public_key"} ||
	fail 'swanmon did not build'

apk_tool="$sdk/staging_dir/host/bin/apk"
[ -x "$apk_tool" ] || fail 'the SDK apk tool is missing'
rm -rf "$output"
mkdir -p "$output"
find "$sdk/bin" -type f -name "swanmon-$version-r$release.apk" -exec cp {} "$output/" \;
package="$output/swanmon-$version-r$release.apk"
[ -e "$package" ] || fail 'the swanmon package was not built'
if [ -n "$signing_key" ]; then
	"$apk_tool" --allow-untrusted adbsign --sign-key "$signing_key" "$package"
	"$apk_tool" --keys-dir "$root/keys" verify "$package" >/dev/null || fail 'package failed verification'
fi
(
	cd "$output"
	sha256sum ./*.apk | sed 's# \./# #' >SHA256SUMS
)
printf 'swanmon %s-r%s in %s%s\n' "$version" "$release" "$output" "$([ -n "$signing_key" ] || echo ', unsigned')"
