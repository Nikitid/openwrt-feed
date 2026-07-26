#!/bin/sh

# Static checks over the feed sources. Run before every assembly so a malformed
# member list or a drifted key cannot reach a signed index.

set -eu

fail() {
	printf 'check-feed: %s\n' "$*" >&2
	exit 1
}

root="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
. "$root/feed.env"

public_key="$root/$FEED_KEY_FILE"
[ -r "$public_key" ] || fail "public key not found: $FEED_KEY_FILE"
actual="$(sha256sum "$public_key" | awk '{ print $1 }')"
[ "$actual" = "$FEED_TRUST_SHA256" ] ||
	fail "public key checksum mismatch: $actual"
openssl pkey -pubin -in "$public_key" -noout >/dev/null 2>&1 ||
	fail 'publisher key is not a valid PEM public key'

[ -n "${FEED_MEMBERS:-}" ] || fail 'FEED_MEMBERS is empty'
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
	[ "$repository" != "$package" ] || fail "malformed member entry: $member"
done

# The bootstrap script is fetched by routers before any signature can be
# checked, so its pinned trust anchor must match the tracked key.
grep -Fq "FEED_TRUST_SHA256=$FEED_TRUST_SHA256" "$root/install.sh" ||
	fail 'install.sh trust anchor is out of sync with feed.env'
grep -Fq "FEED_BASE=$FEED_BASE" "$root/install.sh" ||
	fail 'install.sh feed base is out of sync with feed.env'

# Private key material must never be tracked here.
git -C "$root" ls-files --cached --others --exclude-standard |
	grep -Ei '(^|/)[^/]*(private|signing|secret)[^/]*\.(pem|key|der)$' &&
	fail 'private signing material is tracked'
key_list="$(mktemp)"
git -C "$root" ls-files --cached --others --exclude-standard |
	grep -Ei '\.(pem|key|der|p8|p12|pfx)$' >"$key_list" || :
while IFS= read -r candidate; do
	[ -f "$root/$candidate" ] || continue
	if grep -qE 'BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY' "$root/$candidate"; then
		rm -f "$key_list"
		fail "tracked file contains private key material: $candidate"
	fi
done <"$key_list"
rm -f "$key_list"

for script in install.sh scripts/fetch-members.sh scripts/assemble-feed.sh \
		scripts/verify-feed.sh scripts/check-feed.sh scripts/test-install.sh; do
	sh -n "$root/$script" || fail "shell syntax error: $script"
done

"$root/scripts/test-install.sh"

printf 'check-feed OK\n'
