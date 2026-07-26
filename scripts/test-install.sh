#!/bin/sh

# The bootstrap runs as root on a live router before any signature can be
# checked, and a half-applied run leaves every later `apk update` broken. Drive
# it against a sandbox root with stubbed apk and wget.

set -eu

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM

. "$root/feed.env"

legacy_url='https://raw.githubusercontent.com/Nikitid/ikev2-openwrt/apk-feed/packages.adb'

mkdir -p "$tmp/bin"
cat >"$tmp/bin/apk" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$APK_LOG"
case "${1:-}" in
	update)
		[ "${APK_UPDATE_FAILS:-0}" = 1 ] && exit 1
		[ "${APK_UPDATE_FAILS_WITH_LEGACY:-0}" = 1 ] &&
			[ -e "$LEGACY_PATH" ] && exit 1
		;;
	info) exit "${APK_INSTALLED_RC:-1}" ;;
	add | upgrade) [ "${APK_TRANSACTION_FAILS:-0}" = 1 ] && exit 1 ;;
esac
exit 0
EOF
cat >"$tmp/bin/wget" <<'EOF'
#!/bin/sh
target=''
while [ "$#" -gt 0 ]; do
	case "$1" in
		-O) target="$2"; shift 2 ;;
		-*) shift ;;
		*) shift ;;
	esac
done
cp "$SERVED_KEY" "$target"
EOF
chmod +x "$tmp/bin/apk" "$tmp/bin/wget"

new_root() {
	rm -rf "$tmp/root"
	mkdir -p "$tmp/root/etc/apk/keys" "$tmp/root/etc/apk/repositories.d"
	cat >"$tmp/root/etc/openwrt_release" <<EOF
DISTRIB_ID='OpenWrt'
DISTRIB_RELEASE='$FEED_OPENWRT_VERSION'
DISTRIB_TARGET='$FEED_OPENWRT_TARGET'
DISTRIB_ARCH='$FEED_OPENWRT_ARCH'
EOF
	: >"$tmp/apk.log"
}

# In POSIX sh, assignments in front of a *function* call persist in the shell
# after it returns, so the failure flag is kept explicit instead.
APK_UPDATE_FAILS=0
APK_UPDATE_FAILS_WITH_LEGACY=0
APK_TRANSACTION_FAILS=0

run() {
	PATH="$tmp/bin:$PATH" \
	APK_LOG="$tmp/apk.log" \
	APK_UPDATE_FAILS="$APK_UPDATE_FAILS" \
	APK_UPDATE_FAILS_WITH_LEGACY="$APK_UPDATE_FAILS_WITH_LEGACY" \
	APK_TRANSACTION_FAILS="$APK_TRANSACTION_FAILS" \
	LEGACY_PATH="$legacy_path" \
	SERVED_KEY="$root/$FEED_KEY_FILE" \
	NIKITID_FEED_INSTALL_ROOT="$tmp/root" \
		sh "$root/install.sh" "$@" >"$tmp/out" 2>&1
}

key_path="$tmp/root/etc/apk/keys/nikitid-openwrt-release.pem"
list_path="$tmp/root/etc/apk/repositories.d/nikitid-openwrt.list"
legacy_path="$tmp/root/etc/apk/repositories.d/ikev2-manager.list"

# A clean install writes exactly one trust anchor and one feed entry, and only
# touches the package it was given.
new_root
run luci-app-ikev2-manager
cmp -s "$key_path" "$root/$FEED_KEY_FILE" || {
	printf 'publisher key was not installed\n' >&2
	exit 1
}
[ "$(cat "$list_path")" = "$FEED_URL" ] || {
	printf 'feed list was not written\n' >&2
	exit 1
}
grep -qx 'update' "$tmp/apk.log"
grep -qx 'add --simulate luci-app-ikev2-manager' "$tmp/apk.log"
grep -qx 'add luci-app-ikev2-manager' "$tmp/apk.log"
grep -q 'upgrade' "$tmp/apk.log" && {
	printf 'a fresh install must not upgrade anything\n' >&2
	exit 1
}

# Configuring the feed without naming a package installs nothing.
new_root
run
grep -qx 'update' "$tmp/apk.log"
grep -qE '^(add|upgrade)' "$tmp/apk.log" && {
	printf 'no package was named yet a transaction ran\n' >&2
	exit 1
}

# A failed index refresh must leave the router exactly as it was.
new_root
printf '%s\n' "$legacy_url" >"$legacy_path"
APK_UPDATE_FAILS=1
if run luci-app-ikev2-manager; then
	APK_UPDATE_FAILS=0
	printf 'bootstrap succeeded despite a failed index refresh\n' >&2
	exit 1
fi
APK_UPDATE_FAILS=0
[ ! -e "$key_path" ] || {
	printf 'a failed bootstrap left its trust anchor behind\n' >&2
	exit 1
}
[ ! -e "$list_path" ] || {
	printf 'a failed bootstrap left a stale feed entry behind\n' >&2
	exit 1
}
[ "$(cat "$legacy_path")" = "$legacy_url" ] || {
	printf 'a failed bootstrap did not restore the previous feed list\n' >&2
	exit 1
}

