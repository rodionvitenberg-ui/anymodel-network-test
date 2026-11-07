# anymodel-network-test

Шлюз для доступа к AI-сервисам из РФ: **Xray-core + VLESS + REALITY (Vision)** в Docker Compose. Разворачивается на чистом Ubuntu 22.04/24.04 (проверено и на 26.04) за две команды, клиентский профиль выдаётся сразу же в виде VLESS-строки и QR-кода.

> Исследование методов фильтрации и обоснование выбора протокола: [`research/`](research/). Метода замеров: [`benchmarks/methodology.md`](benchmarks/methodology.md). Результаты замеров: [`benchmarks/results/summary.md`](benchmarks/results/summary.md). Итоговый отчёт: [`report/final-report.md`](report/final-report.md).

## Быстрый старт (сервер)

Требования: VPS **за пределами РФ** с публичным IPv4, Ubuntu 22.04/24.04/26.04, root.

```bash
git clone https://github.com/rodionvitenberg-ui/anymodel-network-test.git && cd anymodel-network-test/deploy
sudo ./scripts/install.sh <SERVER_IP>
```

Скрипт сам воткнет Docker, сгенеририт UUID/x25519/shortId (секреты остаются в `deploy/.env`, в git не попадают), отрендерит конфиг, проверит его пиннед-версией ядра, поднимет контейнер и выведет клиентский профиль.

Дополнительно: `sudo ./scripts/install.sh <SERVER_IP> www.nvidia.com` - задать свой сайт-маску (SNI/dest).

Порт inbound'а по умолчанию — **443** (стандартный HTTPS: туннель неотличим от обычной сессии; см. [ADR 0002](docs/adr/0002-reality-on-port-443-dedicated-host.md)). Если 443 занят — третий аргумент, например `sudo ./scripts/install.sh <SERVER_IP> www.nvidia.com 8443`. Контейнер работает от root, поскольку иначе Docker не разрешает не-root-процессу занять порт <1024.

## Быстрый старт (клиент)

**ПК (Linux)** — без сторонних приложений, туннель поднимается сам при каждом входе в систему:

```bash
./client/install.sh "vless://..."     # строка из вывода серверного install.sh
./client/install.sh --ssh final       # или стянуть секреты прямо с сервера
```

Скрипт разбирает VLESS-строку и кладёт секреты в `~/.config/anygateway/client.env` (600, вне git, переживает ребут — никаких `/tmp`), при необходимости скачивает пиннед-ядро Xray с официального релиза (go не требуется), ставит systemd user-сервис `anymodel-gw` (автостарт при входе, `Restart=on-failure` при падении) и включает системный прокси браузера; при `systemctl --user stop` прокси снимается автоматически (`ExecStopPost`).

Управление: `systemctl --user status|stop|start|disable anymodel-gw`. Смена сервера или ключей - повторный запуск `install.sh` с новой строкой.

**Одноразовый установщик**: на настроенной машине `./client/make-one-shot.sh` → `dist/anymodel-gw-installer.sh` — автономный файл с зашитым профилем: получателю достаточно `bash anymodel-gw-installer.sh` (репозиторий и ввод не нужны, ядро скачается само). Файл содержит секреты - в git не коммитится и передаётся проверяющему по защищённому каналу; отзыв доступа - ротация ключей на сервере.

**Мобильные**: [v2rayNG 2.3.15](https://github.com/2dust/v2rayNG/releases) (Android) или [Streisand](https://apps.apple.com/app/streisand/id6450534064) (iOS - в RU App Store отсутствует, нужен Apple ID другой страны; RU-альтернатива - Shadowrocket) - «+» → импорт VLESS-строки/QR из вывода `install.sh`. Пошаговая установка и проверка - в [`client/README.md`](client/README.md). [Hiddify](https://github.com/hiddify/hiddify-app/releases) (sing-box) поддерживается: сервер закреплён на Xray-core **26.6.27** — версии, на которой работают все четыре клиента (матрица версий - `client/README.md`, `docs/adr/0001-server-pinned-26.6.27.md`).

Подробности и диагностика: [`client/README.md`](client/README.md).

## Структура репозитория

```
├── CONTEXT.md           # глоссарий домена: канонический язык документации
├── research/            # исследование ТСПУ/DPI и обоснование протокола
├── deploy/              # деплой: docker-compose, шаблон конфига, скрипты
│   ├── config/config.template.json
│   └── scripts/{install,gen-keys,gen-client-profile}.sh
├── client/              # клиент: install.sh (systemd user-сервис) + инструкция
├── benchmarks/          # методика, скрипты замеров, результаты, графики
├── report/              # итоговый отчёт
└── docs/adr/            # ключевые решения: пин сервера (совместимость клиентов), порт 443
Xray-core/               # git-субмодуль исходников ядра (HEAD, для локальных сборок/смоука;
                         # сервер в деплое — пин 26.6.27, клиенты — пин 26.10.31)
```

Секреты (`deploy/.env`, `deploy/config/config.json`) генерируются на сервере и игнорируются git. Локальные рабочие файлы, которые не публикуются: `ABOUT.md` (эссе о проекте), `report/private-access.md` (адрес сервера + VLESS-строка), `dist/`.

## Локальная проверка без VPS

Полный путь (curl → socks → Xray-клиент → REALITY → Xray-сервер → интернет) проверяется одной командой:

```bash
cd Xray-core && go build -o ../.bin/xray ./main && cd ..
./benchmarks/scripts/local-smoke-test.sh
```

## Эксплуатация

```bash
cd deploy
docker compose logs -f          # логи шлюза
docker compose pull && docker compose up -d   # перезапуск на пиннед-версии; смена версии — XRAY_VERSION в deploy/.env + проверка benchmarks/scripts/compat-matrix.sh
./scripts/gen-client-profile.sh # повторно вывести профиль/QR
```

Смена сайта-маски: правка `XRAY_DEST` в `deploy/.env` → перезапуск `install.sh` (секреты сохранятся).
