#!/bin/sh
#
# Build strongSwan 6.0.7 for the release this feed targets, signed with the
# publisher key, until the release feed carries a version with the fix for
# CVE-2026-47895 (EAP server). OpenWrt 25.12 ships 6.0.3.
#
# The release's own recipe is used unchanged - its init scripts and package
# split are what installed routers run - except for the upstream version, its
# source hash and the three patches, which are taken refreshed for 6.0.7 from a
# pinned commit of the development branch and verified by hash. Its newer
# recipe is not used: it moves eap-mschapv2 behind an "insecure" option and
# rewrites the UCI schema of the init script.
#
# The release is r0, below any r1 the release feed publishes for the same
# version, so an official build replaces this one as soon as it appears.
#
# The packages are the set IKEv2 Manager installs, which is what routers
# using this feed run, and what they pull in. Every package of the recipe
# drags in bash and a host Python as well, and other plugins need libraries
# from the packages feed; a router with more strongSwan plugins than this keeps
# 6.0.3 for them, which IKEv2 Manager's readiness check reports.
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
public_key="$root/$FEED_KEY_FILE"

version=6.0.7
release=0
source_hash=e518e34e159514f4c6ba80d1f926cb151e0dd4e3a1d94213171234b8b9ae6f55
patch_commit=95d73ebcc95ade2ea78b0a281898cf8b6ec7b7f9
patches='
0903-updown-Call-sbin-hotplug-call-ipsec-1-in-updown-scri.patch 7f83be9b09b9992dad36c882cd88cdecaffbc4edbf3d91dbddcf30d6aa8fae45
0904-gmpdh-Plugin-that-implements-gmp-DH-functions-in-an-.patch 6889536d3d028038ec27391e5a199b6da318367841a0bd6c36647335f3d3f5e7
0905-wolfssl-Adapt-to-removed-ML-KEM-header.patch 9357d65feebfc79f6527ddcc51a8cdac74e15c1738f788d5f1999a8e541aceb8
'
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
grep -Fxq 'PKG_VERSION:=6.0.3' "$recipe/Makefile" ||
	fail "the SDK recipe is not the release's 6.0.3 one"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT INT TERM
printf '%s\n' "$patches" | while read -r name hash; do
	[ -n "$name" ] || continue
	curl -fsSL -o "$work/$name" \
		"https://raw.githubusercontent.com/openwrt/packages/$patch_commit/net/strongswan/patches/$name"
	printf '%s  %s\n' "$hash" "$work/$name" | sha256sum -c - >/dev/null ||
		fail "patch failed verification: $name"
done
rm -f "$recipe"/patches/*.patch
cp "$work"/*.patch "$recipe/patches/"
sed -i \
	-e "s/^PKG_VERSION:=6\.0\.3$/PKG_VERSION:=$version/" \
	-e "s/^PKG_RELEASE:=.*/PKG_RELEASE:=$release/" \
	-e "s/^PKG_HASH:=.*/PKG_HASH:=$source_hash/" \
	"$recipe/Makefile"
grep -Fxq "PKG_VERSION:=$version" "$recipe/Makefile" &&
	grep -Fxq "PKG_RELEASE:=$release" "$recipe/Makefile" &&
	grep -Fxq "PKG_HASH:=$source_hash" "$recipe/Makefile" ||
	fail 'unable to set the version'

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
# Only the set above and what it needs. The SDK selects every package by
# default, and a selection a cached SDK kept from another run would stay; both
# go. It still packages every kernel module, a fixed default of its own,
# whenever the configuration changed.
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
