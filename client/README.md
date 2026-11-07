# Клиентская настройка

На ПК стороннее VPN-приложение **не нужно**: [`client/install.sh`](install.sh) ставит локальный Xray-клиент как systemd user-сервис с автозапуском (раздел «ПК: установка клиента одним скриптом» ниже). Это одна команда на свежей машине: toolchain и ручные настройки не требуются, ядро скачивается с официального релиза. Приложения из этого файла нужны только мобильным платформам.

## Требования к версиям и совместимость

Сервер: Xray-core **26.6.27** (пиннед-образ, `XRAY_VERSION` в `deploy/.env.example`). Версия выбрана не «самая последняя»: REALITY-аутентификация ужесточалась дважды, и оба ужестоения предъявляют к клиенту требования, которые выполняют не все ядра —

- **26.7.x** ввёл дефолтный `minClientVer = v26.3.27`; sing-box присылает `ClientVer=[1,8,1]` — ниже порога;
- **26.9.9+** (`xtls/reality` 8cdf7bf9, 2026-09-08) принимает только ClientHello с пост-квантовым key share `X25519MLKEM768`, которого sing-box не присылает.

Измерено на локальном стенде с реальными бинарниками (`benchmarks/scripts/compat-matrix.sh`):

| Сервер Xray-core | sing-box 1.14.4 (ядро Hiddify) | Xray-клиент 26.10.31 | Xray-клиент 26.6.27 |
|---|---|---|---|
| **26.6.27** | **204 ✅** | 204 ✅ | 204 ✅ |
| 26.7.28 | ❌ `reality verification failed` | 204 ✅ | — |
| 26.9.9 | ❌ `reality verification failed` | 204 ✅ | — |
| 26.10.31 | ❌ `reality verification failed` | 204 ✅ | 204 ✅ |

Вывод: **xray-клиенты работают с любым сервером, sing-box — только с сервером ≤ 26.6.27**; поэтому сервер пиннится на 26.6.27, а клиентское ядро — отдельный пин `CLIENT_XRAY_VERSION=26.10.31` (самый новый xray). Обоснование и детали: `docs/adr/0001-server-pinned-26.6.27.md`.

| Клиент | Ядро | Совместимость |
|---|---|---|
| v2rayNG 2.3.15 (Android) | Xray-core 26.10.31 | ✅ |
| `client/install.sh` (ПК, systemd user-сервис) | Xray-core 26.10.31 | ✅ |
| Streisand 1.7.0 (iOS/macOS) | Xray-core 26.10.29 | ✅ |
| **Hiddify 5.5.x** (Android/iOS/Windows/macOS/Linux) | sing-box 1.14.4 | ✅ с сервером 26.6.27 |

Матрица перепроверяется скриптом `benchmarks/scripts/compat-matrix.sh` (в том числе на свежих ядрах sing-box — проверялся 1.15.0-alpha.13); серверное ядро обновляется только после её прогона.

| Клиент | Платформа | Где брать |
|---|---|---|
| v2rayNG 2.3.15 | Android | https://github.com/2dust/v2rayNG/releases — APK `v2rayNG_2.3.15_arm64-v8a.apk` (есть `-fdroid_`-варианты и universal) |
| Streisand 1.7.0 | iOS / macOS | https://apps.apple.com/app/streisand/id6450534064 — бесплатно, но **в RU App Store отсутствует**, нужен Apple ID другой страны |
| Shadowrocket 2.2.93 | iOS / macOS | https://apps.apple.com/ru/app/shadowrocket/id932747118 — есть в RU App Store (249 ₽); реализация REALITY собственная, не Xray — совместимость проверяется только на устройстве |
| Hiddify | Android / iOS / Windows / macOS / Linux | https://github.com/hiddify/hiddify-app/releases — ядро sing-box, работает с сервером 26.6.27 (таблица выше) |

## Импорт профиля (мобильные приложения)

