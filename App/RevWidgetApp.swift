import AppKit
import ServiceManagement
import SwiftUI
import WidgetKit

/// The host app. It has no Dock icon: it sits in the background, refreshes
/// GitHub data every 5 minutes for the widget, and handles widget taps.
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var shared: AppDelegate!
    let model = StatusModel()
    private var timer: Timer?
    private var window: NSWindow?

    static func main() {
        let app = NSApplication.shared
        shared = AppDelegate()
        app.delegate = shared
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.openRev = { [weak self] in self?.openRev() }
        model.refresh = { [weak self] in self?.refresh() }
        model.showWindow = { [weak self] in self?.showStatusWindow() }

        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }

        // First launch: turn on "open at login" and show the status window once.
        if !UserDefaults.standard.bool(forKey: "didFirstLaunch") {
            UserDefaults.standard.set(true, forKey: "didFirstLaunch")
            try? SMAppService.mainApp.register()
            showStatusWindow()
        }
        model.loginItemEnabled = SMAppService.mainApp.status == .enabled
    }

    // Double-clicking the app while it's already running brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showStatusWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Widget taps (revwidget://...)

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "revwidget" {
            switch url.host {
            case "open-rev":
                openRev()
            case "refresh":
                refresh()
                showStatusWindow()
            case "open":
                if let web = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "url" })?.value,
                   let webURL = URL(string: web), webURL.scheme == "https" {
                    NSWorkspace.shared.open(webURL)
                }
            default:
                break
            }
        }
    }

    // MARK: - Refresh

    func refresh() {
        guard !model.isRefreshing else { return }
        model.isRefreshing = true
        DispatchQueue.global(qos: .utility).async {
            let snapshot = GitHubFetcher.fetch()
            var saveError: String?
            do { try SharedStore.save(snapshot) } catch { saveError = error.localizedDescription }
            WidgetCenter.shared.reloadAllTimelines()
            Self.log("refresh: reviews=\(snapshot.reviewCount) myPRs=\(snapshot.myPRCount) unread=\(snapshot.unreadCount) error=\(snapshot.error ?? "none") save=\(saveError ?? "ok")")
            DispatchQueue.main.async {
                self.model.snapshot = snapshot
                self.model.saveError = saveError
                self.model.isRefreshing = false
            }
        }
    }

    /// Small log at ~/Library/Logs/RevWidget.log (counts and errors only, never titles or tokens).
    static func log(_ line: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/RevWidget.log")
        let text = "\(Date().formatted(.iso8601)) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Open Rev

    /// Opens the installed Rev AI app if there is one, otherwise the dev copy in ~/code/rev-ai.
    func openRev() {
        let ws = NSWorkspace.shared
        if let appURL = ws.urlForApplication(withBundleIdentifier: "dev.revai.app") {
            ws.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        let revPath = UserDefaults.standard.string(forKey: "RevPath")
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("code/rev-ai")

        // Already running via `npm start`? Just bring it forward.
        if let running = ws.runningApplications.first(where: {
            $0.bundleURL?.path.hasPrefix(revPath + "/node_modules/electron") == true
        }) {
            running.activate()
            return
        }
        guard FileManager.default.fileExists(atPath: revPath + "/package.json") else {
            model.saveError = "Couldn't find Rev. Set its folder with: defaults write dev.revai.widget RevPath /path/to/rev-ai"
            showStatusWindow()
            return
        }
        let quoted = "'" + revPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "cd \(quoted) && nohup npm start >/dev/null 2>&1 &"]
        try? p.run()
    }

    // MARK: - Status window

    func showStatusWindow() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: StatusView(model: model)))
            w.title = "Rev Widget"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

final class StatusModel: ObservableObject {
    @Published var snapshot: RevSnapshot?
    @Published var saveError: String?
    @Published var isRefreshing = false
    @Published var loginItemEnabled = false
    var openRev: () -> Void = {}
    var refresh: () -> Void = {}
    var showWindow: () -> Void = {}

    func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            saveError = error.localizedDescription
        }
        loginItemEnabled = SMAppService.mainApp.status == .enabled
    }
}

struct StatusView: View {
    @ObservedObject var model: StatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rev Widget").font(.title2.bold())
            Text("Keeps the Rev widget up to date from your `gh` login. It runs in the background with no Dock icon.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let s = model.snapshot {
                HStack(spacing: 24) {
                    stat(s.reviewCount, "Reviews")
                    stat(s.myPRCount, "My PRs")
                    stat(s.unreadCount, s.unreadCapped ? "Unread (50+)" : "Unread")
                }
                Text("Updated \(s.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                if let e = s.error { Label(e, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption) }
            } else {
                ProgressView().controlSize(.small)
            }
            if let e = model.saveError { Label(e, systemImage: "xmark.octagon").foregroundStyle(.red).font(.caption) }

            Toggle("Open at login", isOn: Binding(get: { model.loginItemEnabled }, set: { model.setLoginItem($0) }))

            Text("Add the widget: right-click the desktop → Edit Widgets…, search \"Rev\".")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Button(model.isRefreshing ? "Refreshing…" : "Refresh now") { model.refresh() }
                    .disabled(model.isRefreshing)
                Button("Open Rev") { model.openRev() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading) {
            Text("\(n)").font(.title.monospacedDigit().bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
