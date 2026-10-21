import SwiftUI
import WidgetKit

@main
struct BMSWidgetApp: App {
    @StateObject private var client = BMSClient()
    @State private var language = SnapshotStore.loadLanguage()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(client: client, language: $language)
                .environment(\.language, language)
                .environment(\.locale, language.locale)
                .onChange(of: language) {
                    SnapshotStore.save(language)
                    WidgetCenter.shared.reloadAllTimelines()
                }
        } label: {
            MenuBarLabel(snapshot: client.snapshot, connected: client.state == .connected)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let snapshot: BMSSnapshot?
    let connected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            if let snapshot {
                Text("\(snapshot.percent)%")
            }
        }
    }

    private var icon: String {
        guard connected, let snapshot else { return "bolt.slash" }
        return snapshot.batterySymbol
    }
}
