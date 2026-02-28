//
//  TenureView.swift
//  MPS-iOS
//

import SwiftUI

struct TenureView: View {
    var embedded = false

    var body: some View {
        if embedded {
            Text("").navigationTitle("Tenure")
        } else {
            NavigationStack {
                Text("").navigationTitle("Tenure")
            }
        }
    }
}

#Preview {
    TenureView()
        .environment(AuthManager())
}
