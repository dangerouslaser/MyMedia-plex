//
//  PlexAuthService.swift
//  MyMediaPlex
//
//  Created by Claude on 14.12.25.
//

import Foundation

/// Handles Plex PIN-based authentication flow
actor PlexAuthService {
    static let shared = PlexAuthService()

    private let session: URLSession
    private let tokenManager: PlexTokenManager
    private let decoder: JSONDecoder

    /// Polling interval for PIN authorization check (2 seconds)
    private let pollingInterval: TimeInterval = 2.0

    /// Maximum time to wait for PIN authorization (5 minutes)
    private let maxPollingDuration: TimeInterval = 300.0

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        self.tokenManager = PlexTokenManager.shared
        self.decoder = JSONDecoder()
    }

    // MARK: - Client Identifier

    /// Gets or creates a unique client identifier for this app
    var clientIdentifier: String {
        tokenManager.getOrCreateClientIdentifier()
    }

    // MARK: - PIN Authentication Flow

    /// Requests a new PIN for user authorization
    /// - Returns: PIN response with code to display to user
    func requestPIN() async throws -> PlexPINResponse {
        guard let url = URL(string: PlexEndpoints.pins) else {
            throw PlexAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let headers = PlexHeaders.forPinRequest(clientIdentifier: clientIdentifier)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        // Empty POST body for simple 4-character PIN
        request.httpBody = Data()

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PlexAuthError.pinRequestFailed
        }

        do {
            return try decoder.decode(PlexPINResponse.self, from: data)
        } catch {
            throw PlexAuthError.decodingError(error)
        }
    }

    /// Polls for PIN authorization until user completes auth or timeout
    /// - Parameters:
    ///   - pinID: The PIN ID from requestPIN()
    ///   - onStatusUpdate: Callback for status updates during polling
    /// - Returns: Auth token when user authorizes
    func pollForAuthorization(
        pinID: Int,
        onStatusUpdate: ((PlexAuthStatus) -> Void)? = nil
    ) async throws -> String {
        let startTime = Date()
        let url = PlexEndpoints.pinStatus(id: pinID)

        while Date().timeIntervalSince(startTime) < maxPollingDuration {
            onStatusUpdate?(.polling)

            guard let requestURL = URL(string: url) else {
                throw PlexAuthError.invalidURL
            }

            var request = URLRequest(url: requestURL)
            request.httpMethod = "GET"

            let headers = PlexHeaders.standard(token: nil, clientIdentifier: clientIdentifier)
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw PlexAuthError.pollingFailed
            }

            let pinResponse = try decoder.decode(PlexPINResponse.self, from: data)

            if let authToken = pinResponse.authToken, !authToken.isEmpty {
                // User authorized - store token
                try tokenManager.storeAuthToken(authToken)
                onStatusUpdate?(.authorized)
                return authToken
            }

            // Wait before next poll
            try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
        }

        onStatusUpdate?(.timeout)
        throw PlexAuthError.authorizationTimeout
    }

    // MARK: - Server Discovery

    /// Fetches available servers for the authenticated user
    func fetchServers() async throws -> [PlexServer] {
        guard let token = tokenManager.retrieveAuthToken() else {
            throw PlexAuthError.notAuthenticated
        }

        guard let url = URL(string: PlexEndpoints.resources) else {
            throw PlexAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let headers = PlexHeaders.standard(token: token, clientIdentifier: clientIdentifier)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PlexAuthError.serverFetchFailed
        }

        do {
            let servers = try decoder.decode([PlexServer].self, from: data)
            // Filter to only Plex Media Servers
            return servers.filter { $0.isMediaServer }
        } catch {
            throw PlexAuthError.decodingError(error)
        }
    }

    /// Fetches user info for the authenticated user
    func fetchUser() async throws -> PlexUser {
        guard let token = tokenManager.retrieveAuthToken() else {
            throw PlexAuthError.notAuthenticated
        }

        guard let url = URL(string: PlexEndpoints.user) else {
            throw PlexAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let headers = PlexHeaders.standard(token: token, clientIdentifier: clientIdentifier)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PlexAuthError.userFetchFailed
        }

        return try decoder.decode(PlexUser.self, from: data)
    }

    // MARK: - Server Selection

    /// Tests connection to a server and saves it if successful
    func selectServer(_ server: PlexServer) async throws {
        guard let connectionURL = server.bestConnectionURL else {
            throw PlexAuthError.noServerConnection
        }

        // Test the connection
        let testURL = PlexEndpoints.sections(baseURL: connectionURL)
        guard let url = URL(string: testURL),
              let token = tokenManager.retrieveAuthToken() else {
            throw PlexAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let headers = PlexHeaders.standard(token: token, clientIdentifier: clientIdentifier)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PlexAuthError.serverConnectionFailed
        }

        // Save server details
        UserDefaults.standard.set(connectionURL, forKey: PreferenceKeys.plexServerURL)
        UserDefaults.standard.set(server.clientIdentifier, forKey: PreferenceKeys.plexServerUUID)
        UserDefaults.standard.set(server.name, forKey: PreferenceKeys.plexServerName)

        // Update PlexAPIService
        await PlexAPIService.shared.setServerURL(connectionURL)
    }

    // MARK: - Sign Out

    /// Signs out and clears all Plex data
    func signOut() async throws {
        try tokenManager.clearAll()

        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.plexServerURL)
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.plexServerUUID)
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.plexServerName)
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.plexSelectedLibraries)
        UserDefaults.standard.removeObject(forKey: PreferenceKeys.lastPlexSyncDate)
    }

    // MARK: - Status Checks

    /// Returns true if user is authenticated
    var isAuthenticated: Bool {
        tokenManager.isAuthenticated
    }

    /// Returns the configured server name, if any
    var serverName: String? {
        UserDefaults.standard.string(forKey: PreferenceKeys.plexServerName)
    }
}

// MARK: - Auth Status

enum PlexAuthStatus {
    case idle
    case requestingPIN
    case waitingForAuth(pin: String)
    case polling
    case authorized
    case timeout
    case error(PlexAuthError)
}

// MARK: - Auth Errors

enum PlexAuthError: LocalizedError {
    case invalidURL
    case pinRequestFailed
    case pollingFailed
    case authorizationTimeout
    case notAuthenticated
    case serverFetchFailed
    case userFetchFailed
    case noServerConnection
    case serverConnectionFailed
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .pinRequestFailed:
            return "Failed to request PIN from Plex"
        case .pollingFailed:
            return "Failed to check authorization status"
        case .authorizationTimeout:
            return "Authorization timed out. Please try again."
        case .notAuthenticated:
            return "Not signed in to Plex"
        case .serverFetchFailed:
            return "Failed to fetch servers"
        case .userFetchFailed:
            return "Failed to fetch user info"
        case .noServerConnection:
            return "No connection available for server"
        case .serverConnectionFailed:
            return "Failed to connect to server"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        }
    }
}
