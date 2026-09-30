import AppKit
import Foundation
import SunriseCore

/// Trial and license state, kept in the keychain.
@MainActor
final class LicenseManager: ObservableObject {
    @Published private(set) var trialStart: Date?
    @Published private(set) var record: LicenseRecord?
    @Published private(set) var busy = false
    @Published var error: String?
    /// Bumped hourly so "days left" and expiry refresh on screen.
    @Published private(set) var now = Date()

    private enum Account {
        static let trialStart = "trialStart"
        static let license = "license"
    }

    private var clock: Timer?

    init() {
        if let data = KeychainStore.read(Account.trialStart), let seconds = Double(String(decoding: data, as: UTF8.self)) {
            trialStart = Date(timeIntervalSince1970: seconds)
        }
        if let data = KeychainStore.read(Account.license) {
            record = try? JSONDecoder().decode(LicenseRecord.self, from: data)
        }
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.now = Date()
                self?.revalidateIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        clock = timer
        revalidateIfNeeded()
    }

    var state: LicenseState { LicensePolicy.state(trialStart: trialStart, license: record, now: Date()) }

    var alarmsMayRing: Bool { LicensePolicy.alarmsMayRing(state, now: Date()) }

    /// "SUNRISE-…-6D2344CF" → "SUNRISE-…44CF", for showing which key is active.
    var maskedKey: String? {
        guard let key = record?.key else { return nil }
        let prefix = key.split(separator: "-").first.map(String.init) ?? ""
        return "\(prefix)-…\(key.suffix(4))"
    }

    // MARK: - Actions

    func startTrial() {
        guard trialStart == nil else { return }
        let start = Date()
        KeychainStore.write(Account.trialStart, Data(String(start.timeIntervalSince1970).utf8))
        trialStart = start
        // Starting the trial never wipes the start date: a later reinstall keeps counting from here.
    }

    func activate(_ rawKey: String) {
        let key = LicensePolicy.normalize(rawKey)
        guard !key.isEmpty else {
            error = PolarLicenseAPI.Failure.invalid.message
            return
        }
        busy = true
        error = nil
        let label = Host.current().localizedName ?? "Mac"
        Task {
            defer { busy = false }
            do {
                let id = try await PolarLicenseAPI.activate(key: key, label: label)
                store(LicenseRecord(key: key, activationID: id, activatedAt: Date(), lastValidatedAt: Date()))
            } catch let failure as PolarLicenseAPI.Failure {
                error = failure.message
            } catch {
                self.error = PolarLicenseAPI.Failure.offline.message
            }
        }
    }

    /// Frees this Mac's seat so the key can go to another one.
    func deactivate() {
        guard let record else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await PolarLicenseAPI.deactivate(key: record.key, activationID: record.activationID)
                store(nil)
            } catch PolarLicenseAPI.Failure.notFound {
                store(nil) // already gone on Polar's side
            } catch let failure as PolarLicenseAPI.Failure {
                error = failure.message
            } catch {
                self.error = PolarLicenseAPI.Failure.offline.message
            }
        }
    }

    /// Weekly check. Only a clear answer from Polar (revoked key, removed activation) drops the
    /// license; being offline never does.
    func revalidateIfNeeded() {
        guard let record, LicensePolicy.needsRevalidation(record, now: Date()) else { return }
        Task {
            do {
                let status = try await PolarLicenseAPI.validate(key: record.key, activationID: record.activationID)
                if status == "granted" {
                    var updated = record
                    updated.lastValidatedAt = Date()
                    store(updated)
                } else {
                    store(nil)
                }
            } catch PolarLicenseAPI.Failure.notFound {
                store(nil)
            } catch {
                // Offline or a server hiccup: keep the license, try again next time.
            }
        }
    }

    func openCheckout() {
        NSWorkspace.shared.open(LicenseConfig.checkoutURL)
    }

    // MARK: - Debug

    func debugReset() {
        KeychainStore.delete(Account.trialStart)
        KeychainStore.delete(Account.license)
        trialStart = nil
        record = nil
        error = nil
    }

    func debugExpireTrial() {
        let start = Date().addingTimeInterval(-Double(LicensePolicy.trialDays + 1) * 24 * 3600)
        KeychainStore.write(Account.trialStart, Data(String(start.timeIntervalSince1970).utf8))
        KeychainStore.delete(Account.license)
        trialStart = start
        record = nil
    }

    // MARK: -

    private func store(_ new: LicenseRecord?) {
        if let new, let data = try? JSONEncoder().encode(new) {
            KeychainStore.write(Account.license, data)
        } else {
            KeychainStore.delete(Account.license)
        }
        record = new
    }
}
