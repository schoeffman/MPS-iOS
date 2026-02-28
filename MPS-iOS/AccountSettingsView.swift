//
//  AccountSettingsView.swift
//  MPS-iOS
//

import SwiftUI

struct AccountSettingsView: View {
    var body: some View {
        NavigationStack {
            Text("")
                .navigationTitle("Account Settings")
        }
    }
}

#Preview {
    AccountSettingsView()
        .environment(AuthManager())
}
