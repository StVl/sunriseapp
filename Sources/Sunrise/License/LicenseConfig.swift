import Foundation

/// Polar settings. Both values are public (they ship in the app by design).
enum LicenseConfig {
    /// Polar → Settings → General → Organization ID.
    static let organizationID = ""
    /// Polar → Products → Sunrise → Checkout Links.
    static let checkoutURL = URL(string: "https://polar.sh")!
    /// Public customer-portal endpoints: made for desktop apps, no access token.
    static let apiBase = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/")!

    static var isConfigured: Bool { !organizationID.isEmpty }
}
