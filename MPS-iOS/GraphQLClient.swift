//
//  GraphQLClient.swift
//  MPS-iOS
//

import Foundation

struct GraphQLClient {
    private static let endpoint = URL(string: "https://mps-p.up.railway.app/graphql")!

    func fetch<T: Decodable>(query: String, variables: [String: Any]? = nil, token: String) async throws -> T {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = ["query": query]
        if let variables { body["variables"] = variables }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GQLResponse<T>.self, from: data)

        if let errors = response.errors, !errors.isEmpty {
            throw GQLError(message: errors.map(\.message).joined(separator: "\n"))
        }
        guard let result = response.data else { throw URLError(.badServerResponse) }
        return result
    }
}

private struct GQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [GQLErrorDetail]?
}

private struct GQLErrorDetail: Decodable {
    let message: String
}

struct GQLError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
