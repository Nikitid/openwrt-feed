# Repository Guidelines

## Scope

This repository publishes the shared signed APK feed for the Nikitid OpenWrt
LuCI applications. It contains no application code. Application changes belong
in the member repositories listed in `feed.env`.

## Start of Work

- Read `README.md` and `feed.env`.
- Run `git status -sb` and preserve unrelated user changes.
- `main` holds sources. `feed` holds published artifacts and is written only by
  the build workflow; never commit to it by hand.

## Invariants

- One publisher key signs every member package and the index. Do not introduce
  a per-application key: apk binds a key to neither a package nor a repository,
  so an extra key only adds a trust anchor to every router.
- Member applications never push into this repository. They publish their own
  GitHub Release; this repository pulls, verifies and indexes.
- A member without a published release is skipped, never fatal.
- Only packages that already verify against the tracked publisher key may enter
  the index.
- The feed URL is recorded in `/etc/apk/repositories.d` on installed routers.
  Changing `FEED_BASE` or `FEED_BRANCH` strands every router that does not
  re-run `install.sh`; treat it as a migration, not an edit.
- Package transactions in `install.sh` are scoped to the names passed on the
  command line. Never add a blanket `apk upgrade`.

## Verification

- Run `./scripts/check-feed.sh` after changing sources.
- `./scripts/verify-feed.sh` checks an assembled directory independently of the
  script that produced it; keep it that way.

## Secrets

- The signing private key exists only as the `OPENWRT_APK_SIGNING_KEY` Actions
  secret. Never write it into the repository, a log or a build artifact.
- Do not commit private key material, router backups or private network
  identifiers.
