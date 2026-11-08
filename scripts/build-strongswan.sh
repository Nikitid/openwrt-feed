#!/bin/sh
#
# Build strongSwan 6.0.7 for the release this feed targets, signed with the
# publisher key, until the release feed carries the fix for CVE-2026-78127
# (libcharon: memory leaked for each message logged before authentication).
# OpenWrt 25.12 ships 6.0.7-r1 without it.
#
# The release's own recipe is used unchanged - its patches, init scripts and
# package split are what installed routers run - except for one patch, kept in
# patches/strongswan, taken from the strongSwan security page and verified by
# hash, and the release number. The release recipe is r1; this build is r2, so
# it replaces r1, and the line is dropped together with FEED_EXTRAS once the
# release feed carries the fix.
#
# Every package of the recipe is built, as the release feed builds it: the
# SDK selects them all by default. A router with more strongSwan plugins than
# IKEv2 Manager installs then upgrades those with the rest, instead of keeping
# r1 plugins beside an r2 daemon.
#
#   FEED_SDK_DIR=/path/to/sdk FEED_SIGNING_KEY=/path/to/key.pem \
#     ./scripts/build-strongswan.sh [output directory]
#
# Without FEED_SIGNING_KEY the packages are left unsigned, for a local test.

set -eu

fail() {
	printf 'build-strongswan: %s\n' "$*" >&2
	exit 1
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/feed.env"

sdk="${FEED_SDK_DIR:-}"
signing_key="${FEED_SIGNING_KEY:-}"
output="${1:-$root/dist/extras}"
# A relative directory is the caller's. The build changes into the SDK, and
# the packages of a relative one ended up inside it, where the workflow's next
# step did not look.
case "$output" in /*) ;; *) output="$PWD/$output" ;; esac
public_key="$root/$FEED_KEY_FILE"

version=6.0.7
release=2
patch="$root/patches/strongswan/100-message-log-leak.patch"
patch_hash=288076365021a18c34fa101e12f65f39809122bdd357e31f8bfa6893341bb599
built_packages='strongswan strongswan-charon strongswan-swanctl
strongswan-mod-aes strongswan-mod-attr strongswan-mod-constraints strongswan-mod-des
strongswan-mod-eap-identity strongswan-mod-eap-mschapv2 strongswan-mod-gcm
strongswan-mod-gmp strongswan-mod-hmac strongswan-mod-kdf strongswan-mod-kernel-netlink
strongswan-mod-md4 strongswan-mod-openssl strongswan-mod-pem strongswan-mod-pkcs1
strongswan-mod-pubkey strongswan-mod-random strongswan-mod-sha2
strongswan-mod-socket-default strongswan-mod-vici strongswan-mod-x509'

[ -n "$sdk" ] && [ -d "$sdk" ] || fail 'FEED_SDK_DIR is required'
case "$(basename "$sdk")" in
	"${FEED_SDK_ARCHIVE%.tar.zst}") ;;
	*) fail "unexpected SDK directory: $(basename "$sdk")" ;;
esac
[ -z "$signing_key" ] || [ -r "$signing_key" ] || fail 'FEED_SIGNING_KEY is not readable'
[ -r "$public_key" ] || fail "public key not found: $public_key"
printf '%s  %s\n' "$patch_hash" "$patch" | sha256sum -c - >/dev/null || fail 'the patch changed'

# The feeds script works on the directory it is run in.
cd "$sdk"
recipe="$sdk/feeds/packages/net/strongswan"
# base as well as packages: the recipe builds a host Python, which needs the
# host ncurses from base, and without it fails on its curses module.
for feed in base packages; do
	[ -d "feeds/$feed" ] || ./scripts/feeds update "$feed" >/dev/null
	# An index is built after the checkout; an interrupted run leaves none,
	# and without one "feeds install" registers nothing and still succeeds.
	[ -s "feeds/$feed.index" ] || ./scripts/feeds update -i "$feed" >/dev/null
done
[ -d "$recipe" ] || fail 'the SDK packages feed has no strongswan recipe'
# The release recipe, nothing else: a cached SDK that already holds this
# build's edits is refused rather than edited twice.
grep -Fxq "PKG_VERSION:=$version" "$recipe/Makefile" &&
	grep -Fxq 'PKG_RELEASE:=1' "$recipe/Makefile" ||
	fail "the SDK recipe is not the release's $version-r1 one"
[ ! -e "$recipe/patches/100-message-log-leak.patch" ] ||
	fail 'the SDK recipe already holds this build'"'"'s patch'
cp "$patch" "$recipe/patches/"
sed -i "s/^PKG_RELEASE:=.*/PKG_RELEASE:=$release/" "$recipe/Makefile"
grep -Fxq "PKG_RELEASE:=$release" "$recipe/Makefile" || fail 'unable to set the release'

# Registered again so that its dependencies from base (gmp, openssl) come with
# it: a registration made before base was indexed went without them.
./scripts/feeds uninstall strongswan >/dev/null 2>&1 || :
./scripts/feeds install strongswan >/dev/null
[ -e package/feeds/packages/strongswan ] || fail 'unable to register the strongswan package'
[ -e package/feeds/base/gmp ] && [ -e package/feeds/base/openssl ] ||
	fail "strongSwan's libraries from base were not registered"
# The host Python's own host dependency. A Python registered before base was
# indexed is not given it by the line above, and builds without curses.
./scripts/feeds install -p base ncurses >/dev/null
[ -e package/feeds/base/ncurses ] || fail 'unable to register the host ncurses'
make -C "$sdk" defconfig >/dev/null
# The SDK selects every package by default, so the whole recipe is built.
# The set IKEv2 Manager installs is named as well, so that an SDK configured
# otherwise by an earlier run still builds what the routers of this feed run.
sed -i -e '/^CONFIG_PACKAGE_/d' -e '/^# CONFIG_PACKAGE_/d' "$sdk/.config"
for package in $built_packages; do
	printf 'CONFIG_PACKAGE_%s=m\n' "$package"
done >>"$sdk/.config"
make -C "$sdk" defconfig >/dev/null
make -C "$sdk" package/feeds/packages/strongswan/clean V=s >/dev/null
make -C "$sdk" -j"$(nproc)" package/feeds/packages/strongswan/compile V=s \
	${signing_key:+BUILD_KEY_APK_SEC="$signing_key" BUILD_KEY_APK_PUB="$public_key"} ||
	fail 'strongSwan did not build'

apk_tool="$sdk/staging_dir/host/bin/apk"
[ -x "$apk_tool" ] || fail 'the SDK apk tool is missing'
rm -rf "$output"
mkdir -p "$output"
find "$sdk/bin" -type f -name "strongswan*-$version-r$release.apk" -exec cp {} "$output/" \;
set -- "$output"/strongswan-"$version"-r"$release".apk
[ -e "$1" ] || fail 'the strongswan package was not built'
for package in "$output"/*.apk; do
	[ -n "$signing_key" ] || continue
	"$apk_tool" --allow-untrusted adbsign --sign-key "$signing_key" "$package"
	"$apk_tool" --keys-dir "$root/keys" verify "$package" >/dev/null ||
		fail "package failed verification: ${package##*/}"
done
(
	cd "$output"
	sha256sum ./*.apk | sed 's# \./# #' >SHA256SUMS
)
printf 'strongSwan %s-r%s: %s packages in %s%s\n' "$version" "$release" \
	"$(find "$output" -name '*.apk' | wc -l | tr -d ' ')" "$output" \
	"$([ -n "$signing_key" ] || echo ', unsigned')"
