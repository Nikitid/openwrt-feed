# APK-фид Nikitid для OpenWrt

[English](README.md)

[![CI](https://github.com/Nikitid/openwrt-feed/actions/workflows/build-feed.yml/badge.svg)](https://github.com/Nikitid/openwrt-feed/actions/workflows/build-feed.yml)
[![Лицензия: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Подписанный индекс пакетов для приложений LuCI от Nikitid. Один издательский
ключ подписывает и каждый пакет, и сам индекс. apk не привязывает ключ ни к
пакету, ни к репозиторию, поэтому роутеру нужен ровно один якорь доверия и одна
запись фида на все приложения.

## Возможности

- одна запись фида и один ключ на все приложения Nikitid;
- установщик сверяет ключ издателя с закреплённой контрольной суммой;
- ставятся и обновляются только названные пакеты, роутер целиком не
  обновляется;
- индекс пересобирается сам при выходе релиза любого приложения.

## Требования

- OpenWrt `25.12.x` с `apk`;
- цель `mediatek/filogic`, архитектура `aarch64_cortex-a53`.

## Установка

```sh
wget -O /tmp/nikitid-feed.sh \
  https://raw.githubusercontent.com/Nikitid/openwrt-feed/feed/install.sh
sh /tmp/nikitid-feed.sh luci-app-ikev2-manager
```

Установщик сверяет издательский ключ с закреплённой контрольной суммой,
записывает `/etc/apk/repositories.d/nikitid-openwrt.list`, убирает старый
однопакетный список фида и ставит только те пакеты, которые названы в
аргументах. Запуск без аргументов настраивает только сам фид.

Обновление всегда с именем пакета - роутер целиком не обновляется:

```sh
apk update
apk upgrade luci-app-ikev2-manager
```

## Участники

| Приложение | Пакет и репозиторий |
| --- | --- |
| IKEv2 Manager | [`luci-app-ikev2-manager`](https://github.com/Nikitid/luci-app-ikev2-manager) |
| Overview Manager | [`luci-app-overview-manager`](https://github.com/Nikitid/luci-app-overview-manager) |
| MTProto Monitor | [`luci-app-mtproto-monitor`](https://github.com/Nikitid/luci-app-mtproto-monitor) |
| IKEv2 Site Link | [`luci-app-ikev2-site-link`](https://github.com/Nikitid/luci-app-ikev2-site-link) |
| Wi-Fi QR | [`luci-app-wrqr`](https://github.com/Nikitid/luci-app-wrqr) |

Список участников - в [`feed.env`](feed.env). Участник без опубликованного
релиза пропускается: приложение можно внести в список до первого выпуска, и
застрявшее не блокирует остальные.

## Разработка

```sh
./scripts/check-feed.sh
```

Как собирается фид, его устройство и ключи: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Документация

- [Карта репозитория](docs/MAP.md) - где что лежит
- [Эксплуатация](docs/OPERATIONS.md)
- [Как стать участником](docs/MEMBER_INTEGRATION.md)
- [Разработка](docs/DEVELOPMENT.md) - как собирается фид, устройство и ключи

## Поддержка

Вопросы и сообщения об ошибках - в
[Issues](https://github.com/Nikitid/openwrt-feed/issues/new/choose), выберите
подходящую форму. Об уязвимости сообщайте приватно через
[security advisory](https://github.com/Nikitid/openwrt-feed/security/advisories/new).
Можно писать по-русски или по-английски.

## Лицензия

[MIT](LICENSE).
