import Foundation

/// Polar settings. Both values are public (they ship in the app by design).
enum LicenseConfig {
    /// Polar → Settings → General → Organization ID.
    static let organizationID = "300a5340-3886-4986-a25d-4776fb239e09"
    /// Polar → Products → Sunrise → Checkout Links.
    static let checkoutURL = URL(string: "https://buy.polar.sh/polar_cl_QdDOIQeErSAshNIub87iwSeOFJ9ZlLc9HgSXb3alJIp")!
    /// Public customer-portal endpoints: made for desktop apps, no access token.
    static let apiBase = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/")!

    static var isConfigured: Bool { !organizationID.isEmpty }
}