На сервере после `install.sh` выполните:

```bash
cd deploy && ./scripts/gen-client-profile.sh
```

Получите VLESS-строку и QR-код. Затем:

- **v2rayNG**: «+» → «Импорт Vless из буфера обмена» (строка уже в буфере после `gen-client-profile.sh`) или «Сканирование QR-кода».
- **Streisand**: «+» → «Вставить из буфера» / сканирование QR.
- **Hiddify**: «+» → «Импорт из буфера обмена» / «Сканировать QR».

## Установка с нуля (мобильные) и проверка за 2 минуты

### Android — v2rayNG (рекомендованный путь)

1. Скачайте APK со страницы релизов: <https://github.com/2dust/v2rayNG/releases> — файл `v2rayNG_2.3.15_arm64-v8a.apk` для современных телефонов (armeabi-v7a / x86_64 / universal — под свою архитектуру; `-fdroid_` — те же сборки для F-Droid). Google Play в РФ приложение может не показывать — GitHub-релиз это обходит.
2. Установите APK (разрешив установку из этого источника), откройте v2rayNG.
3. «+» → «Импорт Vless из буфера обмена» (сначала скопируйте VLESS-строку, полученную с сервера) или «Сканирование QR-кода».
4. Выделите профиль, в верхнем меню «тест задержки» (⏱) — ожидается ~100–200 мс, не `timeout`.
5. Кнопка подключения внизу (V-иконка) → разрешите Android создать VPN-профиль.
6. Проверка: <https://www.google.com/generate_204> → пустая страница; затем <https://chat.openai.com>, <https://claude.ai>, <https://gemini.google.com>.

### iOS — Streisand (бесплатно, основной путь)

1. Приложение **не опубликовано в RU App Store** — нужен Apple ID другой страны (выйти из RU-аккаунта в App Store, войти в иностранный; сам аккаунт регистрируется бесплатно, регион выбирается при создании).
2. Установите Streisand: <https://apps.apple.com/app/streisand/id6450534064> (v1.7.0, ядро Xray 26.10.29 — совместимо с сервером 26.6.27).
3. «+» → «Вставить из буфера» (скопированная VLESS-строка) → разрешите добавить VPN-конфигурацию iOS.
4. Включите тумблер; проверка — как на Android (generate_204 → AI-сервисы).

### iOS без иностранного Apple ID

- **Shadowrocket** (249 ₽, есть в RU App Store): «+» → «Scan QR» / вставить ссылку. Ядро собственное (не Xray): если «тест задержки» даёт `timeout` при работающих ПК/Android — попробуйте сначала Hiddify (sing-box), затем Streisand; при отказе REALITY-реализации приложения сервер тут не поможет (пин 26.6.27 уже максимально совместимый).
- **Happ** (бесплатно, заявляет VLESS Reality) — альтернатива с той же оговоркой.

### Проверка за 2 минуты (любое приложение)

1. «Тест задержки» профиля → число (~100–200 мс), не `timeout`.
2. `https://www.google.com/generate_204` → пустая страница (HTTP 204).
3. `https://api.openai.com/v1/models` → JSON с ошибкой авторизации (401 = API достижим из-под туннеля).
4. Не запускайте два клиента одновременно — ОС допускает только один активный VPN-профиль.

## ПК: установка клиента одним скриптом (автозапуск)

Один раз:

```bash
cd <репозиторий>
./client/install.sh "vless://..."     # та самая строка из gen-client-profile.sh
# или: ./client/install.sh --ssh final  # стянуть секреты прямо с сервера
```

Скрипт разберёт профиль в `~/.config/anygateway/client.env` (600, вне git), при необходимости скачает пиннед-ядро с официального релиза Xray (go и ручные настройки не нужны), поставит **systemd --user сервис** `anymodel-gw` (автостарт при входе в систему, автоперезапуск при падении) и включит системный прокси (HTTP/HTTPS `127.0.0.1:10809` + SOCKS `127.0.0.1:10808`). Перезапусти браузер.

