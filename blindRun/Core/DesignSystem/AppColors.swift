import SwiftUI

// MARK: - App Colors

enum AppColors {
    static let primary = Color.blue
    static let destructive = Color.red
    static let background = Color(uiColor: .systemBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
    static let textPrimary = Color(uiColor: .label)
    static let textSecondary = Color(uiColor: .secondaryLabel)
    static let success = Color.green
    static let warning = Color.orange
}

// MARK: - App Fonts

enum AppFonts {
    static func largeTitle() -> Font {
        .largeTitle.bold()
    }

    static func title() -> Font {
        .title2.bold()
    }

    static func body() -> Font {
        .body
    }

    static func caption() -> Font {
        .caption
    }

    static func primaryButton() -> Font {
        .title3.bold()
    }
}
