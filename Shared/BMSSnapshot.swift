import Foundation

/// One reading from the BMS. Written by the app, read by the widget.
/// Foundation-only on purpose: UI helpers live in BMSSnapshot+UI.swift.
struct BMSSnapshot: Codable, Equatable {
    var timestamp: Date
    var voltage: Double          // V
    var current: Double          // A: > 0 charging, < 0 discharging
    var remainingAh: Double
    var nominalAh: Double
    var cycles: Int
    var percent: Int             // RSOC, 0...100
    var chargeFET: Bool
    var dischargeFET: Bool
    var cellCount: Int
    var temperatures: [Double]   // °C, one per NTC sensor
    var protectionFlags: UInt16
    var cellVoltages: [Double]   // V; empty until the first 0x04 reply
    var disconnected: Bool?      // set when the app quits; nil while readings are live
}

extension BMSSnapshot {
    var power: Double { voltage * current }
    var isCharging: Bool { current > 0.1 }
    var isDischarging: Bool { current < -0.1 }
    var maxTemperature: Double? { temperatures.max() }

    var cellDeltaMillivolts: Double? {
        guard let lo = cellVoltages.min(), let hi = cellVoltages.max() else { return nil }
        return (hi - lo) * 1000
    }

    /// Seconds until full (charging) or empty (discharging); nil when idle.
    var eta: TimeInterval? {
        if isCharging { return max(nominalAh - remainingAh, 0) / current * 3600 }
        if isDischarging { return remainingAh / -current * 3600 }
        return nil
    }

    func etaText(_ lang: Language) -> String? {
        guard let seconds = eta, seconds.isFinite, seconds < 100 * 3600 else { return nil }
        let minutes = Int(seconds / 60)
        let text = minutes >= 60
            ? lang.tr("\(minutes / 60) год \(minutes % 60) хв", "\(minutes / 60) h \(minutes % 60) min")
            : lang.tr("\(max(minutes, 1)) хв", "\(max(minutes, 1)) min")
        return (isCharging ? lang.tr("до повного: ", "to full: ") : lang.tr("до нуля: ", "to empty: ")) + text
    }

    /// Indexed by bit of `protectionFlags`.
    static let protectionNames = [
        ("Перенапруга комірки", "Cell overvoltage"),
        ("Недонапруга комірки", "Cell undervoltage"),
        ("Перенапруга батареї", "Pack overvoltage"),
        ("Недонапруга батареї", "Pack undervoltage"),
        ("Перегрів при заряді", "Charge overtemperature"),
        ("Переохолодження при заряді", "Charge undertemperature"),
        ("Перегрів при розряді", "Discharge overtemperature"),
        ("Переохолодження при розряді", "Discharge undertemperature"),
        ("Перевантаження по струму заряду", "Charge overcurrent"),
        ("Перевантаження по струму розряду", "Discharge overcurrent"),
        ("Коротке замикання", "Short circuit"),
        ("Помилка мікросхеми BMS", "BMS IC error"),
        ("Блокування MOSFET", "MOSFET lock"),
    ]

    func activeProtections(_ lang: Language) -> [String] {
        var result: [String] = []
        for (bit, (uk, en)) in Self.protectionNames.enumerated()
        where protectionFlags & (UInt16(1) << UInt16(bit)) != 0 {
            result.append(lang.tr(uk, en))
        }
        return result
    }

    static let sample = BMSSnapshot(
        timestamp: .now, voltage: 52.4, current: -8.2,
        remainingAh: 14.5, nominalAh: 20, cycles: 42, percent: 72,
        chargeFET: true, dischargeFET: true, cellCount: 14,
        temperatures: [24.5, 25.1], protectionFlags: 0,
        cellVoltages: Array(repeating: 3.743, count: 14)
    )
}
