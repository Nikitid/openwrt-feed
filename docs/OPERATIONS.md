# Operations

Day-to-day work with the shared feed. Nothing here is environment-specific;
site details belong in a local runbook that is not published.

## The model

Three places hold something:

```text
workstation            GitHub                         router
application sources    builds and signs               installs packages
publisher private key  keeps a copy as an Actions     keeps the publisher
(never committed)      secret                         public key
```

Four repositories: three applications and this feed.

```text
ikev2-openwrt  ─┐
luci-layout    ─┼─→  openwrt-feed  ─→  router
luci-mtproto   ─┘
```

Applications never write here. Each publishes its own signed APK as a GitHub
Release asset. This repository collects the current release of every member,
verifies each signature against the publisher key, builds and signs the index,
and pushes it to the `feed` branch. A member without a release is skipped, so
one application is never blocked by another.

One publisher key signs every package and the index. apk binds a key to neither
a package nor a repository, so a router needs exactly one trust anchor and one
feed entry for all applications. A per-application key would add another anchor
to every router without adding isolation.

## Releasing a new version of an existing application

1. Change the code.
2. Raise the version in `release.env`, and in the OpenWrt `Makefile` if the
   project keeps literals there. The version-sync check fails on drift.
3. Record the change in `CHANGELOG.md`.
4. Commit, push, and tag. The tag must match the version exactly: version
   `1.2.3` means tag `v1.2.3`, which the release workflow verifies.
5. Rebuild the index once the release is published:

   ```sh
   gh workflow run "Build feed" --repo Nikitid/openwrt-feed
   ```

   Skipping this is fine — the feed also rebuilds daily.

On the router:

```sh
apk update
apk upgrade luci-app-ikev2-manager
```

Always name the package. A bare `apk upgrade` would touch every installed
package on the router, including kernel modules tied to the running kernel.

## Adding another application

In the new repository:

1. Track the shared public key as `keys/nikitid-openwrt-release.pem`. Do not
   generate a new one.
2. Copy the release workflow from an existing member. It must build and sign
   only its own package and publish it as a release asset; it must not
   assemble an index or download sibling applications.
3. Name the asset `<package>-<version>.apk`. The fetcher matches exactly that
   shape and fails if a release contains more than one match.
4. Do not add a bootstrap script. Point the README at the shared installer.

Then publish it and give it the signing key:

```sh
gh repo create Nikitid/<repo> --public --source . --push
gh secret set OPENWRT_APK_SIGNING_KEY --repo Nikitid/<repo> < <private key path>
```

Finally register it here by appending `owner/repo:package` to `FEED_MEMBERS` in
[`feed.env`](../feed.env), then run `./scripts/check-feed.sh`. A member may be
listed before it has ever released; it is skipped until it has.

The full contract is in [Member integration](MEMBER_INTEGRATION.md).

## Installing on a router

```sh
wget -O /tmp/nikitid-feed.sh \
  https://raw.githubusercontent.com/Nikitid/openwrt-feed/feed/install.sh
sh /tmp/nikitid-feed.sh luci-app-ikev2-manager
```

Several packages can be named at once. Running it with no arguments configures
the key and the feed entry without installing anything.

The installer verifies the publisher key against a pinned checksum, writes
`/etc/apk/repositories.d/nikitid-openwrt.list`, retires the per-application feed
list and duplicate key left by earlier releases, releases stale local-install
constraints for the packages named, and installs or upgrades only those
packages. A failed index refresh rolls all of that back.

## Never install a package from a file

```sh
apk add /tmp/some-package.apk     # do not do this
```

apk records an identity constraint in `/etc/apk/world` pinning that package to
that exact build. The feed publishes a different build, so the constraint keeps
the router on the file it was given — and it does so silently: `apk update`
succeeds, `apk upgrade <package>` reports nothing to do, and the router looks
healthy while never updating again.

Check for it with:

```sh
grep '><Q' /etc/apk/world
```

A name followed by `><Q...` is pinned. Running the shared installer with that
package name releases the constraint.

## Notifying the feed automatically

A release can tell this repository to rebuild immediately instead of waiting
for the schedule. That requires a token with `contents: write` on this
repository, stored as `OPENWRT_FEED_DISPATCH_TOKEN` in each member repository.

This is deliberately not configured. The only gain is latency, while the cost
is a write-capable account token copied into every member repository — a wider
credential than the signing key, which can only do one thing. A manual
`gh workflow run` achieves the same result immediately. If it is ever wanted,
use a fine-grained token scoped to this single repository with no permission
other than `contents: write`.

The notification step is written to succeed when the secret is absent, so its
absence never fails a release.

## Checking the feed

```sh
curl -s https://raw.githubusercontent.com/Nikitid/openwrt-feed/feed/SHA256SUMS
```

Lists every published package, the index, the public key and the installer.

To validate a locally assembled feed independently of the script that produced
it:

```sh
FEED_APK_TOOL=<sdk>/staging_dir/host/bin/apk ./scripts/verify-feed.sh dist/feed
```

## Keys

`keys/nikitid-openwrt-release.pem` is the publisher public key, checksum
`f27474d9261f1084350cf4ba34ecdff29e533769c36483d8dd85566e30a6a703`.

The private half is never committed. It exists on the maintainer workstation
and as the `OPENWRT_APK_SIGNING_KEY` Actions secret in this repository and in
every member repository. GitHub secrets are write-only, so the value cannot be
read back from a repository.

Losing the private key requires installing a new trust anchor by hand on every
router, because a replacement key cannot be delivered inside a signed package —
nothing would be able to verify it.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `apk update` reports `1 unavailable` | The feed branch has no index yet, or the URL is wrong. Official feeds keep working. |
| A package never upgrades, no error | Local-install constraint in `/etc/apk/world`. See above. |
| Feed build fails on `Assemble signed feed` | Usually a member APK not signed by the publisher key, or a release containing more than one matching asset. |
| Feed build fails on `Prepare publisher signing key` | `OPENWRT_APK_SIGNING_KEY` is missing in this repository. |
| A member is missing from the index | It has no published release, or its asset is not named `<package>-<version>.apk`. |
