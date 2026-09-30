import AppKit
import Foundation
import SunriseCore

/// Drives the desktop Spotify app over AppleScript (no Web API, no Premium needed).
/// macOS asks once for permission to control Spotify (Privacy & Security → Automation).
@MainActor
final class Spotify {
    static let bundleID = "com.spotify.client"

    enum Failure: Error {
        case notInstalled
        case notAuthorized
        case script(String)

        var message: String {
            switch self {
            case .notInstalled: return "Spotify app isn't installed."
            case .notAuthorized: return "Allow Sunrise to control Spotify: System Settings → Privacy & Security → Automation."
            case .script(let text): return "Spotify didn't respond: \(text)"
            }
        }
    }

    /// AppleScript runs off the main thread: launching Spotify can take seconds.
    private let queue = DispatchQueue(label: "sunrise.spotify")
    /// Volumes to restore after the alarm; nil when we haven't touched them.
    private var savedSpotifyVolume: Int?
    private var savedOutput: (volume: Int, muted: Bool)?
    private var lastVolume: Int?
    private(set) var isPlayingAlarm = false

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    private static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    // MARK: - Connect

    /// Checks we may control Spotify (triggers the permission prompt the first time).
    func connect(_ done: @escaping @MainActor (Failure?) -> Void) {
        guard Self.isInstalled else { return done(.notInstalled) }
        launchHidden { [weak self] in
            self?.run(#"tell application id "com.spotify.client" to get player state"#) { result in
                switch result {
                case .success: done(nil)
                case .failure(let f): done(f)
                }
            }
        }
    }

    /// Resolves a spotify.link short link: follows redirects, then looks for the open.spotify.com link
    /// in the final URL or the page (Branch links sometimes redirect in JavaScript).
    static func resolveShortLink(_ link: String, _ done: @escaping @MainActor (String?) -> Void) {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else { return done(nil) }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let finalURL = response?.url?.absoluteString ?? ""
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let uri = SpotifyURI.find(in: finalURL) ?? SpotifyURI.find(in: body)
            DispatchQueue.main.async { done(uri) }
        }.resume()
    }

    /// Display name for a spotify: URI via the public oEmbed endpoint (no auth).
    static func fetchTitle(for uri: String, _ done: @escaping @MainActor (String?) -> Void) {
        let parts = uri.split(separator: ":")
        guard parts.count == 3,
              var comps = URLComponents(string: "https://open.spotify.com/oembed")
        else { return done(nil) }
        comps.queryItems = [URLQueryItem(name: "url", value: "https://open.spotify.com/\(parts[1])/\(parts[2])")]
        guard let url = comps.url else { return done(nil) }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let title = data
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                .flatMap { $0["title"] as? String }
            DispatchQueue.main.async { done(title) }
        }.resume()
    }

    // MARK: - Alarm

    /// Starts playback at volume 0; `setVolume` then ramps it. Makes sure the Mac itself is audible.
    func startAlarm(uri: String?) {
        guard Self.isInstalled, !isPlayingAlarm else { return }
        isPlayingAlarm = true
        lastVolume = 0
        ensureAudibleOutput()
        launchHidden { [weak self] in
            guard let self, self.isPlayingAlarm else { return }
            self.run(#"tell application id "com.spotify.client" to get sound volume"#) { result in
                if case .success(let v) = result, self.savedSpotifyVolume == nil {
                    self.savedSpotifyVolume = Int(v) ?? nil
                }
                let play = uri.map { #"play track "\#($0)""# } ?? "play"
                self.run("""
                tell application id "com.spotify.client"
                    set sound volume to 0
                    \(play)
                end tell
                """) { _ in }
            }
        }
    }

    /// 0…100. Sent only when the integer value changes.
    func setVolume(_ volume: Int) {
        guard isPlayingAlarm, Self.isRunning, volume != lastVolume else { return }
        lastVolume = volume
        run(#"tell application id "com.spotify.client" to set sound volume to \#(volume)"#) { _ in }
    }

    /// Pause and hand the volumes back.
    func stopAlarm() {
        guard isPlayingAlarm else { return }
        isPlayingAlarm = false
        lastVolume = nil
        if Self.isRunning {
            let restore = savedSpotifyVolume.map { "\n    set sound volume to \($0)" } ?? ""
            run("""
            tell application id "com.spotify.client"
                pause\(restore)
            end tell
            """) { _ in }
        }
        savedSpotifyVolume = nil
        if let out = savedOutput {
            run("set volume output volume \(out.volume) output muted \(out.muted)") { _ in }
            savedOutput = nil
        }
    }

    // MARK: - Plumbing

    /// Mac muted or below 50% at night → unmute / raise to 50% for the alarm, restored on stop.
    private func ensureAudibleOutput() {
        run("get {output volume, output muted} of (get volume settings)") { [weak self] result in
            guard let self, case .success(let text) = result else { return }
            let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, let volume = Int(parts[0]) else { return }
            let muted = parts[1] == "true"
            guard muted || volume < 50 else { return }
            self.savedOutput = (volume, muted)
            self.run("set volume output volume \(max(volume, 50)) without output muted") { _ in }
        }
    }

    /// Opens Spotify in the background (no window over the alarm) and waits until it's up.
    private func launchHidden(_ then: @escaping @MainActor () -> Void) {
        if Self.isRunning { return then() }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            // Spotify accepts Apple Events a moment after it launches.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { then() }
        }
    }

    private func run(_ source: String, _ done: @escaping @MainActor (Result<String, Failure>) -> Void) {
        queue.async {
            var error: NSDictionary?
            let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let result: Result<String, Failure>
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                // -1743: not authorized; -1744: would need to ask but can't.
                result = .failure(code == -1743 || code == -1744
                    ? .notAuthorized
                    : .script(error[NSAppleScript.errorMessage] as? String ?? "error \(code)"))
            } else {
                result = .success(Self.text(of: output))
            }
            DispatchQueue.main.async { done(result) }
        }
    }

    /// Flattens a descriptor: lists become "a, b".
    private nonisolated static func text(of d: NSAppleEventDescriptor?) -> String {
        guard let d else { return "" }
        if d.numberOfItems > 0 {
            return (1...d.numberOfItems).map { text(of: d.atIndex($0)) }.joined(separator: ", ")
        }
        if d.descriptorType == typeTrue { return "true" }
        if d.descriptorType == typeFalse { return "false" }
        return d.stringValue ?? ""
    }
}
