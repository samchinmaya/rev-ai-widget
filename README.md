# Rev Widget

A free macOS desktop / Notification Center widget for [Rev](../rev-ai). It shows:

- **To review**: open PRs where your review is requested
- **My PRs**: your open PRs
- **Unread**: unread GitHub notifications

Tapping a PR or notification opens it on GitHub. Tapping the **Rev** title opens Rev.
Small, medium and large sizes are available.

Completely free: built with Xcode and signed with a free Apple ID ("Personal Team"). No paid developer account, no AI calls, no tokens stored by this app.

## How it works

```
gh CLI (your login) ──> Rev Widget.app (background, no Dock icon)
                          │  every 5 min + on wake
                          ▼
              App Group folder: snapshot.json
                          │
                          ▼
              Widget extension (sandboxed, read-only, no network)
```

A widget can't run programs or reach your keychain, so the small host app does the GitHub calls through `gh` and writes a JSON snapshot that the widget reads. Widget taps go to the host app via `revwidget://` links, which opens the browser or Rev.

## Setup (once)

1. **Add your Apple ID to Xcode (free).** Open Xcode, go to **Settings → Accounts**, click **+**, choose **Apple ID** and sign in. A "Personal Team" appears. No payment needed.
2. **Build and install:**
   ```bash
   cd ~/code/rev-ai-widget && ./build.sh
   ```
   This finds your Personal Team, builds, copies **Rev Widget.app** to `~/Applications`, launches it and turns on "Open at login". A small status window shows your counts.
   If you'd rather pin the team, copy `Local.xcconfig.example` to `Local.xcconfig` and set `DEVELOPMENT_TEAM`.
3. **Add the widget:**
   - **Desktop:** right-click an empty spot on the desktop → **Edit Widgets…** → search **Rev** → drag the size you want onto the desktop.
   - **Notification Center:** click the date/time in the menu bar → scroll to the bottom → **Edit Widgets…** → search **Rev** → click or drag it in.

## Everyday use

- Data refreshes every 5 minutes and when your Mac wakes. To force it, open **Rev Widget** from `~/Applications` and click **Refresh now**.
- "Open Rev" opens the installed **Rev AI** app (`dev.revai.app`) if you have it. Otherwise it brings forward, or starts, the dev copy in `~/code/rev-ai` with `npm start`. Point it elsewhere with:
  ```bash
  defaults write dev.revai.widget RevPath /path/to/rev-ai
  ```
- Log (counts and errors only): `~/Library/Logs/RevWidget.log`
- Quit or turn off "Open at login" from the status window.

## Notes

- Free Personal Team certificates are valid for a year. If the widget stops updating after that, run `./build.sh` again.
- The project file is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). Open `RevWidget.xcodeproj` in Xcode to edit and preview the widget.
- Uninstall: quit from the status window, then delete `~/Applications/Rev Widget.app`.
