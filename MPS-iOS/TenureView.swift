//
//  TenureView.swift
//  MPS-iOS
//

import SwiftUI

struct TenureView: View {
    var body: some View {
        NavigationStack {
            Text("")
                .navigationTitle("Tenure")
        }
    }
}

#Preview {
    TenureView()
        .environment(AuthManager())
}
