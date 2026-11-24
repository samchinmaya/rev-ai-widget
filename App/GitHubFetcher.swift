import Foundation

/// Talks to GitHub through the `gh` CLI you're already signed in to,
/// so no token is ever copied into this app or onto disk.
enum GitHubFetcher {
    enum FetchError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    static let ghCandidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]

    static func ghPath() -> String? {
        ghCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func gh(_ args: [String]) throws -> Data {
        guard let gh = ghPath() else {
            throw FetchError.message("gh CLI not found. Install it with: brew install gh")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gh)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["GH_PROMPT_DISABLED"] = "1"
        env["NO_COLOR"] = "1"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let msg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw FetchError.message(msg.isEmpty ? "gh exited with \(p.terminationStatus)" : msg)
        }
        return data
    }

    // MARK: - API shapes

    private struct SearchResponse: Decodable { let total_count: Int; let items: [SearchItem] }
    private struct SearchItem: Decodable {
        let title: String
        let number: Int
        let html_url: String
        let repository_url: String
        let updated_at: Date?
        let draft: Bool?
    }
    private struct Notification: Decodable {
        struct Subject: Decodable { let title: String; let url: String?; let type: String }
        struct Repo: Decodable { let full_name: String; let html_url: String }
        let reason: String
        let updated_at: Date?
        let subject: Subject
        let repository: Repo
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static func searchPRs(_ query: String) throws -> (items: [RevItem], total: Int) {
        let data = try gh(["api", "-X", "GET", "search/issues",
                           "-f", "q=\(query)", "-f", "sort=updated", "-f", "per_page=20"])
        let res = try decoder.decode(SearchResponse.self, from: data)
        let items = res.items.map { i in
            let repo = i.repository_url.split(separator: "/").suffix(2).joined(separator: "/")
            return RevItem(title: i.title, repo: repo, number: i.number, url: i.html_url,
                           updatedAt: i.updated_at, detail: (i.draft ?? false) ? "draft" : nil)
        }
        return (items, res.total_count)
    }

    private static let notificationLimit = 50

    private static func notifications() throws -> [RevItem] {
        let data = try gh(["api", "notifications?per_page=\(notificationLimit)"])
        return try decoder.decode([Notification].self, from: data).map { n in
            RevItem(title: n.subject.title, repo: n.repository.full_name, number: nil,
                    url: webURL(for: n), updatedAt: n.updated_at,
                    detail: n.reason.replacingOccurrences(of: "_", with: " "))
        }
    }

    /// api.github.com/repos/o/r/pulls/12 -> github.com/o/r/pull/12
    private static func webURL(for n: Notification) -> String {
        guard let api = n.subject.url, api.hasPrefix("https://api.github.com/repos/") else {
            return n.repository.html_url
        }
        var path = String(api.dropFirst("https://api.github.com/repos/".count))
        path = path.replacingOccurrences(of: "/pulls/", with: "/pull/")
        if path.contains("/releases/") || path.contains("/commits/") { return n.repository.html_url }
        return "https://github.com/" + path
    }

    // MARK: - Public

    static func fetch() -> RevSnapshot {
        do {
            let mine = try searchPRs("is:pr is:open archived:false author:@me")
            let reviews = try searchPRs("is:pr is:open archived:false review-requested:@me")
            let notes = try notifications()
            return RevSnapshot(updatedAt: Date(), myPRs: mine.items, reviewRequests: reviews.items,
                               notifications: notes, myPRCount: mine.total, reviewCount: reviews.total,
                               unreadCount: notes.count,
                               unreadCapped: notes.count >= notificationLimit, error: nil)
        } catch {
            // Keep showing the last good data, just flag the error.
            var last = SharedStore.load() ?? RevSnapshot(updatedAt: Date(), myPRs: [], reviewRequests: [],
                                                         notifications: [], myPRCount: 0, reviewCount: 0,
                                                         unreadCount: 0, unreadCapped: false)
            last.error = error.localizedDescription
            return last
        }
    }
}
