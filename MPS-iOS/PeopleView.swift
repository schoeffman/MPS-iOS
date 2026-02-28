//
//  PeopleView.swift
//  MPS-iOS
//

import SwiftUI

struct PeopleView: View {
    var body: some View {
        NavigationStack {
            UsersView(embedded: true)
        }
    }
}
