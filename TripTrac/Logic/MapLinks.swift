import Foundation

enum MapLinks {
    /// Address is the most precise thing we have; fall back to the place name.
    static func query(place: String, address: String) -> String? {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = place.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { return p.isEmpty || a.localizedCaseInsensitiveContains(p) ? a : "\(p), \(a)" }
        return p.isEmpty ? nil : p
    }

    static func search(_ query: String) -> URL? {
        var c = URLComponents(string: "https://maps.apple.com/")
        c?.queryItems = [URLQueryItem(name: "q", value: query)]
        return c?.url
    }

    /// Public-transit directions (dirflg=r), the way the family's website links them.
    static func transitDirections(from: String, to: String) -> URL? {
        var c = URLComponents(string: "https://maps.apple.com/")
        c?.queryItems = [URLQueryItem(name: "saddr", value: from), URLQueryItem(name: "daddr", value: to),
                         URLQueryItem(name: "dirflg", value: "r")]
        return c?.url
    }
}

enum LinkNormalizer {
    /// "example.com/tickets" → https://example.com/tickets; nil when it can't be a web link.
    static func normalize(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        let withScheme = t.contains("://") ? t : "https://" + t
        guard let url = URL(string: withScheme), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host, host.contains(".") else { return nil }
        return url
    }
}