# A dead superseded feed must be taken out before apk refreshes every
# repository. The stub makes update fail while that file exists, reproducing
# the failure mode seen when the old URL returns 404.
new_root
printf '%s\n' "$legacy_url" >"$legacy_path"
cp "$root/$FEED_KEY_FILE" "$tmp/root/etc/apk/keys/ikev2-manager-release.pem"
APK_UPDATE_FAILS_WITH_LEGACY=1
run luci-app-ikev2-manager
APK_UPDATE_FAILS_WITH_LEGACY=0
[ ! -e "$legacy_path" ] || {
	printf 'the superseded feed list was kept\n' >&2
	exit 1
}
[ ! -e "$tmp/root/etc/apk/keys/ikev2-manager-release.pem" ] || {
	printf 'the duplicate trust anchor was kept\n' >&2
	exit 1
}
[ "$(cat "$list_path")" = "$FEED_URL" ]

# A package installed from a local file is pinned to that exact build in
# /etc/apk/world. Unless the constraint is released, the feed can never upgrade
# it and the router silently stays on the file it was given.
new_root
world="$tmp/root/etc/apk/world"
cat >"$world" <<'WORLD'
luci-app-ikev2-manager><Q1hnFhYbfQVZRKz8zs/MXTAMqO7bY=
luci-app-overview-manager><Q1MiEeB7sku9/2/VREGukFdpCzV2U=
busybox
WORLD
run luci-app-ikev2-manager
grep -qx 'luci-app-ikev2-manager' "$world" || {
	printf 'the local-install constraint was not released\n' >&2
	exit 1
}
grep -qx 'luci-app-overview-manager><Q1MiEeB7sku9/2/VREGukFdpCzV2U=' "$world" || {
	printf 'a constraint for a package we were not given was touched\n' >&2
	exit 1
}
grep -qx 'busybox' "$world" || {
	printf 'an unrelated world entry was lost\n' >&2
	exit 1
}

# A failed refresh restores the constraints it released.
new_root
cat >"$world" <<'WORLD'
luci-app-ikev2-manager><Q1hnFhYbfQVZRKz8zs/MXTAMqO7bY=
WORLD
APK_UPDATE_FAILS=1
if run luci-app-ikev2-manager; then
	APK_UPDATE_FAILS=0
	printf 'bootstrap succeeded despite a failed index refresh\n' >&2
	exit 1
fi
APK_UPDATE_FAILS=0
grep -qx 'luci-app-ikev2-manager><Q1hnFhYbfQVZRKz8zs/MXTAMqO7bY=' "$world" || {
	printf 'a failed bootstrap did not restore the world constraint\n' >&2
	exit 1
}

# A package transaction failure after a successful refresh restores the
# previous feed entry and every configuration file changed by the bootstrap.
new_root
printf '%s\n' "$legacy_url" >"$legacy_path"
cat >"$world" <<'WORLD'
luci-app-ikev2-manager><Q1hnFhYbfQVZRKz8zs/MXTAMqO7bY=
WORLD
APK_TRANSACTION_FAILS=1
if run luci-app-ikev2-manager; then
	APK_TRANSACTION_FAILS=0
	printf 'bootstrap succeeded despite a failed package transaction\n' >&2
	exit 1
fi
APK_TRANSACTION_FAILS=0
[ ! -e "$key_path" ] || {
	printf 'a failed package transaction left its trust anchor behind\n' >&2
	exit 1
}
[ ! -e "$list_path" ] || {
	printf 'a failed package transaction left a stale feed entry behind\n' >&2
	exit 1
}
[ "$(cat "$legacy_path")" = "$legacy_url" ] || {
	printf 'a failed package transaction did not restore the previous feed\n' >&2
	exit 1
}
grep -qx 'luci-app-ikev2-manager><Q1hnFhYbfQVZRKz8zs/MXTAMqO7bY=' "$world" || {
	printf 'a failed package transaction did not restore the world constraint\n' >&2
	exit 1
}

# A list an operator or another project points elsewhere is never touched.
new_root
foreign='https://example.invalid/custom/packages.adb'
printf '%s\n' "$foreign" >"$legacy_path"
run luci-app-ikev2-manager
[ "$(cat "$legacy_path")" = "$foreign" ] || {
	printf 'a foreign feed list was rewritten\n' >&2
	exit 1
}

# A different key already sitting at our path is a hard stop, never an
# overwrite.
new_root
printf 'not the publisher key\n' >"$key_path"
if run luci-app-ikev2-manager; then
	printf 'bootstrap overwrote a foreign trust anchor\n' >&2
	exit 1
fi
[ "$(cat "$key_path")" = 'not the publisher key' ]

# An unsupported target is rejected before anything is written.
new_root
sed 's|^DISTRIB_TARGET=.*|DISTRIB_TARGET='"'"'x86/64'"'"'|' \
	"$tmp/root/etc/openwrt_release" >"$tmp/release.new"
mv "$tmp/release.new" "$tmp/root/etc/openwrt_release"
if run luci-app-ikev2-manager; then
	printf 'bootstrap accepted an unsupported target\n' >&2
	exit 1
fi
[ ! -e "$list_path" ] && [ ! -e "$key_path" ] || {
	printf 'an unsupported target still changed the router\n' >&2
	exit 1
}

# An invalid package name never reaches the package manager.
new_root
if run 'luci-app; rm -rf /'; then
	printf 'bootstrap accepted an invalid package name\n' >&2
	exit 1
fi

printf 'install bootstrap tests OK\n'
