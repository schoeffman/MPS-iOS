# CLAUDE.md — MPS-iOS

## Project Overview

iOS client for MPS (My Project Scheduler). SwiftUI app backed by a GraphQL + Better Auth server deployed on Railway.

- **Server**: `https://mps-p.up.railway.app`
- **GraphQL endpoint**: `https://mps-p.up.railway.app/graphql`
- **Bundle ID**: `schoeftware.MPS-iOS`
- **Deployment target**: iOS 26.2
- **Xcode**: 26.2

---

## Critical Build Settings

These are set in the Xcode project and affect how Swift code must be written:

| Setting | Value |
|---|---|
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` |
| `SWIFT_APPROACHABLE_CONCURRENCY` | `YES` |

**Consequence**: `ObservableObject` + `@Published` does **not** work with these settings. Always use the `@Observable` macro with `@State` / `@Environment` instead.

---

## State Management Pattern

```swift
// CORRECT
@Observable final class Foo { var bar = "" }
struct MyView: View {
    @Environment(Foo.self) var foo
}

// WRONG — do not use
class Foo: ObservableObject { @Published var bar = "" }
struct MyView: View {
    @EnvironmentObject var foo: Foo
}
```

Auth state switching must live in a `View` struct (e.g. `RootView`), not directly in `App.body` — `App.body` is not a SwiftUI-tracked context for `@Observable`.

---

## SwiftUI Compiler Gotchas

The Swift type checker frequently times out on complex view bodies. Follow these rules to avoid build errors:

1. **Break up `body`** into `private var` sub-views (`nameSection`, `membersSection`, etc.) rather than writing everything inline.
2. **Extract row views** into separate `private struct` types rather than nesting complex closures inside `ForEach`.
3. **Use `ForEach(collection, id: \.id)`** with an explicit `id` parameter to avoid the compiler picking the wrong overload (the `Binding<[C]>` editable-list overload).
4. **Break up chained boolean expressions** into named `let` constants before combining them.
5. **Use `Color.accentColor`** not `.accentColor` in `foregroundStyle()` — `.accentColor` is not a `ShapeStyle` member.

---

## File Organization

The project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+). Any `.swift` file added to `MPS-iOS/` is **automatically included in the build** — no need to edit `project.pbxproj` for new source files.

`Info.plist` is manually managed (`GENERATE_INFOPLIST_FILE = NO`). It registers the `mps-ios://` custom URL scheme used for the OAuth callback.

---

## Authentication Architecture

Google OAuth via `ASWebAuthenticationSession` (web redirect, no Google SDK):

1. App opens `/auth/mobile-start` in `ASWebAuthenticationSession` with `prefersEphemeralWebBrowserSession = true`
2. That page's JavaScript calls `/api/auth/sign-in/social` from within the browser — this is critical so Better Auth's CSRF state cookie lands in the browser's cookie jar, not a URLSession
3. After Google auth, server relays token to `mps-ios://auth/callback?token=…`
4. App parses the token, saves to Keychain, sets `sessionToken` on `AuthManager`

All API requests use `Authorization: Bearer <token>`. Better Auth's `bearer` plugin must be registered on the server for this to work.

`validateSession()` only clears the stored token on a definitive `401` or an explicit `200` with `{ user: null }` — network errors and 5xx responses leave the token intact.

---

## GraphQL Client Usage

```swift
// Query
struct Response: Decodable { let users: [User] }
let result: Response = try await client.fetch(
    query: "{ users { id fullName } }",
    token: token
)

// Mutation with variables
struct Result: Decodable { let createUser: User }
let result: Result = try await client.fetch(
    query: """
    mutation CreateUser($input: CreateUserInput!) {
        createUser(input: $input) { id fullName }
    }
    """,
    variables: ["input": ["fullName": "Jane", "craftAbility": "Engineering"]],
    token: token
)

// Combined query (multiple root fields)
struct LoadResponse: Decodable { let users: [User]; let teams: [Team] }
let result: LoadResponse = try await client.fetch(query: "{ users { ... } teams { ... } }", token: token)
```

Variables are `[String: Any]?` and serialized with `JSONSerialization` — nested dicts and `[Int]` arrays work fine.

---

## Data Models

Defined in `Models.swift`. Key rule: `User` contains all scalar fields. For nested user references inside `Team`, use the lightweight `TeamMember` struct (only `id` + `fullName`) to avoid decoding failures when not all `User` fields are present in the response.

```
User        — id, fullName, craftAbility, jobLevel, craftFocus, levelStartDate?
TeamMember  — id, fullName  (used as teamLead / members inside Team)
Team        — id, name, teamLead: TeamMember, members: [TeamMember]
```

Enums (`CraftAbility`, `JobLevel`, `CraftFocus`) use their `rawValue` strings directly in GraphQL variables.

---

## Sorting & Filtering Convention

Always sort user-facing lists with `localizedCaseInsensitiveCompare` for correct locale-aware alphabetical order:

```swift
.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
```

---

## Server Notes

- Better Auth mounted at `/api/auth/*`
- Mobile OAuth relay at `/auth/mobile-start` and `/auth/mobile-callback`
- `bearer` plugin must be active in `auth.ts` for `Authorization: Bearer` headers to work
- `trustedOrigins` must include `https://mps-p.up.railway.app` for the mobile callback URL to be accepted
- Server source: `/Users/schoeffman/projects/mps/server/src/`
