# ABB Agent для Ubuntu 20.04 — публичное зеркало и установщик

## ⚡ Быстрая установка (Ubuntu 20.04)

```bash
curl -fsSL https://raw.githubusercontent.com/dealenx/agent-synology-ubuntu-20/main/install-abb.sh | sudo bash
```

Если не нравится pipe в bash:

```bash
curl -fsSL -o install-abb.sh https://raw.githubusercontent.com/dealenx/agent-synology-ubuntu-20/main/install-abb.sh
sudo bash install-abb.sh
```

Скрипт сам скачает `install.run`, поставит зависимости и исправляет ошибку
`linux-headers-$(uname -r) has no installation candidate` (стороннее ядро).
После установки: `abb-cli -c` для подключения к NAS.

---

## Почему установка падает с `no installation candidate`

`install.run` (Makeself) внутри запускает `install.sh`, который жёстко требует
пакет `linux-headers-$(uname -r)` для **текущего** ядра:

```bash
packages=(linux-headers-$(uname -r) dkms make)
...
test_dependency ${packages[@]}
```

Если ядро стороннее (mainline 5.19, HWE, кастомное) и его заголовков нет в
репозиториях Ubuntu 20.04 — `apt install` отвечает
`Package 'linux-headers-...' has no installation candidate`, скрипт выходит с
кодом 1 и установка останавливается ещё до распаковки deb-пакетов.

`install-abb.sh` решает это так:

1. Проверяет наличие заголовков для текущего ядра.
2. Если их нет — ставит `linux-generic` (каноническое ядро focal) и подставляет
   установщику заголовки установленного ядра (shim `uname -r`).
3. После установки агента нужно перезагрузиться в новое ядро и `modprobe synosnap`.

## Тест скрипта в Docker (Ubuntu 20.04)

`Dockerfile` — облегчённый focal, `compose.yml` монтирует `install.run` и
`install-abb.sh`. Локальный запуск:

```bash
docker compose build
docker compose run --rm abb bash /verify.sh
```

`verify.sh` (используется и в CI):

1. Запускает `install.run` с настоящим `uname -r` → ожидает падения с
   `no installation candidate` (тот же лог, что у коллеги).
2. Запускает `install-abb.sh` → ожидает `exit 0` и `The installation is complete`.

## GitHub Actions

`.github/workflows/test.yml` на каждый push запускает `verify.sh` в чистом
контейнере `ubuntu:20.04` (job `container: ubuntu:20.04`). Нативный раннер
`ubuntu-20.04` GitHub удалил в апреле 2025 — контейнер это заменяет, и это
близко к машине коллеги: голый focal, ничего не предустановлено.

## Содержимое

| Файл | Назначение |
|---|---|
| `install.run` | официальный установщик Synology ABB Agent 3.2.2 (Makeself) |
| `install-abb.sh` | одностраничный установщик для коллеги (с фиксом стороннего ядра) |
| `Dockerfile`, `compose.yml` | тестовый контейнер ubuntu 20.04 |
| `verify.sh` | автотест: репро ошибки + успех установки |

Системные требования (из README вендора): Ubuntu 20.04 x86_64, `linux-headers`,
`dkms ≥ 2.2.0.3`, `make ≥ 4.1`, `gcc ≥ 4.8.2`. Драйвер (`synosnap`) — DKMS-модуль,
собирается только под установленное ядро с заголовками.
