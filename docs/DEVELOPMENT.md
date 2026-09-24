# Development

## Checks

```sh
./scripts/check-feed.sh
```

Checks the feed sources, the build workflow, the installer and both READMEs.

## How it is built

Application repositories do not write here. Each one publishes its own GitHub
Release containing an APK already signed with the publisher key. This
repository downloads the current release of every member, verifies each
signature, builds `packages.adb` over them, signs the index and publishes the
result to the `feed` branch.

```text
application repo -> GitHub Release (signed .apk)
                                     |
                        openwrt-feed -> feed branch -> router
```

The build runs on `repository_dispatch` (type `member-release`), on manual
dispatch, and daily as a fallback so a missed notification cannot leave the
index stale.

## Layout

- `main` - sources: member list, publisher public key, build and check scripts.
- `feed` - published artifacts: `packages.adb`, member APKs, the public key,
  `install.sh` and `SHA256SUMS`.

Keeping the feed in its own repository is deliberate. It previously lived on a
branch of one application repository, which meant renaming that application
moved a URL recorded in `/etc/apk/repositories.d` on every installed router.

## Keys

`keys/nikitid-openwrt-release.pem` is the shared publisher public key.

```text
f27474d9261f1084350cf4ba34ecdff29e533769c36483d8dd85566e30a6a703
```

The private half is not stored in any repository. Builds read it from the
`OPENWRT_APK_SIGNING_KEY` GitHub Actions secret, which must be configured
identically here and in every member repository.

Losing the private key requires a rotation bootstrap on every installed router.
Exposing it allows an attacker to publish a trusted package for every
application in the feed.
