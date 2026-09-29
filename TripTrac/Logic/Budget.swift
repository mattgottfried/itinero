import Foundation

struct CurrencyTotals: Equatable {
    var currency: String
    var planned = 0.0
    var paid = 0.0
    var remaining: Double { planned - paid }
    /// Each item's cost split evenly across the travelers on it (whole group when none are listed).
    var perTraveler: [UUID: Double] = [:]
}

enum BudgetLogic {
    static func totals<T: Schedulable>(_ items: [T], travelerIDs: [UUID]) -> [CurrencyTotals] {
        var byCurrency: [String: CurrencyTotals] = [:]
        for item in items where item.status != .cancelled && item.status != .idea {
            guard let cost = item.cost, cost > 0 else { continue }
            let code = item.currency.uppercased()
            var t = byCurrency[code] ?? CurrencyTotals(currency: code)
            t.planned += cost
            if item.isPaid { t.paid += cost }
            let people = item.attendeeIDs.isEmpty ? travelerIDs : item.attendeeIDs
            if !people.isEmpty {
                let share = cost / Double(people.count)
                for id in people { t.perTraveler[id, default: 0] += share }
            }
            byCurrency[code] = t
        }
        return byCurrency.values.sorted { $0.currency < $1.currency }
    }

    static func itemsWithoutCost<T: Schedulable>(_ items: [T]) -> Int {
        items.filter { ($0.cost ?? 0) <= 0 && $0.status != .cancelled && $0.status != .idea && $0.category.usuallyNeedsBooking }.count
    }

    /// "¥12,000" for a real ISO code, "12,000 XYZ" otherwise.
    static func format(_ amount: Double, currency: String) -> String {
        let code = currency.uppercased()
        if Locale.commonISOCurrencyCodes.contains(code) {
            return amount.formatted(.currency(code: code).precision(.fractionLength(amount.rounded() == amount ? 0 : 2)))
        }
        return amount.formatted(.number.precision(.fractionLength(0...2))) + (code.isEmpty ? "" : " " + code)
    }
}
