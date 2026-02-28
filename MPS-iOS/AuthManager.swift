//
//  AuthManager.swift
//  MPS-iOS
//

import Foundation
import AuthenticationServices
import Observation

// MARK: - Helpers

private enum AuthError: LocalizedError {
    case badServerResponse
    case callbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .badServerResponse: return "Unexpected response from auth server"
        case .callbackFailed(let msg): return msg
        }
    }
}

private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
}

// MARK: - AuthManager

@MainActor
@Observable
final class AuthManager {
    var sessionToken: String?
    var activeSpaceId: String?
    var isLoading = false
    var lastError: String?

    var isAuthenticated: Bool { sessionToken != nil }

    private var activeSession: ASWebAuthenticationSession?
    private var activePresentationProvider: PresentationContextProvider?

    private static let baseURL = "https://mps-p.up.railway.app"
    private static let spaceKey = "mps.activeSpaceId"

    init() {
        sessionToken = KeychainHelper.read()
        activeSpaceId = UserDefaults.standard.string(forKey: Self.spaceKey)
        if sessionToken != nil {
            Task { await validateSession() }
        }
    }

    func switchSpace(_ id: String) {
        activeSpaceId = id
        UserDefaults.standard.set(id, forKey: Self.spaceKey)
    }

    func clearActiveSpace() {
        activeSpaceId = nil
        UserDefaults.standard.removeObject(forKey: Self.spaceKey)
    }

    // MARK: Session validation

    func validateSession() async {
        guard let token = sessionToken else { return }
        guard let url = URL(string: "\(Self.baseURL)/api/auth/get-session") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }

            if http.statusCode == 401 {
                // Definitive rejection — token is invalid or expired
                clearSession()
            } else if http.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["user"] == nil {
                // Server confirmed no active session
                clearSession()
            }
            // Any other status (5xx, network hiccup, etc.) — keep the stored token
        } catch {
            // Network error — keep stored token
        }
    }

    // MARK: Sign in

    func signInWithGoogle(anchor: ASPresentationAnchor) async {
        isLoading = true
        lastError = nil
        defer {
            isLoading = false
            activeSession = nil
            activePresentationProvider = nil
        }

        guard let startURL = URL(string: "\(Self.baseURL)/auth/mobile-start") else { return }

        do {
            // Open the mobile-start page in a browser session.
            // That page's JavaScript calls /api/auth/sign-in/social so that
            // Better Auth's state-verification cookie is stored in THIS browser's
            // cookie jar, not in a separate URLSession.
            let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
                let provider = PresentationContextProvider(anchor: anchor)
                let session = ASWebAuthenticationSession(
                    url: startURL,
                    callback: .customScheme("mps-ios")
                ) { url, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: URLError(.badServerResponse)) }
                }
                session.prefersEphemeralWebBrowserSession = true
                session.presentationContextProvider = provider
                self.activeSession = session
                self.activePresentationProvider = provider
                session.start()
            }

            // Extract token from mps-ios://auth/callback?token=...
            guard
                let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                let token = components.queryItems?.first(where: { $0.name == "token" })?.value
            else {
                let errParam = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "error" })?.value
                throw AuthError.callbackFailed(errParam ?? "No token in callback")
            }

            KeychainHelper.save(token)
            sessionToken = token

        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User cancelled — not an error
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Sign out

    func signOut() async {
        guard let token = sessionToken else { return }
        if let url = URL(string: "\(Self.baseURL)/api/auth/sign-out") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            try? await URLSession.shared.data(for: request)
        }
        clearSession()
    }

    private func clearSession() {
        KeychainHelper.delete()
        sessionToken = nil
        activeSpaceId = nil
        UserDefaults.standard.removeObject(forKey: Self.spaceKey)
    }
}
