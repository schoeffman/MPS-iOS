//
//  MPS_iOSApp.swift
//  MPS-iOS
//

import SwiftUI

@main
struct MPS_iOSApp: App {
    private let authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
        }
    }
}

private struct RootView: View {
    @Environment(AuthManager.self) var authManager

    var body: some View {
        if authManager.isAuthenticated {
            ContentView()
        } else {
            LoginView()
        }
    }
}
