//
//  LoginView.swift
//  MPS-iOS
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(AuthManager.self) var authManager

    private var presentationAnchor: ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow } ?? UIWindow()
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Color.accentColor)
                Text("MPS")
                    .font(.system(size: 40, weight: .bold))
                Text("Music Practice Studio")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                let anchor = presentationAnchor
                Task { await authManager.signInWithGoogle(anchor: anchor) }
            } label: {
                HStack(spacing: 10) {
                    if authManager.isLoading {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "globe")
                            .font(.body.weight(.medium))
                    }
                    Text("Sign in with Google")
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.primary)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(authManager.isLoading)
            .padding(.horizontal, 32)
            .padding(.bottom, 56)
        }
        .alert("Sign In Failed", isPresented: Binding(
            get: { authManager.lastError != nil },
            set: { if !$0 { authManager.lastError = nil } }
        )) {
            Button("OK") { authManager.lastError = nil }
        } message: {
            Text(authManager.lastError ?? "")
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthManager())
}
