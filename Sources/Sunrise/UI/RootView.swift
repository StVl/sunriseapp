import SwiftUI

/// Lamp + the three layers. All layers stay mounted; transitions are scale/opacity/blur (SPEC §10).
struct RootView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var license: LicenseManager

    /// Welcome / paywall (forced) or License… (by hand) instead of the alarm panel.
    private var licenseVisible: Bool {
        state.phase == .editing && (!license.state.canUseApp || state.showLicensePanel)
    }
    @State private var panelFrame: CGRect = .zero
    @State private var cardFrame: CGRect = .zero

    /// Everything collapses into / grows out of this point: 24 pt from the left and bottom edges.
    private func cornerAnchor(for frame: CGRect, in size: CGSize) -> UnitPoint {
        guard frame.width > 0, frame.height > 0 else { return .bottomLeading }
        return UnitPoint(x: (24 - frame.minX) / frame.width, y: (size.height - 24 - frame.minY) / frame.height)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LavaLampView(state: state)

                Text("Sunrise")
                    .font(AppFont.make(13, .semibold))
                    .tracking(13 * 0.02)
                    .foregroundColor(Color(r: 255, g: 245, b: 235, a: 0.85))
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                    .frame(height: 52)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                EditingPanel()
                    .cornerCollapse(
                        visible: state.phase == .editing && !state.sleepToastVisible && !licenseVisible,
                        anchor: cornerAnchor(for: panelFrame, in: geo.size),
                        inDelay: 0.12, scaleDuration: 0.7
                    )
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { panelFrame = $0 }
                    .padding(.top, 60)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                LicensePanel()
                    .scaleEffect(licenseVisible ? 1 : 0.94)
                    .opacity(licenseVisible ? 1 : 0)
                    .blur(radius: licenseVisible ? 0 : 6)
                    .animation(licenseVisible ? Theme.sheet(0.5).delay(0.15) : .easeInOut(duration: 0.35), value: licenseVisible)
                    .allowsHitTesting(licenseVisible)
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                SleepToast()
                    .scaleEffect(state.sleepToastVisible ? 1 : 0.92)
                    .opacity(state.sleepToastVisible ? 1 : 0)
                    // In after the panel has started to leave; out together with the lamp dimming.
                    .animation(state.sleepToastVisible ? Theme.sheet(0.5).delay(0.25) : .easeInOut(duration: 0.6), value: state.sleepToastVisible)
                    .allowsHitTesting(state.sleepToastVisible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ArmedPill()
                    .pillTransition(visible: state.phase == .armed)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                RingingCard()
                    .cornerCollapse(
                        visible: state.phase == .ringing,
                        anchor: cornerAnchor(for: cardFrame, in: geo.size),
                        inDelay: 0, scaleDuration: 0.8
                    )
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { cardFrame = $0 }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .coordinateSpace(name: "root")
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}

private extension View {
    /// Panel/card ↔ corner: scale 0.18 around the window corner, plus opacity and blur.
    func cornerCollapse(visible: Bool, anchor: UnitPoint, inDelay: Double, scaleDuration: Double) -> some View {
        self
            .scaleEffect(visible ? 1 : 0.18, anchor: anchor)
            .animation(visible ? Theme.sheet(scaleDuration).delay(inDelay) : Theme.sheet(scaleDuration), value: visible)
            .blur(radius: visible ? 0 : 6)
            .opacity(visible ? 1 : 0)
            .animation(visible ? .easeInOut(duration: 0.5).delay(inDelay) : .easeInOut(duration: 0.5), value: visible)
            .allowsHitTesting(visible)
    }

    /// Armed pill: translateY(8) scale(0.85) → identity, appears after the panel has left.
    func pillTransition(visible: Bool) -> some View {
        self
            .scaleEffect(visible ? 1 : 0.85, anchor: .bottomLeading)
            .offset(y: visible ? 0 : 8)
            .animation(visible ? Theme.sheet(0.5).delay(0.38) : Theme.sheet(0.5), value: visible)
            .opacity(visible ? 1 : 0)
            .animation(visible ? .easeInOut(duration: 0.35).delay(0.38) : .easeInOut(duration: 0.35), value: visible)
            .allowsHitTesting(visible)
    }
}
