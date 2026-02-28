//
//  WorkHistoryView.swift
//  MPS-iOS
//

import SwiftUI

struct WorkHistoryView: View {
    var body: some View {
        NavigationStack {
            Text("")
                .navigationTitle("Work History")
        }
    }
}

#Preview {
    WorkHistoryView()
        .environment(AuthManager())
}
