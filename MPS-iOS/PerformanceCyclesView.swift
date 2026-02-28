//
//  PerformanceCyclesView.swift
//  MPS-iOS
//

import SwiftUI

struct PerformanceCyclesView: View {
    var embedded = false

    var body: some View {
        if embedded {
            Text("").navigationTitle("Performance Cycles")
        } else {
            NavigationStack {
                Text("").navigationTitle("Performance Cycles")
            }
        }
    }
}

#Preview {
    PerformanceCyclesView()
        .environment(AuthManager())
}
