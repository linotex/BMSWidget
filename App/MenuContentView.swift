import SwiftUI

struct MenuContentView: View {
    @ObservedObject var client: BMSClient
    @Binding var language: Language

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let snapshot = client.snapshot {
                SnapshotDetails(snapshot: snapshot)
            }
            StatusSection(client: client)
            Divider()
            HStack {
                if client.state == .connecting || client.state == .connected {
                    Button(language.tr("Забути пристрій", "Forget device")) { client.forgetDevice() }
                }
                Spacer()
                Picker("", selection: $language) {
                    Text("UA").tag(Language.uk)
                    Text("EN").tag(Language.en)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button(language.tr("Вийти", "Quit")) { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 290)
    }
}

private struct SnapshotDetails: View {
    @Environment(\.language) private var lang
    let snapshot: BMSSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(snapshot.percent)%")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(snapshot.levelColor)
                if snapshot.showsChargingBolt {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.green)
                        .accessibilityLabel(lang.tr("Заряджається", "Charging"))
                }
                Spacer()
                if let eta = snapshot.etaText(lang) {
                    Text(eta).font(.callout).foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    stat(lang.tr("Напруга", "Voltage"), String(format: lang.tr("%.2f В", "%.2f V"), snapshot.voltage))
                    stat(lang.tr("Струм", "Current"), String(format: lang.tr("%+.1f А", "%+.1f A"), snapshot.current))
                }
                GridRow {
                    stat(lang.tr("Потужність", "Power"), String(format: lang.tr("%+.0f Вт", "%+.0f W"), snapshot.power))
                    stat(lang.tr("Температура", "Temperature"), snapshot.temperatureText)
                }
                GridRow {
                    stat(lang.tr("Ємність", "Capacity"),
                         String(format: lang.tr("%.1f / %.1f А·год", "%.1f / %.1f Ah"),
                                snapshot.remainingAh, snapshot.nominalAh))
                    stat(lang.tr("Цикли", "Cycles"), "\(snapshot.cycles)")
                }
            }

            if let lo = snapshot.cellVoltages.min(), let hi = snapshot.cellVoltages.max(),
               let delta = snapshot.cellDeltaMillivolts {
                Text(String(format: lang.tr("Комірки: %.3f–%.3f В · Δ %.0f мВ", "Cells: %.3f–%.3f V · Δ %.0f mV"),
                            lo, hi, delta))
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(snapshot.activeProtections(lang), id: \.self) { name in
                Label(name, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            }
            if !snapshot.chargeFET {
                Text(lang.tr("MOSFET заряду вимкнено", "Charge MOSFET is off"))
                    .font(.caption).foregroundStyle(.orange)
            }
            if !snapshot.dischargeFET {
                Text(lang.tr("MOSFET розряду вимкнено", "Discharge MOSFET is off"))
                    .font(.caption).foregroundStyle(.orange)
            }

            (Text(lang.tr("оновлено ", "updated ")) + Text(snapshot.timestamp, style: .relative))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}

private struct StatusSection: View {
    @Environment(\.language) private var lang
    @ObservedObject var client: BMSClient

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch client.state {
            case .starting:
                Text(lang.tr("Запуск…", "Starting…")).foregroundStyle(.secondary)

            case .bluetoothOff:
                Label(lang.tr("Bluetooth вимкнено", "Bluetooth is off"), systemImage: "exclamationmark.triangle")

            case .unauthorized:
                Label(lang.tr("Немає доступу до Bluetooth. Дозволь його в Системних налаштуваннях → Конфіденційність і безпека → Bluetooth.",
                              "No Bluetooth access. Allow it in System Settings → Privacy & Security → Bluetooth."),
                      systemImage: "lock")
                    .font(.caption)

            case .scanning:
                Text(lang.tr("Обери BMS:", "Choose your BMS:")).font(.headline)
                if client.devices.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(lang.tr("Пошук…", "Searching…")).foregroundStyle(.secondary)
                    }
                }
                ForEach(client.devices) { device in
                    Button { client.select(device) } label: {
                        HStack {
                            Text(device.name)
                            Spacer()
                            Text("\(device.rssi) dBm").foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

            case .connecting:
                Text(lang.tr("Підключення до \(client.deviceName ?? "BMS")…",
                             "Connecting to \(client.deviceName ?? "BMS")…"))
                    .foregroundStyle(.secondary)
                Text(lang.tr("BMS тримає лише одне BLE-з'єднання — закрий Xiaoxiang на телефоні.",
                             "The BMS allows only one BLE connection — close Xiaoxiang on your phone."))
                    .font(.caption).foregroundStyle(.tertiary)

            case .connected:
                Label(client.deviceName ?? "BMS", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if client.issue == .noBMSService {
                Text(lang.tr("На пристрої немає сервісу FF00/FFE0 — це точно JBD BMS?",
                             "No FF00/FFE0 service on this device — is it really a JBD BMS?"))
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }
}
