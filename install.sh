#!/bin/sh

# Bootstrap the shared Nikitid OpenWrt application feed on a router, and
# optionally install or upgrade the named packages.
#
#   sh install.sh                          # set up the key and feed only
#   sh install.sh luci-app-ikev2-manager   # and install/upgrade that package
#
# Package transactions are always scoped to the names given here. This script
# never upgrades unrelated packages.

set -eu

FEED_BASE=https://raw.githubusercontent.com/Nikitid/openwrt-feed/feed
FEED_TRUST_SHA256=f27474d9261f1084350cf4ba34ecdff29e533769c36483d8dd85566e30a6a703
FEED_OPENWRT_TARGET=mediatek/filogic
FEED_OPENWRT_ARCH=aarch64_cortex-a53

FEED_BASE="${NIKITID_FEED_BASE:-$FEED_BASE}"
FEED_URL="$FEED_BASE/packages.adb"
KEY_URL="$FEED_BASE/nikitid-openwrt-release.pem"

fail() {
	printf 'Nikitid OpenWrt feed: %s\n' "$*" >&2
	exit 1
}

install_root="${NIKITID_FEED_INSTALL_ROOT:-}"
[ -n "$install_root" ] || [ "$(id -u)" -eq 0 ] ||
	fail 'run this installer as root'

release_file="$install_root/etc/openwrt_release"
[ -r "$release_file" ] || fail 'OpenWrt is required'
. "$release_file"

[ "${DISTRIB_ID:-}" = OpenWrt ] ||
	fail "official OpenWrt is required; found ${DISTRIB_ID:-unknown vendor firmware}"
case "${DISTRIB_RELEASE:-}" in
	25.12.*) ;;
	*) fail "OpenWrt 25.12.x is required; found ${DISTRIB_RELEASE:-unknown}" ;;
esac
[ "${DISTRIB_TARGET:-}" = "$FEED_OPENWRT_TARGET" ] ||
	fail "this feed supports $FEED_OPENWRT_TARGET; found ${DISTRIB_TARGET:-unknown}"
[ "${DISTRIB_ARCH:-}" = "$FEED_OPENWRT_ARCH" ] ||
	fail "this feed supports $FEED_OPENWRT_ARCH; found ${DISTRIB_ARCH:-unknown}"

for command in apk sha256sum wget; do
	command -v "$command" >/dev/null 2>&1 ||
		fail "required command is missing: $command"
done

for package in "$@"; do
	case "$package" in
		'' | *[!A-Za-z0-9+_.-]*) fail "invalid package name: $package" ;;
	esac
done

tmp="$(mktemp -d)"
key_path="$install_root/etc/apk/keys/nikitid-openwrt-release.pem"
repo_dir="$install_root/etc/apk/repositories.d"
repo_path="$repo_dir/nikitid-openwrt.list"
world_path="$install_root/etc/apk/world"
legacy_path="$repo_dir/ikev2-manager.list"
key_added=0
repo_changed=0
world_changed=0
legacy_changed=0
committed=0

# A failed bootstrap must leave the feed configuration exactly as it was. A
# stale new entry would make every later `apk update` report an error, while
# removing the previous entry before the full transaction succeeds would make
# a failed migration irreversible.
cleanup() {
	rc=$?
	if [ "$rc" -ne 0 ] && [ "$committed" -eq 0 ]; then
		[ "$key_added" -eq 0 ] || rm -f "$key_path"
		if [ "$repo_changed" -eq 1 ]; then
			if [ -f "$tmp/repository.previous" ]; then
				cp "$tmp/repository.previous" "$repo_path"
			else
				rm -f "$repo_path"
			fi
		fi
		[ "$world_changed" -eq 0 ] || cp "$tmp/world.previous" "$world_path"
		[ "$legacy_changed" -eq 0 ] ||
			cp "$tmp/legacy.previous" "$legacy_path"
	fi
	rm -rf "$tmp"
	trap - EXIT HUP INT TERM
	exit "$rc"
}
trap cleanup EXIT HUP INT TERM

