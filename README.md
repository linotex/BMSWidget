# BMS Widget — JBD / Xiaoxiang → macOS

Menu bar застосунок читає JBD BMS (Xiaoxiang Electric) по Bluetooth LE і віддає дані WidgetKit-віджету.
Віджет сам по BLE працювати не може, тому застосунок пише `~/Library/Application Support/BMSWidget/snapshot.json`, а віджет його читає.

## Встановлення

Потрібен macOS 14+ і Mac на Apple Silicon.

1. Завантаж `BMSWidget-<версія>.zip` з [Releases](https://github.com/linotex/BMSWidget/releases), розпакуй і перенеси `BMSWidget.app` у `/Applications`.
2. Застосунок не підписаний сертифікатом Apple, тож macOS не дасть його відкрити. Зніми карантин:
   ```bash
   xattr -cr /Applications/BMSWidget.app
   ```
3. Запусти застосунок, дозволь Bluetooth і в іконці в рядку меню обери свій BMS.
4. Робочий стіл → Редагувати віджети → «Акумулятор».

Мова інтерфейсу (UA / EN) перемикається внизу меню.

## Збірка

Xcode не потрібен, вистачає Command Line Tools:

1. `tools/build.sh` → `build/BMSWidget.app` (ad-hoc підпис, `BUNDLE_PREFIX` і версія беруться з `project.yml`).
2. Запусти `build/BMSWidget.app` (або скопіюй у `/Applications`). Дозволь Bluetooth.
3. В іконці меню обери свій BMS зі списку (запам'ятається).
4. Робочий стіл → Редагувати віджети → «Акумулятор».

Через Xcode: `brew install xcodegen && xcodegen && open BMSWidget.xcodeproj`, схема **BMSWidget** → Run (`DEVELOPMENT_TEAM` у `project.yml` для підпису).

## Важливо

- BMS тримає **одне** BLE-з'єднання. Поки відкритий Xiaoxiang на телефоні, Mac не підключиться.
- Віджет живий лише поки запущений застосунок — додай його в Login Items.
- Віджет оновлюється не частіше ніж раз на хвилину (ліміти WidgetKit), меню — кожні 10 с.
- Протокол: сервіс `FF00` (`FF01` notify / `FF02` write) або `FFE0`/`FFE1`.
  Кадри: запит `DD A5 03 00 FF FD 77`, відповідь `DD 03 00 <len> … <chk> 77`.
- App Group не використовується: на macOS 15 без Team ID він показує запит доступу на кожному запуску, а віджет просто не стартує. Замість нього temporary-exception entitlements на одну теку.

## Перевірка парсера без Mac

`python3 tools/verify_jbd.py` — Python-порт `App/JBDProtocol.swift` з тестами.
