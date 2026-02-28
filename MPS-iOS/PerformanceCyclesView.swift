//
//  PerformanceCyclesView.swift
//  MPS-iOS
//

import SwiftUI

struct PerformanceCyclesView: View {
    var body: some View {
        NavigationStack {
            Text("")
                .navigationTitle("Performance Cycles")
        }
    }
}

#Preview {
    PerformanceCyclesView()
        .environment(AuthManager())
}
