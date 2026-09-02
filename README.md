# APK-фид Nikitid для OpenWrt

[English](README.en.md)

Подписанный индекс пакетов для приложений LuCI от Nikitid: OpenWrt `25.12.x`,
цель `mediatek/filogic`, архитектура `aarch64_cortex-a53`.

Один издательский ключ подписывает и каждый пакет, и сам индекс. apk не
привязывает ключ ни к пакету, ни к репозиторию, поэтому роутеру нужен ровно
один якорь доверия и одна запись фида на все приложения.

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

Обновление всегда с именем пакета — роутер целиком не обновляется:

```sh
apk update
apk upgrade luci-app-ikev2-manager
```

## Участники

| Приложение | Репозиторий | Пакет |
| --- | --- | --- |
| IKEv2 Manager | [ikev2-openwrt](https://github.com/Nikitid/ikev2-openwrt) | `luci-app-ikev2-manager` |
| Overview Manager | [luci-layout](https://github.com/Nikitid/luci-layout) | `luci-app-overview-manager` |
| MTProto Monitor | [luci-mtproto](https://github.com/Nikitid/luci-mtproto) | `luci-app-mtproto-monitor` |
| IKEv2 Site Link | [ikev2-site-link-openwrt](https://github.com/Nikitid/ikev2-site-link-openwrt) | `luci-app-ikev2-site-link` |
| Wi-Fi QR | [luci-wrqr](https://github.com/Nikitid/luci-wrqr) | `luci-app-wrqr` |

Список участников — в [`feed.env`](feed.env). Участник без опубликованного
релиза пропускается: приложение можно внести в список до первого выпуска, и
застрявшее не блокирует остальные.

## Как это собирается

Репозитории приложений сюда не пишут. Каждый публикует свой релиз на GitHub с
APK, уже подписанным издательским ключом. Этот репозиторий скачивает текущий
релиз каждого участника, проверяет подписи, собирает по ним `packages.adb`,
подписывает индекс и публикует результат в ветку `feed`.

```text
репозиторий приложения -> релиз GitHub (подписанный .apk)
                                        |
                           openwrt-feed -> ветка feed -> роутер
```

Сборка запускается по `repository_dispatch` (тип `member-release`), вручную и
раз в сутки как страховка, чтобы пропущенное уведомление не оставило индекс
устаревшим.

## Устройство

- `main` — исходники: список участников, публичный ключ, скрипты сборки и
  проверок.
- `feed` — опубликованное: `packages.adb`, APK участников, публичный ключ,
  `install.sh` и `SHA256SUMS`.

Отдельный репозиторий для фида — осознанное решение. Раньше он жил веткой
одного из приложений, и переименование того приложения двигало URL, записанный
в `/etc/apk/repositories.d` на каждом установленном роутере.

## Ключи

`keys/nikitid-openwrt-release.pem` — общий публичный ключ издателя.

```text
f27474d9261f1084350cf4ba34ecdff29e533769c36483d8dd85566e30a6a703
```

Приватная половина не хранится ни в одном репозитории. Сборки читают её из
секрета `OPENWRT_APK_SIGNING_KEY` в GitHub Actions, одинакового здесь и в
каждом репозитории-участнике.

Потеря приватного ключа потребует загрузочной ротации на каждом установленном
роутере. Утечка позволит опубликовать доверенный пакет от имени любого
приложения фида.

## Документация

- [Карта репозитория](docs/MAP.md) — где что лежит
- [Эксплуатация](docs/OPERATIONS.md)
- [Как стать участником](docs/MEMBER_INTEGRATION.md)
- [Правила работы](AGENTS.md)

## Лицензия

[MIT](LICENSE).