Управление: `systemctl --user stop|start|status anymodel-gw`. Смена сервера/ключей — просто повторный запуск `install.sh` с новой строкой.

## Одноразовый установщик (zero-input, без репозитория)

Когда нужно отдать доступ человеку «в один файл» (например, непубличный репозиторий открыт не всем):

```bash
./client/make-one-shot.sh            # профиль из ~/.config/anygateway/client.env
# или: ./client/make-one-shot.sh /путь/к/client.env
```

Получится `dist/anymodel-gw-installer.sh` — автономный скрипт с зашитым профилем. Тестировщику:

```bash
bash anymodel-gw-installer.sh
```

Всё: секреты раскладываются в `~/.config/anygateway/client.env` (600), ядро скачивается с официального релиза (go и репозиторий не нужны), раннер и бинарник живут в `~/.local/share/anygateway/`, ставится тот же systemd user-сервис `anymodel-gw` (автозапуск, чистый stop, автосброс системного прокси), в конце — самопроверка (generate_204 + exit-IP).

Гигиена: файл = credential (внутри UUID/PublicKey/shortId). `dist/` в `.gitignore` — в репозиторий не попадает; передавать доверенным каналом; повторный запуск на той же машине идемпотентен; отзыв доступа — ротация ключей на сервере (после ротации сгенерировать установщик заново).

## Структура профиля (для ручной настройки)

```
Адрес:        <SERVER_HOST>
Порт:         <XRAY_PORT из deploy/.env>  (боевой сервер: 443)
ID (UUID):    <из deploy/.env>
Flow:         xtls-rprx-vision      ← обязательно
Шифрование:   none
Транспорт:    tcp
Security:     reality
SNI:          www.samsung.com       ← = XRAY_DEST из deploy/.env
Fingerprint:  chrome                ← обязательно
PublicKey:    <XRAY_REALITY_PUBLIC из deploy/.env>
ShortId:      <XRAY_SHORT_ID из deploy/.env>
SpiderX:      /
```

## Проверка работоспособности

1. ПК (`install.sh`): сервис запускается сам, системный прокси уже включён — просто откройте браузер. Проверка в терминале: `curl -x http://127.0.0.1:10809 https://www.google.com/generate_204` → `204`.
   Мобильные: включите профиль (TUN/VPN-режим или «Proxy»).
2. Откройте https://www.google.com/generate_204 — ожидается пустая страница (HTTP 204).
3. Проверьте доступ к AI-сервисам: https://chat.openai.com , https://claude.ai , https://gemini.google.com .
4. Если соединение есть, но «замерзает» под нагрузкой — см. `report/final-report.md`, раздел «TCP 16-20» (смена IP/сервера, клиентский фрагментатор ByeDPI).

## Диагностика с клиента

```bash
# без VPN — что видит оператор
ping <SERVER_HOST>
curl -v --connect-timeout 5 "https://<SERVER_HOST>:<XRAY_PORT>"   # должен отдать сертификат samsung.com (REALITY редирект); на боевом сервере XRAY_PORT=443

# наш клиент (install.sh / сервис anymodel-gw): HTTP 10809, SOCKS 10808
curl -sS -x http://127.0.0.1:10809 -o /dev/null -w '%{http_code}\n' https://www.google.com/generate_204
journalctl --user -u anymodel-gw -f   # живые логи туннеля

# сторонние приложения (локальный socks обычно 127.0.0.1:2080 или :12334)
curl -sS --socks5-hostname 127.0.0.1:2080 -o /dev/null -w '%{http_code}\n' https://www.google.com/generate_204
```

Если прямой curl на :443 **не** возвращает сертификат samsung.com — SNI/dest на сервере не совпадает с профилем, либо IP заблокирован оператором.
