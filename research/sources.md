# Источники

## Первоисточники по фильтрации в РФ

1. **Human Rights Watch — «Disrupted, Throttled, and Blocked: State Censorship, Control, and Increasing Isolation of Internet Users in Russia»** (30.07.2025, EN/RU)
   https://www.hrw.org/report/2025/07/30/disrupted-throttled-and-blocked/state-censorship-control-and-increasing-isolation
   → Устройство ТСПУ, отсутствие контроля со стороны ISP, «учебные» отключения (Дагестан/Чечня/Ингушетия, 12.2024), коллатеральные сбои (02.2024, 01.2025), блокировка диапазонов Cloudflare (20.03.2025), региональная/операторская неоднородность.

2. **HRW — Russia Crackdown on Bypassing Online Censorship** (24.09.2026)
   https://www.hrw.org/europe/central-asia/russia
   → Свежий контекст: блокировки, кибератаки, изъятие приложений-обходчиков.

3. **net4people/bbs #490 — [Russia] Censor has a new method of blocking** (27.06.2025)
   https://github.com/net4people/bbs/issues/490
   → Метод «TCP 16-20»: заморозка TCP-соединения после ≈15–20 КБ сервер→клиент на «подозрительных» ASN (Hetzner/DO...), без RST; в первую очередь мобильные сети; чекер «RU :: TCP 16-20».

4. **net4people/bbs #363 — Blocking of fully encrypted protocols (Shadowsocks, VMess) in Russia, targeting HTTPS traffic fingerprints** (13.05.2024)
   https://github.com/net4people/bbs/issues/363
   → Детект TLS-in-TLS: клиент шлёт ≥3 пакета ≥411 B, сервер отвечает чаще клиента → блок. Метод по мотивам «Fingerprinting Obfuscated Proxy Traffic with Encapsulated TLS Handshakes» (Fifield et al.).

5. **net4people/bbs #274 — OpenVPN and WireGuard blocking reported in multiple ISPs in Russia** (07.08.2023)
   https://github.com/net4people/bbs/issues/274
   → Массовая блокировка OpenVPN/WireGuard на нескольких ISP, хронология сообщений NTC.

6. **net4people/bbs #76 — Roskomnadzor's plans to block various VPN services** (17.06.2021)
   https://github.com/net4people/bbs/issues/76
   → Ранний контекст планов РКН по протоколам.

7. **net4people/bbs #546 — [Russia] TLS connection-based policing / parallel handshake freeze** (2025–2026)
   https://github.com/net4people/bbs/issues/546
   → Поведенческая заморозка по совпадению трёх сигналов (ASN хостера, профиль потока, залп параллельных TLS-рукопожатий к одному IP:443): пауза ~120 с после TLS Finished при живом TCP; волны в феврале и 25.05.2026 (Москва, Сибирь); осенняя волна 2026 — подсети зарубежных облаков и мобильные «белые списки». Используется в `dpi-overview.md`, п. 2.7 и в отчёте (раздел 5, п. 8) как описание механизма по сообщениям сообщества — собственного замера из РФ у проекта нет.

## Инструменты и документация

8. **XTLS/Xray-core** — сетевое ядро (клон в `./Xray-core`, коммит `a52db8f6`, версия v26.10.31-10-ga52db8f6)
   https://github.com/XTLS/Xray-core

9. **XTLS/Xray-docs-next** — официальная документация (сайт xtls.github.io), разделы REALITY/VLESS
   https://github.com/XTLS/Xray-docs-next

10. **REALITY (RFC-style описание протокола) и обсуждение**
    https://github.com/XTLS/REALITY
    → Механика «stolen certificate», анти-проба, параметры.

11. **Selectel — «Диагностика влияния ТСПУ»** (материал предоставлен постановщиком задачи)
    https://selectel.ru/blog/ (раздел по ТСПУ)
    → Принципы фильтрации: IP, SNI, QUIC-метаданные, сигнатуры протоколов.

12. **iperf3** — методика нагрузочного тестирования
    https://iperf.fr/iperf-doc.php

13. **Hiddify** (клиенты всех платформ)
    https://github.com/hiddify/hiddify-app

## Что проверено первоисточниками локально

- Схема конфигурации REALITY (поля `dest`, `serverNames`, `privateKey`, `shortIds`, клиентские `publicKey`/`shortId`/`spiderX`/`fingerprint`) — сверена по коду `infra/conf/transport_security.go` локального клона Xray-core v26.10.31.
- Все гипотезы о работоспособности из РФ подлежат проверке на реальном операторе (см. `benchmarks/methodology.md`).
