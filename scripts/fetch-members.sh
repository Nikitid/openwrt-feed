#!/bin/sh

# Download the current release APK of every member application into one
# directory. Kept separate from assembly so the index build can be exercised
# offline against a prepared directory.
#
# A member without a published release is skipped with a notice: a newly listed
# application may not have shipped yet, and a stalled one must not block the
# others.

set -eu

fail() {
	printf 'fetch-members: %s\n' "$*" >&2
	exit 1
}

note() {
	printf 'fetch-members: %s\n' "$*"
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/feed.env"

output="${1:-${FEED_APK_DIR:-$root/dist/members}}"
command -v gh >/dev/null 2>&1 || fail 'gh is required'

rm -rf "$output"
mkdir -p "$output"

found=0
for member in $FEED_MEMBERS; do
	repository="${member%%:*}"
	package="${member#*:}"
	case "$repository" in
		*/*) ;;
		*) fail "invalid member repository: $member" ;;
	esac
	case "$package" in
		'' | *[!A-Za-z0-9+_.-]*) fail "invalid member package: $member" ;;
	esac

	staging="$output/.staging"
	rm -rf "$staging"
	mkdir -p "$staging"
	if ! gh release download --repo "$repository" \
		--pattern "$package-*.apk" --dir "$staging" >/dev/null 2>&1; then
		note "no published release yet, skipping: $repository ($package)"
		rm -rf "$staging"
		continue
	fi

	count=0
	candidate=''
	for entry in "$staging/$package"-*.apk; do
		[ -f "$entry" ] || continue
		count=$((count + 1))
		candidate="$entry"
	done
	[ "$count" -eq 1 ] ||
		fail "expected one $package APK in the latest $repository release, found $count"

	mv "$candidate" "$output/$(basename "$candidate")"
	rm -rf "$staging"
	found=$((found + 1))
	note "fetched $(basename "$candidate") from $repository"
done

[ "$found" -gt 0 ] || fail 'no member application has a published release'
printf '%s\n' "$output"
