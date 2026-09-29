import SwiftUI

/// What a color *means* in Itinero. Every colored badge/tile maps through `StatusTone`,
/// never an inline `Color`, so a status looks identical on every screen (see DESIGN.md).
enum StatusTone: Equatable {
    case good      // booked, done
    case caution   // needs booking, not urgent yet
    case bad       // cancelled conflicts, over budget
    case alert     // needs booking soon, all-aboard warnings
    case info      // planned, no booking needed
    case neutral   // idea, skipped, unknown
    case star      // must-do
    case money     // cost / budget numbers

    var color: Color {
        switch self {
        case .good: .green
        case .caution: Color(red: 1, green: 0.75, blue: 0)
        case .bad: .red
        case .alert: Color(red: 1, green: 0.55, blue: 0)
        case .info: .blue
        case .neutral: .gray
        case .star: .yellow
        case .money: .purple
        }
    }
}

enum BookingStatus: String, CaseIterable, Identifiable, Codable {
    case idea, planned, needsBooking, booked, done, cancelled
    var id: String { rawValue }

    var label: String {
        switch self {
        case .idea: "Idea"
        case .planned: "Planned"
        case .needsBooking: "Needs booking"
        case .booked: "Booked"
        case .done: "Done"
        case .cancelled: "Cancelled"
        }
    }

    /// One symbol per status across the whole app.
    var symbol: String {
        switch self {
        case .idea: "lightbulb"
        case .planned: "calendar"
        case .needsBooking: "exclamationmark.circle"
        case .booked: "checkmark.seal.fill"
        case .done: "checkmark.circle.fill"
        case .cancelled: "xmark.circle"
        }
    }
}

/// Days within which an unbooked item is escalated from caution to alert.
let bookingUrgencyWindowDays = 30

/// The single mapping from a booking status (and how soon it happens) to a tone.
func statusTone(for status: BookingStatus, daysUntil: Int?) -> StatusTone {
    switch status {
    case .booked, .done: return .good
    case .cancelled, .idea: return .neutral
    case .planned: return .info
    case .needsBooking:
        if let days = daysUntil, days <= bookingUrgencyWindowDays { return .alert }
        return .caution
    }
}

struct AppTheme {
    let primaryColor: Color
    let accentColor: Color
    let cardBackground: Color
    let cardShadowOpacity: Double

    /// Light brand: deep teal primary with a warm gold accent, white cards with a soft shadow.
    static let standard = AppTheme(
        primaryColor: Color(red: 0.10, green: 0.32, blue: 0.43),
        accentColor: Color(red: 0.99, green: 0.73, blue: 0.07),
        cardBackground: Color(.secondarySystemGroupedBackground),
        cardShadowOpacity: 0.06
    )
}
