# Joining the shared feed

What a member application repository must do. `Nikitid/ikev2-openwrt` is the
reference implementation.

## Contract

1. **One publisher key.** Use `keys/nikitid-openwrt-release.pem`, public-file
   SHA-256 `f27474d9261f1084350cf4ba34ecdff29e533769c36483d8dd85566e30a6a703`.
   Do not keep a per-application key: apk binds a key to neither a package nor a
   repository, so a second key only adds another trust anchor to every router
   without adding isolation. The private half is the `OPENWRT_APK_SIGNING_KEY`
   Actions secret and must be configured identically in every member repository.

2. **Build and sign only your own package.** A stable tag builds the APK with
   the pinned OpenWrt SDK, signs it with the publisher key and publishes it as a
   GitHub Release asset named `<package>-<version>.apk`. Do not download sibling
   applications and do not build an index; a release must not depend on any
   other application being ready.

3. **Do not write to this repository.** Notify it instead, best effort:

   ```sh
   gh api repos/Nikitid/openwrt-feed/dispatches --method POST \
     --field event_type=member-release \
     --field "client_payload[repository]=$GITHUB_REPOSITORY" \
     --field "client_payload[tag]=$GITHUB_REF_NAME"
   ```

   This needs a token with `contents: write` on `Nikitid/openwrt-feed`, stored
   as `OPENWRT_FEED_DISPATCH_TOKEN`. The step must be `continue-on-error` and
   must succeed when the secret is absent: the feed also rebuilds daily and on
   manual dispatch, so a missing token delays the index instead of failing a
   release.

4. **No bootstrap script of your own.** Point documentation at the shared
   installer, which sets up one trust anchor and one feed entry and installs
   only the packages it is given:

   ```sh
   wget -O /tmp/nikitid-feed.sh \
     https://raw.githubusercontent.com/Nikitid/openwrt-feed/feed/install.sh
   sh /tmp/nikitid-feed.sh <package>
   ```

5. **Never upgrade the whole router.** Every documented and scripted package
   transaction names the packages it touches. No blanket `apk upgrade`.

## If the application already shipped from its own feed

Routers already trusting a different key and pointing at a different index need
a rotation bootstrap, and it must ship *before* the switch:

1. Publish one more release **signed with the current key** whose package
   postinst installs the shared public key into `/etc/apk/keys/` and rewrites
   its own feed list to the shared URL. Rewrite only a list that still holds
   exactly one of that application's own previous URLs; never touch a list
   pointing elsewhere, and never overwrite an existing shared list.
2. Only after that release has propagated, switch the repository to the shared
   key and join the feed.

An application that has never published a release has no such problem: replace
the key and join directly.

## Registration

Add the member to `FEED_MEMBERS` in `feed.env` as `owner/repo:package`, then run
`./scripts/check-feed.sh`. A member without a published release is skipped, so
it can be listed before it ships.
