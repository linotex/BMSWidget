import SwiftUI

/// UI language. Picked in the menu and stored next to the snapshot, so the widget follows it.
enum Language: String {
    case uk, en

    /// `lang.tr("Напруга", "Voltage")`
    func tr(_ uk: String, _ en: String) -> String { self == .en ? en : uk }

    /// For text SwiftUI formats itself, like relative timestamps.
    var locale: Locale { Locale(identifier: rawValue) }
}

private struct LanguageKey: EnvironmentKey {
    static let defaultValue = Language.uk
}

extension EnvironmentValues {
    var language: Language {
        get { self[LanguageKey.self] }
        set { self[LanguageKey.self] = newValue }
    }
}
