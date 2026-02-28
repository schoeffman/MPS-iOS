//
//  SpaceSettingsView.swift
//  MPS-iOS
//

import SwiftUI

struct SpaceSettingsView: View {
    var body: some View {
        NavigationStack {
            Text("")
                .navigationTitle("Space Settings")
        }
    }
}

#Preview {
    SpaceSettingsView()
        .environment(AuthManager())
}
