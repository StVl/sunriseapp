import Foundation

/// Polar's public license-key endpoints (activate / validate / deactivate).
enum PolarLicenseAPI {
    enum Failure: Error, Equatable {
        case notConfigured
        case notFound
        case limitReached
        case invalid
        case offline
        case server(Int)

        var message: String {
            switch self {
            case .notConfigured: return "Licensing isn't set up in this build yet."
            case .notFound: return "This key wasn't found. Check that you copied all of it."
            case .limitReached: return "This key is already active on 3 Macs. Free one up in your Polar customer portal (link in your receipt)."
            case .invalid: return "That doesn't look like a Sunrise license key."
            case .offline: return "Couldn't reach the license server. Check your internet connection and try again."
            case .server(let code): return "The license server had a problem (\(code)). Try again in a minute."
            }
        }
    }

    /// Activates the key for this Mac; returns the activation ID.
    static func activate(key: String, label: String) async throws -> String {
        let data = try await post("activate", ["key": key, "label": label])
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = json["id"] as? String
        else { throw Failure.server(200) }
        return id
    }

    /// Returns the key's status ("granted" when fine).
    static func validate(key: String, activationID: String) async throws -> String {
        let data = try await post("validate", ["key": key, "activation_id": activationID])
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["status"] as? String ?? "unknown"
    }

    static func deactivate(key: String, activationID: String) async throws {
        _ = try await post("deactivate", ["key": key, "activation_id": activationID])
    }

    private static func post(_ path: String, _ fields: [String: String]) async throws -> Data {
        guard LicenseConfig.isConfigured else { throw Failure.notConfigured }
        var body = fields
        body["organization_id"] = LicenseConfig.organizationID
        var request = URLRequest(url: LicenseConfig.apiBase.appendingPathComponent(path), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.offline
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 403: throw Failure.limitReached
        case 404: throw Failure.notFound
        case 422: throw Failure.invalid
        default: throw Failure.server(status)
        }
    }
}
