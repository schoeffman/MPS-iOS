//
//  GraphQLClient.swift
//  MPS-iOS
//

import Foundation

struct GraphQLClient {
    private static let endpoint = URL(string: "https://mps-p.up.railway.app/graphql")!

    func fetch<T: Decodable>(query: String, variables: [String: Any]? = nil, token: String) async throws -> T {
        let request = try buildRequest(query: query, variables: variables, token: token)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(GQLResponse<T>.self, from: data)
        if let errors = response.errors, !errors.isEmpty {
            throw GQLError(message: errors.map(\.message).joined(separator: "\n"))
        }
        guard let result = response.data else { throw URLError(.badServerResponse) }
        return result
    }

    /// Returns the raw `data` dictionary from the GraphQL response.
    /// Useful when field names are dynamic (e.g., aliased multi-date queries).
    func fetchRaw(query: String, variables: [String: Any]? = nil, token: String) async throws -> [String: Any] {
        let request = try buildRequest(query: query, variables: variables, token: token)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.badServerResponse)
        }
        if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
            let msg = errors.compactMap { $0["message"] as? String }.joined(separator: "\n")
            throw GQLError(message: msg)
        }
        guard let dataObj = json["data"] as? [String: Any] else {
            throw URLError(.badServerResponse)
        }
        return dataObj
    }

    private func buildRequest(query: String, variables: [String: Any]?, token: String) throws -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let spaceId = UserDefaults.standard.string(forKey: "mps.activeSpaceId") {
            request.setValue(spaceId, forHTTPHeaderField: "x-space-id")
        }
        var body: [String: Any] = ["query": query]
        if let variables { body["variables"] = variables }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
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
