# BMSWidget

macOS menu bar застосунок + WidgetKit-віджет, що показує стан акумулятора з BMS **JBD / Xiaoxiang Electric** по Bluetooth LE. Мета: рівень заряду, напруга, струм, потужність, температура, комірки, захисти — прямо на робочому столі Mac.

Спілкуйся українською, коротко і прямо. Код і коментарі в коді — англійською.

## Статус (читай першим)

Код компілюється без помилок і попереджень: `tools/build.sh` (swiftc із Command Line Tools, Xcode на цьому Mac немає) → `build/BMSWidget.app`, ad-hoc підпис. 2026-10-21 перевірено з реальним BMS (4S LiFePO4, 100 А·год): підключення, опитування і віджет на робочому столі працюють. Розібрані значення узгоджені між собою: сума комірок дорівнює напрузі батареї, залишок / номінал = RSOC. Із показами Xiaoxiang поруч ще не звіряли.

## Архітектура

Віджет не може тримати BLE-з'єднання, тому:

```
BMS ──BLE──> BMSClient (застосунок) ──snapshot.json──> ~/Library/Application Support/BMSWidget ──> Віджет
                  │                                  └─ WidgetCenter.reloadAllTimelines()
                  └──> MenuBarExtra (SwiftUI)
```

- `App/BMSClient.swift` — CoreBluetooth: скан → вибір пристрою (UUID зберігається в UserDefaults) → підключення → нотифікації → опитування кожні 10 с (команда 0x03, потім 0x04). Автоперепідключення через 3 с; `central.connect` лишається в очікуванні, поки BMS не в зоні досяжності. Перезавантаження віджета тротлиться: раз на 60 с або при зміні відсотка/напрямку струму. При виході (`willTerminate`) позначає останній знімок `disconnected = true` і одразу перезавантажує віджет. Прапорець скидається з першим новим зчитуванням.
- `App/JBDProtocol.swift` — кадри, контрольна сума, розбір payload, складання 20-байтових BLE-чанків (`JBDFrameAssembler`). Лише Foundation.
- `App/MenuContentView.swift`, `App/BMSWidgetApp.swift` — меню (`LSUIElement`, без іконки в Dock).
- `Shared/BMSSnapshot.swift` — модель (Foundation-only), `BMSSnapshot+UI.swift` — кольори/іконки. Обидва target-и.
- `Shared/Language.swift` — UA/EN без `.strings`: `lang.tr("укр", "eng")`, мова передається через SwiftUI-оточення `\.language` (плюс `\.locale` для відносних дат). Перемикач UA/EN у меню. Вибір зберігається у файлі `language` поруч зі `snapshot.json`, віджет читає його при кожному оновленні. Новий текст в інтерфейсі пиши одразу двома мовами.
- `Shared/SnapshotStore.swift` — JSON у справжньому `~/Library/Application Support/BMSWidget/` (домашня тека через `getpwuid`, бо `NSHomeDirectory()` у пісочниці вказує на контейнер). Доступ дають `temporary-exception.files.home-relative-path` entitlements (застосунок — read-write, віджет — read-only). App Group свідомо не використовується: без Team ID на macOS 15 він не працює.
- `Widget/BMSWidget.swift` — `StaticConfiguration`, small + medium, кільце заряду, позначка «застарілі дані» (>5 хв) або «Відключено» (застосунок закрито).
- `tools/build.sh` — збірка без Xcode: swiftc, ручне складання бандла, Info.plist/entitlements, ad-hoc підпис. Розширення лінкується з `-e _NSExtensionMain`, як у Xcode. Info.plist і entitlements тут дублюють `project.yml`, тож змінюй обидва.
- `project.yml` — XcodeGen (Info.plist і entitlements генеруються в `Support/`, не комітити як джерело правди).

## Протокол JBD (BLE UART)

- Сервіс `FF00`: `FF01` — notify, `FF02` — write. Старіші плати: `FFE0` / `FFE1` (одна характеристика).
- Запит: `DD A5 <cmd> 00 <chk hi> <chk lo> 77`; `0x03` → `DD A5 03 00 FF FD 77`, `0x04` → `DD A5 04 00 FF FC 77`.
- Відповідь: `DD <cmd> <status> <len> <payload> <chk hi> <chk lo> 77`, `status == 0` — ОК.
- Контрольна сума: `0x10000 - (status + len + sum(payload))`.
- 0x03 payload: напруга (u16, 10 мВ), струм (i16, 10 мА, + заряд / − розряд), залишок і номінал (u16, 10 мА·год), цикли, дата, баланс (4 B), захисти (u16 бітова маска), версія, RSOC %, FET (bit0 заряд, bit1 розряд), к-сть комірок, к-сть NTC, NTC (u16, 0.1 K → °C = (raw − 2731) / 10).
- 0x04 payload: N × u16, мВ на комірку.
- Відповіді приходять шматками по ≤20 байт — завжди збирай через `JBDFrameAssembler`.

## Відомі обмеження та ризики

- BMS приймає **одне** BLE-з'єднання: Xiaoxiang на телефоні мусить бути закритий.
- WidgetKit рації перезавантаження; не опитуй частіше ніж раз на ~хвилину в `reloadAllTimelines`.
- Текст системного запиту на Bluetooth (`NSBluetoothAlwaysUsageDescription` в Info.plist) лише українською, перемикач мови на нього не впливає.
- Ad-hoc підпис: після кожної перезбірки змінюється ідентичність коду, тож macOS може знову спитати дозвіл на Bluetooth. chronod не кешує дескриптори такого віджета («shouldn't cache it» у логах), бере їх при відкритті галереї.
- На цьому Mac у CLT лежить застарілий `usr/include/swift/module.modulemap`, що дублює `bridging.modulemap` і ламає будь-який `import`. `build.sh` ховає його через VFS-overlay. Постійне виправлення: `sudo rm /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap`.
- Якщо BMS не рекламує потрібні сервіси або використовує інші UUID — правити `BMSClient.services` і `didDiscoverCharacteristicsFor`.
- Сканування йде без фільтра сервісів (JBD часто не рекламує UUID), список показує лише пристрої з іменем.

## Ідеї далі (не робити без запиту)

- Відображення окремих комірок і балансування (`payload[12..<16]`).
- Історія/графік заряду, сповіщення при низькому заряді чи захистах.
- Віддалений моніторинг через ESP32/Raspberry Pi як BLE→MQTT міст.
- Запис у Login Items (`SMAppService`).

## Конвенції

- Парсер-логіку змінюй разом із `tools/verify_jbd.py` і прогоняй його.
- Не додавай залежностей без потреби; чисте SwiftUI + CoreBluetooth + WidgetKit.
