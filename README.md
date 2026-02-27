# MPS-iOS

iOS client for **MPS (My Project Scheduler)** — a tool for managing people, teams, and project assignments.

## Requirements

- Xcode 26.2+
- iOS 26.2+ deployment target
- Backend server running at `https://mps-p.up.railway.app` (or locally)

## Architecture

- **SwiftUI** with the `@Observable` macro for state management
- **GraphQL** over HTTP for all data fetching and mutations
- **Google OAuth** via `ASWebAuthenticationSession` (web redirect flow, no native SDK)
- **Keychain** for secure session token persistence

## Authentication

Sign-in uses Google OAuth through the server's Better Auth integration. The flow:

1. App opens `/auth/mobile-start` in an `ASWebAuthenticationSession` browser
2. The page initiates Google OAuth from within the browser so the CSRF state cookie lands in the correct cookie jar
3. After Google completes auth, the server relays the session token to `mps-ios://auth/callback?token=…`
4. The app intercepts the custom scheme callback, saves the token to Keychain, and transitions to the main UI

The session token is sent as `Authorization: Bearer <token>` on all subsequent GraphQL requests.

## Project Structure

```
MPS-iOS/
├── MPS_iOSApp.swift       # App entry point, injects AuthManager
├── AuthManager.swift      # Google sign-in, session validation, sign-out
├── KeychainHelper.swift   # Keychain read/write/delete for session token
├── GraphQLClient.swift    # Generic GraphQL fetch with Bearer auth
├── Models.swift           # Data models: User, Team, TeamMember, enums
│
├── ContentView.swift      # Root TabView (Dashboard / Users / Teams)
├── LoginView.swift        # Sign-in screen
├── DashboardView.swift    # Dashboard tab (placeholder)
│
├── UsersView.swift        # Users list with craft ability filter and search
├── CreateUserView.swift   # New user form
├── UserDetailView.swift   # User detail with edit button
├── EditUserView.swift     # Edit user form
│
├── TeamsView.swift        # Teams list sorted alphabetically
└── CreateTeamView.swift   # New team form with member and lead selection
```

## Features

### Users
- List all users sorted alphabetically, filterable by craft ability (Engineering, Design, Product Management, Data Science) and searchable by name
- Create a user with full name, craft ability, craft focus, job level, and level start date
- Tap a user to view their details
- Edit any user field inline

### Teams
- List all teams sorted alphabetically, showing team lead and member count
- Create a team with a name, member selection, and a team lead chosen from the selected members
- Users already assigned to a team are greyed out with their current team shown as a hint

## Data Models

| Model | Key Fields |
|---|---|
| `User` | id, fullName, craftAbility, jobLevel, craftFocus, levelStartDate |
| `Team` | id, name, teamLead, members |
| `TeamMember` | id, fullName |

### Enums

- **CraftAbility**: Engineering, Design, ProductManagement, DataScience
- **JobLevel**: Junior, Mid, Senior, Staff, Principal
- **CraftFocus**: Frontend, Backend, Fullstack, Mobile, Infrastructure, NotApplicable

## Backend

The server is a Node.js/TypeScript app using:
- **Better Auth** for authentication (Google OAuth + session management)
- **GraphQL** (Yoga) for the API
- **Drizzle ORM** + PostgreSQL for persistence
- Deployed on [Railway](https://railway.app)

GraphQL endpoint: `https://mps-p.up.railway.app/graphql`
