# Nikitid APK feed for OpenWrt

[Русский](README.ru.md)

[![CI](https://github.com/Nikitid/openwrt-feed/actions/workflows/build-feed.yml/badge.svg)](https://github.com/Nikitid/openwrt-feed/actions/workflows/build-feed.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Signed package index for the Nikitid LuCI applications. One publisher key signs
every member package and the index. apk binds a key to neither a package nor a
repository, so a router needs exactly one trust anchor and one feed entry for
all applications.

## Features

- one feed entry and one key for every Nikitid application;
- the installer checks the publisher key against a pinned checksum;
- only the named packages are installed and upgraded, never the whole router;
- the index rebuilds itself whenever any application publishes a release.

## Requirements

- OpenWrt `25.12.x` with `apk`;
- target `mediatek/filogic`, architecture `aarch64_cortex-a53`.

## Installation

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

| Application | Package and repository |
| --- | --- |
| IKEv2 Manager | [`luci-app-ikev2-manager`](https://github.com/Nikitid/luci-app-ikev2-manager) |
| Overview Manager | [`luci-app-overview-manager`](https://github.com/Nikitid/luci-app-overview-manager) |
| MTProto Monitor | [`luci-app-mtproto-monitor`](https://github.com/Nikitid/luci-app-mtproto-monitor) |
| IKEv2 Site Link | [`luci-app-ikev2-site-link`](https://github.com/Nikitid/luci-app-ikev2-site-link) |
| Wi-Fi QR | [`luci-app-wrqr`](https://github.com/Nikitid/luci-app-wrqr) |

Members are listed in [`feed.env`](feed.env). Day-to-day work is described in
[Operations](docs/OPERATIONS.md); what a member repository must implement is in
[Member integration](docs/MEMBER_INTEGRATION.md). A member without a published
release is skipped, so an application can be listed before it ships and a
stalled one never blocks the others.

## Development

```sh
./scripts/check-feed.sh
```

How the feed is built, its layout and keys: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Documentation

- [Repository map](docs/MAP.md) - where things live
- [Operations](docs/OPERATIONS.md)
- [Becoming a member](docs/MEMBER_INTEGRATION.md)
- [Development](docs/DEVELOPMENT.md) - how the feed is built, its layout and keys

## Support

Questions and bug reports go to
[Issues](https://github.com/Nikitid/openwrt-feed/issues/new/choose): pick the form that
fits. Report a vulnerability privately through
[a security advisory](https://github.com/Nikitid/openwrt-feed/security/advisories/new).
English or Russian is fine.

## License

[MIT](LICENSE).
