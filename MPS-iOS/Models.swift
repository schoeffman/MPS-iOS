//
//  Models.swift
//  MPS-iOS
//

import Foundation

// MARK: - User

struct User: Identifiable, Decodable {
    let id: Int
    let fullName: String
    let craftAbility: String
    let jobLevel: String
    let craftFocus: String
    let levelStartDate: String?
}

// MARK: - Team

struct TeamMember: Identifiable, Decodable {
    let id: Int
    let fullName: String
}

struct Team: Identifiable, Decodable {
    let id: Int
    let name: String
    let teamLead: TeamMember
    let members: [TeamMember]
}

// MARK: - Enums

enum CraftAbility: String, CaseIterable, Identifiable {
    case Engineering
    case Design
    case ProductManagement
    case DataScience

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ProductManagement: return "Product Management"
        case .DataScience: return "Data Science"
        default: return rawValue
        }
    }
}

enum JobLevel: String, CaseIterable, Identifiable {
    case Junior, Mid, Senior, Staff, Principal
    var id: String { rawValue }
}

enum CraftFocus: String, CaseIterable, Identifiable {
    case Frontend, Backend, Fullstack, Mobile, Infrastructure, NotApplicable
    var id: String { rawValue }
    var displayName: String { self == .NotApplicable ? "N/A" : rawValue }
}
