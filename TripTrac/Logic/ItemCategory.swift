import Foundation

enum ItemCategory: String, CaseIterable, Identifiable, Codable {
    case flight, train, stay, activity, meal, dayTrip, themePark, rest, portDay, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .flight: "Flight"
        case .train: "Train"
        case .stay: "Stay"
        case .activity: "Activity"
        case .meal: "Meal"
        case .dayTrip: "Day trip"
        case .themePark: "Theme park"
        case .rest: "Free time"
        case .portDay: "Port day"
        case .other: "Other"
        }
    }

    /// One symbol per category, used everywhere a category appears.
    var symbol: String {
        switch self {
        case .flight: "airplane"
        case .train: "tram.fill"
        case .stay: "bed.double.fill"
        case .activity: "sparkles"
        case .meal: "fork.knife"
        case .dayTrip: "signpost.right.and.left.fill"
        case .themePark: "ticket.fill"
        case .rest: "cup.and.saucer.fill"
        case .portDay: "ferry.fill"
        case .other: "mappin.and.ellipse"
        }
    }

    /// Categories that normally need a real reservation/ticket to exist.
    var usuallyNeedsBooking: Bool {
        switch self {
        case .flight, .train, .stay, .themePark, .portDay: true
        default: false
        }
    }
}
