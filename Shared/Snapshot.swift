import Foundation

/// One row in the widget: a PR, a review request or a notification.
struct RevItem: Codable, Hashable, Identifiable {
    var id: String { url + title }
    let title: String
    let repo: String
    let number: Int?
    let url: String
    let updatedAt: Date?
    var detail: String?
}

/// Everything the widget shows. The host app writes it, the widget only reads it.
struct RevSnapshot: Codable {
    var updatedAt: Date
    var myPRs: [RevItem]
    var reviewRequests: [RevItem]
    var notifications: [RevItem]
    var myPRCount: Int
    var reviewCount: Int
    var unreadCount: Int
    var unreadCapped: Bool
    var error: String?

    static let sample = RevSnapshot(
        updatedAt: Date(),
        myPRs: [
            RevItem(title: "Add Dynamic Island diff preview", repo: "you/rev-ai", number: 42, url: "https://github.com", updatedAt: Date(), detail: nil),
            RevItem(title: "Fix inbox polling backoff", repo: "you/rev-ai", number: 39, url: "https://github.com", updatedAt: Date(), detail: "draft"),
        ],
        reviewRequests: [
            RevItem(title: "Refactor risk scoring", repo: "team/api", number: 118, url: "https://github.com", updatedAt: Date(), detail: nil),
        ],
        notifications: [
            RevItem(title: "CI failed on main", repo: "team/api", number: nil, url: "https://github.com/notifications", updatedAt: Date(), detail: "ci_activity"),
        ],
        myPRCount: 2,
        reviewCount: 1,
        unreadCount: 5,
        unreadCapped: false,
        error: nil
    )
}

enum SharedStore {
    /// "<TEAMID>.dev.revai.widget", filled in from Info.plist at build time.
    static var groupID: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String) ?? "dev.revai.widget"
    }

    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("snapshot.json")
    }

    static func load() -> RevSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RevSnapshot.self, from: data)
    }

    static func save(_ snapshot: RevSnapshot) throws {
        guard let url = fileURL else {
            throw NSError(domain: "RevWidget", code: 1, userInfo: [NSLocalizedDescriptionKey: "App Group container unavailable (\(groupID)). Is the app signed with your team?"])
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}

/// Widget taps go through the host app's revwidget:// scheme so they work the same everywhere.
enum RevLinks {
    static let openRev = URL(string: "revwidget://open-rev")!
    static let refresh = URL(string: "revwidget://refresh")!
    static let reviewRequestedPage = "https://github.com/pulls/review-requested"
    static let myPRsPage = "https://github.com/pulls"
    static let notificationsPage = "https://github.com/notifications"

    static func open(_ web: String) -> URL {
        var c = URLComponents()
        c.scheme = "revwidget"
        c.host = "open"
        c.queryItems = [URLQueryItem(name: "url", value: web)]
        return c.url ?? openRev
    }
}
