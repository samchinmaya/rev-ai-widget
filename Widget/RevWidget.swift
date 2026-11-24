import SwiftUI
import WidgetKit

struct RevEntry: TimelineEntry {
    let date: Date
    let snapshot: RevSnapshot?
}

/// The widget never touches the network: it reads the JSON the host app writes
/// into the shared App Group folder. The host app pokes WidgetCenter after each write.
struct RevProvider: TimelineProvider {
    func placeholder(in context: Context) -> RevEntry { RevEntry(date: .now, snapshot: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (RevEntry) -> Void) {
        let s = SharedStore.load()
        completion(RevEntry(date: .now, snapshot: s ?? (context.isPreview ? .sample : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RevEntry>) -> Void) {
        let entry = RevEntry(date: .now, snapshot: SharedStore.load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

@main
struct RevWidgetBundle: WidgetBundle {
    var body: some Widget { RevStatusWidget() }
}

struct RevStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RevStatusWidget", provider: RevProvider()) { entry in
            RevWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Rev")
        .description("Your open PRs, review requests and unread GitHub notifications.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Views

private enum Palette {
    static let reviews = Color.orange
    static let mine = Color.green
    static let unread = Color.blue
}

struct RevWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: RevEntry

    var body: some View {
        if let s = entry.snapshot {
            switch family {
            case .systemSmall: SmallView(s: s)
            case .systemMedium: MediumView(s: s)
            default: LargeView(s: s)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Header(s: nil)
                Spacer()
                Text("Open the Rev Widget app to connect to GitHub.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .widgetURL(RevLinks.refresh)
        }
    }
}

private struct Header: View {
    let s: RevSnapshot?
    var body: some View {
        HStack(spacing: 4) {
            Link(destination: RevLinks.openRev) {
                Label("Rev", systemImage: "arrow.triangle.pull").font(.headline)
            }
            Spacer()
            if let s {
                if s.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption2)
                }
                Text(s.updatedAt, style: .relative)
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .frame(maxWidth: 70, alignment: .trailing)
            }
        }
    }
}

private struct CountRow: View {
    let count: String
    let label: String
    let color: Color
    let link: String
    var body: some View {
        Link(destination: RevLinks.open(link)) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(count).font(.title2.monospacedDigit().bold()).foregroundStyle(color)
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }
}

private func counts(_ s: RevSnapshot) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        CountRow(count: "\(s.reviewCount)", label: "to review", color: Palette.reviews, link: RevLinks.reviewRequestedPage)
        CountRow(count: "\(s.myPRCount)", label: "my PRs", color: Palette.mine, link: RevLinks.myPRsPage)
        CountRow(count: s.unreadCapped ? "50+" : "\(s.unreadCount)", label: "unread", color: Palette.unread, link: RevLinks.notificationsPage)
    }
}

private struct ItemRow: View {
    let item: RevItem
    let color: Color
    var body: some View {
        Link(destination: RevLinks.open(item.url)) {
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(color).frame(width: 6, height: 6).padding(.top, 5)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title).font(.caption.weight(.medium)).lineLimit(1)
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }
    private var subtitle: String {
        var parts = [item.repo + (item.number.map { " #\($0)" } ?? "")]
        if let d = item.detail { parts.append(d) }
        return parts.joined(separator: " · ")
    }
}

private struct SmallView: View {
    let s: RevSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Header(s: s)
            Spacer(minLength: 0)
            counts(s)
        }
    }
}

private struct MediumView: View {
    let s: RevSnapshot
    var body: some View {
        let top = Array((s.reviewRequests.map { ($0, Palette.reviews) } + s.myPRs.map { ($0, Palette.mine) }).prefix(3))
        VStack(alignment: .leading, spacing: 6) {
            Header(s: s)
            HStack(alignment: .top, spacing: 12) {
                counts(s).frame(width: 100)
                VStack(alignment: .leading, spacing: 5) {
                    if top.isEmpty {
                        Text("No open PRs or review requests 🎉").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(top, id: \.0.id) { item, color in ItemRow(item: item, color: color) }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct LargeView: View {
    let s: RevSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Header(s: s)
            Section(title: "To review", count: "\(s.reviewCount)", items: s.reviewRequests, color: Palette.reviews, link: RevLinks.reviewRequestedPage, limit: 3)
            Section(title: "My PRs", count: "\(s.myPRCount)", items: s.myPRs, color: Palette.mine, link: RevLinks.myPRsPage, limit: 3)
            Section(title: "Unread", count: s.unreadCapped ? "50+" : "\(s.unreadCount)", items: s.notifications, color: Palette.unread, link: RevLinks.notificationsPage, limit: 3)
            Spacer(minLength: 0)
            if let e = s.error {
                Text(e).font(.caption2).foregroundStyle(.orange).lineLimit(1)
            }
        }
    }

    private struct Section: View {
        let title: String
        let count: String
        let items: [RevItem]
        let color: Color
        let link: String
        let limit: Int
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Link(destination: RevLinks.open(link)) {
                    HStack {
                        Text(title).font(.caption.bold()).foregroundStyle(color)
                        Text(count).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                if items.isEmpty {
                    Text("Nothing here").font(.caption2).foregroundStyle(.tertiary)
                }
                ForEach(items.prefix(limit)) { ItemRow(item: $0, color: color) }
            }
        }
    }
}

#Preview(as: .systemMedium) {
    RevStatusWidget()
} timeline: {
    RevEntry(date: .now, snapshot: .sample)
}
