# Nikitid OpenWrt APK feed

Signed package index for the Nikitid LuCI applications on OpenWrt `25.12.x`,
target `mediatek/filogic`, architecture `aarch64_cortex-a53`.

One publisher key signs every member package and the index. apk binds a key to
neither a package nor a repository, so a router needs exactly one trust anchor
and one feed entry for all applications.

## Install

```sh
wget -O /tmp/nikitid-feed.sh \
  https://raw.githubusercontent.com/Nikitid/openwrt-feed/feed/install.sh
sh /tmp/nikitid-feed.sh luci-app-ikev2-manager
```

The installer verifies the publisher key against a pinned checksum, writes
`/etc/apk/repositories.d/nikitid-openwrt.list`, retires the per-application feed
list used before this repository existed, and installs only the packages named
on its command line. Running it without arguments configures the feed alone.

Updates are always scoped to a package:

```sh
apk update
apk upgrade luci-app-ikev2-manager
```

## Members

| Application | Repository | Package |
| --- | --- | --- |
| IKEv2 Manager | [ikev2-openwrt](https://github.com/Nikitid/ikev2-openwrt) | `luci-app-ikev2-manager` |
| Overview Manager | [luci-layout](https://github.com/Nikitid/luci-layout) | `luci-app-overview-manager` |
| MTProto Monitor | [luci-mtproto](https://github.com/Nikitid/luci-mtproto) | `luci-app-mtproto-monitor` |

Members are listed in [`feed.env`](feed.env); what a member repository must do is described in [Member integration](docs/MEMBER_INTEGRATION.md). A member without a published
release is skipped, so an application can be listed before it ships and a
stalled one never blocks the others.

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

- `main` — sources: member list, publisher public key, build and check scripts.
- `feed` — published artifacts: `packages.adb`, member APKs, the public key,
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

## License

[MIT](LICENSE).
