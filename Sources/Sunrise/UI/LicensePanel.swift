import SunriseCore
import SwiftUI

/// Welcome (first launch), paywall (trial over) and "License…" (by hand), in the glass panel.
struct LicensePanel: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var license: LicenseManager
    @State private var key = ""

    private enum Mode { case welcome, paywall, manageTrial, licensed }

    private var mode: Mode {
        switch license.state {
        case .undecided: return .welcome
        case .expired: return .paywall
        case .trial: return .manageTrial
        case .licensed: return .licensed
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            switch mode {
            case .welcome:
                keyEntry
                orDivider
                Button("Start 30-day free trial") { license.startTrial() }
                    .buttonStyle(PillButtonStyle(kind: .primary, height: 44, fontSize: 15, fullWidth: true))
                buyLink(text: "Buy a license — $7")
            case .paywall:
                Button("Buy for $7") { license.openCheckout() }
                    .buttonStyle(PillButtonStyle(kind: .primary, height: 44, fontSize: 15, fullWidth: true))
                orDivider
                keyEntry
            case .manageTrial:
                keyEntry
                buyLink(text: "Buy a license — $7")
            case .licensed:
                licensedInfo
            }

            if let error = license.error {
                Text(error)
                    .font(AppFont.make(12))
                    .foregroundColor(Color(hex: 0xff9a7a))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(EdgeInsets(top: 28, leading: 36, bottom: 26, trailing: 36))
        .frame(maxWidth: 440)
        .glass(radius: 30)
        .onChange(of: license.record) { _, record in
            // Activated from "License…": back to the list.
            if record != nil, mode == .licensed, state.showLicensePanel { key = "" }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Text(title)
                    .font(AppFont.make(24, .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(AppFont.make(14))
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            // Closable only when opened by hand; the welcome screen and the paywall stay.
            if state.showLicensePanel, license.state.canUseApp {
                Button { state.showLicensePanel = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(GhostButtonStyle(shape: AnyShape(Circle()), hoverOpacity: 0.12))
                .keyboardShortcut(.cancelAction)
                .offset(x: 16, y: -12)
            }
        }
    }

    private var title: String {
        switch mode {
        case .welcome: return "Welcome to Sunrise"
        case .paywall: return "Your free trial has ended"
        case .manageTrial:
            if case .trial(let days, _) = license.state { return "Trial · \(days) \(days == 1 ? "day" : "days") left" }
            return "Trial"
        case .licensed: return "Sunrise is yours"
        }
    }

    private var subtitle: String {
        switch mode {
        case .welcome: return "Wake up with light. Enter your license key, or try Sunrise free for 30 days."
        case .paywall: return "Buy Sunrise once — $7, yours forever, on up to 3 Macs. Alarms you already set keep ringing for one more day."
        case .manageTrial: return "Enter your license key to keep Sunrise after the trial."
        case .licensed: return "Thanks for supporting Sunrise."
        }
    }

    private var keyEntry: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("SUNRISE-XXXXXXXX-…", text: $key)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .onSubmit { license.activate(key) }
                Button {
                    license.activate(key)
                } label: {
                    if license.busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Activate")
                    }
                }
                .buttonStyle(PillButtonStyle(kind: mode == .paywall ? .secondary : .secondary, height: 40))
                .disabled(license.busy || key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Your key is on the order page and in the receipt email from Polar.")
                .font(AppFont.make(11))
                .foregroundColor(Theme.textTertiary)
        }
    }

    private var orDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            Text("or").font(AppFont.make(12)).foregroundColor(Theme.textTertiary)
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }
    }

    private func buyLink(text: String) -> some View {
        Button(text) { license.openCheckout() }
            .buttonStyle(.plain)
            .font(AppFont.make(13, .semibold))
            .foregroundColor(Theme.textSecondary)
            .underline()
    }

    private var licensedInfo: some View {
        VStack(spacing: 14) {
            HStack {
                Text("License").foregroundColor(Theme.textSecondary)
                Spacer()
                Text(license.maskedKey ?? "").font(.system(size: 13, design: .monospaced)).foregroundColor(Theme.textPrimary)
            }
            .font(AppFont.make(13))
            Button {
                license.deactivate()
            } label: {
                if license.busy { ProgressView().controlSize(.small) } else { Text("Deactivate this Mac") }
            }
            .buttonStyle(PillButtonStyle(kind: .secondary, height: 36))
            Text("Frees one of your 3 activations, e.g. before moving to a new Mac.")
                .font(AppFont.make(11))
                .foregroundColor(Theme.textTertiary)
        }
    }
}

/// "Trial · 23 days left" chip next to the list title; opens License….
struct TrialBadge: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var license: LicenseManager

    var body: some View {
        if case .trial(let days, _) = license.state {
            Button { state.showLicensePanel = true } label: {
                Text("Trial · \(days) \(days == 1 ? "day" : "days") left")
                    .font(AppFont.make(11, .semibold))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .help("Enter a license key or buy Sunrise")
        }
    }
}
