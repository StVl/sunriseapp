import SunriseCore
import SwiftUI

/// 44×26 switch (SPEC §6.1).
struct AlarmToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.toggleOn : Color.white.opacity(0.22))
                    .frame(width: 44, height: 26)
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .padding(2)
            }
            .animation(.easeInOut(duration: 0.2), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

/// M T W T F S S (SPEC §6.3).
struct DaysPicker: View {
    @Binding var days: [Bool]
    private let letters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    let on = days[i]
                    Button { days[i].toggle() } label: {
                        Text(letters[i])
                            .font(AppFont.make(14, .semibold))
                            .foregroundColor(on ? Theme.textDark : Color(r: 255, g: 240, b: 225, a: 0.75))
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(on ? Theme.cream : Color.white.opacity(0.08)))
                            .overlay(Circle().strokeBorder(Color.white.opacity(on ? 0 : 0.12), lineWidth: 1))
                            .shadow(color: on ? Theme.warmGlow : .clear, radius: 6, y: 2)
                            .contentShape(Circle())
                            .animation(.easeInOut(duration: 0.2), value: on)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(DaysLabel.make(days))
                .font(AppFont.make(12))
                .foregroundColor(Theme.textTertiary)
        }
    }
}

/// 5–30 min slider with custom drawing (SPEC §6.5).
struct SunriseSlider: View {
    @Binding var value: Int
    private let range = Alarm.sunriseRange
    private let ticks = [5, 10, 15, 20, 25, 30]

    private var span: CGFloat { CGFloat(range.upperBound - range.lowerBound) }
    private func fraction(_ v: Int) -> CGFloat { CGFloat(v - range.lowerBound) / span }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let f = fraction(value)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16)).frame(height: 4)
                    Capsule()
                        .fill(LinearGradient(colors: [Color(r: 255, g: 200, b: 120, a: 0.5), Color(hex: 0xffe2a8)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, f * w), height: 4)
                    Circle()
                        .fill(.white)
                        .frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .shadow(color: Color(r: 255, g: 210, b: 140, a: 0.7), radius: 9)
                        .offset(x: f * w - 11)
                }
                .frame(width: w, height: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { g in
                        let f = min(max(g.location.x / max(w, 1), 0), 1)
                        value = Int((CGFloat(range.lowerBound) + f * span).rounded())
                    }
                )
            }
            .frame(height: 28)

            GeometryReader { geo in
                ForEach(ticks, id: \.self) { t in
                    Text("\(t)")
                        .font(AppFont.make(12))
                        .foregroundColor(Theme.textTertiary)
                        .fixedSize()
                        .position(x: fraction(t) * geo.size.width, y: 8)
                }
            }
            .frame(height: 16)
        }
    }
}

/// Spotify row (SPEC §6.6): connect through the desktop app, optionally with a link to what to play.
struct SpotifyButton: View {
    @EnvironmentObject var state: AppState
    @State private var hover = false
    @State private var showConnect = false

    private var link: SpotifyLink { state.spotifyLink }

    private var subtitle: String {
        guard link.uri != nil else { return "Resumes your last track when the light starts" }
        return link.playlist.isEmpty ? "Plays your Spotify pick when the light starts" : "Plays “\(link.playlist)” when the light starts"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button { showConnect = true } label: {
                HStack(spacing: 12) {
                    let dot = link.connected ? Color(hex: 0x3ddc84) : Color(r: 255, g: 240, b: 225, a: 0.4)
                    Circle()
                        .fill(dot)
                        .frame(width: 10, height: 10)
                        .shadow(color: dot.opacity(0.8), radius: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.connected ? "Spotify connected" : "Connect Spotify")
                            .font(AppFont.make(14, .semibold))
                            .foregroundColor(Theme.textPrimary)
                        if link.connected {
                            Text(subtitle)
                                .font(AppFont.make(12))
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 8)
                    if !link.connected {
                        Text("Connect")
                            .font(AppFont.make(13))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showConnect, arrowEdge: .bottom) {
                SpotifyConnectForm(isPresented: $showConnect)
                    .environmentObject(state)
            }

            if link.connected {
                Button("Disconnect") { state.disconnectSpotify() }
                    .buttonStyle(.plain)
                    .font(AppFont.make(13))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(hover ? 0.14 : 0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

private struct SpotifyConnectForm: View {
    @EnvironmentObject var state: AppState
    @Binding var isPresented: Bool
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.spotifyLink.connected ? "Change music" : "Connect Spotify")
                .font(AppFont.make(15, .semibold))
            Text("Paste a link to an artist, playlist, album or track (Share → Copy link). An artist plays from the top of their page. Leave it empty to resume whatever you played last.")
                .font(AppFont.make(12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("https://open.spotify.com/artist/…", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(connect)
            if let error = state.spotifyError {
                Text(error)
                    .font(AppFont.make(12))
                    .foregroundColor(Color(hex: 0xff8a6b))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if state.spotifyBusy {
                    ProgressView().controlSize(.small)
                    Text("Waiting for Spotify…").font(AppFont.make(12)).foregroundColor(.secondary)
                }
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Connect", action: connect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(state.spotifyBusy)
            }
        }
        .padding(18)
        .frame(width: 340)
        .onAppear {
            state.clearSpotifyError()
            if let uri = state.spotifyLink.uri { text = uri }
        }
        // Close once connected (or re-connected with a new link).
        .onChange(of: state.spotifyLink) { _, link in
            if link.connected, !state.spotifyBusy { isPresented = false }
        }
    }

    private func connect() {
        state.connectSpotify(link: text)
    }
}

/// Sunrise progress bar (SPEC §8), styled like the slider track.
struct ProgressTrack: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                Capsule()
                    .fill(LinearGradient(colors: [Color(r: 255, g: 200, b: 120, a: 0.5), Color(hex: 0xffe2a8)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * fraction))
                    .shadow(color: Color(r: 255, g: 210, b: 140, a: 0.8), radius: 6)
            }
        }
        .frame(height: 4)
    }
}