if [ -e "$key_path" ]; then
	existing_hash="$(sha256sum "$key_path" | awk '{ print $1 }')"
	[ "$existing_hash" = "$FEED_TRUST_SHA256" ] ||
		fail "a different key already exists at $key_path"
else
	wget -q -O "$tmp/publisher.pem" "$KEY_URL" ||
		fail 'unable to download the publisher public key'
	downloaded_hash="$(sha256sum "$tmp/publisher.pem" | awk '{ print $1 }')"
	[ "$downloaded_hash" = "$FEED_TRUST_SHA256" ] ||
		fail "publisher public-key checksum mismatch: $downloaded_hash"
	mkdir -p "$install_root/etc/apk/keys"
	cp "$tmp/publisher.pem" "$key_path"
	chmod 0644 "$key_path"
	key_added=1
fi

mkdir -p "$repo_dir"
printf '%s\n' "$FEED_URL" >"$tmp/feed.list"
if ! cmp -s "$tmp/feed.list" "$repo_path" 2>/dev/null; then
	[ ! -f "$repo_path" ] || cp "$repo_path" "$tmp/repository.previous"
	cp "$tmp/feed.list" "$repo_path"
	chmod 0644 "$repo_path"
	repo_changed=1
fi

# apk refreshes every configured repository. A dead superseded URL therefore
# prevents the new feed from ever proving itself unless that exact legacy entry
# is taken out first. Keep it in the transaction backup and restore it on any
# later failure; a file an operator points elsewhere is left untouched.
if [ -f "$legacy_path" ]; then
	case "$(cat "$legacy_path")" in
		https://raw.githubusercontent.com/Nikitid/ikev2-manager-openwrt/apk-feed/packages.adb | \
		https://raw.githubusercontent.com/Nikitid/ikev2-openwrt/apk-feed/packages.adb | \
		https://github.com/Nikitid/ikev2-manager-openwrt/releases/download/*/packages.adb | \
		https://github.com/Nikitid/ikev2-openwrt/releases/download/*/packages.adb)
			cp "$legacy_path" "$tmp/legacy.previous"
			rm -f "$legacy_path"
			legacy_changed=1
			;;
	esac
fi

# A package installed from a local file leaves an identity constraint in
# /etc/apk/world that pins it to that exact build. The feed publishes a
# different build of the same version, so the constraint silently keeps the
# router on the file it was given and no upgrade ever applies. Release only the
# constraints for packages named here, and only after the key and feed are in
# place, so an unrelated pin an operator set is preserved.
for package in "$@"; do
	[ -r "$world_path" ] || break
	grep -q "^${package}><Q" "$world_path" || continue
	[ "$world_changed" -eq 1 ] || cp "$world_path" "$tmp/world.previous"
	awk -v package="$package" '
		index($0, package "><Q") == 1 { print package; next }
		{ print }
	' "$world_path" >"${world_path}.new" || fail "unable to rewrite $world_path"
	chmod 0644 "${world_path}.new"
	mv "${world_path}.new" "$world_path"
	world_changed=1
	printf 'Released the local-install constraint on %s.\n' "$package"
done

apk update || fail 'package indexes could not be updated'

for package in "$@"; do
	if apk info --installed "$package" >/dev/null 2>&1; then
		apk upgrade --simulate "$package" ||
			fail "upgrade validation failed for $package; nothing was changed"
		apk upgrade "$package" || fail "upgrade failed for $package"
	else
		apk add --simulate "$package" ||
			fail "install validation failed for $package; nothing was changed"
		apk add "$package" || fail "install failed for $package"
	fi
done

# The publisher key used to be installed under an application-specific name.
# The material is identical, so drop the duplicate trust anchor only after the
# feed and every requested package transaction have succeeded.
legacy_key="$install_root/etc/apk/keys/ikev2-manager-release.pem"
if [ -f "$legacy_key" ] && cmp -s "$legacy_key" "$key_path"; then
	rm -f "$legacy_key"
fi

committed=1
[ "$legacy_changed" -eq 0 ] ||
	printf 'Retired the previous feed list: %s\n' "$legacy_path"
printf '\nNikitid OpenWrt feed is configured.\n'
[ "$#" -gt 0 ] || printf 'Install an application with: apk add <package>\n'
