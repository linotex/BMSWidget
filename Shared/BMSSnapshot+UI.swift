import SwiftUI

extension BMSSnapshot {
    var levelColor: Color {
        switch percent {
        case 31...: return .green
        case 16..<31: return .orange
        default: return .red
        }
    }

    var batterySymbol: String {
        if isCharging { return "battery.100.bolt" }
        switch percent {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }

    var temperatureText: String {
        guard !temperatures.isEmpty else { return "—" }
        return temperatures.map { String(format: "%.0f°", $0) }.joined(separator: " / ")
    }
}
