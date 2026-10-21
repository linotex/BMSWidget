import SwiftUI
import WidgetKit

struct BMSEntry: TimelineEntry {
    let date: Date
    let snapshot: BMSSnapshot?
    var language = SnapshotStore.loadLanguage()
}

struct BMSProvider: TimelineProvider {
    func placeholder(in context: Context) -> BMSEntry {
        BMSEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BMSEntry) -> Void) {
        let snapshot = SnapshotStore.load()
        if snapshot == nil, context.isPreview {
            completion(BMSEntry(date: .now, snapshot: .sample))
        } else {
            completion(BMSEntry(date: .now, snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BMSEntry>) -> Void) {
        // The app pushes fresh data via WidgetCenter; this is only a fallback refresh.
        let entry = BMSEntry(date: .now, snapshot: SnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(300))))
    }
}

@main
struct BMSBatteryWidget: Widget {
    let kind = "BMSBatteryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BMSProvider()) { entry in
            BMSWidgetView(entry: entry)
        }
        .configurationDisplayName(SnapshotStore.loadLanguage().tr("Акумулятор", "Battery"))
        .description(SnapshotStore.loadLanguage().tr("Рівень заряду, напруга і струм з BMS.",
                                                     "Charge level, voltage and current from the BMS."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Views

struct BMSWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BMSEntry

    var body: some View {
        content
            .environment(\.language, entry.language)
            .environment(\.locale, entry.language.locale)
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = entry.snapshot {
            let stale = snapshot.disconnected == true || entry.date.timeIntervalSince(snapshot.timestamp) > 300
            if family == .systemMedium {
                MediumLayout(snapshot: snapshot, stale: stale)
            } else {
                SmallLayout(snapshot: snapshot, stale: stale)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "battery.0").font(.largeTitle)
                Text(entry.language.tr("Запусти застосунок BMS Widget", "Launch the BMS Widget app"))
                    .font(.caption).multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
        }
    }
}

private struct LevelRing: View {
    let snapshot: BMSSnapshot
    var lineWidth: CGFloat = 9

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(snapshot.percent, 100))) / 100)
                .stroke(snapshot.levelColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(snapshot.percent)%")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                if snapshot.showsChargingBolt {
                    Image(systemName: "bolt.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: snapshot.batterySymbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct StaleBadge: View {
    @Environment(\.language) private var lang
    let snapshot: BMSSnapshot

    var body: some View {
        Group {
            if snapshot.disconnected == true {
                Label(lang.tr("Відключено", "Disconnected"), systemImage: "bolt.slash.fill")
            } else {
                Label {
                    Text(snapshot.timestamp, style: .relative)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.orange)
    }
}

private struct SmallLayout: View {
    @Environment(\.language) private var lang
    let snapshot: BMSSnapshot
    let stale: Bool

    var body: some View {
        VStack(spacing: 8) {
            LevelRing(snapshot: snapshot)
                .frame(width: 88, height: 88)
            VStack(spacing: 1) {
                Text(String(format: lang.tr("%.1f В · %+.1f А", "%.1f V · %+.1f A"), snapshot.voltage, snapshot.current))
                    .font(.caption).monospacedDigit()
                if stale {
                    StaleBadge(snapshot: snapshot)
                } else if let eta = snapshot.etaText(lang) {
                    Text(eta).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .opacity(stale ? 0.7 : 1)
    }
}

private struct MediumLayout: View {
    @Environment(\.language) private var lang
    let snapshot: BMSSnapshot
    let stale: Bool

    var body: some View {
        HStack(spacing: 16) {
            LevelRing(snapshot: snapshot, lineWidth: 11)
                .frame(width: 104, height: 104)

            VStack(alignment: .leading, spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow {
                        stat(lang.tr("Напруга", "Voltage"), String(format: lang.tr("%.2f В", "%.2f V"), snapshot.voltage))
                        stat(lang.tr("Струм", "Current"), String(format: lang.tr("%+.1f А", "%+.1f A"), snapshot.current))
                    }
                    GridRow {
                        stat(lang.tr("Потужність", "Power"), String(format: lang.tr("%+.0f Вт", "%+.0f W"), snapshot.power))
                        stat(lang.tr("Темп.", "Temp."), snapshot.temperatureText)
                    }
                }

                if snapshot.disconnected != true, let alert = snapshot.activeProtections(lang).first {
                    Label(alert, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.red)
                } else if stale {
                    StaleBadge(snapshot: snapshot)
                } else if let eta = snapshot.etaText(lang) {
                    Text(eta).font(.caption).foregroundStyle(.secondary)
                } else if let delta = snapshot.cellDeltaMillivolts {
                    Text(String(format: lang.tr("Δ комірок %.0f мВ", "Cell Δ %.0f mV"), delta))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .opacity(stale ? 0.7 : 1)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout).monospacedDigit()
        }
    }
}
