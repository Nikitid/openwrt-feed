# Repository map

The shared signed APK feed. It builds no application of its own: it collects
released assets from the member repositories and publishes one signed index
every router installs from. The packages it builds are upstream ones,
swanmon and strongSwan, while the release feed lacks a fix.

## The shape of it

| file | owns |
| --- | --- |
| `install.sh` | what a router runs once: trust anchor and feed entry |
| `scripts/fetch-members.sh` | pulls each member's released APK, and the packages of the releases in `FEED_EXTRAS` |
| `scripts/build-swanmon.sh` | swanmon 0.1-r3, waiting for charon to answer its event unregistration |
| `.github/workflows/build-swanmon.yml` | builds it by hand, publishes it as a release here, rebuilds the feed |
| `scripts/build-strongswan.sh` | strongSwan 6.0.7-r2: the release recipe plus the fix for CVE-2026-78127 (`patches/strongswan`) |
| `.github/workflows/build-strongswan.yml` | the same, by hand, for strongSwan |
| `scripts/assemble-feed.sh` | builds and signs the index |
| `scripts/verify-feed.sh` | proves the published index is installable |
| `scripts/check-feed.sh` | validates the member list before a build |
| `scripts/test-install.sh` | exercises `install.sh` against fixtures |
| `feed.env` | pinned SDK, target and feed identity |
| `keys/` | publisher public key |

Members publish their own releases and never write here; this repository only
reads their release assets. `docs/MEMBER_INTEGRATION.md` is the contract a
member has to meet.

## The one trap worth knowing

A member's release does **not** reach the routers on its own. The dispatch that
should trigger a feed build is not configured, so the workflow's notification
step reports success while nothing arrives. After every member tag someone has
to run:

```
gh workflow run "Build feed" --repo Nikitid/openwrt-feed
```

Until `OPENWRT_FEED_DISPATCH_TOKEN` exists, a published release that skipped
this step is invisible to `apk update`. Several already were.

## Documentation

| file | for |
| --- | --- |
| `docs/MAP.md` | this file |
| `docs/DEVELOPMENT.md` | how the feed is built, its layout and keys |
| `docs/MEMBER_INTEGRATION.md` | what a member repository must provide |
| `docs/OPERATIONS.md` | running and recovering the feed |
| `docs/private/` | site-specific notes, untracked |
